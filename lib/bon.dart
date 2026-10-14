import 'models.dart';

/// Dokumen pengiriman gudang ke cabang (Permintaan Cabang / Kirim ke Cabang).
bool isBonDoc(Doc d) => d.type == 'minta_cabang' || d.type == 'kirim_cabang';

/// Bon baru terbit setelah barang dikirim.
bool bonTerbit(Doc d) => isBonDoc(d) && (d.status == 'dikirim' || d.status == 'diterima');

/// Dasar bon: jumlah diterima bila sudah diterima, selain itu jumlah dikirim.
double bonQty(DocLine l) => l.qtyReceived ?? l.qty;

/// Nilai bon satu dokumen = harga jual gudang x jumlah (0 bila belum terbit).
double bonNilai(Doc d) => bonTerbit(d) ? d.lines.fold<double>(0, (a, l) => a + l.sellPrice * bonQty(l)) : 0.0;

/// Modal (harga beli rata-rata) dari baris yang sudah punya harga jual.
double bonHpp(Doc d) => bonTerbit(d) ? d.lines.where((l) => l.sellPrice > 0).fold<double>(0, (a, l) => a + l.price * bonQty(l)) : 0.0;

/// Keuntungan kotor = harga jual - modal, hanya untuk baris yang sudah berharga jual.
double bonLaba(Doc d) => bonNilai(d) - bonHpp(d);

/// Jumlah baris yang belum diberi harga jual (dan memang ada barangnya).
int bonTanpaHarga(Doc d) => bonTerbit(d) ? d.lines.where((l) => l.sellPrice <= 0 && bonQty(l) > 0).length : 0;

/// Jumlah baris berharga jual tapi modalnya tidak diketahui (barang belum pernah dibeli lewat Barang Masuk).
int bonTanpaModal(Doc d) => bonTerbit(d) ? d.lines.where((l) => l.sellPrice > 0 && l.price <= 0 && bonQty(l) > 0).length : 0;

/// Waktu acuan bon: saat dikirim.
DateTime bonWaktu(Doc d) => d.sentAt ?? d.createdAt;

/// Status pelunasan bon: 'lunas', 'sebagian', 'belum', atau 'nol' (belum ada nilai).
String bonStatusBayar(double total, double dibayar) {
  if (total <= 0.5) return 'nol';
  if (dibayar >= total - 0.5) return 'lunas';
  if (dibayar > 0.5) return 'sebagian';
  return 'belum';
}

String bonStatusLabel(String st) {
  switch (st) {
    case 'lunas':
      return 'Lunas';
    case 'sebagian':
      return 'Dicicil';
    case 'belum':
      return 'Belum lunas';
    default:
      return 'Belum ada harga';
  }
}
