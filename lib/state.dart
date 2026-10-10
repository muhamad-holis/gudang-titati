import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient, PostgrestException;
import 'bon.dart';
import 'models.dart';
import 'tagihan.dart';
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
  List<Payment> payments = [];
  String? payError;
  List<RekapRow> rekap = [];
  String? salesError;
  List<NilaiRow> nilaiGudang = [];
  String? nilaiError;
  bool nilaiLoaded = false;
  AppRules rules = const AppRules();
  bool rulesLoaded = false;
  String? rulesError;
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
    payments = [];
    payError = null;
    rekap = [];
    salesError = null;
    nilaiGudang = [];
    nilaiError = null;
    nilaiLoaded = false;
    rules = const AppRules();
    rulesLoaded = false;
    rulesError = null;
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
        await _loadRules();
        await _loadPayments();
        if (me!.role == 'owner') {
          await _loadNilai();
          final pr = await sb.from('profiles').select('branch, role');
          profileBranches = {
            for (final e in pr)
              if (e['role'] == 'cabang' && ((e['branch'] as String?) ?? '').isNotEmpty) e['branch'] as String,
          }.toList()
            ..sort();
        } else if (me!.role == 'gudang') {
          // gudang tidak boleh membaca profil; daftar cabang tujuan diambil lewat fungsi database
          try {
            final r = await sb.rpc('list_cabang');
            profileBranches = [for (final e in (r as List)) e.toString()]..sort();
          } catch (_) {}
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

  /// Nilai stok gudang (owner). Dimuat terpisah supaya aplikasi tetap jalan walau SQL nilai gudang belum dijalankan.
  Future<void> _loadNilai() async {
    try {
      final r = await sb.rpc('nilai_gudang');
      nilaiGudang = [for (final e in (r as List)) NilaiRow.fromJson(Map<String, dynamic>.from(e as Map))];
      nilaiError = null;
      nilaiLoaded = true;
    } catch (e) {
      nilaiError = errText(e);
    }
  }

  double get totalNilaiGudang => nilaiGudang.fold(0.0, (a, r) => a + r.nilai);

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

  /// Pembayaran (bon cabang & tagihan grosir) dimuat terpisah supaya aplikasi tetap jalan walau SQL omzet_tagihan belum dijalankan.
  Future<void> _loadPayments() async {
    try {
      final r = await sb.from('doc_payments').select().order('paid_at', ascending: false).order('id', ascending: false).limit(2000);
      payments = [for (final e in r) Payment.fromJson(Map<String, dynamic>.from(e))];
      payError = null;
    } catch (e) {
      payError = errText(e);
    }
  }

  /// Rincian pembayaran satu dokumen (terbaru di atas).
  List<Payment> paymentsOf(String docId) => payments.where((p) => p.docId == docId).toList();

  double paidOf(String docId) => payments.where((p) => p.docId == docId).fold(0.0, (a, p) => a + p.amount);

  /// Sisa bon cabang yang belum dibayar.
  double bonSisa(Doc d) {
    final v = bonNilai(d) - paidOf(d.id);
    return v < 0 ? 0 : v;
  }

  /// Sisa tagihan grosir yang belum dibayar.
  double masukSisa(Doc d) {
    final v = masukTotal(d) - paidOf(d.id);
    return v < 0 ? 0 : v;
  }

  /// Semua nota grosir tempo, yang belum lunas dulu (jatuh tempo terdekat di atas).
  List<Doc> get tagihanSupplier {
    final list = docs.where(masukTempo).toList();
    list.sort((a, b) {
      final la = masukSisa(a) <= 0.5, lb = masukSisa(b) <= 0.5;
      if (la != lb) return la ? 1 : -1;
      final ja = a.jatuhTempo ?? DateTime(2100), jb = b.jatuhTempo ?? DateTime(2100);
      final c = ja.compareTo(jb);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<Doc> get tagihanBelumLunas => tagihanSupplier.where((d) => masukSisa(d) > 0.5).toList();

  /// Tagihan yang jatuh temponya sudah lewat atau tinggal beberapa hari.
  List<Doc> get tagihanMendekati => tagihanBelumLunas.where((d) {
        final st = tagihanStatus(d, masukSisa(d));
        return st == 'lewat' || st == 'dekat';
      }).toList();

  /// Aturan ACC dimuat terpisah supaya aplikasi tetap jalan walau SQL ACC selektif belum dijalankan.
  Future<void> _loadRules() async {
    try {
      final r = await sb.from('app_rules').select().eq('id', 1).maybeSingle();
      if (r != null) rules = AppRules.fromJson(Map<String, dynamic>.from(r));
      rulesLoaded = true;
      rulesError = null;
    } catch (e) {
      rulesError = errText(e);
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

  /// Barang di gudang yang stoknya sudah di bawah atau sama dengan batas minimum (stok minimum > 0).
  List<LowStock> get stokMenipis {
    final out = <LowStock>[];
    for (final i in items) {
      if (!i.active || i.stokMin <= 0) continue;
      final q = stockAt('gudang', i.id);
      if (q <= i.stokMin) out.add(LowStock(i, q));
    }
    out.sort((a, b) => (a.qty / a.item.stokMin).compareTo(b.qty / b.item.stokMin));
    return out;
  }

  /// Semua lokasi stok: gudang, produksi, lalu cabang.
  List<String> get locations {
    if (role == 'cabang') return [me?.branch ?? ''];
    final br = <String>{
      ...profileBranches,
      ...stock.map((r) => r.location).where((l) => l != 'gudang' && l != 'produksi'),
      ...docs.where((d) => (d.type == 'minta_cabang' || d.type == 'kirim_cabang') && d.branch.isNotEmpty).map((d) => d.branch),
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
  /// Hanya barang yang dijual (bahan jadi / siap jual); bahan dan perlengkapan cabang tidak ikut.
  List<RekapSum> rekapFor(String branch, DateTime from, DateTime to) {
    final m = <String, RekapSum>{};
    for (final r in rekap) {
      if (r.location != branch || r.day.isBefore(from) || r.day.isAfter(to)) continue;
      if (!sellable(r.itemId)) continue;
      final x = m.putIfAbsent(r.itemId, () => RekapSum(itemId: r.itemId, name: r.name, unit: r.unit, category: r.category));
      x.masuk += r.masuk;
      x.terjual += r.terjual;
    }
    return m.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Barang yang kurang diterima satu cabang (dikirim gudang lebih banyak dari yang diterima), berdasarkan tanggal terima.
  List<KurangRow> kurangFor(String branch, DateTime from, DateTime to) {
    final m = <String, KurangRow>{};
    for (final d in docs) {
      if ((d.type != 'minta_cabang' && d.type != 'kirim_cabang') || d.branch != branch || d.status != 'diterima' || d.receivedAt == null) continue;
      final r = d.receivedAt!;
      final day = DateTime(r.year, r.month, r.day);
      if (day.isBefore(from) || day.isAfter(to)) continue;
      for (final l in d.lines) {
        if (l.qtyReceived == null || l.qty - l.qtyReceived! <= 0.0001) continue;
        final x = m.putIfAbsent(l.itemId, () => KurangRow(itemId: l.itemId, name: l.name, unit: l.unit));
        x.dikirim += l.qty;
        x.diterima += l.qtyReceived!;
      }
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
      ((d.type == 'kirim_produksi' || d.type == 'minta_cabang' || d.type == 'kirim_cabang') && role == 'gudang') || (d.type == 'setor_jadi' && role == 'produksi');

  bool isReceiver(Doc d) =>
      (d.type == 'kirim_produksi' && role == 'produksi') ||
      (d.type == 'setor_jadi' && role == 'gudang') ||
      ((d.type == 'minta_cabang' || d.type == 'kirim_cabang') && role == 'cabang' && me?.branch == d.branch);

  bool isCreator(Doc d) => me != null && d.createdBy == me!.id;

  /// Teks tindakan yang menunggu akun ini pada dokumen (null = tidak ada).
  String? actionFor(Doc d) {
    if (isOwner && d.belumVerif) return 'Verifikasi pembelian';
    if (isOwner && d.status == 'diajukan') return 'Perlu ACC';
    if (d.status == 'disetujui' && d.type != 'masuk' && isSender(d)) return 'Siap dikirim';
    if (d.status == 'dikirim' && isReceiver(d)) return 'Konfirmasi terima';
    return null;
  }

  List<Doc> get myTasks => docs.where((d) => actionFor(d) != null).toList();

  /// Pembelian (Barang Masuk) yang stoknya sudah masuk dan menunggu verifikasi owner.
  List<Doc> get pembelianBelumVerif => docs.where((d) => d.belumVerif).toList();

  /// Untuk owner (memantau): selisih terima 14 hari terakhir, dan dokumen tertahan lebih dari 24 jam.
  List<Doc> get ownerAlerts {
    final now = DateTime.now();
    return docs.where((d) {
      if (d.hasDiff) return now.difference(d.receivedAt ?? d.createdAt).inDays < 14;
      if (d.status == 'dikirim' && d.sentAt != null) return now.difference(d.sentAt!).inHours >= 24;
      if (d.status == 'disetujui' && d.type == 'minta_cabang') return now.difference(d.createdAt).inHours >= 24;
      return false;
    }).toList();
  }

  // ---------- aksi (semua lewat fungsi database) ----------
  /// Mengembalikan dokumen yang baru dibuat (statusnya menunjukkan apakah langsung jalan atau menunggu ACC owner).
  Future<Doc?> createDoc(String type, String supplier, String note, List<Map<String, dynamic>> lines) async {
    final id = await sb.rpc('create_doc', params: {'p_type': type, 'p_supplier': supplier, 'p_note': note, 'p_lines': lines});
    await refresh(silent: true);
    return id is String ? docById(id) : null;
  }

  /// Barang Masuk dengan cara bayar: mode 'cash' (lunas) atau 'tempo' (isi jatuhTempo).
  Future<Doc?> createMasuk(String supplier, String note, List<Map<String, dynamic>> lines, String mode, DateTime? jatuhTempo) async {
    final id = await sb.rpc('create_masuk', params: {
      'p_supplier': supplier,
      'p_note': note,
      'p_lines': lines,
      'p_mode': mode,
      'p_jatuh_tempo': jatuhTempo == null ? null : ymd(jatuhTempo),
    });
    await refresh(silent: true);
    return id is String ? docById(id) : null;
  }

  /// Kirim ke Cabang dengan harga jual per barang (payload memuat sell_price).
  Future<Doc?> createKirimCabang(String cabang, String note, List<Map<String, dynamic>> lines) async {
    final id = await sb.rpc('create_kirim_cabang', params: {'p_cabang': cabang, 'p_note': note, 'p_lines': lines});
    await refresh(silent: true);
    return id is String ? docById(id) : null;
  }

  Future<void> aturPembayaranMasuk(String docId, String mode, DateTime? jatuhTempo) async {
    await sb.rpc('atur_pembayaran_masuk', params: {'p_doc': docId, 'p_mode': mode, 'p_jatuh_tempo': jatuhTempo == null ? null : ymd(jatuhTempo)});
    await refresh(silent: true);
  }

  /// lines: [{line_id, sell_price}]
  Future<void> aturHargaJual(String docId, List<Map<String, dynamic>> lines) async {
    await sb.rpc('atur_harga_jual', params: {'p_doc': docId, 'p_lines': lines});
    await refresh(silent: true);
  }

  Future<void> bayarBon(String docId, double amount, String method, DateTime paidAt, String note) async {
    await sb.rpc('catat_bayar_bon', params: {'p_doc': docId, 'p_amount': amount, 'p_method': method, 'p_paid_at': ymd(paidAt), 'p_note': note});
    await refresh(silent: true);
  }

  Future<void> bayarSupplier(String docId, double amount, String method, DateTime paidAt, String note) async {
    await sb.rpc('catat_bayar_supplier', params: {'p_doc': docId, 'p_amount': amount, 'p_method': method, 'p_paid_at': ymd(paidAt), 'p_note': note});
    await refresh(silent: true);
  }

  Future<void> batalBayar(int paymentId) async {
    await sb.rpc('batal_bayar', params: {'p_id': paymentId});
    await refresh(silent: true);
  }

  /// Harga beli rata-rata sebuah barang dari Barang Masuk yang tercatat (acuan modal saat menentukan harga jual).
  double modalRata(String itemId) {
    var qty = 0.0, nilai = 0.0;
    for (final d in docs) {
      if (d.type != 'masuk' || d.status != 'diterima') continue;
      for (final l in d.lines) {
        if (l.itemId == itemId && l.price > 0) {
          qty += l.qty;
          nilai += l.qty * l.price;
        }
      }
    }
    return qty > 0 ? nilai / qty : 0;
  }

  /// Isian awal harga jual: harga jual standar barang bila sudah diatur, selain itu harga jual terakhir. 0 bila belum ada.
  double hargaAwal(String itemId, {String? cabang}) {
    final std = itemById(itemId)?.sellPriceDefault ?? 0;
    if (std > 0) return std;
    final last = hargaJualTerakhir(itemId, cabang: cabang);
    return last > 0 ? last : hargaJualTerakhir(itemId);
  }

  /// Barang bahan jadi (hasil produksi) boleh dikirim tanpa harga jual dulu; harga diisi menyusul.
  bool hargaBolehKosong(String itemId) => itemById(itemId)?.kind == 'jadi';

  /// Pengiriman ke cabang yang sudah terkirim tetapi masih ada barang tanpa harga jual.
  List<Doc> get kirimanBelumBerharga => [for (final d in docs) if (bonTanpaHarga(d) > 0) d];

  /// Harga jual terakhir sebuah barang ke cabang tertentu (untuk isian awal), 0 bila belum pernah.
  double hargaJualTerakhir(String itemId, {String? cabang}) {
    DateTime? best;
    var harga = 0.0;
    for (final d in docs) {
      if (!isBonDoc(d) || (cabang != null && d.branch != cabang)) continue;
      for (final l in d.lines) {
        if (l.itemId == itemId && l.sellPrice > 0) {
          final t = bonWaktu(d);
          if (best == null || t.isAfter(best)) {
            best = t;
            harga = l.sellPrice;
          }
        }
      }
    }
    return harga;
  }

  Future<void> setRules(double toleransi, double faktor, int hari, int minData) async {
    await sb.rpc('set_rules', params: {'p_toleransi': toleransi, 'p_faktor': faktor, 'p_hari': hari, 'p_min': minData});
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

  Future<void> sendDoc(String docId, {List<Map<String, dynamic>>? lines}) async {
    await sb.rpc('send_doc', params: {'p_doc': docId, 'p_lines': lines});
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
  Future<Item> addItem(String name, String kind, String category, String unit, {bool siapJual = false, String jalur = 'olah'}) async {
    final r = await sb
        .from('items')
        .insert({
          'name': name.trim(),
          'kind': kind,
          'category': category.trim(),
          'unit': unit.trim(),
          if (siapJual) 'siap_jual': true,
          if (kind == 'mentah' && !siapJual && jalur != 'olah') ...{'untuk_produksi': jalur != 'cabang', 'ke_cabang': true},
        })
        .select()
        .single();
    final it = Item.fromJson(Map<String, dynamic>.from(r));
    items = [...items, it]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    notifyListeners();
    return it;
  }

  Future<void> updateItem(String id,
      {required String name,
      required String category,
      required String unit,
      required bool active,
      bool? siapJual,
      double? rendemenStd,
      bool setRendemen = false,
      String? jalur,
      double? stokMin,
      bool setStokMin = false,
      double? sellPriceDefault}) async {
    await sb.from('items').update({
      'name': name.trim(),
      'category': category.trim(),
      'unit': unit.trim(),
      'active': active,
      if (siapJual != null) 'siap_jual': siapJual,
      if (setRendemen) 'rendemen_std': rendemenStd,
      if (setStokMin) 'stok_min': stokMin ?? 0,
      if (sellPriceDefault != null) 'sell_price_default': sellPriceDefault,
      if (jalur != null) ...{'untuk_produksi': jalur != 'cabang', 'ke_cabang': jalur != 'olah'},
    }).eq('id', id);
    await refresh(silent: true);
  }

  /// Hapus barang (owner). 'hapus' = dihapus permanen; 'arsip' = punya riwayat, hanya dinonaktifkan.
  Future<String> hapusBarang(String id) async {
    final r = await sb.rpc('hapus_barang', params: {'p_item': id});
    await refresh(silent: true);
    return r.toString();
  }

  /// Gabungkan barang dobel: riwayat dan stok [dari] dipindah ke [ke], lalu [dari] dihapus (owner).
  Future<void> gabungBarang(String dari, String ke) async {
    await sb.rpc('gabung_barang', params: {'p_dari': dari, 'p_ke': ke});
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
