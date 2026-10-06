import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'item_picker.dart';

class _FLine {
  final Item item;
  final String role;
  final TextEditingController qty = TextEditingController();
  final TextEditingController price = TextEditingController();
  _FLine(this.item, this.role);
  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

class DocFormPage extends StatefulWidget {
  final String type;
  const DocFormPage({super.key, required this.type});
  @override
  State<DocFormPage> createState() => _DocFormPageState();
}

class _DocFormPageState extends State<DocFormPage> {
  final lines = <_FLine>[];
  final supplier = TextEditingController();
  final note = TextEditingController();
  bool saving = false;
  String? error;
  String? branch; // cabang tujuan (khusus Kirim ke Cabang)

  @override
  void dispose() {
    for (final l in lines) {
      l.dispose();
    }
    supplier.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _add(String role, String kind, {String? stockLocation, bool sellable = false, bool noSiap = false}) async {
    final it = await pickItem(context, kind: sellable ? null : kind, stockLocation: stockLocation, sellable: sellable, noSiap: noSiap);
    if (it == null || !mounted) return;
    if (lines.any((l) => l.item.id == it.id && l.role == role)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bahan itu sudah ada di daftar')));
      return;
    }
    setState(() => lines.add(_FLine(it, role)));
  }

  Future<void> _submit() async {
    final s = context.read<AppState>();
    final payload = <Map<String, dynamic>>[];
    for (final l in lines) {
      final q = parseQty(l.qty.text);
      if (q == null || q <= 0) {
        setState(() => error = 'Isi jumlah untuk ${l.item.name}');
        return;
      }
      final pr = parseQty(l.price.text) ?? 0;
      if (widget.type == 'masuk' && pr <= 0) {
        setState(() => error = 'Isi harga satuan untuk ${l.item.name}');
        return;
      }
      payload.add({'item_id': l.item.id, 'qty': q, 'role': l.role, 'unit_price': pr});
    }
    if (payload.isEmpty) {
      setState(() => error = 'Tambahkan minimal satu bahan');
      return;
    }
    if (widget.type == 'setor_jadi' && (!lines.any((l) => l.role == 'pakai') || !lines.any((l) => l.role == 'hasil'))) {
      setState(() => error = 'Isi bahan yang dipakai DAN hasil jadi');
      return;
    }
    if (widget.type == 'masuk' && supplier.text.trim().isEmpty) {
      setState(() => error = 'Isi nama grosir / supplier');
      return;
    }
    if (widget.type == 'kirim_cabang' && (branch == null || branch!.isEmpty)) {
      setState(() => error = 'Pilih cabang tujuan');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      // untuk Kirim ke Cabang, kolom "supplier" membawa nama cabang tujuan
      final doc = await s.createDoc(widget.type, widget.type == 'kirim_cabang' ? branch! : supplier.text.trim(), note.text.trim(), payload);
      if (mounted) Navigator.pop<Object>(context, doc ?? true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = errText(e);
        });
      }
    }
  }

  Widget _lineTile(AppState s, _FLine l, {String? stockLoc, bool withPrice = false}) {
    final stk = stockLoc == null ? null : s.stockAt(stockLoc, l.item.id);
    final q = parseQty(l.qty.text) ?? 0;
    final over = stk != null && q > stk;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: cardDeco(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${l.item.category} • ${l.item.unit}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            if (stk != null)
              Text('Stok tersedia: ${fmtQty(stk)} ${l.item.unit}${over ? ' (kurang)' : ''}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: over ? red : green)),
          ]),
        ),
        SizedBox(
          width: 84,
          child: TextField(
            controller: l.qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Jumlah', suffixText: l.item.unit, isDense: true, border: const OutlineInputBorder()),
          ),
        ),
        if (withPrice) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 92,
            child: TextField(
              controller: l.price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Harga/sat.', isDense: true, border: OutlineInputBorder()),
            ),
          ),
        ],
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          onPressed: () => setState(() {
            lines.remove(l);
            l.dispose();
          }),
        ),
      ]),
    );
  }

  Widget _section(AppState s, String title, String role, String kind, {String? stockLoc, bool withPrice = false, bool sellable = false, bool noSiap = false}) {
    final mine = lines.where((l) => l.role == role).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(2, 14, 2, 8), child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      for (final l in mine) _lineTile(s, l, stockLoc: stockLoc, withPrice: withPrice),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        onPressed: () => _add(role, kind, stockLocation: stockLoc, sellable: sellable, noSiap: noSiap),
        icon: const Icon(Icons.add),
        label: Text(sellable ? 'Tambah barang' : (kind == 'jadi' ? 'Tambah bahan jadi' : 'Tambah bahan mentah')),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final t = widget.type;
    return Scaffold(
      appBar: AppBar(title: Text(typeLabel(t)), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: cardDeco(color: const Color(0xFFEAF2FF)),
          child: Text(
              t == 'masuk'
                  ? 'Stok gudang langsung bertambah setelah disimpan. Harga wajib diisi: owner akan memverifikasi harga dan pembelian.'
                  : (t == 'kirim_cabang'
                      ? 'Kirim barang langsung ke cabang tanpa produksi dan tanpa ACC. Stok gudang langsung berkurang, cabang menekan Terima.'
                      : t == 'minta_cabang'
                      ? 'Permintaan masuk ke gudang. Jika jumlahnya jauh di atas biasanya, owner perlu ACC dulu.'
                      : (t == 'setor_jadi'
                          ? 'Jika hasil wajar sesuai standar, setoran langsung terkirim dan gudang menekan Terima. Jika jauh dari standar, owner perlu ACC dulu.'
                          : 'Setelah disimpan, barang dianggap terkirim dan stok pengirim berkurang. Penerima menekan Terima.')),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: navy)),
        ),
        if (t == 'masuk') ...[
          const SizedBox(height: 12),
          TextField(controller: supplier, decoration: const InputDecoration(labelText: 'Nama grosir / supplier', border: OutlineInputBorder())),
          _section(s, 'Bahan yang dibeli', 'item', 'mentah', withPrice: true),
        ],
        if (t == 'kirim_produksi') _section(s, 'Bahan mentah yang dikirim ke produksi', 'item', 'mentah', stockLoc: 'gudang', noSiap: true),
        if (t == 'setor_jadi') ...[
          _section(s, 'Bahan mentah yang dipakai', 'pakai', 'mentah', stockLoc: 'produksi', noSiap: true),
          _section(s, 'Hasil jadi yang disetor', 'hasil', 'jadi'),
        ],
        if (t == 'kirim_cabang') ...[
          const SizedBox(height: 12),
          if (s.profileBranches.isEmpty)
            const Text('Daftar cabang belum bisa dimuat. Pastikan supabase_update_kirim_cabang.sql sudah dijalankan, lalu tarik layar untuk menyegarkan.',
                style: TextStyle(color: red, fontWeight: FontWeight.w600))
          else
            DropdownButtonFormField<String>(
              value: branch,
              decoration: const InputDecoration(labelText: 'Kirim ke cabang', border: OutlineInputBorder()),
              items: [for (final b in s.profileBranches) DropdownMenuItem(value: b, child: Text(b))],
              onChanged: (v) => setState(() => branch = v),
            ),
          _section(s, 'Barang yang dikirim', 'item', 'jadi', stockLoc: 'gudang', sellable: true),
        ],
        if (t == 'minta_cabang') _section(s, 'Barang yang diminta', 'item', 'jadi', sellable: true),
        const SizedBox(height: 14),
        TextField(
          controller: note,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: t == 'minta_cabang' ? 'Catatan (mis. dibutuhkan kapan)' : 'Catatan (opsional)',
            border: const OutlineInputBorder(),
          ),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: red, fontWeight: FontWeight.w600))),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(52)),
          onPressed: saving ? null : _submit,
          icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
          label: Text(t == 'masuk' ? 'Simpan Barang Masuk' : (t == 'minta_cabang' ? 'Kirim Permintaan' : 'Simpan & Kirim')),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
