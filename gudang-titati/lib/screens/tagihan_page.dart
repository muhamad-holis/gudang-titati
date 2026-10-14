import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../tagihan.dart';
import '../theme.dart';
import '../utils.dart';
import 'doc_detail_page.dart';
import 'pembayaran.dart';

/// Tagihan grosir / supplier: nota Barang Masuk yang dibayar tempo.
/// Menampilkan sisa tagihan, jatuh tempo, tombol Sudah dibayar, dan riwayat pelunasan.
class TagihanPage extends StatefulWidget {
  const TagihanPage({super.key});
  @override
  State<TagihanPage> createState() => _TagihanPageState();
}

class _TagihanPageState extends State<TagihanPage> {
  String tampil = 'belum'; // belum | lunas | riwayat
  bool busy = false;

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _bayar(AppState s, Doc d) async {
    final r = await showBayarDialog(context,
        title: 'Bayar ke ${d.supplier.isEmpty ? 'grosir' : d.supplier}',
        sisa: s.masukSisa(d),
        info: 'Catat pembayaran yang sudah Anda lakukan ke grosir (transfer atau cash). Boleh dicicil.',
        okText: 'Sudah dibayar');
    if (r == null) return;
    setState(() => busy = true);
    try {
      await s.bayarSupplier(d.id, r.amount, r.method, r.paidAt, r.note);
      if (mounted) _toast('Pembayaran dicatat');
    } catch (e) {
      if (mounted) _toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final semua = s.tagihanSupplier;
    final belum = semua.where((d) => s.masukSisa(d) > 0.5).toList();
    final lunas = semua.where((d) => s.masukSisa(d) <= 0.5).toList();
    final totalSisa = belum.fold<double>(0, (a, d) => a + s.masukSisa(d));
    final mendekati = s.tagihanMendekati;
    final kelola = s.role == 'gudang' || s.isOwner;

    final riwayat = s.payments.where((p) => p.kind == 'supplier').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Tagihan grosir'), backgroundColor: navy, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: () => s.refresh(silent: true),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total belum dibayar ke grosir', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              Text(rp(totalSisa), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: totalSisa > 0.5 ? red : green)),
              const SizedBox(height: 4),
              Text('${belum.length} nota belum lunas', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              if (mendekati.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${mendekati.length} nota sudah lewat atau mendekati jatuh tempo (≤ $tagihanIngatHari hari)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: orange)),
                ),
              if (s.payError != null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Data pembayaran belum tersedia. Pastikan supabase_update_omzet_tagihan.sql sudah dijalankan.',
                      style: TextStyle(fontSize: 11, color: red, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: Text('Belum lunas (${belum.length})'), selected: tampil == 'belum', onSelected: (_) => setState(() => tampil = 'belum')),
            ChoiceChip(label: Text('Lunas (${lunas.length})'), selected: tampil == 'lunas', onSelected: (_) => setState(() => tampil = 'lunas')),
            ChoiceChip(label: const Text('Riwayat bayar'), selected: tampil == 'riwayat', onSelected: (_) => setState(() => tampil = 'riwayat')),
          ]),
          const SizedBox(height: 8),
          if (tampil == 'riwayat') ...[
            if (riwayat.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Belum ada pembayaran ke grosir', style: TextStyle(color: Colors.grey)))),
            for (final p in riwayat) _riwayatRow(context, s, p),
          ] else ...[
            if ((tampil == 'belum' ? belum : lunas).isEmpty)
              Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(tampil == 'belum' ? 'Tidak ada tagihan yang belum dibayar' : 'Belum ada nota tempo yang lunas',
                      style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
                ),
              ),
            for (final d in (tampil == 'belum' ? belum : lunas)) _kartu(context, s, d, kelola),
          ],
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _kartu(BuildContext context, AppState s, Doc d, bool kelola) {
    final sisa = s.masukSisa(d);
    final st = tagihanStatus(d, sisa);
    final total = masukTotal(d);
    final paid = s.paidOf(d.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: cardDeco(color: st == 'lewat' ? const Color(0xFFFFF5F5) : (st == 'dekat' ? const Color(0xFFFFFBF2) : Colors.white)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocDetailPage(docId: d.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(d.supplier.isEmpty ? '(tanpa nama grosir)' : d.supplier, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              pilTagihan(st, tagihanLabel(d, st)),
            ]),
            const SizedBox(height: 2),
            Text('${d.no} • nota ${tgl(d.createdAt)}${d.jatuhTempo == null ? '' : ' • jatuh tempo ${tgl(d.jatuhTempo!)}'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            const SizedBox(height: 4),
            Text(d.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _kv('Total nota', rp(total), Colors.black87)),
              Expanded(child: _kv('Dibayar', rp(paid), green)),
              Expanded(child: _kv('Sisa', rp(sisa), sisa > 0.5 ? red : green)),
            ]),
            if (kelola && sisa > 0.5)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(44)),
                  onPressed: busy ? null : () => _bayar(s, d),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Sudah dibayar'),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _kv(String a, String b, Color c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(a, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        Text(b, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
      ]);

  Widget _riwayatRow(BuildContext context, AppState s, Payment p) {
    final d = s.docById(p.docId);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: cardDeco(),
      child: ListTile(
        dense: true,
        onTap: d == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocDetailPage(docId: d.id))),
        title: Text(d == null || d.supplier.isEmpty ? 'Pembayaran grosir' : d.supplier, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${tgl(p.paidAt)} • ${p.methodLabel}${d == null ? '' : ' • ${d.no}'}${p.note.isEmpty ? '' : ' • ${p.note}'}', style: const TextStyle(fontSize: 12)),
        trailing: Text(rp(p.amount), style: const TextStyle(fontWeight: FontWeight.w800, color: green)),
      ),
    );
  }
}
