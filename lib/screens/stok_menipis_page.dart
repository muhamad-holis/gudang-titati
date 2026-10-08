import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

/// Daftar barang gudang yang stoknya sudah mencapai atau di bawah batas minimum.
class StokMenipisPage extends StatelessWidget {
  const StokMenipisPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.stokMenipis;
    return Scaffold(
      appBar: AppBar(title: const Text('Stok menipis'), backgroundColor: navy, foregroundColor: Colors.white),
      body: RefreshIndicator(
        onRefresh: () => s.refresh(silent: true),
        child: list.isEmpty
            ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Semua stok di atas batas minimum', style: TextStyle(color: Colors.grey))))])
            : ListView(padding: const EdgeInsets.all(12), children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    s.isOwner
                        ? 'Batas minimum diatur di Master, ketuk barang, isi Stok minimum gudang.'
                        : 'Batas minimum diatur owner. Segera belanja barang di bawah ini.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ),
                for (final l in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: cardDeco(),
                    child: ListTile(
                      dense: true,
                      title: Text(l.item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('Minimum ${fmtQty(l.item.stokMin)} ${l.item.unit} • kurang ${fmtQty(l.kurang < 0 ? 0 : l.kurang)} ${l.item.unit}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      trailing: Text('${fmtQty(l.qty)} ${l.item.unit}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: l.qty <= 0 ? red : orange)),
                    ),
                  ),
              ]),
      ),
    );
  }
}
