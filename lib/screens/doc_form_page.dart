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

  /// Validasi form. Mengembalikan daftar baris bila valid; bila tidak, mengisi pesan error dan mengembalikan null.
  List<Map<String, dynamic>>? _payload() {
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
    setState(() => error = null);
    return payload;
  }

  Future<void> _submit() async {
    final p = _payload();
    if (p != null) await _simpan(p);
  }

  /// Barang Masuk: tampilkan pratinjau (cek kecocokan + koreksi) dulu, baru simpan.
  Future<void> _pratinjau() async {
    if (_payload() == null) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => _PratinjauSheet(
        lines: lines,
        supplier: supplier.text.trim(),
        note: note.text.trim(),
        onRemove: (l) => setState(() => lines.remove(l)),
      ),
    );
    if (ok != true || !mounted) return;
    final payload = _payload();
    if (payload == null) return;
    await _simpan(payload);
  }

  Future<void> _simpan(List<Map<String, dynamic>> payload) async {
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
                  ? 'Cek dulu lewat Pratinjau. Stok gudang bertambah setelah Anda menyimpan dari pratinjau. Harga wajib diisi: owner akan memverifikasi harga dan pembelian.'
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
          onPressed: saving ? null : (t == 'masuk' ? _pratinjau : _submit),
          icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(t == 'masuk' ? Icons.fact_check_outlined : Icons.send),
          label: Text(t == 'masuk' ? 'Pratinjau Barang Masuk' : (t == 'minta_cabang' ? 'Kirim Permintaan' : 'Simpan & Kirim')),
        ),
        const SizedBox(height: 20),
      ]),
    );
  }
}

/// Pratinjau Barang Masuk: cocokkan catatan dengan barang fisik/nota, koreksi bila salah, lalu simpan.
class _PratinjauSheet extends StatefulWidget {
  final List<_FLine> lines;
  final String supplier, note;
  final void Function(_FLine) onRemove;
  const _PratinjauSheet({required this.lines, required this.supplier, required this.note, required this.onRemove});
  @override
  State<_PratinjauSheet> createState() => _PratinjauSheetState();
}

class _PratinjauSheetState extends State<_PratinjauSheet> {
  final cocok = <_FLine>{};

  double _q(_FLine l) => parseQty(l.qty.text) ?? 0;
  double _p(_FLine l) => parseQty(l.price.text) ?? 0;
  double get total => widget.lines.fold<double>(0, (a, l) => a + _q(l) * _p(l));

  /// Peringatan bila harga jauh berbeda dari pembelian terakhir barang yang sama (mis. salah nol).
  String? _aneh(AppState s, _FLine l) {
    final p = _p(l);
    if (p <= 0) return null;
    DateTime? t;
    double? last;
    for (final d in s.docs) {
      if (d.type != 'masuk' || d.status != 'diterima') continue;
      for (final x in d.lines) {
        if (x.itemId == l.item.id && x.price > 0 && (t == null || d.createdAt.isAfter(t))) {
          t = d.createdAt;
          last = x.price;
        }
      }
    }
    if (last == null) return null;
    if (p < last * 0.2 || p > last * 5) return 'Harga jauh beda dari pembelian terakhir (${rp(last)}). Cek lagi, mungkin kurang atau kelebihan nol.';
    return null;
  }
  bool get semua => widget.lines.isNotEmpty && widget.lines.every(cocok.contains);

  Future<void> _koreksi(_FLine l) async {
    final q = TextEditingController(text: l.qty.text);
    final p = TextEditingController(text: l.price.text);
    String? err;
    final res = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('Koreksi ${l.item.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: q,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Jumlah', suffixText: l.item.unit),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: p,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Harga satuan (per ${l.item.unit})', prefixText: 'Rp '),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: red))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, 'hapus'), child: const Text('Hapus baris', style: TextStyle(color: red))),
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final nq = parseQty(q.text);
                final np = parseQty(p.text);
                if (nq == null || nq <= 0) {
                  setS(() => err = 'Jumlah harus lebih dari 0');
                  return;
                }
                if (np == null || np <= 0) {
                  setS(() => err = 'Harga harus lebih dari 0');
                  return;
                }
                Navigator.pop(d, 'simpan');
              },
              child: const Text('Simpan koreksi'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (res == 'simpan') {
      setState(() {
        l.qty.text = q.text.trim();
        l.price.text = p.text.trim();
        cocok.remove(l); // yang dikoreksi harus dicek ulang
      });
    } else if (res == 'hapus') {
      widget.onRemove(l);
      setState(() => cocok.remove(l));
      if (widget.lines.isEmpty) Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ls = widget.lines;
    final st = context.read<AppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Pratinjau Barang Masuk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Grosir: ${widget.supplier}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Cocokkan dengan barang fisik dan nota. Centang barang yang sudah cocok. Ada yang salah? Ketuk Koreksi pada barangnya.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final l in ls)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                  decoration: cardDeco(),
                  child: Row(children: [
                    Checkbox(value: cocok.contains(l), onChanged: (v) => setState(() => v == true ? cocok.add(l) : cocok.remove(l))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${fmtQty(_q(l))} ${l.item.unit} x ${rp(_p(l))}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                        Text(rp(_q(l) * _p(l)), style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (_aneh(st, l) != null) Text(_aneh(st, l)!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: orange)),
                      ]),
                    ),
                    TextButton(onPressed: () => _koreksi(l), child: const Text('Koreksi')),
                  ]),
                ),
            ]),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => setState(() => cocok.addAll(ls)), child: const Text('Tandai semua cocok')),
          ),
          const Divider(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Expanded(child: Text('Total pembelian', style: TextStyle(fontWeight: FontWeight.w700))),
              Text(rp(total), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: navy)),
            ]),
          ),
          if (widget.note.isNotEmpty) Text('Catatan: ${widget.note}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Kembali ke form'))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(48)),
                onPressed: semua ? () => Navigator.pop(context, true) : null,
                child: Text(semua ? 'Simpan & masuk stok' : 'Cek dulu (${cocok.length}/${ls.length})'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
