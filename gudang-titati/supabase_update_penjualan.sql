-- =====================================================================
-- GUDANG TITATI - UPDATE: PENJUALAN CABANG (barang terjual vs barang masuk)
-- Jalankan SETELAH supabase_setup_gudang.sql. Aman diulang.
-- Supabase -> SQL Editor -> New query -> paste SEMUA -> Run.
-- =====================================================================

-- 1) Ledger boleh mencatat penjualan dan pembatalannya
alter table public.stock_ledger add column if not exists ref_id bigint;
alter table public.stock_ledger drop constraint if exists stock_ledger_kind_check;
alter table public.stock_ledger add constraint stock_ledger_kind_check
  check (kind in ('doc', 'koreksi', 'jual', 'jual_batal'));

-- 2) Rekap harian per cabang per bahan: masuk (diterima dari gudang) vs terjual
create or replace view public.v_rekap_harian with (security_invoker = true) as
  select (l.at at time zone 'Asia/Jakarta')::date as hari,
         l.location, l.item_id, i.name, i.category, i.unit,
         coalesce(sum(l.delta) filter (where l.kind = 'doc' and l.delta > 0), 0) as masuk,
         coalesce(-sum(l.delta) filter (where l.kind in ('jual', 'jual_batal')), 0) as terjual
  from public.stock_ledger l join public.items i on i.id = l.item_id
  where l.location not in ('gudang', 'produksi')
  group by 1, 2, 3, 4, 5, 6
  having coalesce(sum(l.delta) filter (where l.kind = 'doc' and l.delta > 0), 0) <> 0
      or coalesce(-sum(l.delta) filter (where l.kind in ('jual', 'jual_batal')), 0) <> 0;

-- 3) Cabang mencatat barang terjual. p_lines: [{"item_id":"...","qty":5}]
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
    select * into v_item from public.items where id = (v_l->>'item_id')::uuid and kind = 'jadi';
    if not found then raise exception 'Barang tidak ditemukan'; end if;
    select coalesce(sum(delta), 0) into have from public.stock_ledger where location = v_loc and item_id = v_item.id;
    if have < v_qty then
      raise exception 'Stok % di % tidak cukup: tersedia %, dicatat terjual %', v_item.name, v_loc, have, v_qty;
    end if;
    insert into public.stock_ledger (location, item_id, delta, kind, reason, by_name)
    values (v_loc, v_item.id, -v_qty, 'jual', v_note, public.me_name());
  end loop;
end $$;

-- 4) Batalkan catatan penjualan (cabang: hanya hari ini; owner: kapan saja). Stok dikembalikan.
create or replace function public.batal_jual(p_ledger bigint) returns void
language plpgsql security definer set search_path = public as $$
declare r public.stock_ledger;
begin
  select * into r from public.stock_ledger where id = p_ledger for update;
  if not found or r.kind <> 'jual' then raise exception 'Catatan penjualan tidak ditemukan'; end if;
  if exists (select 1 from public.stock_ledger where kind = 'jual_batal' and ref_id = p_ledger) then
    raise exception 'Catatan ini sudah dibatalkan';
  end if;
  if public.me_role() = 'owner' then
    null;
  elsif public.me_role() = 'cabang' and r.location = public.me_branch() then
    if (r.at at time zone 'Asia/Jakarta')::date <> (now() at time zone 'Asia/Jakarta')::date then
      raise exception 'Hanya catatan hari ini yang bisa dibatalkan. Hubungi owner.';
    end if;
  else
    raise exception 'Tidak diizinkan membatalkan catatan ini';
  end if;
  insert into public.stock_ledger (location, item_id, delta, kind, reason, by_name, ref_id)
  values (r.location, r.item_id, -r.delta, 'jual_batal', 'Dibatalkan oleh ' || public.me_name(), public.me_name(), r.id);
end $$;

-- 5) Izin
grant select on public.v_rekap_harian to authenticated;
revoke execute on function public.catat_jual(jsonb, text) from public, anon;
revoke execute on function public.batal_jual(bigint) from public, anon;
grant execute on function public.catat_jual(jsonb, text) to authenticated;
grant execute on function public.batal_jual(bigint) to authenticated;

notify pgrst, 'reload schema';
