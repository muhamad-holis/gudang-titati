import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bon.dart';
import '../models.dart';
import '../state.dart';
import '../tagihan.dart';
import '../theme.dart';
import '../utils.dart';
import 'nota_page.dart';
import 'pembayaran.dart';

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
    final title = d.belumVerif ? 'Verifikasi pembelian ini?' : (payload.isEmpty ? 'ACC dokumen ini?' : 'ACC dengan jumlah diubah?');
    final note = await _noteDialog(title, okText: d.belumVerif ? 'Verifikasi' : 'ACC');
    if (note == null) return;
    await _run(() => s.ownerDecide(d.id, 'acc', note: note, lines: payload.isEmpty ? null : payload), d.belumVerif ? 'Pembelian diverifikasi' : 'Dokumen disetujui');
  }

  Future<void> _tolak(AppState s, Doc d) async {
    final note = await _noteDialog(d.belumVerif ? 'Tolak pembelian ini?' : 'Tolak dokumen ini?',
        required: true, label: d.belumVerif ? 'Alasan (stok yang sudah masuk tidak ditarik)' : 'Alasan penolakan', okText: 'Tolak');
    if (note == null) return;
    await _run(() => s.ownerDecide(d.id, 'tolak', note: note), d.belumVerif ? 'Pembelian ditandai ditolak' : 'Dokumen ditolak');
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
    final nKosong = d.type == 'minta_cabang' ? d.lines.where((l) => s.stockAt('gudang', l.itemId) < l.qty).length : 0;
    final infoKosong = nKosong > 0 ? '\n\n$nKosong barang stoknya kosong/kurang. Barang itu tetap dikirim sebesar stok yang ada dan ditandai KOSONG.' : '';
    // Permintaan Cabang: gudang menentukan harga jual sebelum kirim (jadi bon cabang)
    List<Map<String, dynamic>>? harga;
    if (d.type == 'minta_cabang' && s.role == 'gudang') {
      harga = await _dialogHarga(s, d, title: 'Harga jual ke ${d.branch}', okText: 'Lanjut');
      if (harga == null) return;
    }
    if (!await _confirm('Kirim sekarang?', 'Barang dianggap sudah dikirim.$extra$infoKosong', 'Kirim')) return;
    final payload = (editing && d.type == 'minta_cabang') ? _editPayload(d) : <Map<String, dynamic>>[];
    final hargaFinal = harga;
    await _run(() async {
      if (hargaFinal != null) await s.aturHargaJual(d.id, hargaFinal);
      await s.sendDoc(d.id, lines: payload.isEmpty ? null : payload);
    }, 'Ditandai terkirim');
  }

  /// Dialog harga jual per barang. Mengembalikan [{line_id, sell_price}] atau null bila dibatalkan.
  Future<List<Map<String, dynamic>>?> _dialogHarga(AppState s, Doc d, {required String title, required String okText}) async {
    final lines = d.lines.where((l) {
      if (editing && d.status == 'disetujui') {
        final q = parseQty(ctrls[l.id]?.text ?? '');
        if (q != null && q <= 0) return false; // baris yang dihapus gudang
      }
      return l.qty > 0 || d.status == 'disetujui';
    }).toList();
    final cs = <String, TextEditingController>{};
    for (final l in lines) {
      final awal = l.sellPrice > 0 ? l.sellPrice : s.hargaAwal(l.itemId, cabang: d.branch);
      cs[l.id] = TextEditingController(text: awal > 0 ? awal.round().toString() : '');
    }
    String? err;
    final res = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, setS) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Isi harga jual per satuan. Harga ini yang tercatat di bon cabang dan menjadi dasar omzet. Bahan jadi hasil produksi (mis. bakso) boleh dikosongkan dan diisi menyusul lewat Atur harga jual.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              for (final l in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Builder(builder: (_) {
                      final modal = s.modalRata(l.itemId);
                      final std = s.itemById(l.itemId)?.sellPriceDefault ?? 0;
                      final info = modal > 0
                          ? 'Modal rata-rata ${rp(modal)} / ${l.unit}'
                          : (s.hargaBolehKosong(l.itemId) ? 'Hasil produksi, modal belum dihitung' : 'Modal belum diketahui');
                      return Text('$info${std > 0 ? ' • harga standar ${rp(std)}' : ''}',
                          style: TextStyle(fontSize: 12, color: modal > 0 || s.hargaBolehKosong(l.itemId) ? Colors.grey[700] : orange));
                    }),
                    const SizedBox(height: 4),
                    TextField(
                      controller: cs[l.id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Harga jual / ${l.unit}', prefixText: 'Rp ', isDense: true, border: const OutlineInputBorder()),
                    ),
                  ]),
                ),
              if (err != null) Text(err!, style: const TextStyle(color: red, fontWeight: FontWeight.w600)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final out = <Map<String, dynamic>>[];
                for (final l in lines) {
                  final p = parseQty(cs[l.id]!.text) ?? 0;
                  // barang yang stok gudangnya kosong tidak wajib berharga (akan terkirim 0)
                  final wajib = (d.status != 'disetujui' || s.stockAt('gudang', l.itemId) > 0) && !s.hargaBolehKosong(l.itemId);
                  if (wajib && p <= 0) {
                    setS(() => err = 'Isi harga jual untuk ${l.name}');
                    return;
                  }
                  out.add({'line_id': l.id, 'sell_price': p});
                }
                Navigator.pop(dlg, out);
              },
              child: Text(okText),
            ),
          ],
        ),
      ),
    );
    for (final c in cs.values) {
      c.dispose();
    }
    return res;
  }

  Future<void> _aturHarga(AppState s, Doc d) async {
    final harga = await _dialogHarga(s, d, title: 'Atur harga jual', okText: 'Simpan');
    if (harga == null) return;
    await _run(() => s.aturHargaJual(d.id, harga), 'Harga jual disimpan');
  }

  Future<void> _bayarBon(AppState s, Doc d) async {
    final r = await showBayarDialog(context,
        title: 'Pelunasan bon ${d.branch}', sisa: s.bonSisa(d), info: 'Catat pembayaran yang diterima dari cabang. Boleh dicicil.');
    if (r == null) return;
    await _run(() => s.bayarBon(d.id, r.amount, r.method, r.paidAt, r.note), 'Pembayaran dicatat');
  }

  Future<void> _bayarSupplier(AppState s, Doc d) async {
    final r = await showBayarDialog(context,
        title: 'Bayar ke ${d.supplier.isEmpty ? 'grosir' : d.supplier}',
        sisa: s.masukSisa(d),
        info: 'Catat pembayaran yang sudah Anda lakukan ke grosir (transfer atau cash). Boleh dicicil.',
        okText: 'Sudah dibayar');
    if (r == null) return;
    await _run(() => s.bayarSupplier(d.id, r.amount, r.method, r.paidAt, r.note), 'Pembayaran dicatat');
  }

  Future<void> _batalBayar(AppState s, Payment p) async {
    if (!await _confirm('Batalkan pembayaran ini?', '${rp(p.amount)} (${p.methodLabel}, ${tgl(p.paidAt)}) dihapus dari riwayat. Gunakan hanya untuk salah catat.', 'Batalkan')) return;
    await _run(() => s.batalBayar(p.id), 'Pembayaran dibatalkan');
  }

  Future<void> _aturBayarMasuk(AppState s, Doc d) async {
    var mode = d.bayarMode == 'tempo' ? 'tempo' : 'cash';
    DateTime? jt = d.jatuhTempo;
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlg) => StatefulBuilder(
        builder: (dlg, setS) => AlertDialog(
          title: const Text('Atur cara bayar nota'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Pilih Tempo bila nota ini belum dibayar ke grosir. Nota tempo masuk daftar Tagihan Grosir.', style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Cash (lunas)'), selected: mode == 'cash', onSelected: (_) => setS(() => mode = 'cash')),
              ChoiceChip(label: const Text('Tempo'), selected: mode == 'tempo', onSelected: (_) => setS(() => mode = 'tempo')),
            ]),
            if (mode == 'tempo')
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final p = await showDatePicker(
                      context: dlg,
                      initialDate: jt ?? DateTime(now.year, now.month, now.day).add(const Duration(days: 7)),
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 1, now.month, now.day),
                    );
                    if (p != null) setS(() => jt = p);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(jt == null ? 'Pilih tanggal jatuh tempo' : 'Jatuh tempo: ${tgl(jt!)}'),
                ),
              ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: red))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlg, false), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (mode == 'tempo' && jt == null) return setS(() => err = 'Isi tanggal jatuh tempo');
                Navigator.pop(dlg, true);
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() => s.aturPembayaranMasuk(d.id, mode, mode == 'tempo' ? jt : null), 'Cara bayar disimpan');
  }

  Widget _bonSection(AppState s, Doc d) {
    final total = bonNilai(d);
    final paid = s.paidOf(d.id);
    final sisa = s.bonSisa(d);
    final st = bonStatusBayar(total, paid);
    final kelola = s.role == 'gudang' || s.isOwner;
    final pays = s.paymentsOf(d.id);
    final tanpaHarga = bonTanpaHarga(d);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Bon cabang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          pilBon(st, bonStatusLabel(st)),
        ]),
        const SizedBox(height: 6),
        _kv('Total bon', rp(total)),
        _kv('Sudah dibayar', rp(paid), color: green),
        _kv('Sisa bon', rp(sisa), color: sisa > 0.5 ? red : green),
        if (kelola && total > 0) ...[
          _kv('Modal', rp(bonHpp(d))),
          _kv('Keuntungan', rp(bonLaba(d)), color: bonLaba(d) < 0 ? red : green),
        ],
        if (tanpaHarga > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('$tanpaHarga barang belum diberi harga jual${kelola ? '. Tekan Atur harga jual.' : '.'}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: orange)),
          ),
        if (d.status != 'diterima')
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Pelunasan bisa dicatat setelah barang diterima cabang.', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ),
        if (kelola)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (d.status == 'diterima' && total > 0 && sisa > 0.5)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: green),
                  onPressed: busy ? null : () => _bayarBon(s, d),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Catat pelunasan'),
                ),
              if (pays.isEmpty)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _aturHarga(s, d),
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('Atur harga jual'),
                ),
            ]),
          ),
        const Divider(height: 22),
        const Text('Riwayat pelunasan', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        RiwayatBayar(list: pays, onBatal: s.isOwner ? (p) => _batalBayar(s, p) : null),
      ]),
    );
  }

  Widget _masukBayarSection(AppState s, Doc d) {
    final kelola = s.role == 'gudang' || s.isOwner;
    final tempo = masukTempo(d);
    final total = masukTotal(d);
    final paid = s.paidOf(d.id);
    final sisa = s.masukSisa(d);
    final st = tagihanStatus(d, sisa);
    final pays = s.paymentsOf(d.id);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Pembayaran ke grosir', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          if (tempo) pilTagihan(st, tagihanLabel(d, st)) else Pil(d.bayarMode == 'cash' ? 'Cash' : 'Dianggap lunas', fg: const Color(0xFF14753A), bg: const Color(0xFFDCF5E3)),
        ]),
        const SizedBox(height: 6),
        if (!tempo)
          Text(d.bayarMode == 'cash' ? 'Dibayar cash, lunas saat barang diterima.' : 'Dokumen lama tanpa data cara bayar, dianggap sudah lunas.',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]))
        else ...[
          if (d.jatuhTempo != null) _kv('Jatuh tempo', tgl(d.jatuhTempo!), color: (st == 'lewat' || st == 'dekat') ? (st == 'lewat' ? red : orange) : null),
          _kv('Total nota', rp(total)),
          _kv('Sudah dibayar', rp(paid), color: green),
          _kv('Sisa tagihan', rp(sisa), color: sisa > 0.5 ? red : green),
        ],
        if (kelola)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (tempo && sisa > 0.5)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: green),
                  onPressed: busy ? null : () => _bayarSupplier(s, d),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Sudah dibayar'),
                ),
              if (pays.isEmpty)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _aturBayarMasuk(s, d),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Atur cara bayar'),
                ),
            ]),
          ),
        if (tempo) ...[
          const Divider(height: 22),
          const Text('Riwayat pembayaran', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          RiwayatBayar(list: pays, onBatal: s.isOwner ? (p) => _batalBayar(s, p) : null),
        ],
      ]),
    );
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
    if (!await _confirm('Batalkan dokumen?', 'Dokumen ini dibatalkan dan tidak akan diproses.', 'Batalkan')) return;
    await _run(() => s.cancelDoc(d.id), 'Dokumen dibatalkan');
  }

  void _bukaNota(Doc d) => Navigator.push(context, MaterialPageRoute(builder: (_) => NotaPage(docId: d.id)));

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
            if (d.type == 'minta_cabang' && d.status == 'disetujui' && context.read<AppState>().role == 'gudang')
              Builder(builder: (_) {
                final have = context.read<AppState>().stockAt('gudang', l.itemId);
                final kurang = have < l.qty;
                return Text('Stok gudang: ${fmtQty(have)} ${l.unit}${kurang ? (have <= 0 ? ' (KOSONG, tetap dikirim & ditandai)' : ' (kurang, dikirim sebesar stok)') : ''}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kurang ? red : green));
              }),
            if (l.kosong)
              Text(l.qty <= 0 ? 'KOSONG di gudang • diminta ${fmtQty(l.qtyMinta ?? 0)} ${l.unit}' : 'STOK KURANG • diminta ${fmtQty(l.qtyMinta ?? 0)} ${l.unit}, dikirim ${fmtQty(l.qty)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: red)),
            if (d.type == 'masuk' && l.price > 0) Text('${rp(l.price)} / ${l.unit} • total ${rp(l.price * l.qty)}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            if (bonTerbit(d) && l.sellPrice > 0)
              Text('${rp(l.sellPrice)} / ${l.unit} • bon ${rp(l.sellPrice * bonQty(l))}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            if (bonTerbit(d) && l.sellPrice <= 0 && bonQty(l) > 0)
              const Text('Belum ada harga jual', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: orange)),
            if (bonTerbit(d) && l.sellPrice > 0 && l.price > 0 && (context.read<AppState>().role == 'gudang' || context.read<AppState>().isOwner))
              Text('Modal ${rp(l.price)} • untung ${rp((l.sellPrice - l.price) * bonQty(l))}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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

    final canOwnerDecide = s.isOwner && (d.status == 'diajukan' || d.belumVerif);
    final rejected = d.status == 'ditolak' || d.pembelianDitolak;
    final canOwnerEdit = s.isOwner && d.status == 'disetujui';
    final canSend = d.status == 'disetujui' && d.type != 'masuk' && s.isSender(d);
    final canReceive = d.status == 'dikirim' && s.isReceiver(d);
    final canCancel = (d.status == 'diajukan' || (d.status == 'disetujui' && d.type == 'minta_cabang')) && s.isCreator(d);
    final canGudangAdjust = s.role == 'gudang' && d.type == 'minta_cabang' && d.status == 'disetujui';
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
          if (!d.belumVerif) buttons.add(fb('Ubah jumlah', Icons.edit_outlined, () => _startEdit(d), c: navy2));
          buttons.add(fb(d.belumVerif ? 'Verifikasi (ACC)' : 'ACC', Icons.check, () => _acc(s, d), c: green));
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
      if (canSend && canGudangAdjust) {
        if (editing) {
          buttons.add(fb('Batal', Icons.close, () => setState(() => editing = false), c: Colors.grey));
          buttons.add(fb('Kirim jumlah ini', Icons.local_shipping_outlined, () => _kirim(s, d), c: blue));
        } else {
          buttons.add(fb('Sesuaikan jumlah', Icons.edit_outlined, () => _startEdit(d), c: navy2));
          buttons.add(fb('Kirim', Icons.local_shipping_outlined, () => _kirim(s, d), c: blue));
        }
      } else if (canSend) {
        buttons.add(fb('Kirim', Icons.local_shipping_outlined, () => _kirim(s, d), c: blue));
      }
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
    final bonTotal = bonNilai(d);

    return Scaffold(
      appBar: AppBar(
        title: Text(d.no),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        actions: [IconButton(tooltip: 'Lihat nota', icon: const Icon(Icons.receipt_long), onPressed: () => _bukaNota(d))],
      ),
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
            if (d.belumVerif) _kv('Verifikasi', 'Belum diverifikasi owner (stok sudah masuk)', color: orange),
            if (d.verif == 'ok') _kv('Verifikasi', 'Pembelian diverifikasi owner', color: green),
            if (d.accReason.isNotEmpty) _kv('Perlu ACC karena', d.accReason, color: orange),
            if (d.approvedAt != null) _kv(rejected ? 'Ditolak' : 'Diputuskan', '${tglJam(d.approvedAt!)} oleh ${d.approvedByName}'),
            if (d.ownerNote.isNotEmpty) _kv(rejected ? 'Alasan' : 'Catatan owner', d.ownerNote, color: rejected ? red : null),
            if (d.pembelianDitolak) _kv('Catatan', 'Pembelian ditolak owner. Stok yang sudah masuk tidak ditarik; owner dapat mengoreksi stok bila perlu.', color: red),
            if (d.sentAt != null) _kv('Dikirim', tglJam(d.sentAt!)),
            if (d.receivedAt != null) _kv('Diterima', '${tglJam(d.receivedAt!)}${d.receivedByName.isEmpty ? '' : ' oleh ${d.receivedByName}'}'),
            if (total > 0) _kv('Total pembelian', rp(total)),
            if (bonTotal > 0) _kv('Total bon cabang', rp(bonTotal)),
            if (d.hasDiff) _kv('Selisih', 'Ada selisih jumlah diterima', color: red),
          ]),
        ),
        if (!editing)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), backgroundColor: Colors.white),
              onPressed: () => _bukaNota(d),
              icon: const Icon(Icons.receipt_long, size: 20),
              label: Text(d.type == 'masuk' ? 'Lihat faktur, bagikan atau cetak' : (bonTerbit(d) ? 'Lihat surat jalan & bon, bagikan atau cetak' : 'Lihat surat jalan, bagikan atau cetak')),
            ),
          ),
        if (!editing && bonTerbit(d)) _bonSection(s, d),
        if (!editing && d.type == 'masuk') _masukBayarSection(s, d),
        if (editing)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: cardDeco(color: const Color(0xFFFFF4E0)),
            child: Text(s.role == 'gudang' ? 'Kurangi jumlah sesuai stok. Isi 0 untuk tidak mengirim barang itu.' : 'Ubah jumlah di bawah. Isi 0 untuk menghapus baris.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: orange)),
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
