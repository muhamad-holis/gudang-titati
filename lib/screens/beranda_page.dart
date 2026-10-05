import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'doc_form_page.dart';
import 'docs_page.dart';
import 'sales_form_page.dart';
import 'sales_page.dart';

class BerandaPage extends StatelessWidget {
  const BerandaPage({super.key});

  Future<void> _open(BuildContext context, String type) async {
    final ok = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => DocFormPage(type: type)));
    if (ok == 'acc' && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(type == 'minta_cabang' ? 'Jumlah jauh di atas biasanya, menunggu ACC owner' : 'Hasil menyimpang dari biasanya, menunggu ACC owner')));
    } else if (ok == 'ok' && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(type == 'minta_cabang' ? 'Permintaan terkirim ke gudang' : (type == 'masuk' ? 'Barang masuk tercatat, stok gudang bertambah' : 'Terkirim, menunggu konfirmasi penerima'))));
    }
  }

  /// ACC semua hanya untuk pembelian (Barang Masuk). Dokumen menyimpang harus dilihat satu per satu.
  Future<void> _accAll(BuildContext context, AppState s, int count) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('ACC semua pembelian ($count)?'),
        content: const Text('Semua pembelian barang masuk yang belum diverifikasi akan di-ACC. Dokumen yang menyimpang (setoran produksi / permintaan cabang) tetap harus dibuka dan diputuskan satu per satu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('ACC semua')),
        ],
      ),
    );
    if (ok != true) return;
    String msg;
    try {
      final n = await s.verifyAllMasuk();
      msg = '$n pembelian diverifikasi';
    } catch (e) {
      msg = errText(e);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _btn(BuildContext context, IconData icon, String label, String type) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: const Size.fromHeight(52)),
            onPressed: () => _open(context, type),
            icon: Icon(icon, size: 20),
            label: Text(label, textAlign: TextAlign.center),
          ),
        ),
      );

  Widget _salesBtn(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SalesFormPage()));
              if (ok == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penjualan tersimpan dan terlihat oleh owner')));
              }
            },
            icon: const Icon(Icons.point_of_sale, size: 20),
            label: const Text('Catat Penjualan', textAlign: TextAlign.center),
          ),
        ),
      );

  /// Ringkasan penjualan hari ini per cabang (untuk owner).
  Widget _salesCard(BuildContext context, AppState s) {
    final branches = s.saleBranches;
    if (branches.isEmpty) return const SizedBox.shrink();
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      const Text('Penjualan cabang hari ini', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final b in branches)
        Builder(builder: (_) {
          final sums = s.rekapFor(b, today, today);
          final sold = sums.where((x) => x.terjual > 0).length;
          final diff = sums.where((x) => !x.pas).length;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: cardDeco(),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesPage(initialBranch: b, standalone: true))),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(sums.isEmpty ? Icons.hourglass_empty : (diff == 0 ? Icons.check_circle : Icons.info_outline),
                      color: sums.isEmpty ? Colors.grey : (diff == 0 ? green : orange)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        sums.isEmpty
                            ? 'Belum ada barang masuk atau terjual hari ini'
                            : '$sold jenis terjual • ${diff == 0 ? 'semua pas' : '$diff barang ada selisih/sisa'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ]),
              ),
            ),
          );
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me!;
    final tasks = s.myTasks;
    final recent = s.docs.where((d) => s.actionFor(d) == null).take(8).toList();

    Widget buttons;
    switch (me.role) {
      case 'gudang':
        buttons = Row(children: [
          _btn(context, Icons.add_box_outlined, 'Barang Masuk', 'masuk'),
          _btn(context, Icons.local_shipping_outlined, 'Kirim ke Produksi', 'kirim_produksi'),
        ]);
        break;
      case 'produksi':
        buttons = Row(children: [_btn(context, Icons.soup_kitchen_outlined, 'Setor Hasil Produksi', 'setor_jadi')]);
        break;
      case 'cabang':
        buttons = Row(children: [_btn(context, Icons.shopping_basket_outlined, 'Minta Bahan Jadi', 'minta_cabang'), _salesBtn(context)]);
        break;
      default:
        buttons = const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: () => s.refresh(silent: true),
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(),
          child: Row(children: [
            const Icon(Icons.account_circle, size: 40, color: navy),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me.name.isEmpty ? roleLabel(me.role) : me.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(me.role == 'cabang' ? 'Cabang ${me.branch.isEmpty ? '(belum diatur)' : me.branch}' : roleLabel(me.role),
                    style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              ]),
            ),
          ]),
        ),
        if (me.role != 'owner') ...[const SizedBox(height: 12), buttons],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Perlu tindakan Anda (${tasks.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (s.isOwner && tasks.where((d) => d.type == 'masuk' && d.ownerCheck == 'belum').length > 1)
            TextButton.icon(
                onPressed: () => _accAll(context, s, tasks.where((d) => d.type == 'masuk' && d.ownerCheck == 'belum').length),
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('ACC semua pembelian')),
        ]),
        const SizedBox(height: 6),
        if (tasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(),
            child: const Text('Tidak ada yang menunggu. Semua beres.', style: TextStyle(color: Colors.grey)),
          ),
        for (final d in tasks) DocCard(doc: d),
        if (s.isOwner && s.ownerAlerts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Perlu dipantau (${s.ownerAlerts.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Ada selisih terima, pembelian yang Anda keberatan, atau tertahan lebih dari 24 jam', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 6),
          for (final d in s.ownerAlerts) DocCard(doc: d),
        ],
        if (s.isOwner) _salesCard(context, s),
        const SizedBox(height: 16),
        const Text('Terbaru', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (recent.isEmpty) const Text('Belum ada dokumen', style: TextStyle(color: Colors.grey)),
        for (final d in recent) DocCard(doc: d),
      ]),
    );
  }
}
