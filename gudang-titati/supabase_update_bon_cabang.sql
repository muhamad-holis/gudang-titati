-- =====================================================================
-- GUDANG TITATI - UPDATE: BON CABANG (surat jalan bernilai, versi ringan)
-- Setiap pengiriman ke cabang (Permintaan Cabang & Kirim ke Cabang) membawa harga.
-- Harga = harga rata-rata beli dari grosir (dari Barang Masuk yang diterima),
-- dikunci (snapshot) ke baris dokumen SAAT DIKIRIM, jadi perubahan harga beli
-- sesudahnya tidak mengubah bon lama.
-- Barang yang belum pernah dibeli lewat Barang Masuk (mis. bakso hasil produksi)
-- tetap berharga 0 dan tampil "-" di bon.
--
-- Tidak mengganti fungsi lama (send_doc, create_doc, dll), jadi AMAN dijalankan
-- kapan saja setelah supabase_update_nilai_periode.sql. Aman diulang.
-- =====================================================================

-- 1) Kunci harga saat status dokumen berubah menjadi 'dikirim'
create or replace function public._kunci_harga_bon() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.type in ('minta_cabang', 'kirim_cabang')
     and new.status = 'dikirim' and old.status is distinct from 'dikirim' then
    update public.doc_lines dl
       set unit_price = public._harga_rata(dl.item_id, coalesce(new.sent_at, now()))
     where dl.doc_id = new.id and dl.unit_price = 0;
  end if;
  return new;
end $$;

drop trigger if exists trg_kunci_harga_bon on public.docs;
create trigger trg_kunci_harga_bon
  after update of status on public.docs
  for each row execute function public._kunci_harga_bon();

-- 2) Isi harga untuk pengiriman cabang yang SUDAH ADA (dikirim / diterima, harga masih 0)
update public.doc_lines dl
   set unit_price = public._harga_rata(dl.item_id, coalesce(d.sent_at, d.created_at))
  from public.docs d
 where d.id = dl.doc_id
   and d.type in ('minta_cabang', 'kirim_cabang')
   and d.status in ('dikirim', 'diterima')
   and dl.unit_price = 0;

-- Cek hasil (opsional): pengiriman cabang terakhir beserta nilainya
-- select d.no, d.branch, d.status, sum(dl.qty * dl.unit_price) as nilai
--   from public.docs d join public.doc_lines dl on dl.doc_id = d.id
--  where d.type in ('minta_cabang','kirim_cabang')
--  group by d.no, d.branch, d.status, d.created_at order by d.created_at desc limit 10;
