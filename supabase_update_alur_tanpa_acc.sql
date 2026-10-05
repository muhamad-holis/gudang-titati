-- =====================================================================
-- GUDANG TITATI - UPDATE: ALUR TANPA ACC OWNER
-- Owner tidak lagi dipaksa ACC. Owner memantau; yang menjaga barang adalah
-- penerima (hitung fisik saat Terima) dan gudang (atur jumlah kirim ke cabang).
--
-- Jalankan SETELAH supabase_setup_gudang.sql, supabase_update_penjualan.sql
-- dan supabase_update_siap_jual.sql. Aman diulang.
--
-- Alur baru:
--  1. Barang Masuk      : langsung menambah stok gudang.
--  2. Kirim ke Produksi : langsung terkirim (stok gudang berkurang), produksi Terima.
--  3. Setor Produksi    : langsung terkirim (bahan dipakai berkurang), gudang Terima.
--  4. Permintaan Cabang : masuk antrean gudang, gudang boleh MENGURANGI jumlah
--                         sesuai stok lalu Kirim, cabang Terima.
-- Dokumen lama berstatus "diajukan" tetap bisa di-ACC owner seperti biasa.
-- =====================================================================

-- 1) KIRIM: gudang boleh menyesuaikan (hanya mengurangi) jumlah permintaan cabang
drop function if exists public.send_doc(uuid);

create or replace function public.send_doc(p_doc uuid, p_lines jsonb default null) returns void
language plpgsql security definer set search_path = public as $$
declare
  d public.docs; v_role text := public.me_role(); r record; v_src text; have numeric;
  v_l jsonb; v_q numeric; v_old numeric; v_changed boolean := false; n_left int;
begin
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.type = 'masuk' then raise exception 'Barang masuk tidak perlu dikirim'; end if;
  if d.status <> 'disetujui' then raise exception 'Dokumen belum siap dikirim (status: %)', d.status; end if;
  if d.type in ('kirim_produksi','minta_cabang') then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh mengirim'; end if;
    v_src := 'gudang';
  else
    if v_role <> 'produksi' then raise exception 'Hanya kepala produksi yang boleh mengirim setoran'; end if;
    v_src := 'produksi';
  end if;

  -- penyesuaian jumlah oleh gudang (khusus permintaan cabang, hanya boleh mengurangi)
  if p_lines is not null and jsonb_typeof(p_lines) = 'array' and jsonb_array_length(p_lines) > 0 then
    if d.type <> 'minta_cabang' then raise exception 'Jumlah dokumen ini tidak bisa diubah saat kirim'; end if;
    for v_l in select value from jsonb_array_elements(p_lines) loop
      v_q := (v_l->>'qty')::numeric;
      if v_q is null then continue; end if;
      select qty into v_old from public.doc_lines where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
      if not found then continue; end if;
      if v_q > v_old then raise exception 'Gudang hanya boleh mengurangi jumlah (diminta %)', v_old; end if;
      if v_q <= 0 then
        delete from public.doc_lines where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
        v_changed := true;
      elsif v_q <> v_old then
        update public.doc_lines set qty = v_q where id = (v_l->>'line_id')::uuid and doc_id = p_doc;
        v_changed := true;
      end if;
    end loop;
    select count(*) into n_left from public.doc_lines where doc_id = p_doc;
    if n_left = 0 then raise exception 'Semua barang dihapus. Jika tidak ada yang bisa dikirim, hubungi cabang atau owner.'; end if;
    if v_changed then perform public._log(p_doc, 'jumlah disesuaikan gudang', ''); end if;
  end if;

  for r in select l.item_id, l.qty, l.role, i.name from public.doc_lines l join public.items i on i.id = l.item_id where l.doc_id = p_doc loop
    if d.type = 'setor_jadi' and r.role <> 'pakai' then continue; end if;
    select coalesce(sum(delta), 0) into have from public.stock_ledger where location = v_src and item_id = r.item_id;
    if have < r.qty then raise exception 'Stok % tidak cukup: tersedia %, dibutuhkan %', r.name, have, r.qty; end if;
  end loop;
  for r in select l.item_id, l.qty, l.role from public.doc_lines l where l.doc_id = p_doc loop
    if d.type = 'setor_jadi' and r.role <> 'pakai' then continue; end if;
    insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values (v_src, r.item_id, -r.qty, p_doc, public.me_name());
  end loop;
  update public.docs set status = 'dikirim', sent_at = now() where id = p_doc;
  perform public._log(p_doc, 'dikirim', '');
end $$;

-- 2) BUAT DOKUMEN: tanpa ACC, langsung diproses sesuai jenisnya
create or replace function public.create_doc(p_type text, p_supplier text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.me_role();
  v_branch text := '';
  v_id uuid; v_no text; v_prefix text; v_l jsonb; v_item public.items;
  v_lr text; v_qty numeric; n_pakai int := 0; n_hasil int := 0; r record;
begin
  if auth.uid() is null then raise exception 'Belum login'; end if;
  if p_type in ('masuk','kirim_produksi') then
    if v_role <> 'gudang' then raise exception 'Hanya kepala gudang yang boleh membuat dokumen ini'; end if;
  elsif p_type = 'setor_jadi' then
    if v_role <> 'produksi' then raise exception 'Hanya kepala produksi yang boleh membuat setoran'; end if;
  elsif p_type = 'minta_cabang' then
    if v_role <> 'cabang' then raise exception 'Hanya akun cabang yang boleh membuat permintaan'; end if;
    v_branch := public.me_branch();
    if v_branch = '' then raise exception 'Akun cabang ini belum diberi nama cabang'; end if;
  else
    raise exception 'Jenis dokumen tidak dikenal';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Isi minimal satu barang';
  end if;

  v_prefix := case p_type when 'masuk' then 'BM' when 'kirim_produksi' then 'KP' when 'setor_jadi' then 'SJ' else 'PC' end;
  v_no := v_prefix || to_char(now() at time zone 'Asia/Jakarta', 'YYMMDD') || '-' || lpad((nextval('public.doc_seq') % 10000)::text, 4, '0');

  insert into public.docs (no, type, branch, supplier, note, created_by_name)
  values (v_no, p_type, v_branch, coalesce(p_supplier, ''), coalesce(p_note, ''), public.me_name())
  returning id into v_id;

  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_qty := (v_l->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Jumlah harus lebih dari 0'; end if;
    select * into v_item from public.items where id = (v_l->>'item_id')::uuid and active;
    if not found then raise exception 'Bahan tidak ditemukan atau sudah nonaktif'; end if;
    v_lr := coalesce(nullif(v_l->>'role', ''), 'item');
    if p_type = 'setor_jadi' then
      if v_lr = 'pakai' then
        if v_item.kind <> 'mentah' then raise exception '% bukan bahan mentah', v_item.name; end if;
        n_pakai := n_pakai + 1;
      elsif v_lr = 'hasil' then
        if v_item.kind <> 'jadi' then raise exception '% bukan bahan jadi', v_item.name; end if;
        n_hasil := n_hasil + 1;
      else
        raise exception 'Baris setoran tidak valid';
      end if;
    else
      v_lr := 'item';
      if p_type in ('masuk','kirim_produksi') and v_item.kind <> 'mentah' then raise exception '% bukan bahan mentah', v_item.name; end if;
      if p_type = 'minta_cabang' and v_item.kind <> 'jadi' and not v_item.siap_jual then raise exception '% bukan bahan jadi atau barang siap jual', v_item.name; end if;
    end if;
    insert into public.doc_lines (doc_id, item_id, role, qty, unit_price)
    values (v_id, v_item.id, v_lr, v_qty, coalesce(nullif(v_l->>'unit_price', '')::numeric, 0));
  end loop;

  if p_type = 'setor_jadi' and (n_pakai = 0 or n_hasil = 0) then
    raise exception 'Setoran harus berisi bahan yang dipakai DAN hasil jadi';
  end if;
  perform public._log(v_id, 'dibuat', '');

  -- proses otomatis (tanpa ACC owner)
  if p_type = 'masuk' then
    for r in select item_id, qty from public.doc_lines where doc_id = v_id loop
      insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values ('gudang', r.item_id, r.qty, v_id, public.me_name());
    end loop;
    update public.doc_lines set qty_received = qty where doc_id = v_id;
    update public.docs set status = 'diterima', received_at = now(), received_by_name = public.me_name() where id = v_id;
    perform public._log(v_id, 'stok gudang bertambah', '');
  elsif p_type in ('kirim_produksi','setor_jadi') then
    update public.docs set status = 'disetujui' where id = v_id;
    perform public.send_doc(v_id);   -- stok pengirim dicek & dikurangi; gagal = semua dibatalkan
  else
    update public.docs set status = 'disetujui' where id = v_id;   -- permintaan cabang: antre di gudang
  end if;
  return v_id;
end $$;

-- 3) BATAL: pembuat boleh membatalkan permintaan cabang selama gudang belum mengirim
create or replace function public.cancel_doc(p_doc uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.docs;
begin
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
  if d.created_by is distinct from auth.uid() then raise exception 'Hanya pembuat dokumen yang boleh membatalkan'; end if;
  if not (d.status = 'diajukan' or (d.status = 'disetujui' and d.type = 'minta_cabang')) then
    raise exception 'Dokumen ini sudah diproses dan tidak bisa dibatalkan';
  end if;
  update public.docs set status = 'dibatalkan' where id = p_doc;
  perform public._log(p_doc, 'dibatalkan', '');
end $$;

-- 4) Izin
revoke execute on function public.send_doc(uuid, jsonb) from public, anon;
revoke execute on function public.create_doc(text, text, text, jsonb) from public, anon;
revoke execute on function public.cancel_doc(uuid) from public, anon;
grant execute on function public.send_doc(uuid, jsonb) to authenticated;
grant execute on function public.create_doc(text, text, text, jsonb) to authenticated;
grant execute on function public.cancel_doc(uuid) to authenticated;

notify pgrst, 'reload schema';
