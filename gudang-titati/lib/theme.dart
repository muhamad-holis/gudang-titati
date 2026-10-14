import 'package:flutter/material.dart';
import 'utils.dart';

const navy = Color(0xFF0B2A4A);
const navy2 = Color(0xFF123A66);
const blue = Color(0xFF1565F0);
const bgColor = Color(0xFFF1F5FB);
const green = Color(0xFF16A34A);
const orange = Color(0xFFB45309);
const red = Color(0xFFC62828);
const lineColor = Color(0xFFDCE6F5);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, primary: blue),
      scaffoldBackgroundColor: bgColor,
    );

BoxDecoration cardDeco({Color color = Colors.white}) =>
    BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all(color: lineColor));

Color statusBg(String s) {
  switch (s) {
    case 'diajukan':
      return const Color(0xFFFFF4E0);
    case 'disetujui':
      return const Color(0xFFE6EEFB);
    case 'dikirim':
      return const Color(0xFFEDE7FB);
    case 'diterima':
      return const Color(0xFFDCF5E3);
    default:
      return const Color(0xFFEDEDED);
  }
}

Color statusFg(String s) {
  switch (s) {
    case 'diajukan':
      return const Color(0xFFB45309);
    case 'disetujui':
      return const Color(0xFF1565F0);
    case 'dikirim':
      return const Color(0xFF5B3FC4);
    case 'diterima':
      return const Color(0xFF14753A);
    case 'ditolak':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFF555555);
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: statusBg(status), borderRadius: BorderRadius.circular(20)),
      child: Text(statusLabel(status), style: TextStyle(color: statusFg(status), fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
