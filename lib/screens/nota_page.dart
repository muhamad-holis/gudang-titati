import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../nota.dart';
import '../state.dart';
import '../theme.dart';

/// Tampilan nota/faktur satu dokumen, dengan tombol bagikan PDF dan cetak.
class NotaPage extends StatefulWidget {
  final String docId;
  const NotaPage({super.key, required this.docId});
  @override
  State<NotaPage> createState() => _NotaPageState();
}

class _NotaPageState extends State<NotaPage> {
  bool busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nota belum bisa dibuat. ${errText(e)}')));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.docById(widget.docId);
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nota'), backgroundColor: navy, foregroundColor: Colors.white),
        body: const Center(child: Text('Dokumen tidak ditemukan')),
      );
    }
    final n = buildNota(d);
    final tone = notaTones[n.stampKind] ?? notaTones['info']!;
    final grey = Colors.grey[700];

    Widget row(List<String> cells, List<int> widths, {bool head = false, bool warn = false}) => Container(
          padding: EdgeInsets.symmetric(vertical: head ? 5 : 7),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: head ? Colors.grey : lineColor, width: head ? 0.8 : 0.6))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: widths[i],
                child: Text(
                  cells[i],
                  textAlign: i >= 2 ? TextAlign.right : TextAlign.left,
                  style: TextStyle(fontSize: 12, fontWeight: warn ? FontWeight.w800 : FontWeight.w400, color: warn ? red : (head ? grey : null)),
                ),
              ),
          ]),
        );

    Widget sign(NotaSign x) => Expanded(
          child: Column(children: [
            const SizedBox(height: 40),
            const Divider(height: 1, color: Colors.grey),
            const SizedBox(height: 4),
            if (x.name.isNotEmpty) Text(x.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            Text(x.label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: grey)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(n.title), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Gudang Titati', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(n.title, style: TextStyle(fontSize: 12, color: grey)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(n.no, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(n.tanggal, style: TextStyle(fontSize: 12, color: grey)),
              ]),
            ]),
            const Divider(height: 22),
            for (final p in n.parties)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 96, child: Text(p[0], style: TextStyle(fontSize: 13, color: grey))),
                  Expanded(child: Text(p[1], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
              ),
            for (final sec in n.sections) ...[
              const SizedBox(height: 14),
              if (sec.title != null)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(sec.title!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
              row(sec.heads, sec.widths, head: true),
              for (final r in sec.rows) row(r.cells, sec.widths, warn: r.warn),
            ],
            if (n.totalValue != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(n.totalLabel ?? 'Total', style: TextStyle(fontSize: 13, color: grey)),
                  Text(n.totalValue!, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ]),
              ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: Color(tone[0]), borderRadius: BorderRadius.circular(8)),
              child: Text(n.stampText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(tone[1]))),
            ),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [sign(n.sign1), const SizedBox(width: 20), sign(n.sign2)]),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: const Size.fromHeight(46)),
                  onPressed: busy ? null : () => _run(() => shareNotaPdf(d)),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Bagikan PDF'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  onPressed: busy ? null : () => _run(() => printNotaPdf(d)),
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Cetak'),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
