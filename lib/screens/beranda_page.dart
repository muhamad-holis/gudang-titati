import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bon.dart';
import '../models.dart';
import '../state.dart';
import '../tagihan.dart';
import '../theme.dart';
import '../utils.dart';
import 'bon_cabang_page.dart';
import 'doc_form_page.dart';
import 'nilai_gudang_page.dart';
import 'docs_page.dart';
import 'omzet_page.dart';
import 'tagihan_page.dart';
import 'sales_form_page.dart';
import 'sales_page.dart';
import 'stok_menipis_page.dart';

class BerandaPage extends StatelessWidget {
  const BerandaPage({super.key});

  Future<void> _open(BuildContext context, String type) async {
    final r = await Navigator.push<Object?>(context, MaterialPageRoute(builder: (_) => DocFormPage(type: type)));
    if (r != null && context.mounted) {
      final held = r is Doc && r.status == 'diajukan';
      final String msg;
      if (type == 'masuk') {
        msg = 'Barang masuk tercatat, stok gudang bertambah.${r is Doc && r.bayarMode == 'tempo' ? ' Nota tempo masuk ke Tagihan grosir.' : ''} Menunggu verifikasi harga oleh owner';
      } else if (type == 'minta_cabang') {
        msg = held ? 'Jumlah jauh di atas biasanya, menunggu ACC owner' : 'Permintaan terkirim ke gudang';
      } else if (type == 'setor_jadi') {
        msg = held ? 'Hasil menyimpang dari standar, menunggu ACC owner' : 'Terkirim, menunggu konfirmasi gudang';
      } else {
        msg = 'Terkirim, menunggu konfirmasi penerima';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// ACC semua hanya untuk verifikasi pembelian. Setoran / permintaan yang menyimpang sengaja dibuka satu per satu.
  Future<void> _accAll(BuildContext context, AppState s, List<Doc> tasks) async {
    final total = tasks.fold<double>(0, (a, d) => a + d.lines.fold<double>(0, (b, l) => b + l.price * l.qty));
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Verifikasi semua pembelian (${tasks.length})?'),
        content: Text('Total pembelian ${rp(total)}. Harga dan pembelian semua dokumen ini dianggap sudah Anda periksa. Stok sudah masuk sejak dokumen dibuat.\n\nUntuk menolak satu pembelian, buka dokumennya.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Verifikasi semua')),
        ],
      ),
    );
    if (ok != true) return;
    var done = 0;
    String? err;
    for (final d in tasks) {
      try {
        await s.ownerDecide(d.id, 'acc');
        done++;
      } catch (e) {
        err = errText(e);
        break;
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err == null ? '$done pembelian diverifikasi' : '$done diverifikasi. Berhenti: $err')));
    }
  }

  Widget _btn(BuildContext context, IconData icon, String label, String type) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: const Size.fromHeight(52)),
            onPressed: () => _open(context, type),
            icon: Icon(icon, size: 20),
            label: Text(label, textAlign: TextAlign.center),
          ),
        ),
      );

  Widget _salesBtn(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: green, minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const SalesFormPage()));
              if (ok == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penjualan tersimpan dan terlihat oleh owner')));
              }
            },
            icon: const Icon(Icons.point_of_sale, size: 20),
            label: const Text('Catat Penjualan', textAlign: TextAlign.center),
          ),
        ),
      );

  /// Ringkasan penjualan hari ini per cabang (untuk owner).
  Widget _salesCard(BuildContext context, AppState s) {
    final branches = s.saleBranches;
    if (branches.isEmpty) return const SizedBox.shrink();
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      const Text('Penjualan cabang hari ini', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      for (final b in branches)
        Builder(builder: (_) {
          final sums = s.rekapFor(b, today, today);
          final sold = sums.where((x) => x.terjual > 0).length;
          final kurang = s.kurangFor(b, today, today);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: cardDeco(),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SalesPage(initialBranch: b, standalone: true))),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(kurang.isNotEmpty ? Icons.warning_amber_rounded : (sums.isEmpty ? Icons.hourglass_empty : Icons.check_circle),
                      color: kurang.isNotEmpty ? red : (sums.isEmpty ? Colors.grey : green)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(b, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                        kurang.isNotEmpty
                            ? 'Ada barang kurang diterima: ${kurang.length} jenis'
                            : (sums.isEmpty ? 'Belum ada barang masuk atau terjual hari ini' : (sold == 0 ? 'Belum ada yang terjual hari ini' : '$sold jenis barang terjual hari ini')),
                        style: TextStyle(fontSize: 12, color: kurang.isNotEmpty ? red : Colors.grey[700], fontWeight: kurang.isNotEmpty ? FontWeight.w700 : FontWeight.w400),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ]),
              ),
            ),
          );
        }),
    ]);
  }

  Widget _nilaiCard(BuildContext context, AppState s) {
    final ada = s.nilaiLoaded;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: cardDeco(),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NilaiGudangPage())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 34, color: navy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nilai stok gudang', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                Text(ada ? rp(s.totalNilaiGudang) : (s.nilaiError == null ? '...' : 'Belum tersedia'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  Widget _bonCard(BuildContext context, AppState s) {
    final n = DateTime.now();
    final awal = DateTime(n.year, n.month, 1);
    final bulanIni = s.docs.where((d) => bonTerbit(d) && !bonWaktu(d).isBefore(awal)).toList();
    final total = bulanIni.fold<double>(0, (a, d) => a + bonNilai(d));
    final sisaSemua = s.docs.where(bonTerbit).fold<double>(0, (a, d) => a + s.bonSisa(d));
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: cardDeco(),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BonCabangPage())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 34, color: navy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((s.isOwner || s.role == 'gudang') ? 'Bon cabang bulan ini' : 'Bon cabang Anda bulan ini', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                Text(rp(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
                Text('${bulanIni.length} pengiriman • sisa bon belum lunas ${rp(sisaSemua)}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sisaSemua > 0.5 ? red : Colors.grey[700])),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  /// Omzet dan keuntungan gudang bulan ini (gudang dan owner).
  Widget _omzetCard(BuildContext context, AppState s) {
    final n = DateTime.now();
    final awal = DateTime(n.year, n.month, 1);
    final bulanIni = s.docs.where((d) => bonTerbit(d) && !bonWaktu(d).isBefore(awal)).toList();
    final omzet = bulanIni.fold<double>(0, (a, d) => a + bonNilai(d));
    final laba = bulanIni.fold<double>(0, (a, d) => a + bonLaba(d));
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: cardDeco(),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OmzetPage())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.trending_up, size: 34, color: navy),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Omzet gudang bulan ini', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                Text(rp(omzet), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
                Text('Keuntungan ${rp(laba)} • ${bulanIni.length} pengiriman',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: laba < 0 ? red : green)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  /// Tagihan grosir (nota tempo). Berwarna dan memuat pengingat bila ada yang lewat / mendekati jatuh tempo.
  Widget _tagihanCard(BuildContext context, AppState s) {
    final belum = s.tagihanBelumLunas;
    final mendekati = s.tagihanMendekati;
    if (belum.isEmpty && s.tagihanSupplier.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        decoration: cardDeco(),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagihanPage())),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.request_quote_outlined, size: 34, color: navy),
              SizedBox(width: 12),
              Expanded(child: Text('Tagihan grosir: belum ada nota tempo', style: TextStyle(fontWeight: FontWeight.w700))),
              Icon(Icons.chevron_right, color: Colors.grey),
            ]),
          ),
        ),
      );
    }
    final total = belum.fold<double>(0, (a, d) => a + s.masukSisa(d));
    final lewat = mendekati.where((d) => tagihanStatus(d, s.masukSisa(d)) == 'lewat').length;
    final warna = lewat > 0 ? red : (mendekati.isNotEmpty ? orange : navy);
    final bg = lewat > 0 ? const Color(0xFFFFF5F5) : (mendekati.isNotEmpty ? const Color(0xFFFFF4E0) : Colors.white);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: cardDeco(color: bg),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TagihanPage())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(mendekati.isNotEmpty ? Icons.notifications_active_outlined : Icons.request_quote_outlined, size: 34, color: warna),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tagihan grosir belum dibayar', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                Text(rp(total), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: warna)),
                if (mendekati.isNotEmpty)
                  Text(
                    '${lewat > 0 ? '$lewat nota lewat jatuh tempo' : ''}${lewat > 0 && mendekati.length > lewat ? ', ' : ''}${mendekati.length > lewat ? '${mendekati.length - lewat} nota segera jatuh tempo' : ''}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: warna),
                  )
                else
                  Text('${belum.length} nota belum lunas', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  Widget _menipisCard(BuildContext context, AppState s) {
    final list = s.stokMenipis;
    if (list.isEmpty) return const SizedBox.shrink();
    final habis = list.where((l) => l.qty <= 0).length;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: cardDeco(color: const Color(0xFFFFF4E0)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StokMenipisPage())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 34, color: orange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${list.length} barang stok menipis', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: orange)),
                Text(
                  '${list.take(3).map((l) => l.item.name).join(', ')}${list.length > 3 ? ', dll' : ''}${habis > 0 ? ' • $habis habis' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me!;
    final tasks = s.myTasks;
    final recent = s.docs.where((d) => s.actionFor(d) == null).take(8).toList();

    Widget buttons;
    switch (me.role) {
      case 'gudang':
        buttons = Column(children: [
          Row(children: [
            _btn(context, Icons.add_box_outlined, 'Barang Masuk', 'masuk'),
            _btn(context, Icons.soup_kitchen_outlined, 'Kirim ke Produksi', 'kirim_produksi'),
          ]),
          const SizedBox(height: 8),
          Row(children: [_btn(context, Icons.local_shipping_outlined, 'Kirim ke Cabang', 'kirim_cabang')]),
        ]);
        break;
      case 'produksi':
        buttons = Row(children: [_btn(context, Icons.soup_kitchen_outlined, 'Setor Hasil Produksi', 'setor_jadi')]);
        break;
      case 'cabang':
        buttons = Row(children: [_btn(context, Icons.shopping_basket_outlined, 'Minta Bahan Jadi', 'minta_cabang'), _salesBtn(context)]);
        break;
      default:
        buttons = const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: () => s.refresh(silent: true),
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(),
          child: Row(children: [
            const Icon(Icons.account_circle, size: 40, color: navy),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me.name.isEmpty ? roleLabel(me.role) : me.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(me.role == 'cabang' ? 'Cabang ${me.branch.isEmpty ? '(belum diatur)' : me.branch}' : roleLabel(me.role),
                    style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              ]),
            ),
          ]),
        ),
        if (s.isOwner) _nilaiCard(context, s),
        if (s.isOwner || me.role == 'gudang') _tagihanCard(context, s),
        if (s.isOwner || me.role == 'gudang') _omzetCard(context, s),
        if (s.isOwner || me.role == 'cabang' || me.role == 'gudang') _bonCard(context, s),
        if (s.isOwner || me.role == 'gudang') _menipisCard(context, s),
        if (me.role != 'owner') ...[const SizedBox(height: 12), buttons],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: Text('Perlu tindakan Anda (${tasks.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (s.isOwner && s.pembelianBelumVerif.length > 1)
            TextButton.icon(onPressed: () => _accAll(context, s, s.pembelianBelumVerif), icon: const Icon(Icons.done_all, size: 18), label: const Text('ACC semua pembelian')),
        ]),
        const SizedBox(height: 6),
        if (tasks.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(),
            child: const Text('Tidak ada yang menunggu. Semua beres.', style: TextStyle(color: Colors.grey)),
          ),
        for (final d in tasks) DocCard(doc: d),
        if (s.isOwner && s.ownerAlerts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Perlu dipantau (${s.ownerAlerts.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Ada selisih terima, atau tertahan lebih dari 24 jam', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const SizedBox(height: 6),
          for (final d in s.ownerAlerts) DocCard(doc: d),
        ],
        if (s.isOwner) _salesCard(context, s),
        const SizedBox(height: 16),
        const Text('Terbaru', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (recent.isEmpty) const Text('Belum ada dokumen', style: TextStyle(color: Colors.grey)),
        for (final d in recent) DocCard(doc: d),
      ]),
    );
  }
}
