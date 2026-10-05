-- =====================================================================
-- GUDANG TITATI - UPDATE: ACC OWNER SELEKTIF (hanya titik yang menyangkut uang)
-- Jalankan SETELAH supabase_update_alur_tanpa_acc.sql. Aman diulang.
--
--  1. Barang Masuk (beli grosir): langsung masuk stok, tertanda "Belum diverifikasi
--     owner" sampai di-ACC (satu per satu atau semua sekaligus).
--  2. Setor Hasil Produksi: jalan langsung kalau rendemen wajar; kalau menyimpang
--     dari biasanya -> status "Menunggu ACC", stok belum bergerak.
--  3. Permintaan Cabang: normal langsung antre di gudang; kalau jumlah jauh di atas
--     biasanya -> "Menunggu ACC".
--  Lainnya tanpa ACC (kirim ke produksi, terima barang). Koreksi stok & batal
--  jual hari lain tetap khusus owner (tidak diubah).
-- =====================================================================

-- 1) Kolom baru
alter table public.docs add column if not exists owner_check text not null default 'na';
alter table public.docs drop constraint if exists docs_owner_check_chk;
alter table public.docs add constraint docs_owner_check_chk check (owner_check in ('na','belum','ok','keberatan'));
alter table public.docs add column if not exists flag_reason text not null default '';
alter table public.docs add column if not exists verified_by_name text not null default '';
alter table public.docs add column if not exists verified_at timestamptz;

-- dokumen Barang Masuk lama: yang sudah di-ACC owner = ok, selebihnya belum diverifikasi
update public.docs set owner_check = case when approved_at is not null then 'ok' else 'belum' end,
       verified_by_name = case when approved_at is not null then approved_by_name else '' end,
       verified_at = approved_at
 where type = 'masuk' and owner_check = 'na';

-- 2) Pengaturan batas "menyimpang" (ubah angkanya lewat SQL Editor bila perlu)
create table if not exists public.app_settings (key text primary key, value numeric not null);
insert into public.app_settings (key, value) values
  ('setor_toleransi_persen', 20),  -- rendemen setoran boleh berbeda maks 20% dari biasanya
  ('minta_kelipatan', 2),          -- permintaan cabang > 2x biasanya = perlu ACC
  ('min_riwayat', 3)               -- butuh minimal 3 data lama; kalau kurang, tidak ditandai
on conflict do nothing;
alter table public.app_settings enable row level security;
drop policy if exists p_settings_select on public.app_settings;
create policy p_settings_select on public.app_settings for select to authenticated using (true);
grant select on public.app_settings to authenticated;

create or replace function public._setting(p_key text, p_def numeric) returns numeric
language sql stable security definer set search_path = public as
$$ select coalesce((select value from public.app_settings where key = p_key), p_def) $$;

-- 3) Deteksi menyimpang (kembali '' = wajar)
create or replace function public._flag_setor(p_doc uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_pakai numeric; v_hasil numeric; v_ratio numeric; v_base numeric; v_n int;
begin
  select coalesce(sum(qty) filter (where role = 'pakai'), 0), coalesce(sum(qty) filter (where role = 'hasil'), 0)
    into v_pakai, v_hasil from public.doc_lines where doc_id = p_doc;
  if v_pakai <= 0 then return ''; end if;
  v_ratio := v_hasil / v_pakai;
  select percentile_cont(0.5) within group (order by r), count(*) into v_base, v_n from (
    select sum(l.qty) filter (where l.role = 'hasil') / nullif(sum(l.qty) filter (where l.role = 'pakai'), 0) as r
      from public.docs d join public.doc_lines l on l.doc_id = d.id
     where d.type = 'setor_jadi' and d.id <> p_doc and d.status in ('disetujui','dikirim','diterima')
     group by d.id order by max(d.created_at) desc limit 10) x
   where r is not null;
  if v_n < public._setting('min_riwayat', 3) or v_base is null or v_base <= 0 then return ''; end if;
  if abs(v_ratio - v_base) / v_base * 100 > public._setting('setor_toleransi_persen', 20) then
    return 'Hasil ' || round(v_ratio * 100) || '% dari bahan dipakai, biasanya ' || round(v_base * 100) || '%';
  end if;
  return '';
end $$;

create or replace function public._flag_minta(p_doc uuid) returns text
language plpgsql security definer set search_path = public as $$
declare d public.docs; r record; v_med numeric; v_n int; v_out text := '';
begin
  select * into d from public.docs where id = p_doc;
  for r in select l.item_id, l.qty, i.name, i.unit from public.doc_lines l join public.items i on i.id = l.item_id where l.doc_id = p_doc loop
    select percentile_cont(0.5) within group (order by q), count(*) into v_med, v_n from (
      select l2.qty as q from public.doc_lines l2 join public.docs d2 on d2.id = l2.doc_id
       where d2.type = 'minta_cabang' and d2.branch = d.branch and l2.item_id = r.item_id
         and d2.id <> p_doc and d2.status not in ('ditolak','dibatalkan')
       order by d2.created_at desc limit 10) x;
    if v_n >= public._setting('min_riwayat', 3) and v_med > 0 and r.qty > public._setting('minta_kelipatan', 2) * v_med then
      v_out := v_out || case when v_out = '' then '' else '; ' end
            || r.name || ' ' || trim(to_char(r.qty, 'FM999999990.##')) || ' ' || r.unit
            || ' (biasanya ' || trim(to_char(v_med, 'FM999999990.##')) || ')';
    end if;
  end loop;
  return v_out;
end $$;

-- 4) BUAT DOKUMEN (menggantikan versi sebelumnya)
create or replace function public.create_doc(p_type text, p_supplier text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.me_role();
  v_branch text := '';
  v_id uuid; v_no text; v_prefix text; v_l jsonb; v_item public.items;
  v_lr text; v_qty numeric; n_pakai int := 0; n_hasil int := 0; r record; v_flag text := '';
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

  if p_type = 'masuk' then
    -- stok langsung bertambah; harga & pembelian menunggu verifikasi owner
    for r in select item_id, qty from public.doc_lines where doc_id = v_id loop
      insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values ('gudang', r.item_id, r.qty, v_id, public.me_name());
    end loop;
    update public.doc_lines set qty_received = qty where doc_id = v_id;
    update public.docs set status = 'diterima', received_at = now(), received_by_name = public.me_name(), owner_check = 'belum' where id = v_id;
    perform public._log(v_id, 'stok gudang bertambah (belum diverifikasi owner)', '');
  elsif p_type = 'kirim_produksi' then
    update public.docs set status = 'disetujui' where id = v_id;
    perform public.send_doc(v_id);
  else
    v_flag := case when p_type = 'setor_jadi' then public._flag_setor(v_id) else public._flag_minta(v_id) end;
    if v_flag <> '' then
      -- menyimpang: tetap 'diajukan' (stok belum bergerak) sampai owner memutuskan
      update public.docs set flag_reason = v_flag where id = v_id;
      perform public._log(v_id, 'perlu ACC owner (menyimpang)', v_flag);
    else
      update public.docs set status = 'disetujui' where id = v_id;
      if p_type = 'setor_jadi' then perform public.send_doc(v_id); end if;
    end if;
  end if;
  return v_id;
end $$;

-- 5) Owner verifikasi Barang Masuk
create or replace function public.verify_masuk(p_doc uuid, p_action text, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare d public.docs; v_note text := coalesce(trim(p_note), '');
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh memverifikasi'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found or d.type <> 'masuk' then raise exception 'Dokumen Barang Masuk tidak ditemukan'; end if;
  if d.owner_check not in ('belum','keberatan') then raise exception 'Dokumen ini sudah diverifikasi'; end if;
  if p_action = 'acc' then
    update public.docs set owner_check = 'ok', owner_note = v_note, verified_by_name = public.me_name(), verified_at = now() where id = p_doc;
    perform public._log(p_doc, 'diverifikasi owner', v_note);
  elsif p_action = 'keberatan' then
    if v_note = '' then raise exception 'Alasan keberatan wajib diisi'; end if;
    update public.docs set owner_check = 'keberatan', owner_note = v_note where id = p_doc;
    perform public._log(p_doc, 'owner keberatan', v_note);
  else
    raise exception 'Aksi tidak dikenal';
  end if;
end $$;

create or replace function public.verify_semua_masuk() returns int
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh memverifikasi'; end if;
  with u as (
    update public.docs set owner_check = 'ok', verified_by_name = public.me_name(), verified_at = now()
     where type = 'masuk' and owner_check = 'belum' returning id
  ), l as (
    insert into public.doc_log (doc_id, by_name, by_role, action)
    select id, public.me_name(), 'owner', 'diverifikasi owner (ACC semua)' from u returning 1
  ) select count(*) into v_n from l;
  return v_n;
end $$;

-- 6) Izin
revoke execute on function public.create_doc(text, text, text, jsonb) from public, anon;
revoke execute on function public.verify_masuk(uuid, text, text) from public, anon;
revoke execute on function public.verify_semua_masuk() from public, anon;
revoke execute on function public._flag_setor(uuid) from public, anon, authenticated;
revoke execute on function public._flag_minta(uuid) from public, anon, authenticated;
grant execute on function public.create_doc(text, text, text, jsonb) to authenticated;
grant execute on function public.verify_masuk(uuid, text, text) to authenticated;
grant execute on function public.verify_semua_masuk() to authenticated;

-- 6b) Barang Masuk lama yang di-ACC lewat jalur lama ikut tercatat terverifikasi
create or replace function public.owner_decide(p_doc uuid, p_action text, p_note text default '', p_lines jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare d public.docs; v_changed boolean := false; r record; v_note text := coalesce(trim(p_note), '');
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang boleh memutuskan'; end if;
  select * into d from public.docs where id = p_doc for update;
  if not found then raise exception 'Dokumen tidak ditemukan'; end if;
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
      -- barang masuk: setelah ACC langsung menambah stok gudang
      for r in select item_id, qty from public.doc_lines where doc_id = p_doc loop
        insert into public.stock_ledger (location, item_id, delta, doc_id, by_name) values ('gudang', r.item_id, r.qty, p_doc, public.me_name());
      end loop;
      update public.doc_lines set qty_received = qty where doc_id = p_doc;
      update public.docs set status = 'diterima', received_at = now(), received_by_name = d.created_by_name where id = p_doc;
      perform public._log(p_doc, 'stok gudang bertambah', '');
      update public.docs set owner_check = 'ok', verified_by_name = public.me_name(), verified_at = now() where id = p_doc;
    end if;
  else
    raise exception 'Aksi tidak dikenal';
  end if;
end $$;
revoke execute on function public.owner_decide(uuid, text, text, jsonb) from public, anon;
grant execute on function public.owner_decide(uuid, text, text, jsonb) to authenticated;

notify pgrst, 'reload schema';
