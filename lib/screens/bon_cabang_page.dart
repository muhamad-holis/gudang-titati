import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bon.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'doc_detail_page.dart';

/// Rekap nilai kiriman gudang ke cabang (bon cabang) per periode.
/// Owner melihat semua cabang; akun cabang hanya melihat cabangnya sendiri.
class BonCabangPage extends StatefulWidget {
  const BonCabangPage({super.key});
  @override
  State<BonCabangPage> createState() => _BonCabangPageState();
}

class _BonCabangPageState extends State<BonCabangPage> {
  String periode = 'bulan';

  static const _opsi = {'hari': 'Hari ini', '7': '7 hari', '30': '30 hari', 'bulan': 'Bulan ini'};

  DateTime _dari() {
    final n = DateTime.now();
    final h = DateTime(n.year, n.month, n.day);
    switch (periode) {
      case 'hari':
        return h;
      case '7':
        return h.subtract(const Duration(days: 6));
      case '30':
        return h.subtract(const Duration(days: 29));
      default:
        return DateTime(n.year, n.month, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final dari = _dari();
    final list = s.docs.where((d) => bonTerbit(d) && !bonWaktu(d).isBefore(dari)).toList()
      ..sort((a, b) => bonWaktu(b).compareTo(bonWaktu(a)));

    final perCabang = <String, List<Doc>>{};
    for (final d in list) {
      perCabang.putIfAbsent(d.branch.isEmpty ? '(tanpa cabang)' : d.branch, () => []).add(d);
    }
    final cabangs = perCabang.keys.toList()..sort();
    final grand = list.fold<double>(0, (a, d) => a + bonNilai(d));
    final tanpaHarga = list.fold<int>(0, (a, d) => a + bonTanpaHarga(d));

    return Scaffold(
      appBar: AppBar(title: const Text('Bon cabang'), backgroundColor: navy, foregroundColor: Colors.white),
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
              Text('Total nilai kiriman (${_opsi[periode]})', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              Text(rp(grand), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 4),
              Text('${list.length} pengiriman • dasar bon: jumlah diterima (belum diterima: jumlah dikirim)',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700])),
              if (tanpaHarga > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$tanpaHarga baris tanpa harga (barang olahan / belum pernah dibeli dari grosir) tidak ikut dihitung',
                      style: const TextStyle(fontSize: 11, color: orange, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Belum ada pengiriman pada periode ini', style: TextStyle(color: Colors.grey)))),
          for (final c in cabangs) _cabangTile(context, c, perCabang[c]!),
        ]),
      ),
    );
  }

  Widget _cabangTile(BuildContext context, String cabang, List<Doc> docs) {
    final total = docs.fold<double>(0, (a, d) => a + bonNilai(d));
    // rincian per barang
    final per = <String, _Rinci>{};
    for (final d in docs) {
      for (final l in d.lines) {
        final r = per.putIfAbsent(l.itemId, () => _Rinci(l.name, l.unit));
        r.qty += bonQty(l);
        r.nilai += l.price * bonQty(l);
      }
    }
    final rinci = per.values.toList()..sort((a, b) => b.nilai.compareTo(a.nilai));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: cardDeco(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(cabang, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('${docs.length} pengiriman', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          trailing: Text(rp(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: navy)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          children: [
            const Align(alignment: Alignment.centerLeft, child: Text('Per barang', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
            for (final r in rinci)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(child: Text('${r.nama} • ${fmtQty(r.qty)} ${r.unit}', style: const TextStyle(fontSize: 13))),
                  Text(r.nilai > 0 ? rp(r.nilai) : '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            const Divider(),
            const Align(alignment: Alignment.centerLeft, child: Text('Per dokumen (ketuk untuk buka)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
            for (final d in docs)
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocDetailPage(docId: d.id))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(child: Text('${d.no} • ${tgl(bonWaktu(d))}', style: const TextStyle(fontSize: 13))),
                    Text(rp(bonNilai(d)), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Rinci {
  final String nama, unit;
  double qty = 0, nilai = 0;
  _Rinci(this.nama, this.unit);
}
