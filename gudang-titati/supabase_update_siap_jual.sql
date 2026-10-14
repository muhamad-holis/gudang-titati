-- =====================================================================
-- GUDANG TITATI - UPDATE: BARANG SIAP JUAL (tanpa produksi)
-- Untuk barang yang dibeli jadi dan dijual apa adanya (mis. air mineral):
-- Barang Masuk -> stok gudang -> Permintaan Cabang -> Kirim -> cabang -> dijual.
-- Satu nama barang saja, tidak perlu dobel "mentah" dan "jadi".
--
-- Jalankan SETELAH supabase_setup_gudang.sql dan supabase_update_penjualan.sql.
-- Aman diulang. Jangan menjalankan ulang file penjualan setelah file ini.
-- =====================================================================

-- 1) Penanda barang siap jual (barang tetap berjenis "mentah" agar bisa dibeli lewat Barang Masuk)
alter table public.items add column if not exists siap_jual boolean not null default false;

-- 2) Permintaan cabang boleh berisi bahan jadi ATAU barang siap jual
create or replace function public.create_doc(p_type text, p_supplier text, p_note text, p_lines jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_role text := public.me_role();
  v_branch text := '';
  v_id uuid; v_no text; v_prefix text; v_l jsonb; v_item public.items;
  v_lr text; v_qty numeric; n_pakai int := 0; n_hasil int := 0;
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
  return v_id;
end $$;

-- 3) Cabang boleh mencatat penjualan bahan jadi ATAU barang siap jual
create or replace function public.catat_jual(p_lines jsonb, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare
  v_loc text := public.me_branch();
  v_note text := coalesce(trim(p_note), '');
  v_l jsonb; v_qty numeric; v_item public.items; have numeric;
begin
  if public.me_role() <> 'cabang' then raise exception 'Hanya akun cabang yang boleh mencatat penjualan'; end if;
  if v_loc = '' then raise exception 'Akun cabang ini belum diberi nama cabang'; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Isi minimal satu barang';
  end if;
  for v_l in select value from jsonb_array_elements(p_lines) loop
    v_qty := (v_l->>'qty')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Jumlah harus lebih dari 0'; end if;
    select * into v_item from public.items where id = (v_l->>'item_id')::uuid and (kind = 'jadi' or siap_jual);
    if not found then raise exception 'Barang tidak ditemukan'; end if;
    select coalesce(sum(delta), 0) into have from public.stock_ledger where location = v_loc and item_id = v_item.id;
    if have < v_qty then
      raise exception 'Stok % di % tidak cukup: tersedia %, dicatat terjual %', v_item.name, v_loc, have, v_qty;
    end if;
    insert into public.stock_ledger (location, item_id, delta, kind, reason, by_name)
    values (v_loc, v_item.id, -v_qty, 'jual', v_note, public.me_name());
  end loop;
end $$;

-- 4) Izin (fungsi diganti ulang, izin dipasang lagi)
revoke execute on function public.create_doc(text, text, text, jsonb) from public, anon;
revoke execute on function public.catat_jual(jsonb, text) from public, anon;
grant execute on function public.create_doc(text, text, text, jsonb) to authenticated;
grant execute on function public.catat_jual(jsonb, text) to authenticated;

notify pgrst, 'reload schema';

-- LANGKAH TERAKHIR (manual): tandai barang yang siap jual, mis. air mineral.
-- Cara mudah: di aplikasi, login Owner -> Master -> Bahan mentah -> ketuk barangnya -> nyalakan "Barang siap jual".
-- Atau lewat SQL (ganti nama barang):
--   update public.items set siap_jual = true where kind = 'mentah' and lower(name) = 'air mineral';
