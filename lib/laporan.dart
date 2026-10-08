import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'nilai_periode.dart';
import 'utils.dart';

pw.Widget _t(String s, {double size = 8.5, bool bold = false, PdfColor? color, pw.TextAlign? align}) => pw.Text(
      s,
      textAlign: align,
      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
    );

pw.Widget _row(List<String> c, List<int> flex, {bool head = false, bool bold = false}) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: head ? PdfColors.grey600 : PdfColors.grey300, width: 0.5))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        for (var i = 0; i < c.length; i++)
          pw.Expanded(flex: flex[i], child: _t(c[i], bold: head || bold, color: head ? PdfColors.grey700 : null, align: i == 0 ? pw.TextAlign.left : pw.TextAlign.right)),
      ]),
    );

String _q(double q, String unit) => '${fmtQty(q)} $unit';

/// Laporan stok dan nilai gudang untuk satu periode (A4).
Future<Uint8List> buildLaporanNilaiPdf(NilaiPeriodeHasil h) async {
  final doc = pw.Document(title: 'Laporan Nilai Stok Gudang', author: 'Gudang Titati');
  const flex = [34, 14, 14, 14, 14, 18];
  final rows = [...h.rows]..sort((a, b) => b.nilaiAkhir.compareTo(a.nilaiAkhir));
  final bergerak = h.palingBergerak.take(5).toList();
  final diam = h.tidakBergerak.take(5).toList();

  pw.Widget kv(String k, String v, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [_t(k, size: 10, bold: bold), _t(v, size: 10, bold: bold)]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: _t('Dicetak ${tglJam(DateTime.now())}  |  Hal ${ctx.pageNumber}/${ctx.pagesCount}', size: 7, color: PdfColors.grey600),
    ),
    build: (ctx) => [
      _t('Gudang Titati', size: 18, bold: true),
      _t('Laporan Nilai Stok Gudang', size: 11, color: PdfColors.grey700),
      _t('Periode: ${labelRentang(h.dari, h.sampai)}', size: 10),
      pw.SizedBox(height: 8),
      pw.Container(height: 0.5, color: PdfColors.grey500),
      pw.SizedBox(height: 6),
      kv('Nilai awal periode', rp(h.nilaiAwal)),
      kv('Barang masuk (+)', rp(h.nilaiMasuk)),
      kv('Barang keluar (-)', rp(h.nilaiKeluar)),
      if (h.efekHarga.abs() >= 1) kv('Perubahan harga', rp(h.efekHarga)),
      pw.Container(height: 0.5, color: PdfColors.grey500, margin: const pw.EdgeInsets.symmetric(vertical: 3)),
      kv('Nilai akhir periode', rp(h.nilaiAkhir), bold: true),
      kv('Selisih awal ke akhir', rp(h.nilaiAkhir - h.nilaiAwal)),
      pw.SizedBox(height: 4),
      _t('Masuk dan keluar sudah termasuk koreksi stok. Harga = rata-rata beli dari grosir sampai akhir periode.', size: 7.5, color: PdfColors.grey600),
      if (bergerak.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        _t('Paling banyak bergerak', size: 11, bold: true),
        pw.SizedBox(height: 3),
        for (final r in bergerak) _row([r.name, '+${fmtQty(r.qtyMasuk)}', '-${fmtQty(r.qtyKeluar)}', r.unit, '', rp(r.nilaiMasuk + r.nilaiKeluar)], flex),
      ],
      if (diam.isNotEmpty) ...[
        pw.SizedBox(height: 12),
        _t('Ada stok tapi tidak bergerak selama periode', size: 11, bold: true),
        pw.SizedBox(height: 3),
        for (final r in diam)
          _row([r.name, _q(r.qtyAkhir, r.unit), r.terakhirGerak == null ? '-' : 'gerak ${tgl(r.terakhirGerak!)}', '', '', rp(r.nilaiAkhir)], flex),
      ],
      pw.SizedBox(height: 14),
      _t('Rincian per barang', size: 11, bold: true),
      pw.SizedBox(height: 3),
      _row(['Barang', 'Awal', 'Masuk', 'Keluar', 'Akhir', 'Nilai akhir'], flex, head: true),
      for (final r in rows)
        _row([r.name, _q(r.qtyAwal, r.unit), fmtQty(r.qtyMasuk), fmtQty(r.qtyKeluar), _q(r.qtyAkhir, r.unit), rp(r.nilaiAkhir)], flex),
      _row(['TOTAL', '', '', '', '', rp(h.nilaiAkhir)], flex, bold: true),
    ],
  ));
  return doc.save();
}

String _namaBerkas(NilaiPeriodeHasil h) => 'Nilai-Stok-${isoTgl(h.dari)}${h.dari == h.sampai ? '' : '_${isoTgl(h.sampai)}'}.pdf';

Future<void> bagikanLaporanNilai(NilaiPeriodeHasil h) async {
  final bytes = await buildLaporanNilaiPdf(h);
  await Printing.sharePdf(bytes: bytes, filename: _namaBerkas(h));
}

Future<void> cetakLaporanNilai(NilaiPeriodeHasil h) async {
  await Printing.layoutPdf(name: _namaBerkas(h), onLayout: (format) => buildLaporanNilaiPdf(h));
}
