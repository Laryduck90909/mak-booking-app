import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'util.dart';

class Slice {
  final String label;
  final double value;
  final Color color;
  const Slice(this.label, this.value, this.color);
}

// ---------------- خط ----------------
class LineChartBox extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color? color;
  final double height;
  const LineChartBox({super.key, required this.values, required this.labels, this.color, this.height = 180});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return SizedBox(
      height: height, width: double.infinity,
      child: CustomPaint(painter: _LinePainter(values, labels, color ?? p.accent, p.border, p.muted)),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<double> v;
  final List<String> l;
  final Color c, grid, text;
  _LinePainter(this.v, this.l, this.c, this.grid, this.text);

  @override
  void paint(Canvas canvas, Size size) {
    const padB = 22.0;
    const padT = 8.0;
    final h = size.height - padB - padT;
    final gp = Paint()..color = grid.fade(0.6)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = padT + h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    if (v.isEmpty) return;
    final maxV = math.max(v.reduce(math.max), 1.0);
    final step = v.length == 1 ? 0.0 : size.width / (v.length - 1);
    final pts = <Offset>[];
    for (var i = 0; i < v.length; i++) {
      final x = v.length == 1 ? size.width / 2 : step * i;
      final y = padT + h - (v[i] / maxV) * h;
      pts.add(Offset(x, y));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mx = (a.dx + b.dx) / 2;
      path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
    }
    final fill = Path.from(path)
      ..lineTo(pts.last.dx, padT + h)
      ..lineTo(pts.first.dx, padT + h)
      ..close();
    canvas.drawPath(fill, Paint()..color = c.fade(0.12));
    canvas.drawPath(path, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2.2);
    for (final o in pts) {
      canvas.drawCircle(o, 3.2, Paint()..color = c);
    }
    for (var i = 0; i < l.length && i < pts.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: l[i], style: TextStyle(color: text, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      var x = pts[i].dx - tp.width / 2;
      if (x < 0) x = 0;
      if (x + tp.width > size.width) x = size.width - tp.width;
      tp.paint(canvas, Offset(x, size.height - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.v != v || old.c != c;
}

// ---------------- أعمدة ----------------
class BarChartBox extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color? color;
  final double height;
  const BarChartBox({super.key, required this.values, required this.labels, this.color, this.height = 180});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return SizedBox(
      height: height, width: double.infinity,
      child: CustomPaint(painter: _BarPainter(values, labels, color ?? p.accent, p.border, p.muted)),
    );
  }
}

class _BarPainter extends CustomPainter {
  final List<double> v;
  final List<String> l;
  final Color c, grid, text;
  _BarPainter(this.v, this.l, this.c, this.grid, this.text);

  @override
  void paint(Canvas canvas, Size size) {
    const padB = 22.0;
    const padT = 14.0;
    final h = size.height - padB - padT;
    final gp = Paint()..color = grid.fade(0.6)..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = padT + h * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    if (v.isEmpty) return;
    final maxV = math.max(v.reduce(math.max), 1.0);
    final slot = size.width / v.length;
    final bw = math.min(34.0, slot * 0.55);
    for (var i = 0; i < v.length; i++) {
      final bh = (v[i] / maxV) * h;
      final x = slot * i + (slot - bw) / 2;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, padT + h - bh, bw, bh),
        topLeft: const Radius.circular(5), topRight: const Radius.circular(5),
      );
      canvas.drawRRect(r, Paint()..color = c);
      if (i < l.length) {
        final tp = TextPainter(
          text: TextSpan(text: l[i], style: TextStyle(color: text, fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slot);
        tp.paint(canvas, Offset(slot * i + (slot - tp.width) / 2, size.height - 14));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.v != v || old.c != c;
}

// ---------------- دائري ----------------
class DonutBox extends StatelessWidget {
  final List<Slice> slices;
  final String centerText;
  final double size;
  const DonutBox({super.key, required this.slices, this.centerText = '', this.size = 140});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: size, height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(size: Size(size, size), painter: _DonutPainter(slices, p.elevated)),
          Text(centerText, style: ts(p, size: 18, w: FontWeight.w800, color: p.fg)),
        ]),
      ),
      const SizedBox(width: 16),
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final s in slices)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 8),
                Flexible(child: Text('${s.label} · ${s.value.round()}', style: ts(p, size: 12, color: p.text), overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  final List<Slice> s;
  final Color bg;
  _DonutPainter(this.s, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 16..color = bg;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final total = s.fold<double>(0, (a, b) => a + b.value);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final x in s) {
      final sweep = (x.value / total) * math.pi * 2;
      if (sweep <= 0) continue;
      canvas.drawArc(rect, start, math.max(sweep - 0.04, 0.01), false, Paint()..style = PaintingStyle.stroke..strokeWidth = 16..color = x.color..strokeCap = StrokeCap.butt);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.s != s;
}
