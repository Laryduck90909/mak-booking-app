import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class _StrokePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;
  _StrokePainter(this.strokes, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length == 1) {
        canvas.drawCircle(s.first, 1.3, Paint()..color = color);
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length; i++) {
        path.lineTo(s[i].dx, s[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}

/// نافذة توقيع بالإصبع/الفأرة. تعيد PNG مُرمَّزاً base64 أو null عند الإلغاء.
Future<String?> showSignatureDialog(BuildContext context, {required String title}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _SignatureDialog(title: title),
  );
}

class _SignatureDialog extends StatefulWidget {
  final String title;
  const _SignatureDialog({required this.title});
  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final List<List<Offset>> _strokes = [];
  Size _size = const Size(320, 160);

  Future<String> _export() async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec, Rect.fromLTWH(0, 0, _size.width, _size.height));
    _StrokePainter(_strokes, const Color(0xFF111111)).paint(canvas, _size);
    final pic = rec.endRecording();
    final img = await pic.toImage(_size.width.round() * 2, _size.height.round() * 2);
    // نرسم بمقياس 2x
    final rec2 = ui.PictureRecorder();
    final c2 = Canvas(rec2);
    c2.scale(2, 2);
    _StrokePainter(_strokes, const Color(0xFF111111)).paint(c2, _size);
    final img2 = await rec2.endRecording().toImage(_size.width.round() * 2, _size.height.round() * 2);
    img.dispose();
    final data = await img2.toByteData(format: ui.ImageByteFormat.png);
    return base64Encode(data!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.title, style: ts(p, size: 16, w: FontWeight.w800, color: p.fg)),
            const SizedBox(height: 4),
            Text(t('وقّع داخل المربع بإصبعك أو بالفأرة', 'Sign inside the box with your finger or mouse'), style: ts(p, size: 12, color: p.muted)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              final h = w * 0.5;
              _size = Size(w, h);
              return Container(
                width: w, height: h,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
                    onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
                    child: CustomPaint(painter: _StrokePainter(_strokes, const Color(0xFF111111)), size: Size(w, h)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: MakButton(t('مسح', 'Clear'), kind: 'ghost', onPressed: () => setState(() => _strokes.clear()))),
              const SizedBox(width: 8),
              Expanded(child: MakButton(t('إلغاء', 'Cancel'), kind: 'ghost', onPressed: () => Navigator.pop(context))),
              const SizedBox(width: 8),
              Expanded(
                child: MakButton(t('اعتماد', 'Confirm'), onPressed: () async {
                  if (_strokes.isEmpty) {
                    toast(context, t('ارسم توقيعك أولاً', 'Draw your signature first'), error: true);
                    return;
                  }
                  final b64 = await _export();
                  if (mounted) Navigator.pop(context, b64);
                }),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
