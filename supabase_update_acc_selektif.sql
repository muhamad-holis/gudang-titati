-- =====================================================================
-- GUDANG TITATI - UPDATE: ACC OWNER SELEKTIF
-- ACC owner hanya dipasang di titik yang menyangkut uang / tidak bisa dicek orang lain.
--
-- Jika supabase_master_data.sql sudah dijalankan, JANGAN jalankan ulang file ini (create_doc akan tertimpa).
-- Jalankan SETELAH: supabase_setup_gudang.sql, supabase_update_penjualan.sql,
-- supabase_update_siap_jual.sql, supabase_update_alur_tanpa_acc.sql. Aman diulang.
--
-- Aturan:
--  1. Barang Masuk   : stok langsung masuk (harga WAJIB diisi). Dokumen ditandai
--                      "Belum diverifikasi owner" sampai owner ACC (atau tolak).
--  2. Setor Produksi : jalan langsung jika hasil wajar menurut rendemen standar;
--                      menyimpang / belum ada standar -> tertahan, menunggu ACC owner.
--  3. Permintaan Cabang: normal langsung antre di gudang; jika jumlah jauh di atas
--                      biasanya (rata-rata permintaan cabang itu) -> menunggu ACC owner.
--  4. Lainnya tanpa ACC. Koreksi stok & pembatalan penjualan hari lain tetap hanya owner.
-- =====================================================================

-- 1) KOLOM BARU
alter table public.items add column if not exists rendemen_std numeric;
alter table public.items drop constraint if exists items_rendemen_std_check;
alter table public.items add constraint items_rendemen_std_check check (rendemen_std is null or rendemen_std > 0);

alter table public.docs add column if not exists verif text not null default '';
alter table public.docs drop constraint if exists docs_verif_check;
alter table public.docs add constraint docs_verif_check check (verif in ('', 'menunggu', 'ok', 'tolak'));
alter table public.docs add column if not exists acc_reason text not null default '';

-- 2) ATURAN (satu baris, diubah owner lewat fungsi set_rules)
create table if not exists public.app_rules (
  id int primary key default 1 check (id = 1),
  rendemen_toleransi numeric not null default 15 check (rendemen_toleransi >= 0),
  minta_faktor numeric not null default 2 check (minta_faktor > 1),
  minta_hari int not null default 28 check (minta_hari > 0),
  minta_min_data int not null default 3 check (minta_min_data >= 1)
);
insert into public.app_rules (id) values (1) on conflict (id) do nothing;
alter table public.app_rules enable row level security;
drop policy if exists p_rules_select on public.app_rules;
create policy p_rules_select on public.app_rules for select to authenticated using (true);
grant select on public.app_rules to authenticated;

create or replace function public.set_rules(p_toleransi numeric, p_faktor numeric, p_hari int, p_min int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh mengubah aturan'; end if;
  if p_toleransi is null or p_toleransi < 0 or p_toleransi > 100 then raise exception 'Toleransi harus antara 0 dan 100 persen'; end if;
  if p_faktor is null or p_faktor <= 1 then raise exception 'Batas permintaan harus lebih dari 1 kali'; end if;
  if p_hari is null or p_hari < 1 then raise exception 'Jumlah hari minimal 1'; end if;
  if p_min is null or p_min < 1 then raise exception 'Minimal data minimal 1'; end if;
  update public.app_rules
     set rendemen_toleransi = p_toleransi, minta_faktor = p_faktor, minta_hari = p_hari, minta_min_data = p_min
   where id = 1;
end $$;

-- 3) PENGECEKAN PENYIMPANGAN (fungsi dalam, tidak dipanggil dari aplikasi)
-- Setoran: tiap hasil dikonversi lewat rendemen standar bahan jadinya menjadi
-- "bahan yang seharusnya terpakai". Dibandingkan dengan bahan yang dicatat terpakai.
-- Catatan: bahan yang dipakai dijumlahkan apa adanya, jadi satuannya sebaiknya sama (mis. kg).
create or replace function public._setor_alasan(p_doc uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_tol numeric; v_pakai numeric; v_exp numeric := 0; v_dev numeric; v_nostd text := ''; r record;
begin
  select rendemen_toleransi into v_tol from public.app_rules where id = 1;
  v_tol := coalesce(v_tol, 15);
  select coalesce(sum(qty), 0) into v_pakai from public.doc_lines where doc_id = p_doc and role = 'pakai';
  for r in
    select l.qty, i.name, i.rendemen_std
      from public.doc_lines l join public.items i on i.id = l.item_id
     where l.doc_id = p_doc and l.role = 'hasil'
  loop
    if r.rendemen_std is null or r.rendemen_std <= 0 then
      v_nostd := v_nostd || case when v_nostd = '' then '' else ', ' end || r.name;
    else
      v_exp := v_exp + r.qty / r.rendemen_std;
    end if;
  end loop;
  if v_nostd <> '' then
    return 'Belum ada standar rendemen untuk ' || v_nostd;
  end if;
  if v_exp <= 0 then return ''; end if;
  v_dev := (v_pakai - v_exp) / v_exp * 100;
  if abs(v_dev) > v_tol then
    return 'Bahan dipakai ' || trim_scale(round(v_pakai, 2))::text
        || ', menurut standar hasil ini butuh sekitar ' || trim_scale(round(v_exp, 2))::text
        || ' (' || case when v_dev > 0 then '+' else '' end || round(v_dev)::text
        || '%, batas ±' || trim_scale(round(v_tol, 1))::text || '%)';
  end if;
  return '';
end $$;

-- Permintaan cabang: bandingkan tiap barang dengan rata-rata permintaan yang sudah dikirim
-- oleh cabang yang sama dalam N hari terakhir. Data kurang dari minimum = tidak dianggap menyimpang.
create or replace function public._minta_alasan(p_doc uuid, p_branch text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_faktor numeric; v_hari int; v_min int; v_out text := ''; r record; v_n int; v_avg numeric;
begin
  select minta_faktor, minta_hari, minta_min_data into v_faktor, v_hari, v_min from public.app_rules where id = 1;
  v_faktor := coalesce(v_faktor, 2); v_hari := coalesce(v_hari, 28); v_min := coalesce(v_min, 3);
  for r in
    select l.item_id, l.qty, i.name, i.unit
      from public.doc_lines l join public.items i on i.id = l.item_id
     where l.doc_id = p_doc
  loop
    select count(*), avg(l2.qty) into v_n, v_avg
      from public.doc_lines l2 join public.docs d2 on d2.id = l2.doc_id
     where d2.type = 'minta_cabang' and d2.branch = p_branch and d2.id <> p_doc
       and d2.status in ('dikirim', 'diterima')
       and d2.created_at >= now() - make_interval(days => v_hari)
       and l2.item_id = r.item_id;
    if v_n >= v_min and v_avg > 0 and r.qty > v_avg * v_faktor then
      v_out := v_out || case when v_out = '' then '' else '; ' end
            || r.name || ' diminta ' || trim_scale(round(r.qty, 2))::text || ' ' || r.unit
            || ', biasanya sekitar ' || trim_scale(round(v_avg, 2))::text;
    end if;
  end loop;
  return v_out;
end $$;

revoke execute on function public._setor_alasan(uuid) from public, anon, authenticated;
revoke execute on function public._minta_alasan(uuid, text) from public, anon, authenticated;

-- 4) BUAT DOKUMEN
create or replace function public.create_doc(p_type text, p_supplier text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.me_role();
  v_branch text := '';
  v_id uuid; v_no text; v_prefix text; v_l jsonb; v_item public.items;
  v_lr text; v_qty numeric; v_price numeric; n_pakai int := 0; n_hasil int := 0; r record;
  v_alasan text := '';
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
    v_price := coalesce(nullif(v_l->>'unit_price', '')::numeric, 0);
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
      if p_type = 'masuk' and v_price <= 0 then raise exception 'Harga satuan % wajib diisi', v_item.name; end if;
    end if;
    insert into public.doc_lines (doc_id, item_id, role, qty, unit_price)
    values (v_id, v_item.id, v_lr, v_qty, v_price);
  end loop;

  if p_type = 'setor_jadi' and (n_pakai = 0 or n_hasil = 0) then
    raise exception 'Setoran harus berisi bahan yang dipakai DAN hasil jadi';
  end if;
  perform public._log(v_id, 'dibuat', '');

  if p_type = 'masuk' then
    -- stok langsung bertambah; owner memverifikasi harga/pembelian menyusul
    for r in select item_id, qty from public.doc_lines where doc_id = v_id loop
      insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values ('gudang', r.item_id, r.qty, v_id, public.me_name());
    end loop;
    update public.doc_lines set qty_received = qty where doc_id = v_id;
    update public.docs set status = 'diterima', received_at = now(), received_by_name = public.me_name(), verif = 'menunggu' where id = v_id;
    perform public._log(v_id, 'stok gudang bertambah', 'belum diverifikasi owner');
  elsif p_type = 'kirim_produksi' then
    update public.docs set status = 'disetujui' where id = v_id;
    perform public.send_doc(v_id);
  elsif p_type = 'setor_jadi' then
    v_alasan := public._setor_alasan(v_id);
    if v_alasan = '' then
      update public.docs set status = 'disetujui' where id = v_id;
      perform public.send_doc(v_id);
    else
      update public.docs set status = 'diajukan', acc_reason = v_alasan where id = v_id;
      perform public._log(v_id, 'menunggu ACC owner (menyimpang)', v_alasan);
    end if;
  else
    v_alasan := public._minta_alasan(v_id, v_branch);
    if v_alasan = '' then
      update public.docs set status = 'disetujui' where id = v_id;   -- antre di gudang
    else
      update public.docs set status = 'diajukan', acc_reason = v_alasan where id = v_id;
      perform public._log(v_id, 'menunggu ACC owner (jumlah jauh di atas biasanya)', v_alasan);
    end if;
  end if;
  return v_id;
end $$;

-- 5) KEPUTUSAN OWNER
-- a) Barang masuk yang belum diverifikasi (stok sudah masuk): ACC = harga/pembelian disetujui.
--    Tolak = ditandai ditolak beserta alasan, stok TIDAK ditarik (barang sudah ada secara fisik);
--    owner menindaklanjuti ke gudang, dan jika perlu mengoreksi stok.
-- b) Dokumen berstatus "diajukan" (setoran / permintaan menyimpang, atau dokumen lama): seperti sebelumnya.
create or replace function public.owner_decide(p_doc uuid, p_action text, p_note text default '', p_lines jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare d public.docs; v_changed boolean := false; r record; v_note text := coalesce(trim(p_note), '');
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh memutuskan'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;

  if d.type = 'masuk' and d.verif = 'menunggu' then
    if p_action = 'tolak' then
      if v_note = '' then raise exception 'Alasan penolakan wajib diisi'; end if;
      update public.docs set verif = 'tolak', owner_note = v_note, approved_by_name = public.me_name(), approved_at = now() where id = p_doc;
      perform public._log(p_doc, 'pembelian ditolak owner', v_note);
    elsif p_action = 'acc' then
      update public.docs set verif = 'ok', owner_note = v_note, approved_by_name = public.me_name(), approved_at = now() where id = p_doc;
      perform public._log(p_doc, 'pembelian diverifikasi owner', v_note);
    else
      raise exception 'Aksi tidak dikenal';
    end if;
    return;
  end if;

  if d.status <> 'diajukan' then raise exception 'Dokumen sudah diproses (status: %)', d.status; end if;

  if p_action = 'tolak' then
    if v_note = '' then raise exception 'Alasan penolakan wajib diisi'; end if;
    update public.docs set status = 'ditolak', owner_note = v_note, approved_by_name = public.me_name(), approved_at = now() where id = p_doc;
    perform public._log(p_doc, 'ditolak', v_note);
  elsif p_action = 'acc' then
    v_changed := public._apply_edits(p_doc, p_lines);
    update public.docs set status = 'disetujui', owner_note = v_note, approved_by_name = public.me_name(), approved_at = now() where id = p_doc;
    perform public._log(p_doc, case when v_changed then 'disetujui (jumlah diubah owner)' else 'disetujui' end, v_note);
    if d.type = 'masuk' then
      -- dokumen barang masuk lama (sebelum alur tanpa ACC): setelah ACC baru menambah stok
      for r in select item_id, qty from public.doc_lines where doc_id = p_doc loop
        insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values ('gudang', r.item_id, r.qty, p_doc, public.me_name());
      end loop;
      update public.doc_lines set qty_received = qty where doc_id = p_doc;
      update public.docs set status = 'diterima', received_at = now(), received_by_name = d.created_by_name where id = p_doc;
      perform public._log(p_doc, 'stok gudang bertambah', '');
    end if;
  else
    raise exception 'Aksi tidak dikenal';
  end if;
end $$;

-- 6) IZIN
revoke execute on function public.create_doc(text, text, text, jsonb) from public, anon;
revoke execute on function public.owner_decide(uuid, text, text, jsonb) from public, anon;
revoke execute on function public.set_rules(numeric, numeric, int, int) from public, anon;
grant execute on function public.create_doc(text, text, text, jsonb) to authenticated;
grant execute on function public.owner_decide(uuid, text, text, jsonb) to authenticated;
grant execute on function public.set_rules(numeric, numeric, int, int) to authenticated;

notify pgrst, 'reload schema';

-- LANGKAH TERAKHIR (di aplikasi): login Owner -> Master -> Bahan jadi -> ketuk tiap bahan jadi
-- -> isi "Rendemen standar". Selama belum diisi, setoran bahan jadi itu selalu minta ACC owner.
