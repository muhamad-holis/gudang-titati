# GUDANG TITATI - Panduan Setup

Aplikasi gudang/inventori TERPISAH dari aplikasi kasir. Project Supabase sendiri, akun sendiri.

## 1. Buat project Supabase baru
- supabase.com -> New project (jangan pakai project kasir).
- SQL Editor -> New query -> paste isi `supabase_setup_gudang.sql` -> Run.

## 2. Buat 6 akun
Authentication -> Users -> Add user (centang *Auto Confirm User*), contoh:
owner@titati.com, gudang@titati.com, produksi@titati.com,
ciomas@titati.com, ciracas@titati.com, ciruas@titati.com
Lalu jalankan `supabase_akun_gudang.sql` (ganti email di dalamnya bila Anda memakai email lain).
Hasil cek harus menampilkan 6 baris dengan peran yang benar.

## 3. Repo GitHub baru + Secrets
- Buat repo baru (mis. `gudang-titati`), push isi folder ini.
- Settings -> Secrets and variables -> Actions:
  - `SUPABASE_URL`  = Project URL (project gudang)
  - `SUPABASE_ANON_KEY` = anon public key (project gudang)
- Build berjalan otomatis; APK ada di Actions -> Artifacts. Tag `v*` juga membuat Release.

## 4. Alur pemakaian (ACC owner selektif)
ACC owner hanya dipasang di titik yang menyangkut uang atau tidak bisa dicek orang lain. Titik lain dijaga oleh penerima yang menghitung fisik.

1. **Barang Masuk (wajib ACC owner, tapi tidak menghambat gudang)**: kepala gudang mencatat pembelian dari grosir, harga satuan WAJIB diisi. Stok gudang langsung bertambah, dokumen ditandai "Belum diverifikasi owner" sampai di-ACC. Owner bisa ACC satu per satu atau lewat tombol "ACC semua pembelian" di Beranda. Jika owner menolak, alasan wajib diisi; stok yang sudah masuk tidak ditarik (barangnya sudah ada), owner menindaklanjuti dan bila perlu mengoreksi stok.
2. **Gudang ke Produksi (tanpa ACC)**: langsung terkirim, kepala produksi Terima.
3. **Setor Hasil Produksi (ACC hanya jika menyimpang)**: hasil jadi dihitung kembali ke bahan mentah lewat *rendemen standar* tiap bahan jadi. Jika bahan yang dipakai berbeda dari perhitungan lebih dari toleransi (bawaan 15%), setoran menunggu ACC owner dan stok belum bergerak. Jika wajar, langsung terkirim dan kepala gudang Terima. Bahan jadi yang belum punya standar rendemen selalu minta ACC.
4. **Permintaan Cabang (tanpa ACC, kecuali jauh di atas biasanya)**: antre di gudang, gudang boleh mengurangi jumlah sesuai stok lalu Kirim, cabang Terima. Jika jumlah satu barang lebih dari 2 kali rata-rata permintaan cabang itu dalam 28 hari terakhir (minimal 3 permintaan sebelumnya), menunggu ACC owner.
5. **Terima barang (tanpa ACC)**: penerima menghitung fisik; selisih otomatis tampil merah di owner.
6. Cabang: Catat Penjualan (tab Jual hanya tampil di akun cabang). Rekap penjualan menampilkan per barang: Masuk, Terjual, dan Sisa (stok cabang sekarang). Kotak merah "Barang kurang diterima" muncul hanya jika barang yang diterima cabang lebih sedikit dari yang dikirim gudang. Pembatalan catatan penjualan hari lain hanya bisa dilakukan owner.
7. Owner: memantau semua dokumen, stok, dan penjualan. Beranda owner menampilkan "Perlu dipantau" (selisih terima / tertahan > 24 jam). Koreksi stok hanya owner (wajib alasan).

### Master data bahan dan jalur barang
Jalankan `supabase_master_data.sql` (paling akhir) untuk memasukkan 51 barang dari PDF master data. Tiap bahan mentah punya **jalur**:
- **Diolah di produksi** (6): daging sapi, lemak sapi, tapioka, sagu, es batu, baking powder. Hanya muncul di pilihan Kirim ke Produksi.
- **Keduanya** (9): daging ayam, tetelan sapi, tepung terigu, garam, gula pasir, merica bubuk, bawang putih, bawang merah, penyedap rasa. Bisa dikirim ke produksi dan diminta cabang.
- **Langsung ke cabang** (36): mie telur, telur, minyak, kecap dan saus, sayuran, saus meja, kemasan, dll. Gudang mengirim langsung ke cabang lewat Permintaan Cabang, tanpa produksi, dan tidak muncul di Catat Penjualan.
Jalur bisa diubah owner: Master -> Bahan mentah -> ketuk barang -> pilih Jalur barang. Barang jadi hasil produksi (bakso, dll) tidak ada di PDF, tambahkan lewat Master -> Bahan jadi.

### Nota / faktur
Tiap dokumen punya nota. Buka dokumen, lalu ketuk tombol "Lihat faktur/surat jalan" atau ikon nota di pojok kanan atas.
- Barang Masuk tampil sebagai *Faktur Pembelian* (harga, subtotal, total, cap status verifikasi owner, tanda tangan kepala gudang dan owner).
- Permintaan cabang tampil sebagai *Surat Jalan*; kirim ke produksi dan setor hasil sebagai *Bukti Serah Terima*. Kolomnya Dikirim, Diterima, Kurang (baris yang kurang berwarna merah), tanpa harga.
- Tombol *Bagikan PDF* mengirim nota lewat WhatsApp/email atau menyimpannya; tombol *Cetak* memakai menu cetak Android.
- Memakai paket Flutter `pdf` dan `printing`; tidak ada perubahan SQL.

### Langkah setelah SQL update
- Jalankan `supabase_update_acc_selektif.sql` SETELAH `supabase_update_alur_tanpa_acc.sql` (urutan: setup, penjualan, siap_jual, alur_tanpa_acc, acc_selektif). Aman diulang.
- Login Owner -> Master -> Bahan jadi -> ketuk tiap bahan -> isi *Rendemen standar* (hasil jadi per 1 satuan bahan mentah, mis. 10 kg jadi 12 kg: isi 1,2). Satuan bahan yang dipakai pada setoran sebaiknya sama (mis. semua kg).
- Toleransi rendemen dan batas permintaan cabang bisa diubah di Master -> Aturan ACC.
- Dokumen lama berstatus "Menunggu ACC" tetap bisa di-ACC owner.

## Aturan penting
- Stok pengirim berkurang saat dikirim; stok penerima bertambah hanya setelah penerima menekan Terima.
- Jumlah diterima bisa lebih kecil dari yang dikirim; selisih tercatat dan ditandai merah untuk owner.
- Semua aksi tercatat (siapa, kapan) di bagian Riwayat tiap dokumen.
- Daftar bahan baru bisa ditambah langsung saat membuat dokumen; owner bisa mengubah/menonaktifkan di tab Master.
- Aplikasi belum punya ikon khusus (memakai ikon bawaan). Tambahkan folder `android_res/` bila sudah ada.
- Aplikasi belum punya fitur lupa password; reset lewat Supabase (Authentication -> Users).
