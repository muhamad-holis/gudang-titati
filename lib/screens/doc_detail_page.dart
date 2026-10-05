import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

class DocDetailPage extends StatefulWidget {
  final String docId;
  const DocDetailPage({super.key, required this.docId});
  @override
  State<DocDetailPage> createState() => _DocDetailPageState();
}

class _DocDetailPageState extends State<DocDetailPage> {
  List<LogEntry> log = [];
  bool busy = false;
  bool editing = false;
  final ctrls = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  @override
  void dispose() {
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLog() async {
    final s = context.read<AppState>();
    try {
      final l = await s.fetchLog(widget.docId);
      if (mounted) setState(() => log = l);
    } catch (_) {}
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _run(Future<void> Function() fn, String okMsg) async {
    setState(() => busy = true);
    try {
      await fn();
      await _loadLog();
      if (mounted) _toast(okMsg);
      if (mounted) setState(() => editing = false);
    } catch (e) {
      if (mounted) _toast(errText(e));
    }
    if (mounted) setState(() => busy = false);
  }

  void _startEdit(Doc d) {
    for (final l in d.lines) {
      final c = ctrls.putIfAbsent(l.id, () => TextEditingController());
      c.text = fmtQty(l.qty);
    }
    setState(() => editing = true);
  }

  /// Hanya baris yang jumlahnya berubah (0 = hapus baris).
  List<Map<String, dynamic>> _editPayload(Doc d) {
    final out = <Map<String, dynamic>>[];
    for (final l in d.lines) {
      final q = parseQty(ctrls[l.id]?.text ?? '');
      if (q == null) continue;
      if ((q - l.qty).abs() > 0.0001) out.add({'line_id': l.id, 'qty': q});
    }
    return out;
  }

  Future<String?> _noteDialog(String title, {bool required = false, String label = 'Catatan (opsional)', String okText = 'Lanjut'}) {
    final c = TextEditingController();
    String? err;
    return showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(title),
          content: TextField(controller: c, autofocus: required, maxLines: 2, decoration: InputDecoration(labelText: label, errorText: err)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (required && c.text.trim().isEmpty) {
                  setS(() => err = 'Wajib diisi');
                  return;
                }
                Navigator.pop(d, c.text.trim());
              },
              child: Text(okText),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title, String body, String okText) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(okText)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _acc(AppState s, Doc d) async {
    final payload = editing ? _editPayload(d) : <Map<String, dynamic>>[];
    final note = await _noteDialog(payload.isEmpty ? 'ACC dokumen ini?' : 'ACC dengan jumlah diubah?', okText: 'ACC');
    if (note == null) return;
    await _run(() => s.ownerDecide(d.id, 'acc', note: note, lines: payload.isEmpty ? null : payload), 'Dokumen disetujui');
  }

  Future<void> _tolak(AppState s, Doc d) async {
    final note = await _noteDialog('Tolak dokumen ini?', required: true, label: 'Alasan penolakan', okText: 'Tolak');
    if (note == null) return;
    await _run(() => s.ownerDecide(d.id, 'tolak', note: note), 'Dokumen ditolak');
  }

  Future<void> _saveEdit(AppState s, Doc d) async {
    final payload = _editPayload(d);
    if (payload.isEmpty) {
      _toast('Tidak ada perubahan');
      setState(() => editing = false);
      return;
    }
    await _run(() => s.ownerEdit(d.id, payload), 'Jumlah diperbarui');
  }

  Future<void> _kirim(AppState s, Doc d) async {
    final extra = d.type == 'setor_jadi' ? ' Bahan yang dipakai akan dikurangi dari stok produksi.' : ' Stok pengirim akan dikurangi.';
    if (!await _confirm('Kirim sekarang?', 'Barang dianggap sudah dikirim.$extra', 'Kirim')) return;
    await _run(() => s.sendDoc(d.id), 'Ditandai terkirim');
  }

  Future<void> _terima(AppState s, Doc d) async {
    final lines = d.receivable;
    final cs = {for (final l in lines) l.id: TextEditingController(text: fmtQty(l.qty))};
    String? err;
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, setS) => AlertDialog(
          title: const Text('Konfirmasi terima'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Isi jumlah yang BENAR-BENAR diterima. Jika berbeda dari yang dikirim, selisih tercatat dan terlihat owner.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(child: Text('${l.name}\nDikirim ${fmtQty(l.qty)} ${l.unit}', style: const TextStyle(fontSize: 13))),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: cs[l.id],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(suffixText: l.unit, isDense: true, border: const OutlineInputBorder()),
                      ),
                    ),
                  ]),
                ),
              if (err != null) Text(err!, style: const TextStyle(color: red)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final out = <Map<String, dynamic>>[];
                for (final l in lines) {
                  final q = parseQty(cs[l.id]!.text);
                  if (q == null || q < 0 || q > l.qty + 0.0001) {
                    setS(() => err = 'Jumlah ${l.name} harus 0 sampai ${fmtQty(l.qty)}');
                    return;
                  }
                  out.add({'line_id': l.id, 'qty_received': q});
                }
                Navigator.pop(dlg, out);
              },
              child: const Text('Terima'),
            ),
          ],
        ),
      ),
    );
    for (final c in cs.values) {
      c.dispose();
    }
    if (result == null) return;
    await _run(() => s.receiveDoc(d.id, result), 'Barang diterima, stok diperbarui');
  }

  Future<void> _batal(AppState s, Doc d) async {
    if (!await _confirm('Batalkan dokumen?', 'Dokumen ini dibatalkan dan tidak diproses owner.', 'Batalkan')) return;
    await _run(() => s.cancelDoc(d.id), 'Dokumen dibatalkan');
  }

  Widget _kv(String a, String b, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 108, child: Text(a, style: TextStyle(color: Colors.grey[700], fontSize: 13))),
          Expanded(child: Text(b, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: color))),
        ]),
      );

  Widget _lineTile(Doc d, DocLine l) {
    final diff = l.qtyReceived != null && (l.qtyReceived! - l.qty).abs() > 0.0001 && (d.type != 'setor_jadi' || l.role == 'hasil');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: cardDeco(),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (d.type == 'masuk' && l.price > 0) Text('${rp(l.price)} / ${l.unit} • total ${rp(l.price * l.qty)}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            if (l.qtyReceived != null && (d.type != 'setor_jadi' || l.role == 'hasil') && d.type != 'masuk')
              Text('Diterima ${fmtQty(l.qtyReceived!)} ${l.unit}${diff ? '  (selisih ${fmtQty(l.qtyReceived! - l.qty)})' : ''}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: diff ? red : green)),
          ]),
        ),
        if (editing)
          SizedBox(
            width: 96,
            child: TextField(
              controller: ctrls[l.id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(suffixText: l.unit, isDense: true, border: const OutlineInputBorder()),
            ),
          )
        else
          Text('${fmtQty(l.qty)} ${l.unit}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 12, 2, 6), child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final d = s.docById(widget.docId);
    if (d == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dokumen'), backgroundColor: navy, foregroundColor: Colors.white),
        body: const Center(child: Text('Dokumen tidak ditemukan')),
      );
    }

    final canOwnerDecide = s.isOwner && d.status == 'diajukan';
    final canOwnerEdit = s.isOwner && d.status == 'disetujui';
    final canSend = d.status == 'disetujui' && d.type != 'masuk' && s.isSender(d);
    final canReceive = d.status == 'dikirim' && s.isReceiver(d);
    final canCancel = d.status == 'diajukan' && s.isCreator(d);
    final hasBar = canOwnerDecide || canOwnerEdit || canSend || canReceive || canCancel;

    Widget? bar;
    if (hasBar) {
      final buttons = <Widget>[];
      Widget fb(String t, IconData i, VoidCallback? f, {Color c = blue}) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c, minimumSize: const Size.fromHeight(48), padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: busy ? null : f,
                icon: Icon(i, size: 18),
                label: Text(t, style: const TextStyle(fontSize: 13)),
              ),
            ),
          );
      if (canOwnerDecide) {
        if (editing) {
          buttons.add(fb('Batal ubah', Icons.close, () => setState(() => editing = false), c: Colors.grey));
          buttons.add(fb('Simpan & ACC', Icons.check, () => _acc(s, d), c: green));
        } else {
          buttons.add(fb('Tolak', Icons.block, () => _tolak(s, d), c: red));
          buttons.add(fb('Ubah jumlah', Icons.edit_outlined, () => _startEdit(d), c: navy2));
          buttons.add(fb('ACC', Icons.check, () => _acc(s, d), c: green));
        }
      }
      if (canOwnerEdit) {
        if (editing) {
          buttons.add(fb('Batal', Icons.close, () => setState(() => editing = false), c: Colors.grey));
          buttons.add(fb('Simpan perubahan', Icons.check, () => _saveEdit(s, d), c: green));
        } else {
          buttons.add(fb('Ubah jumlah', Icons.edit_outlined, () => _startEdit(d), c: navy2));
        }
      }
      if (canSend) buttons.add(fb('Kirim', Icons.local_shipping_outlined, () => _kirim(s, d), c: blue));
      if (canReceive) buttons.add(fb('Terima barang', Icons.inventory_outlined, () => _terima(s, d), c: green));
      if (canCancel) buttons.add(fb('Batalkan', Icons.cancel_outlined, () => _batal(s, d), c: red));
      bar = SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: lineColor))),
          child: Row(children: buttons),
        ),
      );
    }

    final total = d.type == 'masuk' ? d.lines.fold<double>(0, (a, l) => a + l.price * l.qty) : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(d.no), backgroundColor: navy, foregroundColor: Colors.white),
      bottomNavigationBar: bar,
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(typeLabel(d.type), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              StatusChip(d.status),
            ]),
            const SizedBox(height: 8),
            _kv('Dibuat', '${tglJam(d.createdAt)} oleh ${d.createdByName}'),
            if (d.branch.isNotEmpty) _kv('Cabang', d.branch),
            if (d.supplier.isNotEmpty) _kv('Grosir', d.supplier),
            if (d.note.isNotEmpty) _kv('Catatan', d.note),
            if (d.approvedAt != null) _kv(d.status == 'ditolak' ? 'Ditolak' : 'Diputuskan', '${tglJam(d.approvedAt!)} oleh ${d.approvedByName}'),
            if (d.ownerNote.isNotEmpty) _kv(d.status == 'ditolak' ? 'Alasan' : 'Catatan owner', d.ownerNote, color: d.status == 'ditolak' ? red : null),
            if (d.sentAt != null) _kv('Dikirim', tglJam(d.sentAt!)),
            if (d.receivedAt != null) _kv('Diterima', '${tglJam(d.receivedAt!)}${d.receivedByName.isEmpty ? '' : ' oleh ${d.receivedByName}'}'),
            if (total > 0) _kv('Total pembelian', rp(total)),
            if (d.hasDiff) _kv('Selisih', 'Ada selisih jumlah diterima', color: red),
          ]),
        ),
        if (editing)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: cardDeco(color: const Color(0xFFFFF4E0)),
            child: const Text('Ubah jumlah di bawah. Isi 0 untuk menghapus baris.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: orange)),
          ),
        if (d.type == 'setor_jadi') ...[
          _sectionTitle('Bahan mentah dipakai'),
          for (final l in d.lines.where((l) => l.role == 'pakai')) _lineTile(d, l),
          _sectionTitle('Hasil jadi'),
          for (final l in d.lines.where((l) => l.role == 'hasil')) _lineTile(d, l),
        ] else ...[
          _sectionTitle('Barang'),
          for (final l in d.lines) _lineTile(d, l),
        ],
        _sectionTitle('Riwayat'),
        if (log.isEmpty) const Text('...', style: TextStyle(color: Colors.grey)),
        for (final e in log)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${tglJam(e.at)} • ${e.byName} (${roleLabel(e.byRole)})\n${e.action}${e.detail.isEmpty ? '' : ': ${e.detail}'}',
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            ),
          ),
        const SizedBox(height: 20),
      ]),
    );
  }
}
