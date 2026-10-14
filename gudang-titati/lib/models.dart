import 'utils.dart';

class Profile {
  final String id, name, role, branch;
  Profile({required this.id, required this.name, required this.role, required this.branch});
  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        role: (j['role'] as String?) ?? 'cabang',
        branch: (j['branch'] as String?) ?? '',
      );
}

class Item {
  final String id, name, kind, category, unit;
  final bool active;

  /// Barang dagangan: dibeli jadi, dikirim gudang langsung ke cabang, tanpa produksi.
  final bool siapJual;

  /// Standar rendemen bahan jadi: hasil jadi per 1 satuan bahan mentah (mis. 1,2). null = belum diatur.
  final double? rendemenStd;

  /// Bahan mentah yang boleh dikirim ke produksi untuk diolah.
  final bool untukProduksi;

  /// Boleh diminta cabang langsung dari gudang tanpa produksi (bahan/perlengkapan cabang, tidak dijual satuan).
  final bool keCabang;

  /// Batas stok minimum di gudang. 0 = tidak dipantau.
  final double stokMin;

  /// Harga jual standar ke cabang (isian awal saat kirim). 0 = belum diatur.
  final double sellPriceDefault;

  /// Satuan eceran di cabang (mis. botol) dan isi per satuan barang (mis. 24 botol per dus). Kosong/1 = tanpa konversi.
  final String unitEcer;
  final double isiEcer;
  Item({
    required this.id,
    required this.name,
    required this.kind,
    required this.category,
    required this.unit,
    this.active = true,
    this.siapJual = false,
    this.rendemenStd,
    this.untukProduksi = true,
    this.keCabang = false,
    this.stokMin = 0,
    this.sellPriceDefault = 0,
    this.unitEcer = '',
    this.isiEcer = 1,
  });

  /// Barang dicatat gudang dalam [unit] (dus) tetapi stok dan penjualan cabang dalam [unitEcer] (botol).
  bool get punyaEcer => unitEcer.isNotEmpty && isiEcer > 1;

  /// Satuan yang dipakai di sebuah lokasi: cabang memakai satuan eceran bila ada, gudang/produksi memakai satuan barang.
  String unitDi(String location) => (punyaEcer && location != 'gudang' && location != 'produksi') ? unitEcer : unit;

  /// Jalur bahan mentah: 'olah' (hanya produksi), 'cabang' (langsung ke cabang), 'dua' (keduanya).
  String get jalur => !untukProduksi ? 'cabang' : (keCabang ? 'dua' : 'olah');
  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        category: (j['category'] as String?) ?? 'Lainnya',
        unit: (j['unit'] as String?) ?? 'pcs',
        active: (j['active'] as bool?) ?? true,
        siapJual: (j['siap_jual'] as bool?) ?? false,
        rendemenStd: j['rendemen_std'] == null ? null : toD(j['rendemen_std']),
        untukProduksi: (j['untuk_produksi'] as bool?) ?? true,
        keCabang: (j['ke_cabang'] as bool?) ?? false,
        stokMin: j['stok_min'] == null ? 0 : toD(j['stok_min']),
        sellPriceDefault: j['sell_price_default'] == null ? 0 : toD(j['sell_price_default']),
        unitEcer: (j['unit_ecer'] as String?) ?? '',
        isiEcer: j['isi_ecer'] == null ? 1 : toD(j['isi_ecer']),
      );
}

String jalurLabel(String j) => j == 'cabang' ? 'langsung ke cabang' : (j == 'dua' ? 'diolah / langsung ke cabang' : 'diolah di produksi');

/// Aturan kapan owner perlu ACC (diatur owner di tab Master > Aturan).
class AppRules {
  final double rendemenToleransi, mintaFaktor;
  final int mintaHari, mintaMinData;
  const AppRules({this.rendemenToleransi = 15, this.mintaFaktor = 2, this.mintaHari = 28, this.mintaMinData = 3});
  factory AppRules.fromJson(Map<String, dynamic> j) => AppRules(
        rendemenToleransi: toD(j['rendemen_toleransi']),
        mintaFaktor: toD(j['minta_faktor']),
        mintaHari: toD(j['minta_hari']).round(),
        mintaMinData: toD(j['minta_min_data']).round(),
      );
}

class DocLine {
  final String id, itemId, role, name, unit, kind;
  final double qty, price;

  /// Harga jual gudang ke cabang (bon). price = modal (harga beli rata-rata saat dikirim).
  final double sellPrice;
  final double? qtyReceived;

  /// Jumlah yang diminta cabang bila stok gudang kosong/kurang saat dikirim (null = tidak ada masalah).
  final double? qtyMinta;
  final bool kosong;
  DocLine({
    required this.id,
    required this.itemId,
    required this.role,
    required this.name,
    required this.unit,
    required this.kind,
    required this.qty,
    required this.price,
    this.sellPrice = 0,
    this.qtyReceived,
    this.qtyMinta,
    this.kosong = false,
  });
  factory DocLine.fromJson(Map<String, dynamic> j) {
    final it = j['items'] is Map ? Map<String, dynamic>.from(j['items'] as Map) : <String, dynamic>{};
    return DocLine(
      id: j['id'] as String,
      itemId: j['item_id'] as String,
      role: (j['role'] as String?) ?? 'item',
      name: (it['name'] as String?) ?? '?',
      unit: (it['unit'] as String?) ?? '',
      kind: (it['kind'] as String?) ?? '',
      qty: toD(j['qty']),
      price: toD(j['unit_price']),
      sellPrice: toD(j['sell_price']),
      qtyReceived: j['qty_received'] == null ? null : toD(j['qty_received']),
      qtyMinta: j['qty_minta'] == null ? null : toD(j['qty_minta']),
      kosong: (j['kosong'] as bool?) ?? false,
    );
  }
}

class Doc {
  final String id, no, type, status, branch, supplier, note, ownerNote, createdBy, createdByName, approvedByName, receivedByName;

  /// Khusus Barang Masuk: '' (dokumen lama), 'menunggu' (belum diverifikasi owner), 'ok', 'tolak'.
  final String verif;

  /// Alasan dokumen ini menunggu ACC owner (setoran / permintaan yang menyimpang).
  final String accReason;

  /// Khusus Barang Masuk: '' (dokumen lama, dianggap lunas), 'cash' (lunas), 'tempo' (dibayar belakangan).
  final String bayarMode;

  /// Batas bayar nota tempo (tanggal saja).
  final DateTime? jatuhTempo;
  final DateTime createdAt;
  final DateTime? approvedAt, sentAt, receivedAt;
  final List<DocLine> lines;
  Doc({
    required this.id,
    required this.no,
    required this.type,
    required this.status,
    required this.branch,
    required this.supplier,
    required this.note,
    required this.ownerNote,
    required this.createdBy,
    required this.createdByName,
    required this.approvedByName,
    required this.receivedByName,
    this.verif = '',
    this.accReason = '',
    this.bayarMode = '',
    this.jatuhTempo,
    required this.createdAt,
    this.approvedAt,
    this.sentAt,
    this.receivedAt,
    required this.lines,
  });

  factory Doc.fromJson(Map<String, dynamic> j) {
    DateTime? dt(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
    return Doc(
      id: j['id'] as String,
      no: (j['no'] as String?) ?? '',
      type: j['type'] as String,
      status: j['status'] as String,
      branch: (j['branch'] as String?) ?? '',
      supplier: (j['supplier'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      ownerNote: (j['owner_note'] as String?) ?? '',
      createdBy: (j['created_by'] as String?) ?? '',
      createdByName: (j['created_by_name'] as String?) ?? '',
      approvedByName: (j['approved_by_name'] as String?) ?? '',
      receivedByName: (j['received_by_name'] as String?) ?? '',
      verif: (j['verif'] as String?) ?? '',
      accReason: (j['acc_reason'] as String?) ?? '',
      bayarMode: (j['bayar_mode'] as String?) ?? '',
      jatuhTempo: j['jatuh_tempo'] == null ? null : DateTime.parse(j['jatuh_tempo'] as String),
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      approvedAt: dt(j['approved_at']),
      sentAt: dt(j['sent_at']),
      receivedAt: dt(j['received_at']),
      lines: [for (final e in ((j['doc_lines'] as List?) ?? [])) DocLine.fromJson(Map<String, dynamic>.from(e as Map))],
    );
  }

  /// Barang masuk yang stoknya sudah masuk tapi harga/pembelian belum di-ACC owner.
  bool get belumVerif => type == 'masuk' && verif == 'menunggu';

  /// Barang masuk yang pembeliannya ditolak owner (stok tidak ditarik).
  bool get pembelianDitolak => type == 'masuk' && verif == 'tolak';

  /// Baris yang diterima di tujuan (untuk setoran: hanya hasil jadi).
  List<DocLine> get receivable => lines.where((l) => type != 'setor_jadi' || l.role == 'hasil').toList();

  bool get hasDiff => status == 'diterima' && receivable.any((l) => l.qtyReceived != null && (l.qtyReceived! - l.qty).abs() > 0.0001);

  String get summary {
    final src = type == 'setor_jadi' ? lines.where((l) => l.role == 'hasil').toList() : lines;
    final parts = src.take(3).map((l) => '${fmtQty(l.qty)} ${l.unit} ${l.name}').toList();
    final more = src.length > 3 ? ' +${src.length - 3} lainnya' : '';
    return parts.join(', ') + more;
  }
}

class LogEntry {
  final DateTime at;
  final String byName, byRole, action, detail;
  LogEntry({required this.at, required this.byName, required this.byRole, required this.action, required this.detail});
  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        at: DateTime.parse(j['at'] as String).toLocal(),
        byName: (j['by_name'] as String?) ?? '',
        byRole: (j['by_role'] as String?) ?? '',
        action: (j['action'] as String?) ?? '',
        detail: (j['detail'] as String?) ?? '',
      );
}

class StockRow {
  final String location, itemId, name, category, unit, kind;
  final double qty;
  StockRow({required this.location, required this.itemId, required this.name, required this.category, required this.unit, required this.kind, required this.qty});
  factory StockRow.fromJson(Map<String, dynamic> j) => StockRow(
        location: j['location'] as String,
        itemId: j['item_id'] as String,
        name: (j['name'] as String?) ?? '?',
        category: (j['category'] as String?) ?? '',
        unit: (j['unit'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? '',
        qty: toD(j['qty']),
      );
}

/// Nilai stok satu barang di gudang (khusus owner).
class NilaiRow {
  final String itemId, name, category, unit;
  final bool siapJual;
  final double qty, hargaRata, nilai;
  NilaiRow({required this.itemId, required this.name, required this.category, required this.unit, required this.siapJual, required this.qty, required this.hargaRata, required this.nilai});
  bool get adaHarga => hargaRata > 0;
  factory NilaiRow.fromJson(Map<String, dynamic> j) => NilaiRow(
        itemId: j['item_id'] as String,
        name: (j['nama'] as String?) ?? '?',
        category: (j['kategori'] as String?) ?? '',
        unit: (j['satuan'] as String?) ?? '',
        siapJual: j['siap_jual'] == true,
        qty: toD(j['stok']),
        hargaRata: toD(j['harga_rata']),
        nilai: toD(j['nilai']),
      );
}

/// Satu catatan penjualan (atau pembatalannya) di cabang.
class SaleEntry {
  final int id;
  final DateTime at;
  final String location, kind, reason, byName, itemName, unit;
  final double qty;
  final int? refId;
  SaleEntry({
    required this.id,
    required this.at,
    required this.location,
    required this.kind,
    required this.reason,
    required this.byName,
    required this.itemName,
    required this.unit,
    required this.qty,
    this.refId,
  });
  factory SaleEntry.fromJson(Map<String, dynamic> j) {
    final it = j['items'] is Map ? Map<String, dynamic>.from(j['items'] as Map) : <String, dynamic>{};
    return SaleEntry(
      id: (j['id'] as num).toInt(),
      at: DateTime.parse(j['at'] as String).toLocal(),
      location: (j['location'] as String?) ?? '',
      kind: (j['kind'] as String?) ?? 'jual',
      reason: (j['reason'] as String?) ?? '',
      byName: (j['by_name'] as String?) ?? '',
      itemName: (it['name'] as String?) ?? '?',
      unit: (it['unit'] as String?) ?? '',
      qty: toD(j['delta']).abs(),
      refId: j['ref_id'] == null ? null : (j['ref_id'] as num).toInt(),
    );
  }
  bool get isCancel => kind == 'jual_batal';
}

/// Rekap harian per bahan per cabang (barang masuk vs terjual).
class RekapRow {
  final DateTime day;
  final String location, itemId, name, unit, category;
  final double masuk, terjual;
  RekapRow({
    required this.day,
    required this.location,
    required this.itemId,
    required this.name,
    required this.unit,
    required this.category,
    required this.masuk,
    required this.terjual,
  });
  factory RekapRow.fromJson(Map<String, dynamic> j) => RekapRow(
        day: DateTime.parse(j['hari'] as String),
        location: j['location'] as String,
        itemId: j['item_id'] as String,
        name: (j['name'] as String?) ?? '?',
        unit: (j['unit'] as String?) ?? '',
        category: (j['category'] as String?) ?? '',
        masuk: toD(j['masuk']),
        terjual: toD(j['terjual']),
      );
}

/// Barang yang diterima cabang lebih sedikit dari yang dikirim gudang (pada rentang tanggal tertentu).
class KurangRow {
  final String itemId, name, unit;
  double dikirim = 0, diterima = 0;
  KurangRow({required this.itemId, required this.name, required this.unit});
  double get kurang => dikirim - diterima;
}

/// Jumlah rekap satu bahan pada rentang tanggal tertentu.
class RekapSum {
  final String itemId, name, unit, category;
  double masuk = 0, terjual = 0;
  RekapSum({required this.itemId, required this.name, required this.unit, required this.category});

  /// Masuk dikurangi terjual. 0 = pas, positif = masih sisa, negatif = terjual lebih banyak dari yang masuk.
  double get selisih => masuk - terjual;
  bool get pas => selisih.abs() < 0.0001;
}


/// Barang gudang yang stoknya menipis (<= stok minimum).
class LowStock {
  final Item item;
  final double qty;
  LowStock(this.item, this.qty);
  double get kurang => item.stokMin - qty;
}


/// Satu pembayaran: pelunasan bon cabang (kind 'bon') atau pembayaran ke grosir (kind 'supplier').
class Payment {
  final int id;
  final String docId, kind, method, note, byName;
  final double amount;
  final DateTime paidAt;
  Payment({
    required this.id,
    required this.docId,
    required this.kind,
    required this.method,
    required this.note,
    required this.byName,
    required this.amount,
    required this.paidAt,
  });
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: (j['id'] as num).toInt(),
        docId: j['doc_id'] as String,
        kind: (j['kind'] as String?) ?? '',
        method: (j['method'] as String?) ?? 'cash',
        note: (j['note'] as String?) ?? '',
        byName: (j['by_name'] as String?) ?? '',
        amount: toD(j['amount']),
        paidAt: DateTime.parse(j['paid_at'] as String),
      );
  String get methodLabel => method == 'transfer' ? 'Transfer' : 'Cash';
}
