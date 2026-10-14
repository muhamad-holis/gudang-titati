import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'bon.dart';
import 'models.dart';
import 'utils.dart';

/// Satu baris tabel nota. [warn] = baris ditandai merah (mis. barang kurang diterima).
class NotaRow {
  final List<String> cells;
  final bool warn;
  const NotaRow(this.cells, {this.warn = false});
}

/// Satu tabel nota. [widths] = perbandingan lebar kolom (flex), kolom ke-2 dan seterusnya rata kanan.
class NotaSection {
  final String? title;
  final List<String> heads;
  final List<int> widths;
  final List<NotaRow> rows;
  const NotaSection({this.title, required this.heads, required this.widths, required this.rows});
}

class NotaSign {
  final String label, name;
  const NotaSign(this.label, this.name);
}

/// Isi nota yang dipakai bersama oleh tampilan di layar dan PDF.
class NotaData {
  final String title, no, tanggal;
  final List<List<String>> parties; // [label, nilai]
  final List<NotaSection> sections;
  final String? totalLabel, totalValue;
  final String stampText, stampKind; // stampKind: warn | bad | ok | info
  final NotaSign sign1, sign2;
  const NotaData({
    required this.title,
    required this.no,
    required this.tanggal,
    required this.parties,
    required this.sections,
    this.totalLabel,
    this.totalValue,
    required this.stampText,
    required this.stampKind,
    required this.sign1,
    required this.sign2,
  });
}

/// Warna cap status: [latar, teks].
const notaTones = <String, List<int>>{
  'warn': [0xFFFAEEDA, 0xFF854F0B],
  'bad': [0xFFFCEBEB, 0xFFA32D2D],
  'ok': [0xFFEAF3DE, 0xFF27500A],
  'info': [0xFFE6F1FB, 0xFF0C447C],
};

String _num(double v) => rp(v).replaceFirst('Rp ', '');
String _qty(DocLine l, double q) => '${fmtQty(q)} ${l.unit}';

String _namaTanda(DocLine l) => l.kosong
    ? '${l.name} [${l.qty <= 0 ? 'KOSONG' : 'STOK KURANG'}, diminta ${fmtQty(l.qtyMinta ?? 0)} ${l.unit}]'
    : l.name;

NotaRow _kirimRow(int i, DocLine l) {
  final r = l.qtyReceived;
  final kurang = r != null && l.qty - r > 0.0001;
  return NotaRow([
    '$i',
    _namaTanda(l),
    _qty(l, l.qty),
    r == null ? '-' : _qty(l, r),
    kurang ? _qty(l, l.qty - r!) : '-',
  ], warn: kurang || l.kosong);
}

NotaData buildNota(Doc d) {
  final sections = <NotaSection>[];
  String? totalLabel, totalValue;
  String title;
  List<List<String>> parties;
  NotaSign s1, s2;

  switch (d.type) {
    case 'masuk':
      title = 'Faktur Pembelian';
      parties = [
        ['Grosir', d.supplier.isEmpty ? '-' : d.supplier],
        ['Dicatat oleh', d.createdByName],
        if (d.bayarMode == 'tempo') ['Pembayaran', 'Tempo${d.jatuhTempo == null ? '' : ', jatuh tempo ${tgl(d.jatuhTempo!)}'}'],
        if (d.bayarMode == 'cash') ['Pembayaran', 'Cash'],
      ];
      var total = 0.0;
      final rows = <NotaRow>[];
      for (var i = 0; i < d.lines.length; i++) {
        final l = d.lines[i];
        total += l.price * l.qty;
        rows.add(NotaRow(['${i + 1}', l.name, _qty(l, l.qty), l.price > 0 ? _num(l.price) : '-', l.price > 0 ? _num(l.price * l.qty) : '-']));
      }
      sections.add(NotaSection(heads: const ['No', 'Barang', 'Jml', 'Harga', 'Subtotal'], widths: const [1, 6, 3, 4, 5], rows: rows));
      totalLabel = 'Total pembelian';
      totalValue = rp(total);
      s1 = NotaSign('Kepala gudang', d.createdByName);
      s2 = NotaSign('Owner', d.verif == 'ok' ? d.approvedByName : '');
      break;
    case 'minta_cabang':
    case 'kirim_cabang':
      title = bonTerbit(d) ? 'Surat Jalan & Bon Cabang' : 'Surat Jalan';
      parties = [
        ['Dari', 'Gudang'],
        ['Kepada', d.branch.isEmpty ? '-' : d.branch],
      ];
      sections.add(NotaSection(
        heads: const ['No', 'Barang', 'Dikirim', 'Diterima', 'Kurang'],
        widths: const [1, 6, 3, 3, 3],
        rows: [for (var i = 0; i < d.lines.length; i++) _kirimRow(i + 1, d.lines[i])],
      ));
      if (bonTerbit(d)) {
        final bonRows = <NotaRow>[];
        for (var i = 0; i < d.lines.length; i++) {
          final l = d.lines[i];
          final q = bonQty(l);
          bonRows.add(NotaRow([
            '${i + 1}',
            _namaTanda(l),
            _qty(l, q),
            l.sellPrice > 0 ? _num(l.sellPrice) : '-',
            (l.sellPrice > 0 && q > 0) ? _num(l.sellPrice * q) : '-',
          ], warn: l.kosong));
        }
        sections.add(NotaSection(
          title: d.status == 'diterima' ? 'Bon cabang (jumlah diterima)' : 'Bon cabang (jumlah dikirim)',
          heads: const ['No', 'Barang', 'Jml', 'Harga', 'Subtotal'],
          widths: const [1, 6, 3, 4, 5],
          rows: bonRows,
        ));
        totalLabel = 'Total bon cabang';
        totalValue = rp(bonNilai(d));
      }
      s1 = const NotaSign('Pengirim (gudang)', '');
      s2 = NotaSign('Penerima (${d.branch.isEmpty ? 'cabang' : d.branch})', d.receivedByName);
      break;
    case 'kirim_produksi':
      title = 'Bukti Serah Terima';
      parties = [
        ['Dari', 'Gudang'],
        ['Kepada', 'Produksi'],
      ];
      sections.add(NotaSection(
        heads: const ['No', 'Barang', 'Dikirim', 'Diterima', 'Kurang'],
        widths: const [1, 6, 3, 3, 3],
        rows: [for (var i = 0; i < d.lines.length; i++) _kirimRow(i + 1, d.lines[i])],
      ));
      s1 = const NotaSign('Pengirim (gudang)', '');
      s2 = NotaSign('Penerima (produksi)', d.receivedByName);
      break;
    default: // setor_jadi
      title = 'Bukti Setor Hasil Produksi';
      parties = [
        ['Dari', 'Produksi'],
        ['Kepada', 'Gudang'],
      ];
      final pakai = d.lines.where((l) => l.role == 'pakai').toList();
      final hasil = d.lines.where((l) => l.role == 'hasil').toList();
      sections.add(NotaSection(
        title: 'Bahan mentah dipakai',
        heads: const ['No', 'Barang', 'Jumlah'],
        widths: const [1, 6, 4],
        rows: [for (var i = 0; i < pakai.length; i++) NotaRow(['${i + 1}', pakai[i].name, _qty(pakai[i], pakai[i].qty)])],
      ));
      sections.add(NotaSection(
        title: 'Hasil jadi',
        heads: const ['No', 'Barang', 'Dikirim', 'Diterima', 'Kurang'],
        widths: const [1, 6, 3, 3, 3],
        rows: [for (var i = 0; i < hasil.length; i++) _kirimRow(i + 1, hasil[i])],
      ));
      s1 = const NotaSign('Pengirim (produksi)', '');
      s2 = NotaSign('Penerima (gudang)', d.receivedByName);
  }
  if (d.note.isNotEmpty) parties = [...parties, ['Catatan', d.note]];

  final anyKurang = sections.any((s) => s.rows.any((r) => r.warn));
  String stamp;
  String kind;
  if (d.type == 'masuk' && d.verif == 'menunggu') {
    stamp = 'Belum diverifikasi owner';
    kind = 'warn';
  } else if (d.type == 'masuk' && d.verif == 'ok') {
    stamp = 'Diverifikasi owner${d.approvedAt == null ? '' : ' - ${tglJam(d.approvedAt!)}'}';
    kind = 'ok';
  } else if (d.type == 'masuk' && d.verif == 'tolak') {
    stamp = 'Pembelian ditolak owner';
    kind = 'bad';
  } else if (d.status == 'ditolak') {
    stamp = 'Ditolak owner';
    kind = 'bad';
  } else if (d.status == 'dibatalkan') {
    stamp = 'Dibatalkan';
    kind = 'bad';
  } else if (d.status == 'diterima') {
    stamp = anyKurang ? 'Diterima, ada barang kurang' : 'Diterima lengkap';
    kind = anyKurang ? 'bad' : 'ok';
  } else if (d.status == 'diajukan') {
    stamp = 'Menunggu ACC owner';
    kind = 'warn';
  } else if (d.status == 'dikirim') {
    stamp = 'Dikirim, menunggu diterima';
    kind = 'info';
  } else {
    stamp = statusLabel(d.status);
    kind = 'info';
  }

  return NotaData(
    title: title,
    no: d.no,
    tanggal: tglJam(d.createdAt),
    parties: parties,
    sections: sections,
    totalLabel: totalLabel,
    totalValue: totalValue,
    stampText: stamp,
    stampKind: kind,
    sign1: s1,
    sign2: s2,
  );
}

// ---------------------------------------------------------------- PDF

pw.Widget _t(String s, {double size = 9, bool bold = false, PdfColor? color, pw.TextAlign? align}) => pw.Text(
      s,
      textAlign: align,
      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color),
    );

pw.Widget _pdfRow(NotaSection s, List<String> cells, {bool head = false, bool warn = false}) {
  final color = warn ? PdfColor.fromInt(0xFFA32D2D) : (head ? PdfColors.grey700 : null);
  return pw.Container(
    padding: pw.EdgeInsets.symmetric(vertical: head ? 3 : 4),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: head ? PdfColors.grey600 : PdfColors.grey300, width: 0.5)),
    ),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      for (var i = 0; i < cells.length; i++)
        pw.Expanded(
          flex: s.widths[i],
          child: _t(cells[i], size: 9, bold: warn, color: color, align: i >= 2 ? pw.TextAlign.right : pw.TextAlign.left),
        ),
    ]),
  );
}

pw.Widget _pdfSign(NotaSign s) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.SizedBox(height: 38),
      pw.Container(height: 0.5, color: PdfColors.grey600),
      pw.SizedBox(height: 3),
      if (s.name.isNotEmpty) _t(s.name, size: 8, bold: true, align: pw.TextAlign.center),
      _t(s.label, size: 8, color: PdfColors.grey700, align: pw.TextAlign.center),
    ]);

Future<Uint8List> buildNotaPdf(Doc d) async {
  final n = buildNota(d);
  final tone = notaTones[n.stampKind] ?? notaTones['info']!;
  final doc = pw.Document(title: n.no, author: 'Gudang Titati');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a5,
    margin: pw.EdgeInsets.all(28),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: _t('Dicetak ${tglJam(DateTime.now())}  |  Hal ${ctx.pageNumber}/${ctx.pagesCount}', size: 7, color: PdfColors.grey600),
    ),
    build: (ctx) => [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _t('Gudang Titati', size: 16, bold: true),
          _t(n.title, size: 10, color: PdfColors.grey700),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          _t(n.no, size: 10, bold: true),
          _t(n.tanggal, size: 9, color: PdfColors.grey700),
        ]),
      ]),
      pw.SizedBox(height: 8),
      pw.Container(height: 0.5, color: PdfColors.grey500),
      pw.SizedBox(height: 6),
      for (final p in n.parties)
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 78, child: _t(p[0], color: PdfColors.grey700)),
            pw.Expanded(child: _t(p[1])),
          ]),
        ),
      for (final s in n.sections) ...[
        pw.SizedBox(height: 10),
        if (s.title != null) pw.Padding(padding: pw.EdgeInsets.only(bottom: 3), child: _t(s.title!, size: 10, bold: true)),
        _pdfRow(s, s.heads, head: true),
        for (final r in s.rows) _pdfRow(s, r.cells, warn: r.warn),
      ],
      if (n.totalValue != null)
        pw.Padding(
          padding: pw.EdgeInsets.only(top: 8),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            _t(n.totalLabel ?? 'Total', size: 10, color: PdfColors.grey700),
            _t(n.totalValue!, size: 13, bold: true),
          ]),
        ),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(color: PdfColor.fromInt(tone[0]), borderRadius: pw.BorderRadius.all(pw.Radius.circular(4))),
          child: _t(n.stampText, size: 9, bold: true, color: PdfColor.fromInt(tone[1])),
        ),
      ]),
      pw.SizedBox(height: 14),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(child: _pdfSign(n.sign1)),
        pw.SizedBox(width: 24),
        pw.Expanded(child: _pdfSign(n.sign2)),
      ]),
    ],
  ));
  return doc.save();
}

/// Bagikan nota sebagai file PDF (WhatsApp, email, simpan ke berkas).
Future<void> shareNotaPdf(Doc d) async {
  final bytes = await buildNotaPdf(d);
  await Printing.sharePdf(bytes: bytes, filename: 'Nota-${d.no}.pdf');
}

/// Cetak nota lewat menu cetak Android.
Future<void> printNotaPdf(Doc d) async {
  await Printing.layoutPdf(name: 'Nota-${d.no}', onLayout: (format) => buildNotaPdf(d));
}
