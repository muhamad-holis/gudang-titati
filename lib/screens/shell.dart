import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'account_page.dart';
import 'beranda_page.dart';
import 'docs_page.dart';
import 'master_page.dart';
import 'sales_page.dart';
import 'stock_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;
  late final AppState _s;

  @override
  void initState() {
    super.initState();
    _s = context.read<AppState>();
    _s.start();
  }

  @override
  void dispose() {
    _s.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final me = s.me;
    if (me == null) {
      final err = s.profileError ?? s.loadError;
      return Scaffold(
        body: Center(
          child: err == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(err, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => s.refresh(), child: const Text('Coba lagi')),
                    TextButton(onPressed: s.signOut, child: const Text('Keluar')),
                  ]),
                ),
        ),
      );
    }

    final tabs = <List<Object>>[
      [Icons.home_rounded, 'Beranda'],
      [Icons.description_outlined, 'Dokumen'],
      if (s.role == 'cabang') [Icons.point_of_sale, 'Jual'],
      [Icons.inventory_2_outlined, 'Stok'],
      if (s.isOwner || s.role == 'gudang') [Icons.tune, s.isOwner ? 'Master' : 'Barang'],
      [Icons.person_outline, 'Akun'],
    ];
    final pages = <Widget>[
      const BerandaPage(),
      const DocsPage(),
      if (s.role == 'cabang') const SalesPage(),
      const StockPage(),
      if (s.isOwner || s.role == 'gudang') const MasterPage(),
      const AccountPage(),
    ];
    if (idx >= tabs.length) idx = 0;
    final tasks = s.myTasks.length;

    return Scaffold(
      body: Column(children: [
        Container(
          color: navy,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              child: Row(children: [
                const Icon(Icons.warehouse_outlined, color: Colors.white, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('GUDANG TITATI', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    Text(
                      '${roleLabel(me.role)}${me.role == 'cabang' && me.branch.isNotEmpty ? ' • ${me.branch}' : ' • ${me.name}'}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFB8C7DE), fontSize: 12),
                    ),
                  ]),
                ),
                if (s.loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  )
                else
                  IconButton(tooltip: 'Muat ulang', icon: const Icon(Icons.refresh, color: Colors.white), onPressed: () => s.refresh()),
              ]),
            ),
          ),
        ),
        if (s.loadError != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF4E0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Text('Gagal memuat: ${s.loadError}', style: const TextStyle(fontSize: 12, color: orange, fontWeight: FontWeight.w600)),
          ),
        Expanded(child: IndexedStack(index: idx, children: pages)),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: [
          for (var i = 0; i < tabs.length; i++)
            NavigationDestination(
              icon: (i == 0 && tasks > 0)
                  ? Badge(label: Text('$tasks'), child: Icon(tabs[i][0] as IconData))
                  : Icon(tabs[i][0] as IconData),
              label: tabs[i][1] as String,
            ),
        ],
      ),
    );
  }
}
