import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

class SalesFormPage extends StatefulWidget {
  const SalesFormPage({super.key});
  @override
  State<SalesFormPage> createState() => _SalesFormPageState();
}

class _SalesFormPageState extends State<SalesFormPage> {
  final ctrls = <String, TextEditingController>{};
  final note = TextEditingController();
  bool saving = false;
  String? error;

  TextEditingController _c(String itemId) => ctrls.putIfAbsent(itemId, () => TextEditingController());

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    note.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState s, List<StockRow> rows) async {
    final payload = <Map<String, dynamic>>[];
    for (final r in rows) {
      final t = _c(r.itemId).text.trim();
      if (t.isEmpty) continue;
      final q = parseQty(t);
      if (q == null || q <= 0) {
        setState(() => error = 'Jumlah ${r.name} tidak valid');
        return;
      }
      if (q > r.qty + 0.0001) {
        setState(() => error = 'Terjual ${r.name} (${fmtQty(q)}) melebihi stok (${fmtQty(r.qty)} ${r.unit})');
        return;
      }
      payload.add({'item_id': r.itemId, 'qty': q});
    }
    if (payload.isEmpty) {
      setState(() => error = 'Isi jumlah terjual minimal untuk satu barang');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await s.catatJual(note.text.trim(), payload);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final branch = s.me?.branch ?? '';
    final rows = s.stock.where((r) => r.location == branch && s.sellable(r.itemId) && r.qty > 0).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Catat Penjualan'), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: cardDeco(color: const Color(0xFFE6EEFB)),
          child: const Text(
            'Isi jumlah barang yang terjual saja. Kosongkan barang yang tidak terjual. Stok cabang langsung berkurang dan owner bisa melihatnya.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: blue),
          ),
        ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(),
            child: const Text('Belum ada stok barang di cabang ini. Stok muncul setelah permintaan diterima.', style: TextStyle(color: Colors.grey)),
          ),
        for (final r in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: cardDeco(),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('Stok: ${fmtQty(r.qty)} ${r.unit}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () => setState(() => _c(r.itemId).text = fmtQty(r.qty)),
                    child: const Text('Terjual semua', style: TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _c(r.itemId),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Terjual', suffixText: r.unit, isDense: true, border: const OutlineInputBorder()),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder()),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: red, fontWeight: FontWeight.w600))),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(52)),
          onPressed: (saving || rows.isEmpty) ? null : () => _submit(s, rows),
          icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
          label: const Text('Simpan Penjualan'),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
