import 'package:flutter/material.dart';

const colorFormats = ['hex', 'rgb', 'cmyk'];

String colorFormatLabel(String f) => f.toUpperCase();

String colorHint(String f) {
  switch (f) {
    case 'rgb': return '11, 59, 58';
    case 'cmyk': return '81, 19, 20, 77';
    default: return '#0B3B3A';
  }
}

List<double>? _nums(String v, int count, double max) {
  final cleaned = v.toLowerCase().replaceAll(RegExp(r'[a-z()%]'), ' ').replaceAll(',', ' ').trim();
  if (cleaned.isEmpty) return null;
  final parts = cleaned.split(RegExp(r'\s+'));
  if (parts.length != count) return null;
  final out = <double>[];
  for (final p in parts) {
    final n = double.tryParse(p);
    if (n == null || n < 0 || n > max) return null;
    out.add(n);
  }
  return out;
}

/// يحوّل قيمة لون بصيغتها إلى Color، أو null إن كانت غير صالحة.
Color? parseColor(String format, String value) {
  final v = value.trim();
  if (v.isEmpty) return null;
  switch (format) {
    case 'hex':
      var h = v.startsWith('#') ? v.substring(1) : v;
      if (!RegExp(r'^[0-9a-fA-F]{3}$|^[0-9a-fA-F]{6}$').hasMatch(h)) return null;
      if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
      return Color(int.parse('FF$h', radix: 16));
    case 'rgb':
      final n = _nums(v, 3, 255);
      if (n == null) return null;
      return Color.fromARGB(255, n[0].round(), n[1].round(), n[2].round());
    case 'cmyk':
      final n = _nums(v, 4, 100);
      if (n == null) return null;
      final c = n[0] / 100, m = n[1] / 100, y = n[2] / 100, k = n[3] / 100;
      return Color.fromARGB(255, (255 * (1 - c) * (1 - k)).round(), (255 * (1 - m) * (1 - k)).round(), (255 * (1 - y) * (1 - k)).round());
    default:
      return null;
  }
}

bool validColor(String format, String value) => parseColor(format, value) != null;

String colorError(String format) {
  switch (format) {
    case 'rgb': return 'RGB: 3 / 0–255  (11, 59, 58)';
    case 'cmyk': return 'CMYK: 4 / 0–100  (81, 19, 20, 77)';
    default: return 'HEX: #RGB / #RRGGBB';
  }
}
