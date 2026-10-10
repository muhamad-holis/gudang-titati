import 'models.dart';
import 'utils.dart';

/// Pengingat muncul bila jatuh tempo tinggal sekian hari (atau sudah lewat).
const int tagihanIngatHari = 3;

/// Nota grosir yang dibayar tempo.
bool masukTempo(Doc d) => d.type == 'masuk' && d.bayarMode == 'tempo';

/// Total nota grosir (harga beli x jumlah).
double masukTotal(Doc d) => d.lines.fold<double>(0, (a, l) => a + l.price * l.qty);

DateTime _tanggal(DateTime d) => DateTime(d.year, d.month, d.day);

/// Sisa hari menuju jatuh tempo (negatif = sudah lewat). null bila tidak ada tanggal.
int? hariKeJatuhTempo(Doc d) {
  final jt = d.jatuhTempo;
  if (jt == null) return null;
  return _tanggal(jt).difference(_tanggal(DateTime.now())).inDays;
}

/// Status tagihan: 'lunas', 'lewat', 'dekat' (<= tagihanIngatHari), 'aman'.
String tagihanStatus(Doc d, double sisa) {
  if (sisa <= 0.5) return 'lunas';
  final h = hariKeJatuhTempo(d);
  if (h == null) return 'aman';
  if (h < 0) return 'lewat';
  if (h <= tagihanIngatHari) return 'dekat';
  return 'aman';
}

String tagihanLabel(Doc d, String status) {
  final h = hariKeJatuhTempo(d);
  switch (status) {
    case 'lunas':
      return 'Lunas';
    case 'lewat':
      return 'Lewat ${-(h ?? 0)} hari';
    case 'dekat':
      return h == 0 ? 'Jatuh tempo hari ini' : '$h hari lagi';
    default:
      return d.jatuhTempo == null ? 'Belum lunas' : 'Tempo ${tgl(d.jatuhTempo!)}';
  }
}
