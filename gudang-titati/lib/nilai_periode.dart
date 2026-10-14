import 'state.dart';
import 'utils.dart';

String isoTgl(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
DateTime hariIni() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Satu barang pada satu periode: stok awal, masuk, keluar, akhir (masuk/keluar termasuk koreksi stok).
class NilaiPeriodeRow {
  final String itemId, name, category, unit;
  final bool siapJual;
  final double qtyAwal, qtyMasuk, qtyKeluar, qtyAkhir, hargaAwal, hargaAkhir;
  final DateTime? terakhirGerak;
  NilaiPeriodeRow({
    required this.itemId,
    required this.name,
    required this.category,
    required this.unit,
    required this.siapJual,
    required this.qtyAwal,
    required this.qtyMasuk,
    required this.qtyKeluar,
    required this.qtyAkhir,
    required this.hargaAwal,
    required this.hargaAkhir,
    required this.terakhirGerak,
  });

  factory NilaiPeriodeRow.fromJson(Map<String, dynamic> j) => NilaiPeriodeRow(
        itemId: j['item_id'] as String,
        name: (j['nama'] as String?) ?? '?',
        category: (j['kategori'] as String?) ?? '',
        unit: (j['satuan'] as String?) ?? '',
        siapJual: j['siap_jual'] == true,
        qtyAwal: toD(j['qty_awal']),
        qtyMasuk: toD(j['qty_masuk']),
        qtyKeluar: toD(j['qty_keluar']),
        qtyAkhir: toD(j['qty_akhir']),
        hargaAwal: toD(j['harga_awal']),
        hargaAkhir: toD(j['harga_akhir']),
        terakhirGerak: j['terakhir_gerak'] == null ? null : DateTime.parse(j['terakhir_gerak'] as String).toLocal(),
      );

  double get nilaiAwal => qtyAwal * hargaAwal;
  double get nilaiMasuk => qtyMasuk * hargaAkhir;
  double get nilaiKeluar => qtyKeluar * hargaAkhir;
  double get nilaiAkhir => qtyAkhir * hargaAkhir;
  double get selisih => nilaiAkhir - nilaiAwal;
  bool get bergerak => qtyMasuk != 0 || qtyKeluar != 0;
  bool get adaHarga => hargaAkhir > 0;
}

class TrenPoint {
  final DateTime hari;
  final double nilai;
  TrenPoint(this.hari, this.nilai);
}

class NilaiPeriodeHasil {
  final DateTime dari, sampai;
  final List<NilaiPeriodeRow> rows;
  final List<TrenPoint> tren;
  final String? trenError;
  NilaiPeriodeHasil(this.dari, this.sampai, this.rows, this.tren, this.trenError);

  double get nilaiAwal => rows.fold(0.0, (a, r) => a + r.nilaiAwal);
  double get nilaiMasuk => rows.fold(0.0, (a, r) => a + r.nilaiMasuk);
  double get nilaiKeluar => rows.fold(0.0, (a, r) => a + r.nilaiKeluar);
  double get nilaiAkhir => rows.fold(0.0, (a, r) => a + r.nilaiAkhir);

  /// Selisih akibat harga beli berubah (awal + masuk - keluar tidak sama dengan akhir).
  double get efekHarga => nilaiAkhir - (nilaiAwal + nilaiMasuk - nilaiKeluar);
  int get tanpaHarga => rows.where((r) => r.qtyAkhir > 0 && !r.adaHarga).length;

  /// Paling banyak bergerak: diurutkan dari nilai masuk + keluar terbesar.
  List<NilaiPeriodeRow> get palingBergerak {
    final l = rows.where((r) => r.bergerak).toList()..sort((a, b) => (b.nilaiMasuk + b.nilaiKeluar).compareTo(a.nilaiMasuk + a.nilaiKeluar));
    return l;
  }

  /// Ada stok di akhir periode tapi tidak ada pergerakan selama periode.
  List<NilaiPeriodeRow> get tidakBergerak {
    final l = rows.where((r) => r.qtyAkhir > 0 && !r.bergerak).toList()..sort((a, b) => b.nilaiAkhir.compareTo(a.nilaiAkhir));
    return l;
  }
}

/// Memuat rincian periode (+ tren bila rentang minimal 2 hari dan maksimal 93 hari).
Future<NilaiPeriodeHasil> muatNilaiPeriode(DateTime dari, DateTime sampai) async {
  final p = {'p_dari': isoTgl(dari), 'p_sampai': isoTgl(sampai)};
  final r = await sb.rpc('nilai_gudang_periode', params: p);
  final rows = [for (final e in (r as List)) NilaiPeriodeRow.fromJson(Map<String, dynamic>.from(e as Map))];
  var tren = <TrenPoint>[];
  String? trenErr;
  final hari = sampai.difference(dari).inDays + 1;
  if (hari >= 2 && hari <= 93) {
    try {
      final t = await sb.rpc('nilai_gudang_tren', params: p);
      tren = [for (final e in (t as List)) TrenPoint(DateTime.parse(e['hari'] as String), toD(e['nilai']))];
    } catch (e) {
      trenErr = errText(e);
    }
  }
  return NilaiPeriodeHasil(dari, sampai, rows, tren, trenErr);
}

String labelRentang(DateTime a, DateTime b) => a == b ? tgl(a) : '${tgl(a)} s/d ${tgl(b)}';
