import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bon.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'doc_detail_page.dart';
import 'pembayaran.dart';

/// Bon cabang: nilai kiriman gudang ke cabang (harga jual gudang), status pelunasan, dan sisa bon.
/// Owner dan gudang melihat semua cabang; akun cabang hanya melihat cabangnya sendiri.
class BonCabangPage extends StatefulWidget {
  const BonCabangPage({super.key});
  @override
  State<BonCabangPage> createState() => _BonCabangPageState();
}

class _BonCabangPageState extends State<BonCabangPage> {
  String periode = 'bulan';
  bool belumLunas = false;

  static const _opsi = {'hari': 'Hari ini', '7': '7 hari', '30': '30 hari', 'bulan': 'Bulan ini', 'semua': 'Semua'};

  DateTime? _dari() {
    final n = DateTime.now();
    final h = DateTime(n.year, n.month, n.day);
    switch (periode) {
      case 'hari':
        return h;
      case '7':
        return h.subtract(const Duration(days: 6));
      case '30':
        return h.subtract(const Duration(days: 29));
      case 'semua':
        return null;
      default:
        return DateTime(n.year, n.month, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final dari = _dari();
    final list = s.docs.where((d) {
      if (!bonTerbit(d)) return false;
      if (dari != null && bonWaktu(d).isBefore(dari)) return false;
      if (belumLunas && !(bonNilai(d) > 0 && s.bonSisa(d) > 0.5)) return false;
      return true;
    }).toList()
      ..sort((a, b) => bonWaktu(b).compareTo(bonWaktu(a)));

    final perCabang = <String, List<Doc>>{};
    for (final d in list) {
      perCabang.putIfAbsent(d.branch.isEmpty ? '(tanpa cabang)' : d.branch, () => []).add(d);
    }
    final cabangs = perCabang.keys.toList()..sort();
    final total = list.fold<double>(0, (a, d) => a + bonNilai(d));
    final dibayar = list.fold<double>(0, (a, d) => a + s.paidOf(d.id));
    final sisa = list.fold<double>(0, (a, d) => a + s.bonSisa(d));
    final tanpaHarga = list.fold<int>(0, (a, d) => a + bonTanpaHarga(d));
    final kelola = s.role == 'gudang' || s.isOwner;

    return Scaffold(
      appBar: AppBar(title: const Text('Bon cabang'), backgroundColor: navy, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: () => s.refresh(silent: true),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Wrap(spacing: 8, children: [
            for (final e in _opsi.entries)
              ChoiceChip(label: Text(e.value), selected: periode == e.key, onSelected: (_) => setState(() => periode = e.key)),
          ]),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Hanya yang belum lunas'),
              selected: belumLunas,
              onSelected: (v) => setState(() => belumLunas = v),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total bon (${_opsi[periode]})', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              Text(rp(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _mini('Sudah dibayar', rp(dibayar), green)),
                Expanded(child: _mini('Sisa bon', rp(sisa), sisa > 0.5 ? red : green)),
              ]),
              const SizedBox(height: 6),
              Text('${list.length} pengiriman • dasar bon: harga jual × jumlah diterima', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
              if (tanpaHarga > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$tanpaHarga baris belum diberi harga jual dan belum ikut dihitung${kelola ? '. Buka dokumennya, tekan Atur harga jual.' : '.'}',
                    style: const TextStyle(fontSize: 11, color: orange, fontWeight: FontWeight.w600),
                  ),
                ),
              if (s.payError != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Data pembayaran belum tersedia. Pastikan supabase_update_omzet_tagihan.sql sudah dijalankan.',
                      style: TextStyle(fontSize: 11, color: red, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(child: Text(belumLunas ? 'Tidak ada bon yang belum lunas' : 'Belum ada pengiriman pada periode ini', style: const TextStyle(color: Colors.grey))),
            ),
          for (final c in cabangs) _cabangTile(context, s, c, perCabang[c]!),
        ]),
      ),
    );
  }

  Widget _mini(String label, String value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      ]);

  Widget _cabangTile(BuildContext context, AppState s, String cabang, List<Doc> docs) {
    final total = docs.fold<double>(0, (a, d) => a + bonNilai(d));
    final sisa = docs.fold<double>(0, (a, d) => a + s.bonSisa(d));
    // rincian per barang
    final per = <String, _Rinci>{};
    for (final d in docs) {
      for (final l in d.lines) {
        final r = per.putIfAbsent(l.itemId, () => _Rinci(l.name, l.unit));
        r.qty += bonQty(l);
        r.nilai += l.sellPrice * bonQty(l);
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
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(rp(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: navy)),
            Text(sisa > 0.5 ? 'sisa ${rp(sisa)}' : 'lunas', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sisa > 0.5 ? red : green)),
          ]),
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
            const Align(alignment: Alignment.centerLeft, child: Text('Per bon (ketuk untuk buka / catat pelunasan)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
            for (final d in docs) _bonRow(context, s, d),
          ],
        ),
      ),
    );
  }

  Widget _bonRow(BuildContext context, AppState s, Doc d) {
    final nilai = bonNilai(d);
    final st = bonStatusBayar(nilai, s.paidOf(d.id));
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DocDetailPage(docId: d.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d.no} • ${tgl(bonWaktu(d))}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 3),
              Row(children: [
                pilBon(st, bonStatusLabel(st)),
                if (d.status != 'diterima') ...[const SizedBox(width: 6), Text('belum diterima', style: TextStyle(fontSize: 11, color: Colors.grey[700]))],
              ]),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(rp(nilai), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            if (nilai > 0 && s.bonSisa(d) > 0.5) Text('sisa ${rp(s.bonSisa(d))}', style: const TextStyle(fontSize: 11, color: red, fontWeight: FontWeight.w700)),
          ]),
          const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        ]),
      ),
    );
  }
}

class _Rinci {
  final String nama, unit;
  double qty = 0, nilai = 0;
  _Rinci(this.nama, this.unit);
}
