-- =====================================================================
-- GUDANG TITATI - UPDATE: NILAI STOK GUDANG (khusus OWNER)
-- Total nilai rupiah barang yang ada di gudang, per barang dan total.
--  * Nilai = stok gudang sekarang x harga rata-rata beli dari grosir.
--  * Harga rata-rata = total (qty x harga) semua Barang Masuk / total qty masuk.
--  * Barang keluar (ke produksi / ke cabang) mengurangi stok, jadi nilai ikut turun.
--  * Hanya bahan mentah + barang siap jual yang dinilai. Bahan jadi hasil produksi tidak dinilai.
--  * Koreksi stok ikut mengubah nilai (memakai harga rata-rata yang sama).
-- Tidak mengubah fungsi atau tabel lama. Aman diulang, boleh dijalankan kapan saja
-- setelah supabase_setup_gudang.sql dan supabase_update_siap_jual.sql.
-- =====================================================================

create or replace function public.nilai_gudang()
returns table (
  item_id uuid, nama text, kategori text, satuan text, siap_jual boolean,
  stok numeric, harga_rata numeric, nilai numeric
)
language plpgsql stable security definer set search_path = public as $$
begin
  if public.me_role() <> 'owner' then
    raise exception 'Hanya owner yang boleh melihat nilai stok';
  end if;
  return query
  with sisa as (
    select l.item_id as iid, sum(l.delta) as sisa_qty
    from public.stock_ledger l
    where l.location = 'gudang'
    group by l.item_id
    having sum(l.delta) > 0
  ), beli as (
    select dl.item_id as iid, sum(dl.qty) as beli_qty, sum(dl.qty * dl.unit_price) as beli_nilai
    from public.doc_lines dl
    join public.docs d on d.id = dl.doc_id
    where d.type = 'masuk' and d.status = 'diterima' and dl.unit_price > 0
    group by dl.item_id
  )
  select i.id, i.name, i.category, i.unit, coalesce(i.siap_jual, false),
         s.sisa_qty,
         coalesce(b.beli_nilai / nullif(b.beli_qty, 0), 0)::numeric,
         (s.sisa_qty * coalesce(b.beli_nilai / nullif(b.beli_qty, 0), 0))::numeric
  from sisa s
  join public.items i on i.id = s.iid
  left join beli b on b.iid = s.iid
  where i.kind = 'mentah'
  order by 8 desc, i.name;
end $$;

revoke execute on function public.nilai_gudang() from public, anon;
grant execute on function public.nilai_gudang() to authenticated;

notify pgrst, 'reload schema';
