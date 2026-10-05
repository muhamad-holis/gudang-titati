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
  Item({required this.id, required this.name, required this.kind, required this.category, required this.unit, this.active = true});
  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String,
        category: (j['category'] as String?) ?? 'Lainnya',
        unit: (j['unit'] as String?) ?? 'pcs',
        active: (j['active'] as bool?) ?? true,
      );
}

class DocLine {
  final String id, itemId, role, name, unit, kind;
  final double qty, price;
  final double? qtyReceived;
  DocLine({
    required this.id,
    required this.itemId,
    required this.role,
    required this.name,
    required this.unit,
    required this.kind,
    required this.qty,
    required this.price,
    this.qtyReceived,
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
      qtyReceived: j['qty_received'] == null ? null : toD(j['qty_received']),
    );
  }
}

class Doc {
  final String id, no, type, status, branch, supplier, note, ownerNote, createdBy, createdByName, approvedByName, receivedByName;
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
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      approvedAt: dt(j['approved_at']),
      sentAt: dt(j['sent_at']),
      receivedAt: dt(j['received_at']),
      lines: [for (final e in ((j['doc_lines'] as List?) ?? [])) DocLine.fromJson(Map<String, dynamic>.from(e as Map))],
    );
  }

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
