import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me!;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: cardDeco(),
        child: Row(children: [
          const Icon(Icons.account_circle, size: 46, color: navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(roleLabel(me.role) + (me.branch.isEmpty ? '' : ' • ${me.branch}'), style: TextStyle(color: Colors.grey[700])),
              Text(sb.auth.currentUser?.email ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: red, minimumSize: const Size.fromHeight(48)),
        onPressed: s.signOut,
        icon: const Icon(Icons.logout),
        label: const Text('Keluar'),
      ),
      const SizedBox(height: 14),
      Text(
        'Semua barang masuk, kiriman, setoran, dan permintaan memerlukan persetujuan owner. Stok baru berpindah setelah disetujui dan diterima. Penjualan cabang langsung mengurangi stok cabang dan terlihat oleh owner.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey[700], fontSize: 12),
      ),
    ]);
  }
}
