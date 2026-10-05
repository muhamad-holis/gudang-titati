import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';

const _units = ['kg', 'gram', 'liter', 'pcs', 'pak', 'ikat', 'butir', 'porsi', 'bungkus'];

Widget _chipRow(List<String> values, TextEditingController c, void Function(VoidCallback) setS) {
  return Wrap(spacing: 6, runSpacing: 0, children: [
    for (final v in values) ActionChip(label: Text(v, style: const TextStyle(fontSize: 12)), onPressed: () => setS(() => c.text = v)),
  ]);
}

List<String> categoryChoices(AppState s, String kind) {
  final fromItems = s.items.where((i) => i.kind == kind).map((i) => i.category);
  final base = kind == 'jadi' ? ['Bahan jadi'] : <String>[];
  return {...base, ...s.categories, ...fromItems}.toList();
}

/// Pilih bahan (kind null = semua jenis).
/// sellable = hanya bahan jadi + barang siap jual. noSiap = sembunyikan barang siap jual.
Future<Item?> pickItem(BuildContext context, {String? kind, String? stockLocation, bool sellable = false, bool noSiap = false}) {
  return showModalBottomSheet<Item>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PickSheet(kind: kind, stockLocation: stockLocation, sellable: sellable, noSiap: noSiap),
  );
}

class _PickSheet extends StatefulWidget {
  final String? kind;
  final String? stockLocation;
  final bool sellable, noSiap;
  const _PickSheet({required this.kind, required this.stockLocation, this.sellable = false, this.noSiap = false});
  @override
  State<_PickSheet> createState() => _PickSheetState();
}

class _PickSheetState extends State<_PickSheet> {
  String q = '';
  String cat = 'Semua';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final all = s.items
        .where((i) =>
            i.active &&
            (widget.kind == null || i.kind == widget.kind) &&
            (!widget.sellable || i.kind == 'jadi' || i.siapJual) &&
            (!widget.noSiap || !i.siapJual))
        .toList();
    final cats = ['Semua', ...({...all.map((i) => i.category)}.toList()..sort())];
    final list = all.where((i) => (cat == 'Semua' || i.category == cat) && i.name.toLowerCase().contains(q.toLowerCase())).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: InputDecoration(
                hintText: 'Cari bahan...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c)),
                ),
            ]),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Bahan tidak ditemukan', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final it = list[i];
                      final stk = widget.stockLocation == null ? null : s.stockAt(widget.stockLocation!, it.id);
                      return ListTile(
                        title: Text(it.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${it.category} • ${it.unit}${it.siapJual ? ' • siap jual' : ''}${stk == null ? '' : ' • stok ${_f(stk)}'}'),
                        onTap: () => Navigator.pop(context, it),
                      );
                    },
                  ),
          ),
          if (s.role != 'cabang')
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                onPressed: () async {
                  final it = await addItemDialog(context, s, kind: widget.kind);
                  if (it != null && context.mounted) Navigator.pop(context, it);
                },
                icon: const Icon(Icons.add),
                label: const Text('Tambah bahan baru'),
              ),
            ),
        ]),
      ),
    );
  }

  String _f(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);
}

/// Tambah bahan baru. kind null = pengguna memilih jenisnya.
Future<Item?> addItemDialog(BuildContext context, AppState s, {String? kind}) {
  final name = TextEditingController();
  final unit = TextEditingController(text: 'kg');
  var k = kind ?? 'mentah';
  var siap = false;
  final cat = TextEditingController(text: k == 'jadi' ? 'Bahan jadi' : '');
  String? err;
  var saving = false;
  return showDialog<Item>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text(kind == null ? 'Tambah bahan' : (kind == 'jadi' ? 'Tambah bahan jadi' : 'Tambah bahan mentah')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (kind == null)
              Row(children: [
                ChoiceChip(label: const Text('Bahan mentah'), selected: k == 'mentah', onSelected: (_) => setS(() => k = 'mentah')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Bahan jadi'), selected: k == 'jadi', onSelected: (_) => setS(() => k = 'jadi')),
              ]),
            TextField(controller: name, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Nama bahan')),
            const SizedBox(height: 8),
            TextField(controller: cat, decoration: const InputDecoration(labelText: 'Kategori')),
            _chipRow(categoryChoices(s, k), cat, setS),
            const SizedBox(height: 8),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Satuan')),
            _chipRow(_units, unit, setS),
            if (k == 'mentah')
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Barang siap jual', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Dikirim gudang langsung ke cabang tanpa produksi (mis. air mineral)', style: TextStyle(fontSize: 12)),
                value: siap,
                onChanged: (v) => setS(() => siap = v ?? false),
              ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: red))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (name.text.trim().isEmpty || cat.text.trim().isEmpty || unit.text.trim().isEmpty) {
                      setS(() => err = 'Nama, kategori, dan satuan wajib diisi');
                      return;
                    }
                    setS(() {
                      saving = true;
                      err = null;
                    });
                    try {
                      final it = await s.addItem(name.text, k, cat.text, unit.text, siapJual: k == 'mentah' && siap);
                      if (d.mounted) Navigator.pop(d, it);
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

/// Ubah bahan (owner). Mengembalikan true jika tersimpan.
Future<bool?> editItemDialog(BuildContext context, AppState s, Item it) {
  final name = TextEditingController(text: it.name);
  final cat = TextEditingController(text: it.category);
  final unit = TextEditingController(text: it.unit);
  var active = it.active;
  var siap = it.siapJual;
  String? err;
  var saving = false;
  return showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, setS) => AlertDialog(
        title: Text('Ubah ${it.kind == 'jadi' ? 'bahan jadi' : 'bahan mentah'}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama bahan')),
            const SizedBox(height: 8),
            TextField(controller: cat, decoration: const InputDecoration(labelText: 'Kategori')),
            _chipRow(categoryChoices(s, it.kind), cat, setS),
            const SizedBox(height: 8),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Satuan')),
            _chipRow(_units, unit, setS),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Aktif (muncul di pilihan)'), value: active, onChanged: (v) => setS(() => active = v)),
            if (it.kind == 'mentah')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Barang siap jual'),
                subtitle: const Text('Gudang kirim langsung ke cabang, tanpa produksi', style: TextStyle(fontSize: 12)),
                value: siap,
                onChanged: (v) => setS(() => siap = v),
              ),
            if (err != null) Text(err!, style: const TextStyle(color: red)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (name.text.trim().isEmpty || cat.text.trim().isEmpty || unit.text.trim().isEmpty) {
                      setS(() => err = 'Nama, kategori, dan satuan wajib diisi');
                      return;
                    }
                    setS(() => saving = true);
                    try {
                      await s.updateItem(it.id, name: name.text, category: cat.text, unit: unit.text, active: active, siapJual: (it.kind == 'mentah' && siap != it.siapJual) ? siap : null);
                      if (d.mounted) Navigator.pop(d, true);
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
