double toD(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

double? parseQty(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String fmtQty(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  var s = q.toStringAsFixed(2);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

String rp(num n) {
  final s = n.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}Rp $b';
}

String two(int n) => n.toString().padLeft(2, '0');
const _bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
String tgl(DateTime d) => '${two(d.day)} ${_bulan[d.month - 1]} ${d.year}';
String jam(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String tglJam(DateTime d) => '${tgl(d)} ${jam(d)}';

String roleLabel(String r) {
  switch (r) {
    case 'owner':
      return 'Owner';
    case 'gudang':
      return 'Kepala Gudang';
    case 'produksi':
      return 'Kepala Produksi';
    case 'cabang':
      return 'Cabang';
    default:
      return r;
  }
}

String locLabel(String loc) => loc == 'gudang' ? 'Gudang' : (loc == 'produksi' ? 'Produksi' : loc);

String typeLabel(String t) {
  switch (t) {
    case 'masuk':
      return 'Barang Masuk';
    case 'kirim_produksi':
      return 'Kirim ke Produksi';
    case 'setor_jadi':
      return 'Setor Bahan Jadi';
    case 'minta_cabang':
      return 'Permintaan Cabang';
    default:
      return t;
  }
}

String statusLabel(String s) {
  switch (s) {
    case 'diajukan':
      return 'Menunggu ACC';
    case 'disetujui':
      return 'Menunggu dikirim';
    case 'dikirim':
      return 'Dikirim';
    case 'diterima':
      return 'Diterima';
    case 'ditolak':
      return 'Ditolak';
    case 'dibatalkan':
      return 'Dibatalkan';
    default:
      return s;
  }
}
