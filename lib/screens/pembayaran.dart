import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../utils.dart';

/// Hasil dialog pembayaran.
class BayarInput {
  final double amount;
  final String method; // 'transfer' | 'cash'
  final DateTime paidAt;
  final String note;
  const BayarInput(this.amount, this.method, this.paidAt, this.note);
}

/// Dialog catat pembayaran. Jumlah awal = sisa (tekan Simpan = lunas penuh). Boleh dicicil.
Future<BayarInput?> showBayarDialog(
  BuildContext context, {
  required String title,
  required double sisa,
  String info = '',
  String okText = 'Simpan pembayaran',
}) {
  final amount = TextEditingController(text: sisa.round().toString());
  final note = TextEditingController();
  var method = 'transfer';
  var tanggal = DateTime.now();
  String? err;
  return showDialog<BayarInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (info.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(info, style: const TextStyle(fontSize: 12))),
            Text('Sisa ${rp(sisa)}', style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Jumlah dibayar', prefixText: 'Rp ', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => setD(() => amount.text = sisa.round().toString()), child: const Text('Isi sisa penuh')),
            ),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Transfer'), selected: method == 'transfer', onSelected: (_) => setD(() => method = 'transfer')),
              ChoiceChip(label: const Text('Cash'), selected: method == 'cash', onSelected: (_) => setD(() => method = 'cash')),
            ]),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final p = await showDatePicker(
                  context: ctx,
                  initialDate: tanggal,
                  firstDate: DateTime(now.year - 2),
                  lastDate: DateTime(now.year, now.month, now.day),
                );
                if (p != null) setD(() => tanggal = p);
              },
              icon: const Icon(Icons.event, size: 18),
              label: Text('Tanggal bayar: ${tgl(tanggal)}'),
            ),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder())),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: red, fontWeight: FontWeight.w600))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: green),
            onPressed: () {
              final a = parseQty(amount.text);
              if (a == null || a <= 0) return setD(() => err = 'Isi jumlah pembayaran');
              if (a > sisa + 0.5) return setD(() => err = 'Jumlah melebihi sisa (${rp(sisa)})');
              Navigator.pop(ctx, BayarInput(a, method, tanggal, note.text.trim()));
            },
            child: Text(okText),
          ),
        ],
      ),
    ),
  );
}

/// Daftar riwayat pembayaran. Bila [onBatal] diisi (owner), tiap baris punya tombol batalkan.
class RiwayatBayar extends StatelessWidget {
  final List<Payment> list;
  final void Function(Payment p)? onBatal;
  const RiwayatBayar({super.key, required this.list, this.onBatal});

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Belum ada pembayaran', style: TextStyle(fontSize: 12, color: Colors.grey)));
    }
    return Column(children: [
      for (final p in list)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2, right: 8), child: Icon(Icons.check_circle, size: 16, color: green)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tgl(p.paidAt)} • ${p.methodLabel}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('${p.byName.isEmpty ? '' : 'dicatat ${p.byName}'}${p.note.isEmpty ? '' : '${p.byName.isEmpty ? '' : ' • '}${p.note}'}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[700])),
              ]),
            ),
            Text(rp(p.amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: green)),
            if (onBatal != null)
              IconButton(
                tooltip: 'Batalkan pembayaran ini',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.undo, size: 18, color: red),
                onPressed: () => onBatal!(p),
              ),
          ]),
        ),
    ]);
  }
}

/// Lencana kecil berwarna.
class Pil extends StatelessWidget {
  final String text;
  final Color fg, bg;
  const Pil(this.text, {super.key, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
      );
}

/// Warna lencana status bayar bon: lunas hijau, cicil/belum oranye, nol abu-abu.
Pil pilBon(String st, String label) {
  switch (st) {
    case 'lunas':
      return Pil(label, fg: const Color(0xFF14753A), bg: const Color(0xFFDCF5E3));
    case 'sebagian':
      return Pil(label, fg: orange, bg: const Color(0xFFFFF4E0));
    case 'belum':
      return Pil(label, fg: red, bg: const Color(0xFFFDE8E8));
    default:
      return Pil(label, fg: const Color(0xFF555555), bg: const Color(0xFFEDEDED));
  }
}

/// Warna lencana status tagihan grosir.
Pil pilTagihan(String st, String label) {
  switch (st) {
    case 'lunas':
      return Pil(label, fg: const Color(0xFF14753A), bg: const Color(0xFFDCF5E3));
    case 'lewat':
      return Pil(label, fg: red, bg: const Color(0xFFFDE8E8));
    case 'dekat':
      return Pil(label, fg: orange, bg: const Color(0xFFFFF4E0));
    default:
      return Pil(label, fg: const Color(0xFF1565F0), bg: const Color(0xFFE6EEFB));
  }
}
