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

  /// Validasi form. Mengembalikan payload, atau null (pesan error sudah diisi).
  List<Map<String, dynamic>>? _validate() {
    final payload = <Map<String, dynamic>>[];
    for (final l in lines) {
      final q = parseQty(l.qty.text);
      if (q == null || q <= 0) {
        setState(() => error = 'Isi jumlah untuk ${l.item.name}');
        return null;
      }
      final pr = parseQty(l.price.text) ?? 0;
      if (widget.type == 'masuk' && pr <= 0) {
        setState(() => error = 'Isi harga satuan untuk ${l.item.name}');
        return null;
      }
      payload.add({'item_id': l.item.id, 'qty': q, 'role': l.role, 'unit_price': pr});
    }
    if (payload.isEmpty) {
      setState(() => error = 'Tambahkan minimal satu bahan');
      return null;
    }
    if (widget.type == 'setor_jadi' && (!lines.any((l) => l.role == 'pakai') || !lines.any((l) => l.role == 'hasil'))) {
      setState(() => error = 'Isi bahan yang dipakai DAN hasil jadi');
      return null;
    }
    if (widget.type == 'masuk' && supplier.text.trim().isEmpty) {
      setState(() => error = 'Isi nama grosir / supplier');
      return null;
    }
    if (widget.type == 'kirim_cabang' && (branch == null || branch!.isEmpty)) {
      setState(() => error = 'Pilih cabang tujuan');
      return null;
    }
    return payload;
  }

  Future<void> _save(List<Map<String, dynamic>> payload) async {
    final s = context.read<AppState>();
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

  Future<void> _submit() async {
    final payload = _validate();
    if (payload == null) return;
    // Barang Masuk: tidak langsung disimpan, harus lewat pratinjau + pengecekan dulu.
    if (widget.type == 'masuk') {
      setState(() => error = null);
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => _MasukPreviewPage(lines: lines, supplier: supplier, note: note)),
      );
      if (!mounted) return;
      setState(() {}); // koreksi di pratinjau mengubah isi form
      if (ok != true) return;
      final fresh = _validate(); // validasi ulang setelah koreksi
      if (fresh == null) return;
      await _save(fresh);
      return;
    }
    await _save(payload);
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
          width: 92,
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
              decoration: const InputDecoration(labelText: 'Harga', isDense: true, border: OutlineInputBorder()),
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
                  ? 'Isi barang & harga, lalu tekan Pratinjau untuk mencocokkan dengan belanjaan/nota sebelum disimpan. Stok gudang bertambah setelah disimpan. Owner akan memverifikasi harga dan pembelian.'
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
          icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(t == 'masuk' ? Icons.fact_check_outlined : Icons.send),
          label: Text(t == 'masuk' ? 'Pratinjau & Cek' : (t == 'minta_cabang' ? 'Kirim Permintaan' : 'Simpan & Kirim')),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}


/// Pratinjau Barang Masuk: cocokkan tiap barang dengan belanjaan/nota, koreksi jika salah catat,
/// baru simpan. Mengubah controller milik form secara langsung, jadi koreksi ikut ke form.
class _MasukPreviewPage extends StatefulWidget {
  final List<_FLine> lines;
  final TextEditingController supplier, note;
  const _MasukPreviewPage({required this.lines, required this.supplier, required this.note});
  @override
  State<_MasukPreviewPage> createState() => _MasukPreviewPageState();
}

class _MasukPreviewPageState extends State<_MasukPreviewPage> {
  final checked = <_FLine>{};
  // nilai awal saat pratinjau dibuka, untuk menandai baris yang dikoreksi
  late final Map<_FLine, String> orig = {for (final l in widget.lines) l: _sig(l)};
  late final String origSupplier = widget.supplier.text.trim();

  static String _sig(_FLine l) => '${l.qty.text.trim()}|${l.price.text.trim()}';

  double _q(_FLine l) => parseQty(l.qty.text) ?? 0;
  double _p(_FLine l) => parseQty(l.price.text) ?? 0;
  double get total => widget.lines.fold(0.0, (a, l) => a + _q(l) * _p(l));
  bool get allChecked => widget.lines.isNotEmpty && widget.lines.every(checked.contains);

  Future<void> _editLine(_FLine l) async {
    final q = TextEditingController(text: l.qty.text);
    final p = TextEditingController(text: l.price.text);
    String? err;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Koreksi ${l.item.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: q,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Jumlah', suffixText: l.item.unit, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: p,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Harga per ${l.item.unit}', prefixText: 'Rp ', border: const OutlineInputBorder()),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: red, fontWeight: FontWeight.w600))),
          ]),
          actionsOverflowButtonSpacing: 4,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'hapus'), child: const Text('Hapus bahan', style: TextStyle(color: red))),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final nq = parseQty(q.text), np = parseQty(p.text);
                if (nq == null || nq <= 0) return setD(() => err = 'Jumlah harus lebih dari 0');
                if (np == null || np <= 0) return setD(() => err = 'Harga harus lebih dari 0');
                Navigator.pop(ctx, 'ok');
              },
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || res == null) return;
    if (res == 'hapus') {
      setState(() {
        widget.lines.remove(l);
        checked.remove(l);
      });
      if (widget.lines.isEmpty) Navigator.pop(context, false);
      return;
    }
    setState(() {
      l.qty.text = q.text.trim();
      l.price.text = p.text.trim();
      checked.remove(l); // yang dikoreksi harus dicek ulang
    });
  }

  Future<void> _editSupplier() async {
    final c = TextEditingController(text: widget.supplier.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Koreksi nama grosir / supplier'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim().isNotEmpty), child: const Text('Terapkan')),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => widget.supplier.text = c.text.trim());
  }

  Widget _lineCard(AppState s, _FLine l) {
    final q = _q(l), p = _p(l);
    final stok = s.stockAt('gudang', l.item.id);
    final edited = orig[l] != _sig(l);
    final ok = checked.contains(l);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: cardDeco(color: ok ? const Color(0xFFF0FAF3) : Colors.white),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(value: ok, activeColor: green, onChanged: (v) => setState(() => v == true ? checked.add(l) : checked.remove(l))),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(l.item.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                if (edited)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(10)),
                    child: const Text('Dikoreksi', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: orange)),
                  ),
              ]),
              const SizedBox(height: 2),
              Text('${fmtQty(q)} ${l.item.unit} × ${rp(p)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Subtotal ${rp(q * p)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 2),
              Text('Stok gudang: ${fmtQty(stok)} → ${fmtQty(stok + q)} ${l.item.unit}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ]),
          ),
        ),
        TextButton.icon(
          onPressed: () => _editLine(l),
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Koreksi'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final lines = widget.lines;
    final done = lines.where(checked.contains).length;
    final supplierEdited = origSupplier != widget.supplier.text.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Pratinjau Barang Masuk'), backgroundColor: navy, foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: cardDeco(color: const Color(0xFFFFF4E0)),
          child: const Text(
              'Belum tersimpan. Cocokkan tiap barang dengan belanjaan / nota grosir, lalu centang. Jika ada salah catat, tekan Koreksi. Tombol simpan aktif setelah semua barang dicentang.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: orange)),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: cardDeco(),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Grosir / supplier${supplierEdited ? ' (dikoreksi)' : ''}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                Text(widget.supplier.text.trim(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
            TextButton.icon(onPressed: _editSupplier, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Koreksi')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
          child: Text('Bahan yang dibeli ($done/${lines.length} dicek)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        for (final l in lines) _lineCard(s, l),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: cardDeco(color: const Color(0xFFEAF2FF)),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total belanja (${lines.length} bahan)', style: const TextStyle(fontWeight: FontWeight.w700, color: navy)),
            Text(rp(total), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: navy)),
          ]),
        ),
        if (widget.note.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Catatan: ${widget.note.text.trim()}', style: TextStyle(fontSize: 13, color: Colors.grey[800])),
          ),
        const SizedBox(height: 12),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Kembali ke Form'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(52)),
                onPressed: allChecked ? () => Navigator.pop(context, true) : null,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(allChecked ? 'Simpan Barang Masuk' : 'Cek semua dulu ($done/${lines.length})'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
