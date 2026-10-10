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

### Kirim ke Cabang (gudang kirim langsung)
Selain menunggu Permintaan Cabang, kepala gudang punya tombol **Kirim ke Cabang** di Beranda: pilih cabang tujuan, pilih barang (bahan jadi, barang siap jual, atau barang jalur "langsung ke cabang"/"keduanya"), lalu Simpan & Kirim. Tanpa ACC owner, tanpa produksi. Stok gudang langsung berkurang, cabang menekan Terima, dan selisih terima tampil merah di owner. Notanya berupa Surat Jalan.
Jalankan `supabase_update_kirim_cabang.sql` PALING AKHIR (urutan: setup, penjualan, siap_jual, alur_tanpa_acc, acc_selektif, master_data, kirim_cabang). Jangan menjalankan ulang file master_data atau acc_selektif sesudahnya.

### Update aplikasi tanpa uninstall (tanda tangan tetap)
Android hanya mau menimpa aplikasi lama jika tanda tangan APK sama dan nomor build lebih tinggi. Workflow sudah menaikkan nomor build otomatis (nomor run GitHub) dan menandatangani APK dengan keystore tetap dari GitHub Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`. Buat keystore SEKALI saja, simpan cadangannya, jangan commit ke repo. Jika keystore hilang, aplikasi tidak bisa di-update lagi tanpa uninstall.
APK pertama yang memakai keystore ini tetap harus meng-uninstall versi lama satu kali (data aman di Supabase). Setelah itu semua update bisa langsung dipasang di atasnya.

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

## Omzet gudang, bon cabang bernilai jual, tagihan grosir
Jalankan `supabase_update_omzet_tagihan.sql` PALING AKHIR (setelah semua file lain, termasuk `supabase_update_hapus_barang.sql`). Aman diulang. Tidak mengganti `create_doc`/`send_doc`/`receive_doc`, jadi alur lama tidak berubah.

### Harga jual ke cabang dan omzet
- **Kirim ke Cabang**: kepala gudang mengisi **harga jual per barang** setiap kirim. Layar menampilkan modal rata-rata (dari Barang Masuk) dan estimasi untung. Harga jual boleh berbeda tiap transaksi.
- **Permintaan Cabang**: saat gudang menekan Kirim, muncul isian harga jual per barang. Barang yang stoknya kosong tidak wajib berharga.
- Pengiriman lama (sebelum update ini) belum punya harga jual. Buka dokumennya, tekan **Atur harga jual** (hanya bisa selama belum ada pembayaran).
- **Omzet** = harga jual x jumlah diterima cabang (belum diterima: jumlah dikirim). **Keuntungan** = omzet - modal. Modal = harga beli rata-rata yang dikunci saat barang dikirim (kolom `unit_price` lama).
- Beranda gudang dan owner punya kartu **Omzet gudang bulan ini**; ketuk untuk rincian per periode, per cabang, per barang, dan per transaksi bertanggal.

### Bon cabang dan pelunasan
- Bon cabang kini bernilai harga jual. Tiap bon punya status: Belum lunas, Dicicil, Lunas.
- **Catat pelunasan** dilakukan kepala gudang atau owner (gudang yang menerima uangnya). Boleh dicicil, pilih transfer atau cash, tanggal bayar, catatan. Pelunasan baru bisa dicatat setelah cabang menekan Terima.
- Riwayat pelunasan tampil di detail bon. Salah catat hanya bisa dibatalkan owner (tombol panah balik), tercatat di Riwayat dokumen.
- Akun cabang bisa melihat bon, status, dan riwayat pelunasan cabangnya sendiri.

### Nota grosir tempo dan tagihan supplier
- Di **Barang Masuk**, kepala gudang wajib memilih cara bayar: **Cash** (langsung lunas) atau **Tempo** (isi tanggal jatuh tempo).
- Nota tempo masuk ke **Tagihan grosir** (kartu di Beranda gudang dan owner). Kartu berubah oranye/merah bila ada nota yang jatuh temponya tinggal 3 hari atau kurang, atau sudah lewat. Ini pengingat di dalam aplikasi (bukan notifikasi push ke HP).
- Tombol **Sudah dibayar**: catat jumlah (bawaan = sisa penuh, boleh cicil), transfer/cash, tanggal. Riwayat pembayaran ada di detail nota dan di tab Riwayat bayar pada halaman Tagihan grosir.
- Dokumen Barang Masuk lama dianggap sudah lunas. Bila ada yang sebenarnya belum dibayar, buka dokumennya, tekan **Atur cara bayar**, pilih Tempo.

### Daftar barang diisi gudang sendiri
- Akun gudang kini punya tab **Barang** (sebelumnya hanya owner punya Master): tambah, ubah, hapus barang, dan tambah kategori. Gabung barang dan Aturan ACC tetap khusus owner.
- Barang baru yang ditambah gudang otomatis berjalur "diolah / langsung ke cabang", jadi bisa langsung dikirim ke cabang.
- Opsional: `supabase_bersihkan_master_bawaan.sql` menghapus 51 barang bawaan dari master data yang belum pernah dipakai transaksi. Jalankan bagian preview dulu, cek daftarnya, baru aktifkan bagian hapus.

### Harga jual standar dan bakso hasil produksi tanpa harga
Jalankan `supabase_update_harga_standar.sql` SETELAH `supabase_update_omzet_tagihan.sql`. Aman diulang. Jangan menjalankan ulang file omzet_tagihan sesudahnya (fungsi `create_kirim_cabang` akan kembali ke versi lama).
- **Harga jual standar**: di tab Barang/Master, ketuk barang, isi *Harga jual standar ke cabang*. Nilai ini otomatis terisi di kolom harga saat **Kirim ke Cabang** dan saat menekan **Kirim** pada Permintaan Cabang. Masih bisa diubah tiap kiriman. Bila belum diatur, isian awal memakai harga jual terakhir barang itu.
- **Bahan jadi (bakso hasil produksi) boleh tanpa harga**: kolom harga boleh dikosongkan, pengiriman tetap jalan. Isi menyusul lewat tombol **Atur harga jual** di detail dokumen (hanya selama belum ada pembayaran bon). Barang selain bahan jadi tetap wajib berharga jual.
- Kiriman yang belum berharga belum ikut omzet dan bon. Kartu **Omzet gudang** di Beranda menampilkan pengingat berwarna oranye selama masih ada.

### Satuan ganda: gudang dus, cabang botol (minuman)
Jalankan `supabase_update_satuan_ecer.sql` SETELAH `supabase_update_kirim_cabang.sql` dan `supabase_update_stok_kosong.sql`. Aman diulang. Jangan menjalankan ulang `supabase_update_kirim_cabang.sql` sesudahnya (fungsi `receive_doc` akan kembali ke versi lama).
- Satu nama barang saja, mis. "Air Mineral 600 ml" dengan satuan **dus**. Di tab Barang, ketuk barang, isi **Satuan eceran di cabang** (mis. `botol`) dan **Isi per dus** (mis. `24`). Isi per dus diatur per barang. Kolom ini muncul untuk barang siap jual dan bahan jadi.
- **Gudang dan semua dokumen tetap dalam dus**: Barang Masuk, Kirim ke Cabang, Permintaan Cabang, bon, omzet, dan tagihan. Harga beli dan harga jual per dus.
- **Stok cabang dalam botol**: saat cabang menekan Terima, stok cabang bertambah jumlah diterima x isi per dus (2 dus = 48 botol). Catat Penjualan, stok cabang, dan Rekap (Masuk, Terjual, Sisa) memakai botol. Detail dokumen menampilkan baris "Di cabang: 48 botol".
- Bila barang sudah punya stok di cabang (masih dalam dus) saat satuan eceran pertama kali diatur, stok itu otomatis dikonversi ke botol dan tercatat sebagai koreksi stok. Sebaiknya atur satuan eceran sebelum barang itu dipakai di cabang.
- Satuan eceran tidak bisa dihapus selama masih ada stok di cabang. Koreksi stok owner untuk lokasi cabang memakai satuan botol, untuk gudang memakai dus.
- Hindari Gabung barang antara barang bersatuan eceran dan yang tidak (stok cabang bisa tercampur satuan).

## Aturan penting
- Stok pengirim berkurang saat dikirim; stok penerima bertambah hanya setelah penerima menekan Terima.
- Jumlah diterima bisa lebih kecil dari yang dikirim; selisih tercatat dan ditandai merah untuk owner.
- Semua aksi tercatat (siapa, kapan) di bagian Riwayat tiap dokumen.
- Daftar bahan baru bisa ditambah langsung saat membuat dokumen; owner bisa mengubah/menonaktifkan di tab Master.
- Aplikasi belum punya ikon khusus (memakai ikon bawaan). Tambahkan folder `android_res/` bila sudah ada.
- Aplikasi memuat 400 dokumen terbaru; nota tempo yang jauh lebih lama dari itu tidak akan tampil di Tagihan grosir.
- Aplikasi belum punya fitur lupa password; reset lewat Supabase (Authentication -> Users).

### Nilai stok gudang (khusus owner)
Jalankan `supabase_update_nilai_gudang.sql` (boleh kapan saja, tidak menimpa fungsi lama). Tidak mengubah tabel atau fungsi yang ada.
- Beranda owner menampilkan kartu **Nilai stok gudang**; ketuk untuk melihat rincian per barang (stok x harga rata-rata = nilai).
- Harga rata-rata = total (qty x harga) semua Barang Masuk dibagi total qty masuk. Barang yang keluar ke produksi atau cabang mengurangi stok, sehingga nilai ikut turun. Koreksi stok juga ikut mengubah nilai.
- Yang dinilai: bahan mentah dan barang siap jual. Bahan jadi hasil produksi tidak dinilai (tidak punya harga grosir, dan nilai bahannya sudah terhitung).
- Hanya akun owner yang bisa membaca (dicek di fungsi database).

### Nilai stok per periode, tren, laporan PDF, stok minimum (khusus owner, kecuali stok minimum)
Jalankan `supabase_update_nilai_periode.sql` (setelah `supabase_update_nilai_gudang.sql`, aman diulang). File ini menambah kolom `items.stok_min` dan 3 fungsi database; fungsi lama tidak diubah.
- Beranda owner -> kartu **Nilai stok gudang** -> pilih periode di bagian atas: Sekarang (tampilan lama), Hari ini, Kemarin, 7 hari, 30 hari, atau Pilih tanggal (kalender rentang).
- Tampilan periode: nilai awal, barang masuk (+), barang keluar (-), perubahan harga (bila ada), nilai akhir, dan selisih. Masuk dan keluar sudah termasuk koreksi stok.
- Harga tiap tanggal = rata-rata beli (Barang Masuk berstatus diterima) sampai tanggal itu; bila belum ada pembelian sebelumnya dipakai rata-rata keseluruhan. Tanggal dihitung WIB.
- Grafik **Tren nilai stok** muncul untuk rentang 2 sampai 93 hari; sentuh/geser untuk melihat nilai tiap hari.
- **Paling banyak bergerak** dan **Ada stok tapi tidak bergerak** dihitung dari periode yang dipilih.
- Ikon PDF di pojok kanan atas: bagikan atau cetak laporan periode yang sedang dipilih (Sekarang = laporan hari ini).
- **Stok minimum**: Master -> ketuk barang -> isi *Stok minimum gudang*. Bila stok gudang sama dengan atau di bawah angka itu, Beranda owner dan kepala gudang menampilkan kartu **stok menipis**, dan tab Stok (Gudang) menandai barangnya. Kosong = tidak dipantau. Hanya owner yang bisa mengubah batas minimum.

### Bon cabang (surat jalan bernilai)
Jalankan `supabase_update_bon_cabang.sql` (boleh kapan saja setelah `supabase_update_nilai_periode.sql`, aman diulang; tidak menimpa fungsi lama).
- Setiap pengiriman ke cabang (Permintaan Cabang dan Kirim ke Cabang) membawa harga: harga rata-rata beli dari grosir, dikunci saat barang dikirim. Pengiriman lama ikut diisi harganya.
- Nota menjadi *Surat Jalan & Bon Cabang*: tabel surat jalan (dikirim/diterima/kurang) ditambah tabel bon (jumlah, harga, subtotal, total). Dasar bon: jumlah diterima; sebelum diterima memakai jumlah dikirim.
- Barang yang belum pernah dibeli lewat Barang Masuk (mis. bakso hasil produksi) tidak punya harga: tampil "-" dan tidak dihitung.
- Beranda owner dan cabang punya kartu *Bon cabang bulan ini*; ketuk untuk rekap per cabang dan per barang (Hari ini, 7 hari, 30 hari, Bulan ini). Tanpa pembayaran dan tanpa ACC tambahan.

### Hapus & gabung barang (owner)
Jalankan `supabase_update_hapus_barang.sql` (aman diulang, tidak menimpa fungsi lama). Di tab Master, ketuk barang lalu pilih *Hapus* atau *Gabungkan*.
- Hapus: barang yang belum pernah dipakai transaksi dihapus permanen. Barang yang sudah punya riwayat hanya dinonaktifkan (laporan lama tetap benar). Ditolak bila stok masih ada; kosongkan dulu lewat koreksi stok.
- Gabungkan: untuk barang dobel. Stok dan riwayat dipindah ke barang tujuan lalu barang asal dihapus. Jenis dan satuan harus sama.

### Permintaan cabang tetap terkirim walau stok kosong
Jalankan `supabase_update_stok_kosong.sql` SESUDAH `supabase_update_kirim_cabang.sql` (mengganti `send_doc`; jangan jalankan ulang file kirim_cabang sesudahnya). Aman diulang.
- Permintaan Cabang yang stok gudangnya kurang/kosong tetap bisa dikirim. Barang kosong dikirim 0 dan ditandai KOSONG; barang kurang dikirim sebesar stok dan ditandai STOK KURANG. Jumlah yang diminta tetap tersimpan dan tampil di detail dokumen dan nota.
- Stok gudang hanya berkurang sebesar yang benar-benar dikirim. Jenis dokumen lain tetap menolak bila stok kurang.
