import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../laporan.dart';
import '../models.dart';
import '../nilai_periode.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'tren_chart.dart';

/// Nilai rupiah stok gudang (khusus owner): stok x harga rata-rata beli dari grosir.
class NilaiGudangPage extends StatefulWidget {
  const NilaiGudangPage({super.key});
  @override
  State<NilaiGudangPage> createState() => _NilaiGudangPageState();
}

enum _Per { sekarang, hariIni, kemarin, minggu, bulan, custom }

class _NilaiGudangPageState extends State<NilaiGudangPage> {
  _Per per = _Per.sekarang;
  DateTime dari = hariIni();
  DateTime sampai = hariIni();
  Future<NilaiPeriodeHasil>? fut;
  bool _showAllGerak = false, _showAllDiam = false;

  static const _label = {
    _Per.sekarang: 'Sekarang',
    _Per.hariIni: 'Hari ini',
    _Per.kemarin: 'Kemarin',
    _Per.minggu: '7 hari',
    _Per.bulan: '30 hari',
    _Per.custom: 'Pilih tanggal',
  };

  void _muat() => fut = muatNilaiPeriode(dari, sampai);

  Future<void> _pilih(_Per p) async {
    final t = hariIni();
    switch (p) {
      case _Per.sekarang:
        break;
      case _Per.hariIni:
        dari = t;
        sampai = t;
      case _Per.kemarin:
        dari = t.subtract(const Duration(days: 1));
        sampai = dari;
      case _Per.minggu:
        dari = t.subtract(const Duration(days: 6));
        sampai = t;
      case _Per.bulan:
        dari = t.subtract(const Duration(days: 29));
        sampai = t;
      case _Per.custom:
        final r = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: t,
          initialDateRange: DateTimeRange(start: dari, end: sampai),
          helpText: 'Pilih rentang tanggal',
          saveText: 'Pilih',
          cancelText: 'Batal',
          confirmText: 'Pilih',
        );
        if (r == null) return;
        dari = DateUtils.dateOnly(r.start);
        sampai = DateUtils.dateOnly(r.end);
    }
    setState(() {
      per = p;
      _showAllGerak = false;
      _showAllDiam = false;
      if (p != _Per.sekarang) _muat();
    });
  }

  Future<void> _laporan(String aksi) async {
    try {
      final h = per == _Per.sekarang ? await muatNilaiPeriode(hariIni(), hariIni()) : await (fut ??= muatNilaiPeriode(dari, sampai));
      if (aksi == 'cetak') {
        await cetakLaporanNilai(h);
      } else {
        await bagikanLaporanNilai(h);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membuat laporan: ${errText(e)}')));
    }
  }

  Widget _chips() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final p in _Per.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: p == _Per.custom ? Icon(Icons.calendar_month, size: 18, color: per == p ? Colors.white : navy) : null,
                label: Text(_label[p]!),
                selected: per == p,
                showCheckmark: false,
                selectedColor: blue,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(color: per == p ? Colors.white : navy, fontWeight: FontWeight.w600),
                shape: const StadiumBorder(side: BorderSide(color: lineColor)),
                onSelected: (_) => _pilih(p),
              ),
            ),
        ]),
      );

  Widget _kv(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? null : Colors.grey[800]))),
          Text(v, style: TextStyle(fontSize: bold ? 17 : 14, fontWeight: FontWeight.w800, color: color ?? navy)),
        ]),
      );

  List<Widget> _periode(NilaiPeriodeHasil h) {
    final selisih = h.nilaiAkhir - h.nilaiAwal;
    final gerak = h.palingBergerak;
    final diam = h.tidakBergerak;
    final rows = [...h.rows]..sort((a, b) => b.nilaiAkhir.compareTo(a.nilaiAkhir));

    Widget judul(String t, {String? sub}) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          ]),
        );

    Widget tileGerak(NilaiPeriodeRow r) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: cardDeco(),
          child: ListTile(
            dense: true,
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Masuk ${fmtQty(r.qtyMasuk)} • Keluar ${fmtQty(r.qtyKeluar)} ${r.unit}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            trailing: Text(rp(r.nilaiMasuk + r.nilaiKeluar), style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
          ),
        );

    Widget tileDiam(NilaiPeriodeRow r) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: cardDeco(),
          child: ListTile(
            dense: true,
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${fmtQty(r.qtyAkhir)} ${r.unit} • ${r.terakhirGerak == null ? 'belum pernah bergerak' : 'terakhir bergerak ${tgl(r.terakhirGerak!)}'}',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
            trailing: Text(rp(r.nilaiAkhir), style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
          ),
        );

    Widget tileRinci(NilaiPeriodeRow r) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: cardDeco(),
          child: ListTile(
            dense: true,
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              'Awal ${fmtQty(r.qtyAwal)} • +${fmtQty(r.qtyMasuk)} • -${fmtQty(r.qtyKeluar)} • Akhir ${fmtQty(r.qtyAkhir)} ${r.unit}${r.adaHarga || r.qtyAkhir == 0 ? '' : ' • belum ada harga beli'}',
              style: TextStyle(color: r.adaHarga || r.qtyAkhir == 0 ? Colors.grey[700] : orange, fontSize: 12),
            ),
            trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(rp(r.nilaiAkhir), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: navy)),
              if (r.selisih.abs() >= 1)
                Text('${r.selisih > 0 ? '+' : ''}${rp(r.selisih)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: r.selisih > 0 ? green : red)),
            ]),
          ),
        );

    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(labelRentang(h.dari, h.sampai), style: TextStyle(fontSize: 13, color: Colors.grey[700])),
          const SizedBox(height: 6),
          _kv('Nilai awal', rp(h.nilaiAwal)),
          _kv('Barang masuk (+)', rp(h.nilaiMasuk), color: green),
          _kv('Barang keluar (-)', rp(h.nilaiKeluar), color: red),
          if (h.efekHarga.abs() >= 1) _kv('Perubahan harga', rp(h.efekHarga), color: h.efekHarga > 0 ? green : red),
          const Divider(height: 14),
          _kv('Nilai akhir', rp(h.nilaiAkhir), bold: true),
          _kv('Selisih awal ke akhir', '${selisih > 0 ? '+' : ''}${rp(selisih)}', color: selisih > 0 ? green : (selisih < 0 ? red : navy)),
          const SizedBox(height: 6),
          Text(
            'Masuk dan keluar sudah termasuk koreksi stok. Harga = rata-rata beli dari grosir sampai akhir periode.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ]),
      ),
      if (h.tanpaHarga > 0)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('${h.tanpaHarga} barang ada stok tapi belum pernah dibeli lewat Barang Masuk, nilainya dihitung Rp 0.',
              style: const TextStyle(color: orange, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      if (h.tren.length >= 2) ...[const SizedBox(height: 12), TrenChart(data: h.tren)],
      if (h.trenError != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Tren gagal dimuat: ${h.trenError}\nPastikan supabase_update_nilai_periode.sql sudah dijalankan.', style: const TextStyle(color: red, fontSize: 12)),
        ),
      if (gerak.isNotEmpty) ...[
        judul('Paling banyak bergerak', sub: 'Urut dari nilai masuk + keluar terbesar'),
        for (final r in (_showAllGerak ? gerak : gerak.take(5))) tileGerak(r),
        if (gerak.length > 5) TextButton(onPressed: () => setState(() => _showAllGerak = !_showAllGerak), child: Text(_showAllGerak ? 'Tampilkan lebih sedikit' : 'Lihat semua (${gerak.length})')),
      ],
      if (diam.isNotEmpty) ...[
        judul('Ada stok tapi tidak bergerak', sub: 'Tidak ada masuk atau keluar selama periode ini'),
        for (final r in (_showAllDiam ? diam : diam.take(5))) tileDiam(r),
        if (diam.length > 5) TextButton(onPressed: () => setState(() => _showAllDiam = !_showAllDiam), child: Text(_showAllDiam ? 'Tampilkan lebih sedikit' : 'Lihat semua (${diam.length})')),
      ],
      judul('Rincian per barang (${rows.length})'),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Tidak ada data stok pada periode ini', style: TextStyle(color: Colors.grey)))),
      for (final r in rows) tileRinci(r),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final rows = s.nilaiGudang;
    final siap = rows.where((r) => r.siapJual).toList();
    final mentah = rows.where((r) => !r.siapJual).toList();
    final tanpaHarga = rows.where((r) => !r.adaHarga).length;

    Widget head(String t, List<NilaiRow> list) {
      final sum = list.fold(0.0, (a, r) => a + r.nilai);
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Row(children: [
          Expanded(child: Text('$t (${list.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
          Text(rp(sum), style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
        ]),
      );
    }

    Widget tile(NilaiRow r) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: cardDeco(),
          child: ListTile(
            dense: true,
            title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              r.adaHarga ? '${fmtQty(r.qty)} ${r.unit} x ${rp(r.hargaRata)}' : '${fmtQty(r.qty)} ${r.unit} • belum ada harga beli',
              style: TextStyle(color: r.adaHarga ? Colors.grey[700] : orange, fontSize: 12),
            ),
            trailing: Text(rp(r.nilai), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: navy)),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nilai stok gudang'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Laporan PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onSelected: _laporan,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'bagikan', child: Text('Bagikan laporan PDF')),
              PopupMenuItem(value: 'cetak', child: Text('Cetak laporan')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await s.refresh(silent: true);
          if (per != _Per.sekarang) setState(_muat);
        },
        child: ListView(padding: const EdgeInsets.all(12), children: [
          _chips(),
          const SizedBox(height: 12),
          if (per != _Per.sekarang)
            FutureBuilder<NilaiPeriodeHasil>(
              future: fut,
              builder: (c, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Gagal memuat: ${errText(snap.error!)}\nPastikan supabase_update_nilai_periode.sql sudah dijalankan.', style: const TextStyle(color: red, fontSize: 13)),
                  );
                }
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _periode(snap.data!));
              },
            )
          else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total nilai stok di gudang', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
              const SizedBox(height: 4),
              Text(s.nilaiLoaded ? rp(s.totalNilaiGudang) : '-', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: navy)),
              const SizedBox(height: 6),
              Text(
                'Stok sekarang x harga rata-rata beli dari grosir. Barang yang keluar ke produksi atau cabang mengurangi nilai. Bahan jadi hasil produksi tidak dinilai.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ]),
          ),
          if (s.nilaiError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Gagal memuat: ${s.nilaiError}\nPastikan supabase_update_nilai_gudang.sql sudah dijalankan.',
                style: const TextStyle(color: red, fontSize: 13),
              ),
            ),
          if (tanpaHarga > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('$tanpaHarga barang ada stok tapi belum pernah dibeli lewat Barang Masuk, nilainya dihitung Rp 0.',
                  style: const TextStyle(color: orange, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          if (s.nilaiLoaded && rows.isEmpty)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Stok gudang kosong', style: TextStyle(color: Colors.grey)))),
          if (siap.isNotEmpty) ...[head('Barang siap jual', siap), for (final r in siap) tile(r)],
          if (mentah.isNotEmpty) ...[head('Bahan mentah', mentah), for (final r in mentah) tile(r)],
          ],
        ]),
      ),
    );
  }
}
