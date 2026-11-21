import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import 'i18n.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';

// ------------------------------------------------------------------
// بطاقة / لوحة
// ------------------------------------------------------------------
class Panel extends StatelessWidget {
  final String? title, kicker;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  final Color? accent;
  const Panel({super.key, this.title, this.kicker, this.trailing, required this.child, this.padding = const EdgeInsets.all(16), this.accent});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border),
        boxShadow: p.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null || kicker != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (kicker != null)
                    Text(kicker!, style: ts(p, size: 10, w: FontWeight.w700, color: accent ?? p.accent)),
                  if (title != null) Text(title!, style: ts(p, size: 15, w: FontWeight.w700, color: p.fg, display: true)),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        child,
      ]),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color.fade(0.14), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.fade(0.35))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

Color statusColor(Palette p, String s) {
  switch (s) {
    case 'new': return p.blue;
    case 'quoted': return p.amber;
    case 'accepted': return p.green;
    case 'rejected':
    case 'expired':
    case 'cancelled':
      return p.red;
    case 'contract_pending': return p.violet;
    case 'in_progress': return p.teal;
    case 'preview_sent': return p.gold;
    case 'paid': return p.green;
    case 'delivered': return p.teal;
    case 'completed': return p.green;
    default: return p.muted;
  }
}

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) => Pill(statusLabel(status), color: statusColor(P(context), status));
}

class KpiCard extends StatefulWidget {
  final String label, value;
  final String? sub;
  final IconData icon;
  final Color? color;
  const KpiCard({super.key, required this.label, required this.value, this.sub, required this.icon, this.color});

  @override
  State<KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<KpiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final c = widget.color ?? p.accent;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hover ? c.fade(0.45) : p.border),
          boxShadow: p.cardShadow,
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd,
            colors: [Color.alphaBlend(c.fade(0.10), p.surface), p.surface],
          ),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.fade(0.28)),
              gradient: LinearGradient(colors: [c.fade(0.24), c.fade(0.08)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Icon(widget.icon, color: c, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.label, style: ts(p, size: 11, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(widget.value, style: ts(p, size: 21, w: FontWeight.w800, color: p.fg, display: true), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (widget.sub != null) Text(widget.sub!, style: ts(p, size: 10.5, color: p.subtle), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// خلفية التوهج الخافت (تركوازي + ذهبي) كما في لوحات التحكم الأصلية.
class GlowBackground extends StatelessWidget {
  final Widget child;
  const GlowBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Stack(fit: StackFit.expand, children: [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(-0.76, -1.15), radius: 1.0, colors: [p.glow1, Colors.transparent], stops: const [0, 1]),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(0.9, -1.1), radius: 0.9, colors: [p.glow2, Colors.transparent], stops: const [0, 1]),
            ),
          ),
        ),
      ),
      child,
    ]);
  }
}

/// بطاقة الترحيب الكبيرة (hero-surface): تدرج تركوازي ← سطح ← ذهبي.
class HeroCard extends StatelessWidget {
  final Widget child;
  const HeroCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
        boxShadow: p.cardShadow,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd,
          colors: [Color.alphaBlend(p.accent.fade(0.16), p.surface), p.surface, Color.alphaBlend(p.gold.fade(0.10), p.surface)],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: child,
    );
  }
}

/// نص بتدرج (تركوازي ← ذهبي) للعناوين الكبيرة.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(colors: [p.accent, p.gold]).createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

/// شبكة متجاوبة: تحسب عدد الأعمدة حسب العرض.
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  final double gap;
  const AdaptiveGrid({super.key, required this.children, this.minWidth = 240, this.gap = 12});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
      var cols = (w / minWidth).floor();
      if (cols < 1) cols = 1;
      if (cols > children.length && children.isNotEmpty) cols = children.length;
      final cw = (w - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap, runSpacing: gap,
        children: children.map((e) => SizedBox(width: cw, child: e)).toList(),
      );
    });
  }
}

// ------------------------------------------------------------------
// أزرار
// ------------------------------------------------------------------
class MakButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final FutureOr<void> Function()? onPressed;
  final String kind; // primary | ghost | danger | soft
  final bool dense;
  const MakButton(this.label, {super.key, this.icon, this.onPressed, this.kind = 'primary', this.dense = false});

  @override
  State<MakButton> createState() => _MakButtonState();
}

class _MakButtonState extends State<MakButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      final r = widget.onPressed!();
      if (r is Future) await r;
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    Color bg, fg, bd;
    switch (widget.kind) {
      case 'ghost':
        bg = Colors.transparent; fg = p.fg; bd = p.border; break;
      case 'danger':
        bg = p.red.fade(0.14); fg = p.red; bd = p.red.fade(0.4); break;
      case 'soft':
        bg = p.accent.fade(0.14); fg = p.accent; bd = p.accent.fade(0.3); break;
      default:
        bg = p.accent; fg = p.onAccent; bd = p.accent;
    }
    final disabled = widget.onPressed == null;
    final primary = widget.kind == 'primary';
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled ? null : _tap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: widget.dense ? 12 : 18, vertical: widget.dense ? 8 : 12),
          decoration: BoxDecoration(
            color: primary ? null : bg,
            gradient: primary ? LinearGradient(colors: [p.accent, Color.alphaBlend(p.teal.fade(0.55), p.accent)], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary ? Colors.transparent : bd),
            boxShadow: primary && !disabled ? [BoxShadow(color: p.accent.fade(0.45), blurRadius: 22, spreadRadius: -10, offset: const Offset(0, 8))] : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_busy)
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else if (widget.icon != null)
              Icon(widget.icon, size: 16, color: fg),
            if (_busy || widget.icon != null) const SizedBox(width: 6),
            Flexible(child: Text(widget.label, style: TextStyle(fontSize: widget.dense ? 12 : 13, fontWeight: FontWeight.w700, color: fg), overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

class IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final int badge;
  const IconBtn(this.icon, {super.key, this.onTap, this.tooltip, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final w = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
        child: Stack(alignment: Alignment.center, children: [
          Icon(icon, size: 18, color: p.muted),
          if (badge > 0)
            Positioned(
              top: 3, right: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(color: p.red, borderRadius: BorderRadius.circular(8)),
                child: Text(badge > 9 ? '9+' : '$badge', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

// ------------------------------------------------------------------
// حقول
// ------------------------------------------------------------------
class MakField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint, error;
  final int maxLines;
  final TextInputType? keyboard;
  final bool obscure, enabled;
  final ValueChanged<String>? onChanged;
  final Widget? suffix;
  final TextDirection? dir;
  const MakField({
    super.key, required this.controller, this.label = '', this.hint, this.error, this.maxLines = 1,
    this.keyboard, this.obscure = false, this.enabled = true, this.onChanged, this.suffix, this.dir,
  });

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    OutlineInputBorder b(Color c) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(label, style: ts(p, size: 12, w: FontWeight.w600, color: p.muted))),
      TextField(
        controller: controller, maxLines: obscure ? 1 : maxLines, obscureText: obscure, enabled: enabled,
        keyboardType: keyboard, onChanged: onChanged, textDirection: dir,
        style: ts(p, size: 13, color: p.fg),
        decoration: InputDecoration(
          hintText: hint, hintStyle: ts(p, size: 12.5, color: p.subtle), errorText: error, isDense: true,
          filled: true, fillColor: p.input, suffixIcon: suffix,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: b(p.border), enabledBorder: b(p.border), focusedBorder: b(p.accent), errorBorder: b(p.red),
          focusedErrorBorder: b(p.red), disabledBorder: b(p.borderSoft),
        ),
      ),
    ]);
  }
}

class DropdownBox<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const DropdownBox({super.key, this.label = '', required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (label.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 5), child: Text(label, style: ts(p, size: 12, w: FontWeight.w600, color: p.muted))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value, isExpanded: true, items: items, onChanged: onChanged,
            dropdownColor: p.elevated, style: ts(p, size: 13, color: p.fg), iconEnabledColor: p.muted,
          ),
        ),
      ),
    ]);
  }
}

class SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const SelectChip(this.label, {super.key, required this.selected, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? p.accent.fade(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? p.accent : p.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: selected ? p.accent : p.muted), const SizedBox(width: 5)],
          Flexible(child: Text(label, style: ts(p, size: 12, w: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? p.accent : p.text))),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------
// أخرى
// ------------------------------------------------------------------
class EmptyState extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 38, color: p.subtle),
          const SizedBox(height: 10),
          Text(text, style: ts(p, size: 13, color: p.muted), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class KV extends StatelessWidget {
  final String k, v;
  final Widget? vw;
  const KV(this.k, this.v, {super.key, this.vw});
  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(k, style: ts(p, size: 12, color: p.muted))),
        Expanded(child: vw ?? Text(v, style: ts(p, size: 13, color: p.fg, w: FontWeight.w600))),
      ]),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 32});
  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final ch = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(color: p.accent.fade(0.16), shape: BoxShape.circle, border: Border.all(color: p.accent.fade(0.4))),
      child: Text(ch, style: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: size * 0.42)),
    );
  }
}

class MakLogo extends StatelessWidget {
  final double size;
  final String asset;
  const MakLogo({super.key, this.size = 36, this.asset = 'assets/logos/mak_icon.png'});
  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Image.asset(asset, width: size, height: size, fit: BoxFit.cover, errorBuilder: (c, e, s) {
        return Container(
          width: size, height: size, alignment: Alignment.center,
          decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
          child: Text('M.A.K', style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w900, fontSize: size * 0.26)),
        );
      }),
    );
  }
}

class ProgressLine extends StatelessWidget {
  final double value;
  final Color? color;
  const ProgressLine(this.value, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(value: value.clamp(0.0, 1.0), minHeight: 6, backgroundColor: p.elevated, color: color ?? p.accent),
    );
  }
}

/// تقدّم الطلب عبر المراحل (للعرض).
double orderProgress(String status) {
  switch (status) {
    case 'new': return 0.08;
    case 'quoted': return 0.2;
    case 'accepted': return 0.3;
    case 'contract_pending': return 0.4;
    case 'in_progress': return 0.6;
    case 'preview_sent': return 0.75;
    case 'paid': return 0.88;
    case 'delivered': return 0.95;
    case 'completed': return 1;
    default: return 0;
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  final p = P(context);
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    backgroundColor: error ? p.red.withAlpha(235) : const Color(0xFF1F6F5F),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 3),
  ));
}

Future<bool> confirmDialog(BuildContext context, String message, {String? okLabel, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final p = P(ctx);
      return AlertDialog(
        backgroundColor: p.surface,
        content: Text(message, style: ts(p, size: 14, color: p.fg)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('إلغاء', 'Cancel'), style: TextStyle(color: p.muted))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okLabel ?? t('تأكيد', 'Confirm'), style: TextStyle(color: danger ? p.red : p.accent, fontWeight: FontWeight.w800)),
          ),
        ],
      );
    },
  );
  return r == true;
}

/// نافذة بعنوان ومحتوى قابل للتمرير.
Future<T?> showPanelDialog<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder, double width = 520}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final p = P(ctx);
      return Dialog(
        backgroundColor: p.surface,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border)),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.of(ctx).size.height * 0.88),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: ts(p, size: 16, w: FontWeight.w800, color: p.fg))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: p.muted, size: 20)),
              ]),
              const SizedBox(height: 8),
              builder(ctx),
            ]),
          ),
        ),
      );
    },
  );
}

// ------------------------------------------------------------------
// تحميل بيانات + تحديث تلقائي عند أي تغيير
// ------------------------------------------------------------------
class AsyncData<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  const AsyncData({super.key, required this.load, required this.builder});

  @override
  State<AsyncData<T>> createState() => _AsyncDataState<T>();
}

class _AsyncDataState<T> extends State<AsyncData<T>> {
  T? _data;
  bool _has = false;
  Object? _err;
  int _seq = 0;
  StreamSubscription<void>? _sub;
  Timer? _deb;

  @override
  void initState() {
    super.initState();
    _run();
    _sub = repo.changes.listen((_) {
      _deb?.cancel();
      _deb = Timer(const Duration(milliseconds: 250), _run);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _deb?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final my = ++_seq;
    try {
      final d = await widget.load();
      if (!mounted || my != _seq) return;
      setState(() {
        _data = d;
        _has = true;
        _err = null;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() => _err = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    if (!_has) {
      if (_err != null) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: p.red, size: 32),
            const SizedBox(height: 8),
            Text(errMsg(_err!), style: ts(p, color: p.muted), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            MakButton(t('إعادة المحاولة', 'Retry'), kind: 'ghost', dense: true, onPressed: () {
              setState(() => _err = null);
              _run();
            }),
          ]),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5)),
      );
    }
    return widget.builder(context, _data as T);
  }
}

/// عنوان صفحة
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const PageHeader(this.title, {super.key, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: ts(p, size: 24, w: FontWeight.w800, color: p.fg, display: true)),
            if (subtitle != null) Text(subtitle!, style: ts(p, size: 12.5, color: p.muted)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// صف طلب في القوائم
class OrderTile extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  final bool showClient;
  const OrderTile({super.key, required this.order, required this.onTap, this.showClient = true});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final sc = order.section == 'design' ? p.gold : (order.section == 'web' ? p.blue : p.violet);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
        child: Row(children: [
          Container(
            width: 4, height: 44,
            decoration: BoxDecoration(color: sc, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order.title.isEmpty ? order.id : order.title, style: ts(p, size: 13.5, w: FontWeight.w700, color: p.fg), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(
                '${order.id} · ${sectionName(order.section)}${showClient && order.clientName.isNotEmpty ? ' · ${order.clientName}' : ''} · ${fmtDate(order.createdAt)}',
                style: ts(p, size: 11, color: p.muted), maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              ProgressLine(orderProgress(order.status), color: statusColor(p, order.status)),
            ]),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            StatusPill(order.status),
            const SizedBox(height: 6),
            Text(order.totalMad > 0 ? fmtMad(order.totalMad) : (order.estimate > 0 ? '~${fmtMad(order.estimate)}' : '—'), style: ts(p, size: 11.5, w: FontWeight.w700, color: p.fg)),
          ]),
        ]),
      ),
    );
  }
}
