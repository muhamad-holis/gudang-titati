import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bon.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'doc_detail_page.dart';

/// Omzet dan keuntungan gudang dari penjualan ke cabang (bon cabang).
/// Omzet = harga jual x jumlah diterima. Keuntungan = omzet - modal (harga beli rata-rata saat dikirim).
class OmzetPage extends StatefulWidget {
  const OmzetPage({super.key});
  @override
  State<OmzetPage> createState() => _OmzetPageState();
}

class _Agg {
  double omzet = 0, hpp = 0, qty = 0;
  String unit = '';
  int n = 0;
  double get laba => omzet - hpp;
}

class _OmzetPageState extends State<OmzetPage> {
  String periode = 'bulan';
  static const _opsi = {'hari': 'Hari ini', '7': '7 hari', '30': '30 hari', 'bulan': 'Bulan ini', 'lalu': 'Bulan lalu'};

  (DateTime, DateTime) _rentang() {
    final n = DateTime.now();
    final h = DateTime(n.year, n.month, n.day);
    final besok = h.add(const Duration(days: 1));
    switch (periode) {
      case 'hari':
        return (h, besok);
      case '7':
        return (h.subtract(const Duration(days: 6)), besok);
      case '30':
        return (h.subtract(const Duration(days: 29)), besok);
      case 'lalu':
        return (DateTime(n.year, n.month - 1, 1), DateTime(n.year, n.month, 1));
      default:
        return (DateTime(n.year, n.month, 1), besok);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final (dari, sampai) = _rentang();
    final docs = s.docs.where((d) => bonTerbit(d) && !bonWaktu(d).isBefore(dari) && bonWaktu(d).isBefore(sampai)).toList()
      ..sort((a, b) => bonWaktu(b).compareTo(bonWaktu(a)));

    final omzet = docs.fold<double>(0, (a, d) => a + bonNilai(d));
    final hpp = docs.fold<double>(0, (a, d) => a + bonHpp(d));
    final laba = omzet - hpp;
    final dibayar = docs.fold<double>(0, (a, d) => a + s.paidOf(d.id));
    final sisa = docs.fold<double>(0, (a, d) => a + s.bonSisa(d));
    final tanpaHarga = docs.fold<int>(0, (a, d) => a + bonTanpaHarga(d));
    final tanpaModal = docs.fold<int>(0, (a, d) => a + bonTanpaModal(d));

    final perCabang = <String, _Agg>{};
    final perBarang = <String, _Agg>{};
    final namaBarang = <String, String>{};
    for (final d in docs) {
      final c = perCabang.putIfAbsent(d.branch.isEmpty ? '(tanpa cabang)' : d.branch, () => _Agg());
      c.omzet += bonNilai(d);
      c.hpp += bonHpp(d);
      c.n++;
      for (final l in d.lines) {
        if (l.sellPrice <= 0) continue;
        final q = bonQty(l);
        final b = perBarang.putIfAbsent(l.itemId, () => _Agg());
        namaBarang[l.itemId] = l.name;
        b.unit = l.unit;
        b.qty += q;
        b.omzet += l.sellPrice * q;
        b.hpp += l.price * q;
      }
    }
    final cabangs = perCabang.entries.toList()..sort((a, b) => b.value.omzet.compareTo(a.value.omzet));
    final barangs = perBarang.entries.toList()..sort((a, b) => b.value.omzet.compareTo(a.value.omzet));
    final margin = omzet > 0 ? laba / omzet * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Omzet & keuntungan'), backgroundColor: navy, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: () => s.refresh(silent: true),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Wrap(spacing: 8, children: [
            for (final e in _opsi.entries)
              ChoiceChip(label: Text(e.value), selected: periode == e.key, onSelected: (_) => setState(() => periode = e.key)),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Omzet penjualan ke cabang (${_opsi[periode]})', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              Text(rp(omzet), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _mini('Modal', rp(hpp), Colors.black87)),
                Expanded(child: _mini('Keuntungan', rp(laba), laba < 0 ? red : green)),
                Expanded(child: _mini('Margin', '${margin.toStringAsFixed(1).replaceAll('.', ',')}%', laba < 0 ? red : green)),
              ]),
              const Divider(height: 22),
              Row(children: [
                Expanded(child: _mini('Sudah dibayar cabang', rp(dibayar), green)),
                Expanded(child: _mini('Sisa bon', rp(sisa), sisa > 0.5 ? red : green)),
              ]),
              const SizedBox(height: 6),
              Text('${docs.length} pengiriman • omzet dihitung dari jumlah diterima cabang (belum diterima: jumlah dikirim)',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700])),
              if (tanpaHarga > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$tanpaHarga baris belum diberi harga jual, belum ikut dihitung. Buka dokumennya, tekan Atur harga jual.',
                      style: const TextStyle(fontSize: 11, color: orange, fontWeight: FontWeight.w600)),
                ),
              if (tanpaModal > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$tanpaModal baris modalnya tidak diketahui (barang belum pernah dicatat di Barang Masuk), keuntungannya terhitung penuh.',
                      style: const TextStyle(fontSize: 11, color: orange, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          if (docs.isEmpty)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Belum ada penjualan ke cabang pada periode ini', style: TextStyle(color: Colors.grey)))),
          if (cabangs.isNotEmpty) ...[
            _judul('Per cabang'),
            for (final e in cabangs)
              _baris(e.key, '${e.value.n} pengiriman', rp(e.value.omzet), 'untung ${rp(e.value.laba)}', e.value.laba < 0),
          ],
          if (barangs.isNotEmpty) ...[
            _judul('Per barang'),
            for (final e in barangs)
              _baris(namaBarang[e.key] ?? '?', '${fmtQty(e.value.qty)} ${e.value.unit}', rp(e.value.omzet), 'untung ${rp(e.value.laba)}', e.value.laba < 0),
          ],
          if (docs.isNotEmpty) ...[
            _judul('Rincian transaksi (ketuk untuk buka)'),
            for (final d in docs) _transaksi(context, d),
          ],
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  Widget _judul(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 16, 2, 6), child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)));

  Widget _mini(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
      ]);

  Widget _baris(String judul, String sub, String kanan, String subKanan, bool rugi) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: cardDeco(),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(judul, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(kanan, style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
            Text(subKanan, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: rugi ? red : green)),
          ]),
        ]),
      );

  Widget _transaksi(BuildContext context, Doc d) {
    final laba = bonLaba(d);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: cardDeco(),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocDetailPage(docId: d.id))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tgl(bonWaktu(d))} • ${d.branch}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${d.no} • ${d.summary}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rp(bonNilai(d)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: navy)),
              Text('untung ${rp(laba)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: laba < 0 ? red : green)),
            ]),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ]),
        ),
      ),
    );
  }
}
