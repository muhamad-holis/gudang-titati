import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient, PostgrestException;
import 'models.dart';
import 'utils.dart';

SupabaseClient get sb => Supabase.instance.client;

String errText(Object e) {
  if (e is PostgrestException) {
    if (e.code == '23505') return 'Data dengan nama itu sudah ada';
    return e.message;
  }
  return '$e';
}

class AppState extends ChangeNotifier {
  Profile? me;
  String? profileError;
  String? loadError;
  bool loading = false;
  List<Item> items = [];
  List<String> categories = [];
  List<Doc> docs = [];
  List<StockRow> stock = [];
  List<String> profileBranches = [];
  List<SaleEntry> sales = [];
  List<RekapRow> rekap = [];
  String? salesError;
  Timer? _timer;
  bool _started = false;
  bool _refreshing = false;

  String get role => me?.role ?? '';
  bool get isOwner => role == 'owner';

  // ---------- siklus ----------
  void start() {
    if (_started) return;
    _started = true;
    loading = true;
    _timer = Timer.periodic(const Duration(seconds: 25), (_) => refresh(silent: true));
    Future.microtask(() => refresh());
  }

  /// Dipanggil saat keluar. Sengaja tidak memanggil notifyListeners.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    me = null;
    profileError = null;
    loadError = null;
    items = [];
    categories = [];
    docs = [];
    stock = [];
    profileBranches = [];
    sales = [];
    rekap = [];
    salesError = null;
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing) return;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    _refreshing = true;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final p = await sb.from('profiles').select().eq('id', uid).maybeSingle();
      if (p == null) {
        me = null;
        profileError = 'Akun ini belum diberi peran. Hubungi owner.';
      } else {
        me = Profile.fromJson(p);
        profileError = null;
        final its = await sb.from('items').select().order('name');
        items = [for (final e in its) Item.fromJson(Map<String, dynamic>.from(e))];
        final cats = await sb.from('categories').select().order('name');
        categories = [for (final e in cats) e['name'] as String];
        final ds = await sb
            .from('docs')
            .select('*, doc_lines(*, items(name, unit, kind, category))')
            .order('created_at', ascending: false)
            .limit(400);
        docs = [for (final e in ds) Doc.fromJson(Map<String, dynamic>.from(e))];
        final st = await sb.from('v_stock').select();
        stock = [for (final e in st) StockRow.fromJson(Map<String, dynamic>.from(e))];
        await _loadSales();
        if (me!.role == 'owner') {
          final pr = await sb.from('profiles').select('branch, role');
          profileBranches = {
            for (final e in pr)
              if (e['role'] == 'cabang' && ((e['branch'] as String?) ?? '').isNotEmpty) e['branch'] as String,
          }.toList()
            ..sort();
        }
      }
      loadError = null;
    } catch (e) {
      loadError = errText(e);
    }
    _refreshing = false;
    loading = false;
    notifyListeners();
  }

  /// Data penjualan dimuat terpisah supaya aplikasi tetap jalan walau SQL penjualan belum dijalankan.
  Future<void> _loadSales() async {
    try {
      final since = DateTime.now().subtract(const Duration(days: 62));
      final rk = await sb.from('v_rekap_harian').select().gte('hari', '${since.year}-${two(since.month)}-${two(since.day)}');
      rekap = [for (final e in rk) RekapRow.fromJson(Map<String, dynamic>.from(e))];
      final sl = await sb
          .from('stock_ledger')
          .select('id, at, location, delta, kind, reason, by_name, ref_id, items(name, unit)')
          .inFilter('kind', ['jual', 'jual_batal'])
          .order('at', ascending: false)
          .limit(600);
      sales = [for (final e in sl) SaleEntry.fromJson(Map<String, dynamic>.from(e))];
      salesError = null;
    } catch (e) {
      salesError = errText(e);
    }
  }

  // ---------- bantu ----------
  Doc? docById(String id) {
    for (final d in docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  Item? itemById(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  bool isSiapJual(String itemId) => itemById(itemId)?.siapJual ?? false;

  /// Bisa diminta cabang dan dijual cabang: bahan jadi atau barang siap jual.
  bool sellable(String itemId) {
    final i = itemById(itemId);
    return i != null && (i.kind == 'jadi' || i.siapJual);
  }

  List<Item> itemsOf(String kind) => items.where((i) => i.kind == kind && i.active).toList();

  double stockAt(String location, String itemId) {
    for (final r in stock) {
      if (r.location == location && r.itemId == itemId) return r.qty;
    }
    return 0;
  }

  /// Semua lokasi stok: gudang, produksi, lalu cabang.
  List<String> get locations {
    if (role == 'cabang') return [me?.branch ?? ''];
    final br = <String>{
      ...profileBranches,
      ...stock.map((r) => r.location).where((l) => l != 'gudang' && l != 'produksi'),
      ...docs.where((d) => d.type == 'minta_cabang' && d.branch.isNotEmpty).map((d) => d.branch),
    }.toList()
      ..sort();
    return ['gudang', 'produksi', ...br];
  }

  /// Daftar cabang yang punya data penjualan / stok / permintaan.
  List<String> get saleBranches {
    final list = <String>{
      ...locations.where((l) => l != 'gudang' && l != 'produksi' && l.isNotEmpty),
      ...rekap.map((r) => r.location),
    }.toList()
      ..sort();
    return list;
  }

  /// Rekap masuk vs terjual satu cabang pada rentang tanggal [from, to] (inklusif).
  List<RekapSum> rekapFor(String branch, DateTime from, DateTime to) {
    final m = <String, RekapSum>{};
    for (final r in rekap) {
      if (r.location != branch || r.day.isBefore(from) || r.day.isAfter(to)) continue;
      final x = m.putIfAbsent(r.itemId, () => RekapSum(itemId: r.itemId, name: r.name, unit: r.unit, category: r.category));
      x.masuk += r.masuk;
      x.terjual += r.terjual;
    }
    return m.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Catatan penjualan satu cabang pada rentang tanggal.
  List<SaleEntry> salesFor(String branch, DateTime from, DateTime to) {
    return sales.where((e) {
      if (e.location != branch) return false;
      final d = DateTime(e.at.year, e.at.month, e.at.day);
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList();
  }

  bool isSender(Doc d) =>
      ((d.type == 'kirim_produksi' || d.type == 'minta_cabang') && role == 'gudang') || (d.type == 'setor_jadi' && role == 'produksi');

  bool isReceiver(Doc d) =>
      (d.type == 'kirim_produksi' && role == 'produksi') ||
      (d.type == 'setor_jadi' && role == 'gudang') ||
      (d.type == 'minta_cabang' && role == 'cabang' && me?.branch == d.branch);

  bool isCreator(Doc d) => me != null && d.createdBy == me!.id;

  /// Teks tindakan yang menunggu akun ini pada dokumen (null = tidak ada).
  String? actionFor(Doc d) {
    if (isOwner && d.status == 'diajukan') return 'Perlu ACC';
    if (d.status == 'disetujui' && d.type != 'masuk' && isSender(d)) return 'Siap dikirim';
    if (d.status == 'dikirim' && isReceiver(d)) return 'Konfirmasi terima';
    return null;
  }

  List<Doc> get myTasks => docs.where((d) => actionFor(d) != null).toList();

  // ---------- aksi (semua lewat fungsi database) ----------
  Future<void> createDoc(String type, String supplier, String note, List<Map<String, dynamic>> lines) async {
    await sb.rpc('create_doc', params: {'p_type': type, 'p_supplier': supplier, 'p_note': note, 'p_lines': lines});
    await refresh(silent: true);
  }

  Future<void> ownerDecide(String docId, String action, {String note = '', List<Map<String, dynamic>>? lines}) async {
    await sb.rpc('owner_decide', params: {'p_doc': docId, 'p_action': action, 'p_note': note, 'p_lines': lines});
    await refresh(silent: true);
  }

  Future<void> ownerEdit(String docId, List<Map<String, dynamic>> lines) async {
    await sb.rpc('owner_edit', params: {'p_doc': docId, 'p_lines': lines});
    await refresh(silent: true);
  }

  Future<void> sendDoc(String docId) async {
    await sb.rpc('send_doc', params: {'p_doc': docId});
    await refresh(silent: true);
  }

  Future<void> receiveDoc(String docId, List<Map<String, dynamic>> lines) async {
    await sb.rpc('receive_doc', params: {'p_doc': docId, 'p_lines': lines});
    await refresh(silent: true);
  }

  Future<void> cancelDoc(String docId) async {
    await sb.rpc('cancel_doc', params: {'p_doc': docId});
    await refresh(silent: true);
  }

  Future<void> koreksiStok(String location, String itemId, double newQty, String reason) async {
    await sb.rpc('koreksi_stok', params: {'p_location': location, 'p_item': itemId, 'p_new_qty': newQty, 'p_reason': reason});
    await refresh(silent: true);
  }

  Future<void> catatJual(String note, List<Map<String, dynamic>> lines) async {
    await sb.rpc('catat_jual', params: {'p_lines': lines, 'p_note': note});
    await refresh(silent: true);
  }

  Future<void> batalJual(int ledgerId) async {
    await sb.rpc('batal_jual', params: {'p_ledger': ledgerId});
    await refresh(silent: true);
  }

  Future<List<LogEntry>> fetchLog(String docId) async {
    final r = await sb.from('doc_log').select().eq('doc_id', docId).order('at');
    return [for (final e in r) LogEntry.fromJson(Map<String, dynamic>.from(e))];
  }

  // ---------- master data ----------
  Future<Item> addItem(String name, String kind, String category, String unit, {bool siapJual = false}) async {
    final r = await sb
        .from('items')
        .insert({'name': name.trim(), 'kind': kind, 'category': category.trim(), 'unit': unit.trim(), if (siapJual) 'siap_jual': true})
        .select()
        .single();
    final it = Item.fromJson(Map<String, dynamic>.from(r));
    items = [...items, it]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return it;
  }

  Future<void> updateItem(String id, {required String name, required String category, required String unit, required bool active, bool? siapJual}) async {
    await sb
        .from('items')
        .update({'name': name.trim(), 'category': category.trim(), 'unit': unit.trim(), 'active': active, if (siapJual != null) 'siap_jual': siapJual})
        .eq('id', id);
    await refresh(silent: true);
  }

  Future<void> addCategory(String name) async {
    await sb.from('categories').insert({'name': name.trim()});
    await refresh(silent: true);
  }

  Future<void> deleteCategory(String name) async {
    await sb.from('categories').delete().eq('name', name);
    await refresh(silent: true);
  }

  Future<void> signOut() async {
    await sb.auth.signOut();
  }
}
