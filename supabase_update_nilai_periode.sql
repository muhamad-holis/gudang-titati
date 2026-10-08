-- =====================================================================
-- GUDANG TITATI - UPDATE: NILAI STOK PER PERIODE, TREN, STOK MINIMUM
-- Menambah (tanpa mengubah fungsi/tabel lama selain 1 kolom baru):
--  1. kolom items.stok_min      : batas stok minimum per barang (0 = tidak dipantau)
--  2. _harga_rata()             : harga rata-rata beli sampai waktu tertentu (fungsi bantu)
--  3. nilai_gudang_periode()    : nilai awal, masuk, keluar, akhir per barang untuk rentang tanggal
--  4. nilai_gudang_tren()       : total nilai stok gudang per hari
-- Hanya OWNER yang boleh memanggil fungsi nilai (dicek di dalam fungsi).
-- Tanggal dihitung zona waktu WIB (Asia/Jakarta), 00:00 sampai 23:59.
-- Harga = rata-rata tertimbang Barang Masuk (status diterima) SAMPAI tanggal itu.
-- Bila belum ada pembelian sebelum tanggal itu, dipakai harga rata-rata keseluruhan.
-- Aman diulang. Jalankan setelah supabase_update_nilai_gudang.sql.
-- =====================================================================

alter table public.items add column if not exists stok_min numeric not null default 0;

create or replace function public._harga_rata(p_item uuid, p_sebelum timestamptz)
returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select sum(dl.qty * dl.unit_price) / nullif(sum(dl.qty), 0)
       from public.doc_lines dl join public.docs d on d.id = dl.doc_id
      where dl.item_id = p_item and d.type = 'masuk' and d.status = 'diterima' and dl.unit_price > 0
        and coalesce(d.received_at, d.created_at) < p_sebelum),
    (select sum(dl.qty * dl.unit_price) / nullif(sum(dl.qty), 0)
       from public.doc_lines dl join public.docs d on d.id = dl.doc_id
      where dl.item_id = p_item and d.type = 'masuk' and d.status = 'diterima' and dl.unit_price > 0),
    0)::numeric
$$;

revoke execute on function public._harga_rata(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.nilai_gudang_periode(p_dari date, p_sampai date)
returns table (
  item_id uuid, nama text, kategori text, satuan text, siap_jual boolean,
  qty_awal numeric, qty_masuk numeric, qty_keluar numeric, qty_akhir numeric,
  harga_awal numeric, harga_akhir numeric, terakhir_gerak timestamptz
)
language plpgsql stable security definer set search_path = public as $$
declare
  t0 timestamptz;
  t1 timestamptz;
begin
  if public.me_role() <> 'owner' then
    raise exception 'Hanya owner yang boleh melihat nilai stok';
  end if;
  if p_dari is null or p_sampai is null or p_sampai < p_dari then
    raise exception 'Rentang tanggal tidak valid';
  end if;
  t0 := p_dari::timestamp at time zone 'Asia/Jakarta';
  t1 := (p_sampai + 1)::timestamp at time zone 'Asia/Jakarta';
  return query
  with g as (
    select l.item_id as iid,
           coalesce(sum(l.delta) filter (where l.at < t0), 0) as awal,
           coalesce(sum(l.delta) filter (where l.at >= t0 and l.at < t1 and l.delta > 0), 0) as masuk,
           coalesce(-sum(l.delta) filter (where l.at >= t0 and l.at < t1 and l.delta < 0), 0) as keluar,
           coalesce(sum(l.delta) filter (where l.at < t1), 0) as akhir,
           max(l.at) filter (where l.at < t1) as terakhir
    from public.stock_ledger l
    where l.location = 'gudang'
    group by l.item_id
  )
  select i.id, i.name, i.category, i.unit, coalesce(i.siap_jual, false),
         g.awal, g.masuk, g.keluar, g.akhir,
         public._harga_rata(i.id, t0), public._harga_rata(i.id, t1), g.terakhir
  from g join public.items i on i.id = g.iid
  where i.kind = 'mentah' and (g.awal <> 0 or g.masuk <> 0 or g.keluar <> 0 or g.akhir <> 0)
  order by i.name;
end $$;

revoke execute on function public.nilai_gudang_periode(date, date) from public, anon;
grant execute on function public.nilai_gudang_periode(date, date) to authenticated;

create or replace function public.nilai_gudang_tren(p_dari date, p_sampai date)
returns table (hari date, nilai numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.me_role() <> 'owner' then
    raise exception 'Hanya owner yang boleh melihat nilai stok';
  end if;
  if p_dari is null or p_sampai is null or p_sampai < p_dari then
    raise exception 'Rentang tanggal tidak valid';
  end if;
  if p_sampai - p_dari > 92 then
    raise exception 'Tren maksimal 93 hari';
  end if;
  return query
  select h.hari::date,
         coalesce(sum(q.qty * public._harga_rata(q.iid, h.akhir)), 0)::numeric
  from (
    select gs::date as hari, ((gs::date + 1)::timestamp at time zone 'Asia/Jakarta') as akhir
    from generate_series(p_dari::timestamp, p_sampai::timestamp, interval '1 day') gs
  ) h
  left join lateral (
    select l.item_id as iid, sum(l.delta) as qty
    from public.stock_ledger l join public.items i on i.id = l.item_id and i.kind = 'mentah'
    where l.location = 'gudang' and l.at < h.akhir
    group by l.item_id
    having sum(l.delta) > 0
  ) q on true
  group by h.hari
  order by h.hari;
end $$;

revoke execute on function public.nilai_gudang_tren(date, date) from public, anon;
grant execute on function public.nilai_gudang_tren(date, date) to authenticated;

notify pgrst, 'reload schema';
