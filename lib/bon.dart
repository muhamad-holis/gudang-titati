import 'models.dart';

/// Dokumen pengiriman gudang ke cabang (Permintaan Cabang / Kirim ke Cabang).
bool isBonDoc(Doc d) => d.type == 'minta_cabang' || d.type == 'kirim_cabang';

/// Bon baru terbit setelah barang dikirim (harga dikunci saat dikirim).
bool bonTerbit(Doc d) => isBonDoc(d) && (d.status == 'dikirim' || d.status == 'diterima');

/// Dasar bon: jumlah diterima bila sudah diterima, selain itu jumlah dikirim.
double bonQty(DocLine l) => l.qtyReceived ?? l.qty;

/// Nilai bon satu dokumen (0 bila belum terbit).
double bonNilai(Doc d) => bonTerbit(d) ? d.lines.fold<double>(0, (a, l) => a + l.price * bonQty(l)) : 0.0;

/// Jumlah baris yang belum punya harga (barang olahan / belum pernah dibeli dari grosir).
int bonTanpaHarga(Doc d) => bonTerbit(d) ? d.lines.where((l) => l.price <= 0).length : 0;

/// Waktu acuan bon: saat dikirim.
DateTime bonWaktu(Doc d) => d.sentAt ?? d.createdAt;
