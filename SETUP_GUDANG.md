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

## 4. Alur pemakaian
1. Kepala gudang: Barang Masuk (dari grosir) -> menunggu ACC owner -> stok gudang bertambah.
2. Kepala gudang: Kirim ke Produksi -> ACC owner -> Kirim -> kepala produksi Terima.
3. Kepala produksi: Setor Hasil Produksi (bahan dipakai + hasil jadi) -> ACC owner -> Kirim -> kepala gudang Terima.
4. Cabang: Minta Bahan Jadi -> ACC owner (boleh ubah jumlah / tolak dengan alasan) -> gudang Kirim -> cabang Terima.
5. Owner: melihat semua dokumen & stok, ACC / ubah jumlah / tolak, koreksi stok (tercatat alasannya),
   kelola bahan mentah, bahan jadi, dan kategori di tab Master.

## Aturan penting
- Stok baru berpindah hanya setelah owner ACC dan penerima menekan Terima.
- Jumlah diterima bisa lebih kecil dari yang dikirim; selisih tercatat dan ditandai merah untuk owner.
- Semua aksi tercatat (siapa, kapan) di bagian Riwayat tiap dokumen.
- Daftar bahan baru bisa ditambah langsung saat membuat dokumen; owner bisa mengubah/menonaktifkan di tab Master.
- Aplikasi belum punya ikon khusus (memakai ikon bawaan). Tambahkan folder `android_res/` bila sudah ada.
- Aplikasi belum punya fitur lupa password; reset lewat Supabase (Authentication -> Users).
