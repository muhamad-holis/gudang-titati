import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'item_picker.dart';

class MasterPage extends StatelessWidget {
  const MasterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Material(
          color: Colors.white,
          child: const TabBar(
            labelColor: navy,
            indicatorColor: blue,
            tabs: [Tab(text: 'Bahan mentah'), Tab(text: 'Bahan jadi'), Tab(text: 'Kategori')],
          ),
        ),
        const Expanded(child: TabBarView(children: [_ItemsTab(kind: 'mentah'), _ItemsTab(kind: 'jadi'), _CategoryTab()])),
      ]),
    );
  }
}

class _ItemsTab extends StatelessWidget {
  final String kind;
  const _ItemsTab({required this.kind});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.items.where((i) => i.kind == kind).toList()
      ..sort((a, b) {
        final c = a.category.compareTo(b.category);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        onPressed: () => addItemDialog(context, s, kind: kind),
        icon: const Icon(Icons.add),
        label: Text(kind == 'jadi' ? 'Tambah bahan jadi' : 'Tambah bahan mentah'),
      ),
      body: list.isEmpty
          ? Center(child: Text(kind == 'jadi' ? 'Belum ada bahan jadi' : 'Belum ada bahan mentah', style: const TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: list.length,
              itemBuilder: (c, i) {
                final it = list[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: cardDeco(),
                  child: ListTile(
                    dense: true,
                    onTap: () => editItemDialog(context, s, it),
                    title: Text(it.name, style: TextStyle(fontWeight: FontWeight.w700, color: it.active ? null : Colors.grey)),
                    subtitle: Text('${it.category} • ${it.unit}${it.siapJual ? ' • siap jual' : ''}${it.active ? '' : ' • nonaktif'}'),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                  ),
                );
              },
            ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab();

  Future<void> _add(BuildContext context, AppState s) async {
    final c = TextEditingController();
    String? err;
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: const Text('Tambah kategori'),
          content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: InputDecoration(labelText: 'Nama kategori', errorText: err)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
            FilledButton(
              onPressed: () async {
                if (c.text.trim().isEmpty) {
                  setS(() => err = 'Wajib diisi');
                  return;
                }
                try {
                  await s.addCategory(c.text);
                  if (d.mounted) Navigator.pop(d);
                } catch (e) {
                  if (d.mounted) setS(() => err = errText(e));
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, AppState s, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus kategori $name?'),
        content: const Text('Bahan yang sudah memakai kategori ini tetap ada. Kategori hanya hilang dari pilihan cepat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await s.deleteCategory(name);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        onPressed: () => _add(context, s),
        icon: const Icon(Icons.add),
        label: const Text('Tambah kategori'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
        for (final c in s.categories)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: cardDeco(),
            child: ListTile(
              dense: true,
              title: Text(c, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, color: red, size: 20), onPressed: () => _delete(context, s, c)),
            ),
          ),
      ]),
    );
  }
}
