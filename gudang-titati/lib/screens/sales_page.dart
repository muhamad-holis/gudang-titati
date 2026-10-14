import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'sales_form_page.dart';

/// Sisa stok di cabang saat ini. Hijau jika masih ada, abu-abu jika habis.
class SisaChip extends StatelessWidget {
  final double sisa;
  final String unit;
  const SisaChip({super.key, required this.sisa, required this.unit});

  @override
  Widget build(BuildContext context) {
    final ada = sisa > 0.0001;
    final text = ada ? 'Sisa ${fmtQty(sisa)} $unit' : 'Habis';
    final bg = ada ? const Color(0xFFDCF5E3) : const Color(0xFFEDEDED);
    final fg = ada ? const Color(0xFF14753A) : const Color(0xFF555555);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }
}

class SalesPage extends StatefulWidget {
  final String? initialBranch;
  final bool standalone;
  const SalesPage({super.key, this.initialBranch, this.standalone = false});
  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  String? branch;
  String period = 'hari';

  static const periods = ['hari', 'kemarin', '7', 'bulan'];

  String _periodLabel(String p) {
    switch (p) {
      case 'hari':
        return 'Hari ini';
      case 'kemarin':
        return 'Kemarin';
      case '7':
        return '7 hari';
      default:
        return 'Bulan ini';
    }
  }

  List<DateTime> _range(String p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    switch (p) {
      case 'kemarin':
        final y = today.subtract(const Duration(days: 1));
        return [y, y];
      case '7':
        return [today.subtract(const Duration(days: 6)), today];
      case 'bulan':
        return [DateTime(n.year, n.month, 1), today];
      default:
        return [today, today];
    }
  }

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

  Future<void> _batal(AppState s, SaleEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Batalkan catatan ini?'),
        content: Text('${fmtQty(e.qty)} ${e.unit} ${e.itemName} akan dikembalikan ke stok cabang.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Tidak')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Batalkan')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.batalJual(e.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Catatan dibatalkan, stok dikembalikan')));
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(err))));
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me!;
    final isCabang = me.role == 'cabang';
    final branches = isCabang ? <String>[me.branch].where((b) => b.isNotEmpty).toList() : s.saleBranches;
    final wanted = branch ?? widget.initialBranch;
    final cur = (wanted != null && branches.contains(wanted)) ? wanted : (branches.isNotEmpty ? branches.first : null);
    final range = _range(period);
    final sums = cur == null ? <RekapSum>[] : s.rekapFor(cur, range[0], range[1]);
    final hist = cur == null ? <SaleEntry>[] : s.salesFor(cur, range[0], range[1]);
    final canceled = <int>{for (final e in s.sales) if (e.isCancel && e.refId != null) e.refId!};
    final kurang = cur == null ? <KurangRow>[] : s.kurangFor(cur, range[0], range[1]);
    final now = DateTime.now();

    Widget sumTile(RekapSum x) {
      final stok = cur == null ? 0.0 : s.stockAt(cur, x.itemId);
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            SisaChip(sisa: stok, unit: x.unit),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: Text('Masuk: ${fmtQty(x.masuk)} ${x.unit}', style: const TextStyle(fontSize: 13))),
            Expanded(child: Text('Terjual: ${fmtQty(x.terjual)} ${x.unit}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          ]),
        ]),
      );
    }

    Widget histTile(SaleEntry e) {
      final dead = e.kind == 'jual' && canceled.contains(e.id);
      final canCancel = e.kind == 'jual' && !dead && (s.isOwner || (isCabang && _sameDay(e.at, now)));
      final strike = dead ? TextDecoration.lineThrough : null;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: cardDeco(color: e.isCancel ? const Color(0xFFF6F6F6) : Colors.white),
        child: Row(children: [
          Icon(e.isCancel ? Icons.undo : Icons.point_of_sale, size: 20, color: e.isCancel ? Colors.grey : navy),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${e.isCancel ? 'Pembatalan: ' : ''}${fmtQty(e.qty)} ${e.unit} ${e.itemName}',
                style: TextStyle(fontWeight: FontWeight.w700, decoration: strike),
              ),
              Text(
                '${tglJam(e.at)} • ${e.byName}${e.reason.isEmpty ? '' : ' • ${e.reason}'}${dead ? ' • Dibatalkan' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
            ]),
          ),
          if (canCancel) TextButton(onPressed: () => _batal(s, e), child: const Text('Batal')),
        ]),
      );
    }

    final body = Column(children: [
      if (!isCabang && branches.length > 1) ...[
        const SizedBox(height: 10),
        _chips(branches, cur ?? '', (v) => v, (v) => setState(() => branch = v)),
      ],
      const SizedBox(height: 8),
      _chips(periods, period, _periodLabel, (v) => setState(() => period = v)),
      const SizedBox(height: 6),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => s.refresh(silent: true),
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 6, 12, 90), children: [
            if (s.salesError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: cardDeco(color: const Color(0xFFFFF4E0)),
                child: const Text(
                  'Data penjualan belum bisa dimuat. Jalankan supabase_update_penjualan.sql di Supabase SQL Editor, lalu tarik layar ke bawah untuk memuat ulang.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: orange),
                ),
              ),
            if (cur == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Belum ada cabang', style: TextStyle(color: Colors.grey)))),
            if (cur != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: cardDeco(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${locLabel(cur)} • ${_periodLabel(period)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    sums.isEmpty && kurang.isEmpty ? 'Belum ada barang masuk atau terjual pada periode ini' : '${sums.length} jenis barang',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Masuk = barang dari gudang yang sudah diterima. Sisa = stok di cabang sekarang.',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ]),
              ),
              if (kurang.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: cardDeco(color: const Color(0xFFFDE8E8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Barang kurang diterima', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: red)),
                    const SizedBox(height: 4),
                    for (final k in kurang)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${k.name}: kurang ${fmtQty(k.kurang)} ${k.unit} (dikirim ${fmtQty(k.dikirim)}, diterima ${fmtQty(k.diterima)})',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: red),
                        ),
                      ),
                  ]),
                ),
              ],
              const SizedBox(height: 10),
              for (final x in sums) sumTile(x),
              const Padding(padding: EdgeInsets.fromLTRB(2, 12, 2, 6), child: Text('Riwayat input penjualan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              if (hist.isEmpty) const Text('Belum ada penjualan dicatat', style: TextStyle(color: Colors.grey)),
              for (final e in hist) histTile(e),
            ],
          ]),
        ),
      ),
    ]);

    return Scaffold(
      backgroundColor: widget.standalone ? bgColor : Colors.transparent,
      appBar: widget.standalone
          ? AppBar(title: Text('Penjualan ${cur == null ? '' : locLabel(cur)}'), backgroundColor: navy, foregroundColor: Colors.white)
          : null,
      floatingActionButton: isCabang
          ? FloatingActionButton.extended(
              backgroundColor: green,
              foregroundColor: Colors.white,
              onPressed: () async {
                final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SalesFormPage()));
                if (ok == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penjualan tersimpan dan terlihat oleh owner')));
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Catat Penjualan'),
            )
          : null,
      body: body,
    );
  }
}
