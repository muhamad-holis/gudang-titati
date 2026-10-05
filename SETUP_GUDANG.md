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
1. Kepala gudang: Barang Masuk (dari grosir) -> stok langsung bertambah, dokumen "Belum diverifikasi owner" sampai di-ACC (tombol "ACC semua pembelian" ada di Beranda owner; hanya untuk Barang Masuk).
2. Kepala gudang: Kirim ke Produksi -> langsung terkirim -> kepala produksi Terima.
3. Kepala produksi: Setor Hasil Produksi -> kalau hasil wajar langsung terkirim -> kepala gudang Terima. Kalau jauh dari biasanya -> Menunggu ACC owner (stok belum bergerak).
4. Cabang: Minta Bahan Jadi -> antre di gudang (kalau jumlah jauh di atas biasanya: menunggu ACC owner dulu) -> gudang boleh mengurangi jumlah sesuai stok lalu Kirim -> cabang Terima.
5. Cabang: Catat Penjualan (tab Jual hanya tampil di akun cabang).
6. Owner: memantau semua dokumen, stok, dan penjualan. Beranda owner menampilkan "Perlu dipantau" (selisih terima / tertahan > 24 jam). Owner tetap bisa koreksi stok (wajib alasan) dan kelola Master.

> Jalankan `supabase_update_alur_tanpa_acc.sql`, lalu `supabase_update_acc_selektif.sql`, SETELAH tiga file SQL lainnya. Batas "menyimpang" (toleransi 20%, kelipatan 2x, min. 3 data lama) ada di tabel `app_settings`. Dokumen menyimpang (setoran/permintaan cabang) selalu diputuskan owner satu per satu. Dokumen lama berstatus "Menunggu ACC" tetap bisa di-ACC owner.

## Aturan penting
- Stok pengirim berkurang saat dikirim; stok penerima bertambah hanya setelah penerima menekan Terima.
- Jumlah diterima bisa lebih kecil dari yang dikirim; selisih tercatat dan ditandai merah untuk owner.
- Semua aksi tercatat (siapa, kapan) di bagian Riwayat tiap dokumen.
- Daftar bahan baru bisa ditambah langsung saat membuat dokumen; owner bisa mengubah/menonaktifkan di tab Master.
- Aplikasi belum punya ikon khusus (memakai ikon bawaan). Tambahkan folder `android_res/` bila sudah ada.
- Aplikasi belum punya fitur lupa password; reset lewat Supabase (Authentication -> Users).
