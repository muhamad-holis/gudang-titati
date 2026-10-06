import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'item_picker.dart';

class MasterPage extends StatelessWidget {
  const MasterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Material(
          color: Colors.white,
          child: const TabBar(
            labelColor: navy,
            indicatorColor: blue,
            tabs: [Tab(text: 'Bahan mentah'), Tab(text: 'Bahan jadi'), Tab(text: 'Kategori'), Tab(text: 'Aturan ACC')],
          ),
        ),
        const Expanded(child: TabBarView(children: [_ItemsTab(kind: 'mentah'), _ItemsTab(kind: 'jadi'), _CategoryTab(), _RulesTab()])),
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
                    subtitle: Text.rich(TextSpan(children: [
                      TextSpan(text: '${it.category} • ${it.unit}${it.siapJual ? ' • siap jual' : (it.kind == 'mentah' ? ' • ${jalurLabel(it.jalur)}' : '')}${it.active ? '' : ' • nonaktif'}'),
                      if (kind == 'jadi')
                        it.rendemenStd == null
                            ? const TextSpan(text: ' • belum ada standar rendemen', style: TextStyle(color: orange, fontWeight: FontWeight.w700))
                            : TextSpan(text: ' • rendemen ${fmtQty(it.rendemenStd!)}'),
                    ])),
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

/// Aturan kapan owner perlu ACC: toleransi rendemen setoran dan batas permintaan cabang.
class _RulesTab extends StatelessWidget {
  const _RulesTab();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.rulesError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Aturan belum bisa dimuat.\nJalankan supabase_update_acc_selektif.sql di Supabase terlebih dahulu.\n\n${s.rulesError}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ),
      );
    }
    if (!s.rulesLoaded) return const Center(child: CircularProgressIndicator());
    return _RulesForm(rules: s.rules);
  }
}

class _RulesForm extends StatefulWidget {
  final AppRules rules;
  const _RulesForm({required this.rules});
  @override
  State<_RulesForm> createState() => _RulesFormState();
}

class _RulesFormState extends State<_RulesForm> {
  late final tol = TextEditingController(text: fmtQty(widget.rules.rendemenToleransi));
  late final faktor = TextEditingController(text: fmtQty(widget.rules.mintaFaktor));
  late final hari = TextEditingController(text: '${widget.rules.mintaHari}');
  late final minData = TextEditingController(text: '${widget.rules.mintaMinData}');
  bool saving = false;

  @override
  void dispose() {
    tol.dispose();
    faktor.dispose();
    hari.dispose();
    minData.dispose();
    super.dispose();
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _save() async {
    final t = parseQty(tol.text);
    final f = parseQty(faktor.text);
    final h = parseQty(hari.text);
    final m = parseQty(minData.text);
    if (t == null || t < 0 || t > 100) return _toast('Toleransi harus 0 sampai 100 persen');
    if (f == null || f <= 1) return _toast('Batas permintaan harus lebih dari 1 kali');
    if (h == null || h < 1) return _toast('Jumlah hari minimal 1');
    if (m == null || m < 1) return _toast('Minimal data minimal 1');
    setState(() => saving = true);
    try {
      await context.read<AppState>().setRules(t, f, h.round(), m.round());
      if (mounted) _toast('Aturan disimpan');
    } catch (e) {
      if (mounted) _toast(errText(e));
    }
    if (mounted) setState(() => saving = false);
  }

  Widget _field(TextEditingController c, String label, String suffix) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
        ),
      );

  Widget _card(String title, String body, List<Widget> fields) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(body, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ...fields,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: cardDeco(color: const Color(0xFFEAF2FF)),
        child: const Text(
            'Owner selalu di-ACC untuk: Barang Masuk (verifikasi harga). Setoran produksi dan permintaan cabang hanya minta ACC jika menyimpang menurut aturan di bawah. Lainnya tanpa ACC.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: navy)),
      ),
      _card(
        'Setor hasil produksi',
        'Hasil jadi dihitung kembali ke bahan mentah lewat rendemen standar tiap bahan jadi (isi di tab Bahan jadi). Jika bahan yang dipakai berbeda dari perhitungan lebih dari toleransi, setoran menunggu ACC owner. Bahan jadi tanpa standar rendemen selalu minta ACC. Satuan bahan yang dipakai sebaiknya sama (mis. semua kg).',
        [_field(tol, 'Toleransi selisih', '%')],
      ),
      _card(
        'Permintaan cabang',
        'Jika jumlah satu barang lebih dari batas kali rata-rata permintaan cabang itu (yang sudah dikirim dalam beberapa hari terakhir), permintaan menunggu ACC owner. Data yang kurang dari minimum dianggap normal.',
        [
          _field(faktor, 'Batas di atas rata-rata', 'kali'),
          _field(hari, 'Rata-rata dihitung dari', 'hari terakhir'),
          _field(minData, 'Minimal permintaan sebelumnya', 'kali'),
        ],
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(50)),
        onPressed: saving ? null : _save,
        icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
        label: const Text('Simpan aturan'),
      ),
      const SizedBox(height: 20),
    ]);
  }
}
