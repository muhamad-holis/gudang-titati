import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'item_picker.dart';

Future<void> koreksiDialog(BuildContext context, AppState s, String location, Item item) async {
  final cur = s.stockAt(location, item.id);
  final qty = TextEditingController(text: fmtQty(cur));
  final reason = TextEditingController();
  String? err;
  var saving = false;
  await showDialog<void>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: const Text('Koreksi stok'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item.name} • ${locLabel(location)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Stok sekarang: ${fmtQty(cur)} ${item.unit}', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Stok seharusnya', suffixText: item.unit),
            ),
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'Alasan (wajib, mis. hasil hitung fisik)')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final q = parseQty(qty.text);
                    if (q == null || q < 0) {
                      setS(() => err = 'Jumlah tidak valid');
                      return;
                    }
                    if (reason.text.trim().isEmpty) {
                      setS(() => err = 'Alasan wajib diisi');
                      return;
                    }
                    setS(() {
                      saving = true;
                      err = null;
                    });
                    try {
                      await s.koreksiStok(location, item.id, q, reason.text.trim());
                      if (d.mounted) Navigator.pop(d);
                    } catch (e) {
                      if (d.mounted) {
                        setS(() {
                          saving = false;
                          err = errText(e);
                        });
                      }
                    }
                  },
            child: const Text('Simpan'),
          ),
        ],
      ),
    ),
  );
}

class StockPage extends StatefulWidget {
  const StockPage({super.key});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  String? loc;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final locs = s.locations;
    final cur = (loc != null && locs.contains(loc)) ? loc! : locs.first;
    final rows = s.stock.where((r) => r.location == cur && r.qty != 0).toList()
      ..sort((a, b) {
        final k = a.kind.compareTo(b.kind);
        if (k != 0) return k;
        final c = a.category.compareTo(b.category);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    final siap = rows.where((r) => s.isSiapJual(r.itemId)).toList();
    final mentah = rows.where((r) => r.kind == 'mentah' && !s.isSiapJual(r.itemId)).toList();
    final jadi = rows.where((r) => r.kind == 'jadi').toList();

    Widget tile(StockRow r) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: cardDeco(),
          child: ListTile(
            dense: true,
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Builder(builder: (_) {
              final it = s.itemById(r.itemId);
              final low = cur == 'gudang' && it != null && it.stokMin > 0 && r.qty <= it.stokMin;
              if (!low) return Text(r.category);
              return Text.rich(TextSpan(children: [
                TextSpan(text: '${r.category} • '),
                TextSpan(text: 'menipis (min ${fmtQty(it.stokMin)})', style: const TextStyle(color: orange, fontWeight: FontWeight.w700)),
              ]));
            }),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${fmtQty(r.qty)} ${r.unit}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: r.qty < 0 ? red : navy)),
              if (s.isOwner)
                IconButton(
                  tooltip: 'Koreksi stok',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: () {
                    final it = s.items.where((i) => i.id == r.itemId).toList();
                    if (it.isNotEmpty) koreksiDialog(context, s, cur, it.first);
                  },
                ),
            ]),
          ),
        );

    Widget head(String t, int n) => Padding(padding: const EdgeInsets.fromLTRB(2, 12, 2, 6), child: Text('$t ($n)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: s.isOwner
          ? FloatingActionButton.extended(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              onPressed: () async {
                final it = await pickItem(context);
                if (it != null && context.mounted) await koreksiDialog(context, s, cur, it);
              },
              icon: const Icon(Icons.tune),
              label: const Text('Koreksi stok'),
            )
          : null,
      body: Column(children: [
        if (locs.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final l in locs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(locLabel(l)),
                      selected: cur == l,
                      showCheckmark: false,
                      selectedColor: blue,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(color: cur == l ? Colors.white : navy, fontWeight: FontWeight.w600),
                      shape: const StadiumBorder(side: BorderSide(color: lineColor)),
                      onSelected: (_) => setState(() => loc = l),
                    ),
                  ),
              ]),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => s.refresh(silent: true),
            child: rows.isEmpty
                ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text('Stok ${locLabel(cur)} kosong', style: const TextStyle(color: Colors.grey))))])
                : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), children: [
                    if (siap.isNotEmpty) ...[head('Barang siap jual', siap.length), for (final r in siap) tile(r)],
                    if (mentah.isNotEmpty) ...[head('Bahan mentah', mentah.length), for (final r in mentah) tile(r)],
                    if (jadi.isNotEmpty) ...[head('Bahan jadi', jadi.length), for (final r in jadi) tile(r)],
                  ]),
          ),
        ),
      ]),
    );
  }
}
