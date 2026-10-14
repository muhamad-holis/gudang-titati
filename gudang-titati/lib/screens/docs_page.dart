import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'doc_detail_page.dart';

class DocCard extends StatelessWidget {
  final Doc doc;
  const DocCard({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final act = s.actionFor(doc);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: cardDeco(color: act != null ? const Color(0xFFFFFBF2) : Colors.white),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocDetailPage(docId: doc.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(typeLabel(doc.type), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              StatusChip(doc.status),
            ]),
            const SizedBox(height: 4),
            Text(doc.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              '${doc.no} • ${tglJam(doc.createdAt)} • ${doc.createdByName}${doc.branch.isEmpty ? '' : ' • ${doc.branch}'}',
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
            if (act != null || doc.hasDiff || doc.belumVerif || doc.pembelianDitolak)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 8, children: [
                  if (act != null) Text('▶ $act', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: orange)),
                  if (doc.belumVerif && act == null) const Text('⏳ Belum diverifikasi owner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: orange)),
                  if (doc.pembelianDitolak) const Text('⚠ Pembelian ditolak owner', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: red)),
                  if (doc.hasDiff) const Text('⚠ Ada selisih', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: red)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class DocsPage extends StatefulWidget {
  const DocsPage({super.key});
  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  String status = 'semua';
  String type = 'semua';

  static const statuses = ['semua', 'diajukan', 'belum_verif', 'disetujui', 'dikirim', 'diterima', 'ditolak', 'selisih'];
  static const types = ['semua', 'masuk', 'kirim_produksi', 'setor_jadi', 'minta_cabang', 'kirim_cabang'];

  Widget _chips(List<String> values, String current, String Function(String) label, ValueChanged<String> onPick) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        for (final v in values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label(v)),
              selected: current == v,
              showCheckmark: false,
              selectedColor: blue,
              backgroundColor: Colors.white,
              labelStyle: TextStyle(color: current == v ? Colors.white : navy, fontWeight: FontWeight.w600, fontSize: 12),
              shape: const StadiumBorder(side: BorderSide(color: lineColor)),
              onSelected: (_) => onPick(v),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.docs.where((d) {
      if (type != 'semua' && d.type != type) return false;
      if (status == 'selisih') return d.hasDiff;
      if (status == 'belum_verif') return d.belumVerif;
      if (status != 'semua' && d.status != status) return false;
      return true;
    }).toList();

    return Column(children: [
      const SizedBox(height: 10),
      _chips(statuses, status, (v) => v == 'semua' ? 'Semua status' : (v == 'selisih' ? 'Ada selisih' : (v == 'belum_verif' ? 'Belum diverifikasi' : statusLabel(v))), (v) => setState(() => status = v)),
      const SizedBox(height: 4),
      _chips(types, type, (v) => v == 'semua' ? 'Semua jenis' : typeLabel(v), (v) => setState(() => type = v)),
      const SizedBox(height: 6),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => s.refresh(silent: true),
          child: list.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Tidak ada dokumen', style: TextStyle(color: Colors.grey))))])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                  itemCount: list.length,
                  itemBuilder: (c, i) => DocCard(doc: list[i]),
                ),
        ),
      ),
    ]);
  }
}
