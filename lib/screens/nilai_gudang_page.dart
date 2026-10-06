import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

/// Nilai rupiah stok gudang (khusus owner): stok x harga rata-rata beli dari grosir.
class NilaiGudangPage extends StatelessWidget {
  const NilaiGudangPage({super.key});

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
      appBar: AppBar(title: const Text('Nilai stok gudang'), backgroundColor: navy, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: () => s.refresh(silent: true),
        child: ListView(padding: const EdgeInsets.all(12), children: [
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
        ]),
      ),
    );
  }
}
