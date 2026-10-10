-- =====================================================================
-- GUDANG TITATI - UPDATE: OMZET GUDANG, BON CABANG (HARGA JUAL), TAGIHAN SUPPLIER
--
-- 1. Harga jual ke cabang: gudang mengisi harga jual SETIAP kirim ke cabang
--    (kolom doc_lines.sell_price). Harga beli rata-rata tetap tersimpan di
--    doc_lines.unit_price (modal), jadi keuntungan = harga jual - modal.
-- 2. Bon cabang: nilai bon = harga jual x jumlah diterima. Pelunasan (boleh cicil)
--    dicatat gudang/owner di tabel doc_payments (kind = 'bon'), lengkap riwayat.
-- 3. Barang Masuk dari grosir: pilih cash (langsung lunas) atau tempo (ada tanggal
--    jatuh tempo). Pembayaran ke supplier dicatat di doc_payments (kind = 'supplier').
-- 4. Akun gudang boleh mengubah/menghapus barang (sebelumnya hanya owner), karena
--    gudang mengisi daftar barangnya sendiri.
--
-- JALANKAN PALING AKHIR (setelah supabase_update_stok_kosong.sql dan
-- supabase_update_hapus_barang.sql). Aman diulang.
-- Tidak mengganti create_doc / send_doc / receive_doc, jadi alur lama tidak berubah.
-- Dokumen Barang Masuk lama (bayar_mode kosong) dianggap sudah lunas; bila ada yang
-- sebenarnya belum dibayar, ubah lewat tombol "Atur cara bayar" di detail dokumennya.
-- =====================================================================

-- 1) Kolom baru
alter table public.doc_lines add column if not exists sell_price numeric not null default 0;
alter table public.doc_lines drop constraint if exists doc_lines_sell_price_check;
alter table public.doc_lines add constraint doc_lines_sell_price_check check (sell_price >= 0);

alter table public.docs add column if not exists bayar_mode text not null default '';
alter table public.docs drop constraint if exists docs_bayar_mode_check;
alter table public.docs add constraint docs_bayar_mode_check check (bayar_mode in ('', 'cash', 'tempo'));
alter table public.docs add column if not exists jatuh_tempo date;

-- 2) Tabel pembayaran (satu tabel untuk bon cabang dan tagihan supplier)
create table if not exists public.doc_payments (
  id bigint generated always as identity primary key,
  doc_id uuid not null references public.docs(id) on delete cascade,
  kind text not null check (kind in ('bon', 'supplier')),
  amount numeric not null check (amount > 0),
  method text not null check (method in ('transfer', 'cash')),
  paid_at date not null default ((now() at time zone 'Asia/Jakarta')::date),
  note text not null default '',
  by_name text not null default '',
  created_at timestamptz not null default now()
);
create index if not exists doc_payments_doc_idx on public.doc_payments (doc_id);

alter table public.doc_payments enable row level security;
drop policy if exists p_pay_select on public.doc_payments;
create policy p_pay_select on public.doc_payments for select to authenticated
  using (
    public.me_role() in ('owner', 'gudang')
    or (public.me_role() = 'cabang' and kind = 'bon'
        and exists (select 1 from public.docs d where d.id = doc_id and d.branch = public.me_branch()))
  );
-- tidak ada policy insert/update/delete: semua perubahan lewat fungsi di bawah

-- 3) Akun gudang boleh mengubah barang (sebelumnya hanya owner)
drop policy if exists p_items_update on public.items;
create policy p_items_update on public.items for update to authenticated
  using (public.me_role() in ('owner', 'gudang'))
  with check (public.me_role() in ('owner', 'gudang'));

create or replace function public.hapus_barang(p_item uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_name text; v_lokasi int; v_riwayat boolean;
begin
  if public.me_role() not in ('owner', 'gudang') then raise exception 'Hanya owner atau kepala gudang yang bisa menghapus barang'; end if;
  select name into v_name from public.items where id = p_item;
  if not found then raise exception 'Barang tidak ditemukan'; end if;

  select count(*) into v_lokasi from public.v_stock where item_id = p_item;
  if v_lokasi > 0 then
    raise exception 'Stok "%" masih ada. Kosongkan dulu lewat koreksi stok.', v_name;
  end if;

  v_riwayat := exists (select 1 from public.doc_lines where item_id = p_item)
            or exists (select 1 from public.stock_ledger where item_id = p_item);
  if v_riwayat then
    update public.items set active = false where id = p_item;
    return 'arsip';
  end if;

  delete from public.items where id = p_item;
  return 'hapus';
end $$;

-- 4) Fungsi bantu (internal)
create or replace function public._bon_total(p_doc uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(sell_price * coalesce(qty_received, qty)), 0) from public.doc_lines where doc_id = p_doc
$$;

create or replace function public._masuk_total(p_doc uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(unit_price * qty), 0) from public.doc_lines where doc_id = p_doc
$$;

create or replace function public._dibayar(p_doc uuid, p_kind text) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(sum(amount), 0) from public.doc_payments where doc_id = p_doc and kind = p_kind
$$;

create or replace function public._hari_ini() returns date
language sql stable as $$ select (now() at time zone 'Asia/Jakarta')::date $$;

-- 5) Barang Masuk dengan cara bayar (cash / tempo), satu transaksi dengan create_doc
create or replace function public.create_masuk(p_supplier text, p_note text, p_lines jsonb, p_mode text, p_jatuh_tempo date)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if public.me_role() <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh mencatat barang masuk'; end if;
  if p_mode is null or p_mode not in ('cash', 'tempo') then raise exception 'Pilih cara bayar nota: cash atau tempo'; end if;
  if p_mode = 'tempo' then
    if p_jatuh_tempo is null then raise exception 'Isi tanggal jatuh tempo'; end if;
    if p_jatuh_tempo < public._hari_ini() then raise exception 'Tanggal jatuh tempo tidak boleh sebelum hari ini'; end if;
  end if;
  v_id := public.create_doc('masuk', p_supplier, p_note, p_lines);
  update public.docs
     set bayar_mode = p_mode, jatuh_tempo = case when p_mode = 'tempo' then p_jatuh_tempo else null end
   where id = v_id;
  perform public._log(v_id,
    case when p_mode = 'tempo' then 'nota tempo (belum dibayar)' else 'nota cash (lunas)' end,
    case when p_mode = 'tempo' then 'jatuh tempo ' || to_char(p_jatuh_tempo, 'DD-MM-YYYY') else '' end);
  return v_id;
end $$;

-- Ubah cara bayar / jatuh tempo nota masuk (mis. dokumen lama yang ternyata belum dibayar)
create or replace function public.atur_pembayaran_masuk(p_doc uuid, p_mode text, p_jatuh_tempo date)
returns void language plpgsql security definer set search_path = public as $$
declare d public.docs;
begin
  if public.me_role() not in ('gudang', 'owner') then raise exception 'Hanya kepala gudang atau owner'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found or d.type <> 'masuk' then raise exception 'Bukan dokumen Barang Masuk'; end if;
  if p_mode not in ('cash', 'tempo') then raise exception 'Pilih cash atau tempo'; end if;
  if p_mode = 'tempo' and p_jatuh_tempo is null then raise exception 'Isi tanggal jatuh tempo'; end if;
  if p_mode = 'cash' and exists (select 1 from public.doc_payments where doc_id = p_doc and kind = 'supplier') then
    raise exception 'Nota ini sudah ada pembayaran, tidak bisa diubah ke cash';
  end if;
  update public.docs
     set bayar_mode = p_mode, jatuh_tempo = case when p_mode = 'tempo' then p_jatuh_tempo else null end
   where id = p_doc;
  perform public._log(p_doc, 'cara bayar diatur: ' || p_mode,
    case when p_mode = 'tempo' then 'jatuh tempo ' || to_char(p_jatuh_tempo, 'DD-MM-YYYY') else '' end);
end $$;

-- 6) Kirim ke Cabang dengan harga jual per barang (satu transaksi dengan create_doc)
-- p_lines: [{"item_id":"...","qty":5,"sell_price":12000}]
create or replace function public.create_kirim_cabang(p_cabang text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_l jsonb; v_sell numeric;
begin
  if public.me_role() <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh mengirim ke cabang'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Isi minimal satu barang';
  end if;
  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_sell := coalesce(nullif(v_l->>'sell_price', '')::numeric, 0);
    if v_sell <= 0 then raise exception 'Harga jual wajib diisi untuk semua barang'; end if;
  end loop;

  v_id := public.create_doc('kirim_cabang', p_cabang, p_note, p_lines);

  for v_l in select value from jsonb_array_elements(p_lines) loop
    update public.doc_lines
       set sell_price = (v_l->>'sell_price')::numeric
     where doc_id = v_id and item_id = (v_l->>'item_id')::uuid;
  end loop;
  perform public._log(v_id, 'harga jual diisi gudang', '');
  return v_id;
end $$;

-- Isi / ubah harga jual bon (mis. Permintaan Cabang saat dikirim). Ditolak bila bon sudah ada pembayaran.
-- p_lines: [{"line_id":"...","sell_price":12000}]
create or replace function public.atur_harga_jual(p_doc uuid, p_lines jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare d public.docs; v_l jsonb; v_s numeric; v_qty numeric; v_lid uuid;
begin
  if public.me_role() not in ('gudang', 'owner') then raise exception 'Hanya kepala gudang atau owner yang boleh mengatur harga jual'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.type not in ('minta_cabang', 'kirim_cabang') then raise exception 'Dokumen ini bukan pengiriman ke cabang'; end if;
  if d.status not in ('disetujui', 'dikirim', 'diterima') then raise exception 'Dokumen belum bisa diberi harga (status: %)', d.status; end if;
  if exists (select 1 from public.doc_payments where doc_id = p_doc and kind = 'bon') then
    raise exception 'Bon ini sudah ada pembayaran, harga jual tidak bisa diubah';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then raise exception 'Data harga tidak valid'; end if;
  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_lid := (v_l->>'line_id')::uuid;
    v_s := (v_l->>'sell_price')::numeric;
    select qty into v_qty from public.doc_lines where id = v_lid and doc_id = p_doc;
    if not found then continue; end if;
    if v_s is null or v_s < 0 then raise exception 'Harga jual tidak valid'; end if;
    update public.doc_lines set sell_price = v_s where id = v_lid and doc_id = p_doc;
  end loop;
  perform public._log(p_doc, 'harga jual diatur', 'total bon Rp ' || round(public._bon_total(p_doc))::text);
end $$;

-- 7) Pelunasan bon cabang (dicatat gudang/owner saat menerima pembayaran dari cabang)
create or replace function public.catat_bayar_bon(p_doc uuid, p_amount numeric, p_method text, p_paid_at date default null, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare d public.docs; v_total numeric; v_paid numeric; v_sisa numeric; v_tgl date := coalesce(p_paid_at, public._hari_ini());
begin
  if public.me_role() not in ('gudang', 'owner') then raise exception 'Hanya kepala gudang atau owner yang boleh mencatat pelunasan'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.type not in ('minta_cabang', 'kirim_cabang') then raise exception 'Dokumen ini bukan bon cabang'; end if;
  if d.status <> 'diterima' then raise exception 'Bon baru bisa dilunasi setelah barang diterima cabang'; end if;
  if p_method is null or p_method not in ('transfer', 'cash') then raise exception 'Pilih transfer atau cash'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Jumlah pembayaran harus lebih dari 0'; end if;
  if v_tgl > public._hari_ini() then raise exception 'Tanggal pembayaran tidak boleh di masa depan'; end if;
  v_total := public._bon_total(p_doc);
  if v_total <= 0 then raise exception 'Bon belum punya harga jual. Isi harga jual dulu.'; end if;
  v_paid := public._dibayar(p_doc, 'bon');
  v_sisa := v_total - v_paid;
  if p_amount > v_sisa + 0.005 then raise exception 'Jumlah melebihi sisa bon (Rp %)', round(v_sisa); end if;

  insert into public.doc_payments (doc_id, kind, amount, method, paid_at, note, by_name)
  values (p_doc, 'bon', p_amount, p_method, v_tgl, coalesce(p_note, ''), public.me_name());
  perform public._log(p_doc, case when p_amount >= v_sisa - 0.005 then 'bon lunas' else 'pelunasan bon (cicil)' end,
    'Rp ' || round(p_amount)::text || ' via ' || p_method);
end $$;

-- 8) Pembayaran tagihan grosir / supplier
create or replace function public.catat_bayar_supplier(p_doc uuid, p_amount numeric, p_method text, p_paid_at date default null, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare d public.docs; v_total numeric; v_paid numeric; v_sisa numeric; v_tgl date := coalesce(p_paid_at, public._hari_ini());
begin
  if public.me_role() not in ('gudang', 'owner') then raise exception 'Hanya kepala gudang atau owner yang boleh mencatat pembayaran'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.type <> 'masuk' then raise exception 'Dokumen ini bukan nota grosir'; end if;
  if d.bayar_mode <> 'tempo' then raise exception 'Nota ini tidak berstatus tempo'; end if;
  if p_method is null or p_method not in ('transfer', 'cash') then raise exception 'Pilih transfer atau cash'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Jumlah pembayaran harus lebih dari 0'; end if;
  if v_tgl > public._hari_ini() then raise exception 'Tanggal pembayaran tidak boleh di masa depan'; end if;
  v_total := public._masuk_total(p_doc);
  v_paid := public._dibayar(p_doc, 'supplier');
  v_sisa := v_total - v_paid;
  if v_sisa <= 0.005 then raise exception 'Nota ini sudah lunas'; end if;
  if p_amount > v_sisa + 0.005 then raise exception 'Jumlah melebihi sisa tagihan (Rp %)', round(v_sisa); end if;

  insert into public.doc_payments (doc_id, kind, amount, method, paid_at, note, by_name)
  values (p_doc, 'supplier', p_amount, p_method, v_tgl, coalesce(p_note, ''), public.me_name());
  perform public._log(p_doc, case when p_amount >= v_sisa - 0.005 then 'tagihan grosir lunas' else 'bayar grosir (cicil)' end,
    'Rp ' || round(p_amount)::text || ' via ' || p_method);
end $$;

-- 9) Batalkan salah catat pembayaran (khusus owner; tercatat di riwayat dokumen)
create or replace function public.batal_bayar(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare p public.doc_payments;
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh membatalkan pembayaran'; end if;
  select * into p from public.doc_payments where id = p_id for update;
  if not found then raise exception 'Pembayaran tidak ditemukan'; end if;
  delete from public.doc_payments where id = p_id;
  perform public._log(p.doc_id, 'pembayaran dibatalkan owner',
    'Rp ' || round(p.amount)::text || ' (' || p.method || ', ' || to_char(p.paid_at, 'DD-MM-YYYY') || ')');
end $$;

-- 10) Izin
revoke execute on function public._bon_total(uuid) from public, anon, authenticated;
revoke execute on function public._masuk_total(uuid) from public, anon, authenticated;
revoke execute on function public._dibayar(uuid, text) from public, anon, authenticated;
revoke execute on function public._hari_ini() from public, anon, authenticated;

revoke execute on function public.hapus_barang(uuid) from public, anon;
revoke execute on function public.create_masuk(text, text, jsonb, text, date) from public, anon;
revoke execute on function public.atur_pembayaran_masuk(uuid, text, date) from public, anon;
revoke execute on function public.create_kirim_cabang(text, text, jsonb) from public, anon;
revoke execute on function public.atur_harga_jual(uuid, jsonb) from public, anon;
revoke execute on function public.catat_bayar_bon(uuid, numeric, text, date, text) from public, anon;
revoke execute on function public.catat_bayar_supplier(uuid, numeric, text, date, text) from public, anon;
revoke execute on function public.batal_bayar(bigint) from public, anon;

grant execute on function public.hapus_barang(uuid) to authenticated;
grant execute on function public.create_masuk(text, text, jsonb, text, date) to authenticated;
grant execute on function public.atur_pembayaran_masuk(uuid, text, date) to authenticated;
grant execute on function public.create_kirim_cabang(text, text, jsonb) to authenticated;
grant execute on function public.atur_harga_jual(uuid, jsonb) to authenticated;
grant execute on function public.catat_bayar_bon(uuid, numeric, text, date, text) to authenticated;
grant execute on function public.catat_bayar_supplier(uuid, numeric, text, date, text) to authenticated;
grant execute on function public.batal_bayar(bigint) to authenticated;

notify pgrst, 'reload schema';
