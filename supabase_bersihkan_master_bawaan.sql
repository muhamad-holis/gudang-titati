-- =====================================================================
-- GUDANG TITATI - BERSIHKAN BARANG BAWAAN (OPSIONAL, JALANKAN SEKALI)
-- supabase_master_data.sql memasukkan 51 bahan mentah bawaan yang belum tentu dibeli gudang.
-- File ini menghapus bahan mentah yang BELUM PERNAH dipakai transaksi apa pun
-- (tidak ada di dokumen, tidak ada riwayat stok). Barang yang sudah punya riwayat
-- tidak disentuh. Bahan jadi tidak disentuh.
--
-- LANGKAH:
--  1. Jalankan bagian PREVIEW dulu (select di bawah) dan cek daftarnya.
--  2. Bila sudah sesuai, aktifkan bagian HAPUS (hapus tanda -- di depannya) lalu jalankan.
-- Setelah itu, gudang mengisi daftar barangnya sendiri lewat tombol tambah barang.
-- =====================================================================

-- PREVIEW: barang yang akan dihapus
select name, category, unit
  from public.items i
 where i.kind = 'mentah'
   and not exists (select 1 from public.doc_lines dl where dl.item_id = i.id)
   and not exists (select 1 from public.stock_ledger sl where sl.item_id = i.id)
 order by category, name;

-- HAPUS: hilangkan tanda "--" di depan baris di bawah, lalu jalankan SETELAH preview dicek.
-- delete from public.items i
--  where i.kind = 'mentah'
--    and not exists (select 1 from public.doc_lines dl where dl.item_id = i.id)
--    and not exists (select 1 from public.stock_ledger sl where sl.item_id = i.id);
