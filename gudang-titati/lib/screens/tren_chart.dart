import 'package:flutter/material.dart';
import '../nilai_periode.dart';
import '../theme.dart';
import '../utils.dart';

/// Grafik garis tren nilai stok per hari. Sentuh/geser untuk melihat nilai tiap hari.
class TrenChart extends StatefulWidget {
  final List<TrenPoint> data;
  const TrenChart({super.key, required this.data});
  @override
  State<TrenChart> createState() => _TrenChartState();
}

class _TrenChartState extends State<TrenChart> {
  int? sel;

  void _pick(Offset p, double w) {
    final n = widget.data.length;
    if (n < 2) return;
    final i = ((p.dx / w) * (n - 1)).round().clamp(0, n - 1);
    if (i != sel) setState(() => sel = i);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    if (d.length < 2) return const SizedBox.shrink();
    final idx = (sel ?? d.length - 1).clamp(0, d.length - 1);
    final pt = d[idx];
    final vals = d.map((e) => e.nilai);
    final hi = vals.reduce((a, b) => a > b ? a : b);
    final lo = vals.reduce((a, b) => a < b ? a : b);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tren nilai stok', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('${tgl(pt.hari)}: ${rp(pt.nilai)}', style: const TextStyle(fontSize: 13, color: navy, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (c, box) {
          final w = box.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (e) => _pick(e.localPosition, w),
            onHorizontalDragUpdate: (e) => _pick(e.localPosition, w),
            child: SizedBox(height: 130, width: w, child: CustomPaint(painter: _TrenPainter(d, idx, hi, lo))),
          );
        }),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(tgl(d.first.hari), style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          Text(tgl(d.last.hari), style: TextStyle(fontSize: 11, color: Colors.grey[700])),
        ]),
        const SizedBox(height: 4),
        Text('Tertinggi ${rp(hi)} • Terendah ${rp(lo)}', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
      ]),
    );
  }
}

class _TrenPainter extends CustomPainter {
  final List<TrenPoint> d;
  final int sel;
  final double hi, lo;
  _TrenPainter(this.d, this.sel, this.hi, this.lo);

  @override
  void paint(Canvas canvas, Size size) {
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    const padV = 8.0;
    Offset at(int i) {
      final x = size.width * i / (d.length - 1);
      final y = padV + (size.height - 2 * padV) * (1 - (d[i].nilai - lo) / span);
      return Offset(x, y);
    }

    final grid = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var k = 0; k <= 2; k++) {
      final y = padV + (size.height - 2 * padV) * k / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < d.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = blue.withOpacity(0.10));
    canvas.drawPath(
        path,
        Paint()
          ..color = blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round);
    final p = at(sel);
    canvas.drawLine(Offset(p.dx, 0), Offset(p.dx, size.height), Paint()..color = navy.withOpacity(0.25));
    canvas.drawCircle(p, 5, Paint()..color = Colors.white);
    canvas.drawCircle(p, 4, Paint()..color = navy);
  }

  @override
  bool shouldRepaint(covariant _TrenPainter o) => o.sel != sel || o.d != d || o.hi != hi || o.lo != lo;
}
