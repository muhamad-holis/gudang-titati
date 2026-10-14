-- =====================================================================
-- GUDANG TITATI - UPDATE: HAPUS & GABUNG BARANG (khusus owner)
-- hapus_barang : barang tanpa riwayat -> dihapus permanen.
--                barang yang sudah punya riwayat transaksi/stok -> tidak dihapus,
--                hanya dinonaktifkan (laporan & riwayat lama tetap benar).
--                Ditolak bila stoknya masih ada.
-- gabung_barang: untuk barang dobel. Seluruh riwayat dan stok barang "dari" dipindah
--                ke barang "ke", lalu barang "dari" dihapus. Jenis dan satuan harus sama.
-- Tidak menimpa fungsi lama. Aman dijalankan kapan saja dan aman diulang.
-- =====================================================================

create or replace function public.hapus_barang(p_item uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_name text; v_lokasi int; v_riwayat boolean;
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang bisa menghapus barang'; end if;
  select name into v_name from public.items where id = p_item;
  if not found then raise exception 'Barang tidak ditemukan'; end if;

  select count(*) into v_lokasi from public.v_stock where item_id = p_item;
  if v_lokasi > 0 then
    raise exception 'Stok "%" masih ada. Kosongkan dulu lewat koreksi stok, atau gabungkan ke barang lain.', v_name;
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

create or replace function public.gabung_barang(p_dari uuid, p_ke uuid) returns void
language plpgsql security definer set search_path = public as $$
declare a public.items; b public.items;
begin
  if public.me_role() <> 'owner' then raise exception 'Hanya owner yang bisa menggabungkan barang'; end if;
  if p_dari = p_ke then raise exception 'Barang asal dan tujuan sama'; end if;
  select * into a from public.items where id = p_dari;
  if not found then raise exception 'Barang asal tidak ditemukan'; end if;
  select * into b from public.items where id = p_ke;
  if not found then raise exception 'Barang tujuan tidak ditemukan'; end if;
  if a.kind <> b.kind then raise exception 'Jenis berbeda (bahan mentah dan bahan jadi tidak bisa digabung)'; end if;
  if lower(trim(a.unit)) <> lower(trim(b.unit)) then
    raise exception 'Satuan berbeda (% dan %). Samakan satuannya dulu di Ubah barang.', a.unit, b.unit;
  end if;

  update public.doc_lines   set item_id = p_ke where item_id = p_dari;
  update public.stock_ledger set item_id = p_ke where item_id = p_dari;
  delete from public.items where id = p_dari;
end $$;

revoke execute on function public.hapus_barang(uuid) from public, anon;
revoke execute on function public.gabung_barang(uuid, uuid) from public, anon;
grant execute on function public.hapus_barang(uuid) to authenticated;
grant execute on function public.gabung_barang(uuid, uuid) to authenticated;
