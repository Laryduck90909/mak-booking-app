import 'package:flutter/material.dart';
import '../../core/colors.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../data/catalog.dart';
import '../../models/models.dart';
import '../orders/order_detail.dart' show mockupImage;
import '../orders/order_files.dart';
import 'wizard_data.dart';

typedef Refresh = void Function();

// ------------------------------------------------------------------
// خطوة الخدمات (من الكتالوج، حتى 5)
// ------------------------------------------------------------------
class ServicesStep extends StatefulWidget {
  final WizardData data;
  final List<CatalogItem> catalog;
  final Map<String, int> tierPrice;
  final Refresh onChanged;
  const ServicesStep({super.key, required this.data, required this.catalog, required this.tierPrice, required this.onChanged});
  @override
  State<ServicesStep> createState() => _ServicesStepState();
}

class _ServicesStepState extends State<ServicesStep> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    final l = widget.data.items;
    if (l.contains(key)) {
      l.remove(key);
    } else {
      if (l.length >= AppConfig.maxServices) {
        toast(context, t('الحد الأقصى ${AppConfig.maxServices} خدمات في الطلب الواحد', 'Maximum ${AppConfig.maxServices} services per request'), error: true);
        return;
      }
      l.add(key);
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final q = _q.text.trim().toLowerCase();
    final list = widget.catalog.where((i) => q.isEmpty || i.nameAr.toLowerCase().contains(q) || i.nameEn.toLowerCase().contains(q)).toList();
    final groups = <String, List<CatalogItem>>{};
    for (final i in list) {
      groups.putIfAbsent(i.group, () => []).add(i);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${t('المختار', 'Selected')}: ${widget.data.items.length}/${AppConfig.maxServices}', style: ts(p, size: 12.5, w: FontWeight.w700, color: p.accent)),
      const SizedBox(height: 10),
      MakField(controller: _q, hint: t('بحث…', 'Search…'), onChanged: (_) => setState(() {}), suffix: Icon(Icons.search, color: p.muted, size: 18)),
      const SizedBox(height: 12),
      for (final g in groups.entries) ...[
        Padding(padding: const EdgeInsets.only(top: 8, bottom: 8), child: Text(Catalog.groupLabel(g.key), style: ts(p, size: 13, w: FontWeight.w800, color: p.fg))),
        Wrap(spacing: 8, runSpacing: 8, children: g.value.map((it) {
          final sel = widget.data.items.contains(it.key);
          final price = it.tier == null ? null : widget.tierPrice[it.tier];
          return _ServiceTile(item: it, selected: sel, price: price, onTap: () => _toggle(it.key));
        }).toList()),
      ],
      if (groups.isEmpty) EmptyState(t('لا نتائج', 'No results')),
    ]);
  }
}

class _ServiceTile extends StatelessWidget {
  final CatalogItem item;
  final bool selected;
  final int? price;
  final VoidCallback onTap;
  const _ServiceTile({required this.item, required this.selected, required this.price, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? p.accent.fade(0.14) : p.surfaceHi,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? p.accent : p.borderSoft, width: selected ? 1.5 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? p.accent : p.subtle, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: ts(p, size: 12.5, w: FontWeight.w700, color: p.fg), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(price == null ? t('سعر يُحدَّد لاحقاً', 'Price set later') : fmtMad(price!), style: ts(p, size: 11, color: price == null ? p.amber : p.muted)),
          ])),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------
// خطوة نماذج العرض Mockups (شبكة صور، حتى 5)
// ------------------------------------------------------------------
class MockupStep extends StatefulWidget {
  final WizardData data;
  final Refresh onChanged;
  const MockupStep({super.key, required this.data, required this.onChanged});
  @override
  State<MockupStep> createState() => _MockupStepState();
}

class _MockupStepState extends State<MockupStep> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _toggle(String key) {
    final l = widget.data.mockups;
    if (l.contains(key)) {
      l.remove(key);
    } else {
      if (l.length >= AppConfig.maxMockups) {
        toast(context, t('الحد الأقصى ${AppConfig.maxMockups} نماذج', 'Maximum ${AppConfig.maxMockups} mockups'), error: true);
        return;
      }
      l.add(key);
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final q = _q.text.trim().toLowerCase();
    final list = Catalog.mockups.where((m) => q.isEmpty || m.nameAr.toLowerCase().contains(q) || m.nameEn.toLowerCase().contains(q)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${t('المختار', 'Selected')}: ${widget.data.mockups.length}/${AppConfig.maxMockups}', style: ts(p, size: 12.5, w: FontWeight.w700, color: p.accent)),
      const SizedBox(height: 4),
      Text(t('اختر النماذج التي تريد أن نعرض عليها تصميمك (اختياري).', 'Pick the mockups you want your design shown on (optional).'), style: ts(p, size: 12, color: p.muted)),
      const SizedBox(height: 10),
      MakField(controller: _q, hint: t('بحث…', 'Search…'), onChanged: (_) => setState(() {}), suffix: Icon(Icons.search, color: p.muted, size: 18)),
      const SizedBox(height: 12),
      AdaptiveGrid(
        minWidth: 130, gap: 10,
        children: list.map((m) {
          final sel = widget.data.mockups.contains(m.key);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _toggle(m.key),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: sel ? p.accent.fade(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? p.accent : p.borderSoft, width: sel ? 2 : 1),
              ),
              child: Column(children: [
                AspectRatio(
                  aspectRatio: 1.2,
                  child: Stack(fit: StackFit.expand, children: [
                    mockupImage(p, m.key),
                    if (sel)
                      Positioned(top: 4, right: 4, child: Container(
                        decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.check, size: 14, color: p.onAccent),
                      )),
                  ]),
                ),
                const SizedBox(height: 4),
                Text(m.name, style: ts(p, size: 11, w: FontWeight.w600, color: p.fg), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        }).toList(),
      ),
    ]);
  }
}

// ------------------------------------------------------------------
// خطوة الأسلوب (واحد)
// ------------------------------------------------------------------
class StyleStep extends StatefulWidget {
  final WizardData data;
  final Refresh onChanged;
  const StyleStep({super.key, required this.data, required this.onChanged});
  @override
  State<StyleStep> createState() => _StyleStepState();
}

class _StyleStepState extends State<StyleStep> {
  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: Catalog.styles.map((s) {
      return SelectChip(s.name, selected: widget.data.style == s.key, onTap: () {
        setState(() => widget.data.style = s.key);
        widget.onChanged();
      });
    }).toList());
  }
}

// ------------------------------------------------------------------
// خطوة الألوان (يكتبها العميل: HEX أو RGB أو CMYK) — من 3 إلى 5
// ------------------------------------------------------------------
class ColorsStep extends StatefulWidget {
  final WizardData data;
  final int min;
  final Refresh onChanged;
  const ColorsStep({super.key, required this.data, this.min = AppConfig.minColors, required this.onChanged});
  @override
  State<ColorsStep> createState() => _ColorsStepState();
}

class _ColorsStepState extends State<ColorsStep> {
  @override
  void initState() {
    super.initState();
    while (widget.data.colors.length < widget.min) {
      widget.data.colors.add(ColorEntry('hex', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final cs = widget.data.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        t('أدخل ألوان علامتك بنفسك (من ${widget.min} إلى ${AppConfig.maxColors}). اختر صيغة اللون ثم اكتب القيمة. لون الطباعة المفضّل: CMYK.',
            'Enter your brand colors yourself (${widget.min}–${AppConfig.maxColors}). Choose the format then type the value. Preferred print mode: CMYK.'),
        style: ts(p, size: 12, color: p.muted, height: 1.6),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < cs.length; i++) _row(p, i, cs[i]),
      const SizedBox(height: 4),
      if (cs.length < AppConfig.maxColors)
        MakButton(t('إضافة لون', 'Add color'), icon: Icons.add, kind: 'soft', dense: true, onPressed: () {
          setState(() => cs.add(ColorEntry('hex', '')));
          widget.onChanged();
        }),
    ]);
  }

  Widget _row(Palette p, int i, ColorEntry c) {
    final col = parseColor(c.format, c.value);
    final bad = c.value.isNotEmpty && col == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: bad ? p.red : p.borderSoft)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: col ?? p.elevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: col == null ? Icon(Icons.palette_outlined, size: 18, color: p.subtle) : null,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: DropdownBox<String>(
            value: c.format,
            items: colorFormats.map((f) => DropdownMenuItem(value: f, child: Text(colorFormatLabel(f)))).toList(),
            onChanged: (v) {
              setState(() => c.format = v ?? 'hex');
              widget.onChanged();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MakField(
            controller: c.ctl, hint: colorHint(c.format), error: bad ? colorError(c.format) : null,
            onChanged: (_) {
              setState(() {});
              widget.onChanged();
            },
          ),
        ),
        if (widget.data.colors.length > widget.min)
          IconButton(
            onPressed: () {
              setState(() {
                final r = widget.data.colors.removeAt(i);
                r.ctl.dispose();
              });
              widget.onChanged();
            },
            icon: Icon(Icons.close, color: p.red, size: 20),
          ),
      ]),
    );
  }
}

/// تحقق الألوان: يعيد رسالة خطأ أو null.
String? validateColors(WizardData d, {int min = AppConfig.minColors}) {
  final filled = d.colors.where((c) => c.value.isNotEmpty).toList();
  if (filled.length < min) return t('أدخل $min ألوان على الأقل', 'Enter at least $min colors');
  if (filled.any((c) => !c.valid)) return t('هناك لون بصيغة غير صحيحة', 'A color has an invalid format');
  return null;
}

// ------------------------------------------------------------------
// خطوة أسئلة البريف (شريحة من الأسئلة)
// ------------------------------------------------------------------
class BriefStep extends StatefulWidget {
  final WizardData data;
  final List<BriefQuestion> questions;
  final Refresh onChanged;
  const BriefStep({super.key, required this.data, required this.questions, required this.onChanged});
  @override
  State<BriefStep> createState() => _BriefStepState();
}

class _BriefStepState extends State<BriefStep> {
  final Map<String, TextEditingController> _ctl = {};

  TextEditingController _c(String key) {
    return _ctl.putIfAbsent(key, () => TextEditingController(text: '${widget.data.answers[key] ?? ''}'));
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, dynamic v) {
    if (v == null || '$v'.isEmpty || (v is List && v.isEmpty)) {
      widget.data.answers.remove(key);
    } else {
      widget.data.answers[key] = v;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.questions.map((q) {
      final cur = widget.data.answers[q.key];
      Widget input;
      switch (q.type) {
        case 'choice':
          input = Wrap(spacing: 8, runSpacing: 8, children: q.options.map((o) {
            return SelectChip(Catalog.optionLabel(o), selected: cur == o, onTap: () {
              setState(() => _set(q.key, cur == o ? null : o));
            });
          }).toList());
          break;
        case 'multi':
          final sel = (cur is List) ? cur.map((e) => '$e').toList() : <String>[];
          input = Wrap(spacing: 8, runSpacing: 8, children: q.options.map((o) {
            final on = sel.contains(o);
            return SelectChip(Catalog.optionLabel(o), selected: on, onTap: () {
              final n = List<String>.from(sel);
              if (on) {
                n.remove(o);
              } else {
                n.add(o);
              }
              setState(() => _set(q.key, n));
            });
          }).toList());
          break;
        case 'date':
          input = InkWell(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 7)), firstDate: now, lastDate: now.add(const Duration(days: 730)));
              if (d != null) setState(() => _set(q.key, fmtDate(d)));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
              child: Row(children: [
                Icon(Icons.event, size: 18, color: p.muted),
                const SizedBox(width: 8),
                Text(cur == null ? t('اختر التاريخ', 'Pick a date') : '$cur', style: ts(p, size: 13, color: cur == null ? p.subtle : p.fg)),
              ]),
            ),
          );
          break;
        default:
          input = MakField(controller: _c(q.key), maxLines: q.type == 'longtext' ? 4 : 1, onChanged: (v) => _set(q.key, v.trim()));
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q.label, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
          const SizedBox(height: 7),
          input,
        ]),
      );
    }).toList());
  }
}

// ------------------------------------------------------------------
// خطوة حقول عامة (للويب والكتابة)
// ------------------------------------------------------------------
class FieldsStep extends StatefulWidget {
  final WizardData data;
  final List<FieldDef> fields;
  final Refresh onChanged;
  const FieldsStep({super.key, required this.data, required this.fields, required this.onChanged});
  @override
  State<FieldsStep> createState() => _FieldsStepState();
}

class _FieldsStepState extends State<FieldsStep> {
  final Map<String, TextEditingController> _ctl = {};

  TextEditingController _c(String key) => _ctl.putIfAbsent(key, () => TextEditingController(text: '${widget.data.extra[key] ?? ''}'));

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _set(String key, dynamic v) {
    if (v == null || '$v'.isEmpty || (v is List && v.isEmpty)) {
      widget.data.extra.remove(key);
    } else {
      widget.data.extra[key] = v;
    }
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.fields.map((f) {
      final cur = widget.data.extra[f.key];
      final label = t(f.ar, f.en) + (f.req ? ' *' : '');
      Widget input;
      if (f.type == 'choice') {
        input = Wrap(spacing: 8, runSpacing: 8, children: f.options.map((o) {
          return SelectChip(t(o.$1, o.$2), selected: cur == o.$1, onTap: () => setState(() => _set(f.key, cur == o.$1 ? null : o.$1)));
        }).toList());
      } else if (f.type == 'multi') {
        final sel = (cur is List) ? cur.map((e) => '$e').toList() : <String>[];
        input = Wrap(spacing: 8, runSpacing: 8, children: f.options.map((o) {
          final on = sel.contains(o.$1);
          return SelectChip(t(o.$1, o.$2), selected: on, onTap: () {
            final n = List<String>.from(sel);
            if (on) {
              n.remove(o.$1);
            } else {
              n.add(o.$1);
            }
            setState(() => _set(f.key, n));
          });
        }).toList());
      } else if (f.type == 'date') {
        input = InkWell(
          onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 14)), firstDate: now, lastDate: now.add(const Duration(days: 730)));
            if (d != null) setState(() => _set(f.key, fmtDate(d)));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            child: Row(children: [
              Icon(Icons.event, size: 18, color: p.muted),
              const SizedBox(width: 8),
              Text(cur == null ? t('اختر التاريخ', 'Pick a date') : '$cur', style: ts(p, size: 13, color: cur == null ? p.subtle : p.fg)),
            ]),
          ),
        );
      } else {
        input = MakField(
          controller: _c(f.key), maxLines: f.type == 'long' ? 4 : 1,
          keyboard: f.type == 'number' ? TextInputType.number : null,
          onChanged: (v) => _set(f.key, v.trim()),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: ts(p, size: 13, w: FontWeight.w700, color: p.fg)),
          const SizedBox(height: 7),
          input,
        ]),
      );
    }).toList());
  }
}

String? validateFields(WizardData d, List<FieldDef> fields) {
  for (final f in fields) {
    if (!f.req) continue;
    final v = d.extra[f.key];
    if (v == null || '$v'.isEmpty || (v is List && v.isEmpty)) return t('املأ: ${f.ar}', 'Fill in: ${f.en}');
  }
  return null;
}

// ------------------------------------------------------------------
// خطوة الملفات (تُرفع بعد إنشاء الطلب)
// ------------------------------------------------------------------
class FilesStep extends StatefulWidget {
  final WizardData data;
  const FilesStep({super.key, required this.data});
  @override
  State<FilesStep> createState() => _FilesStepState();
}

class _FilesStepState extends State<FilesStep> {
  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final files = widget.data.files;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('أرفق شعارك الحالي أو صور مرجعية أو أي مواد (حتى ${AppConfig.maxUploadMb}MB للملف).', 'Attach your current logo, references or any material (up to ${AppConfig.maxUploadMb}MB per file).'), style: ts(p, size: 12, color: p.muted, height: 1.6)),
      const SizedBox(height: 10),
      MakButton(t('اختيار ملفات', 'Choose files'), icon: Icons.upload_file, kind: 'soft', onPressed: () async {
        final f = await pickFiles(context);
        if (f.isNotEmpty) setState(() => files.addAll(f));
      }),
      const SizedBox(height: 10),
      for (var i = 0; i < files.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.borderSoft)),
          child: Row(children: [
            Icon(isImageName(files[i].name) ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 18, color: p.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('${files[i].name}  (${(files[i].bytes.length / 1024).round()} KB)', style: ts(p, size: 12, color: p.fg), overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: () => setState(() => files.removeAt(i)), icon: Icon(Icons.close, size: 18, color: p.red)),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------------
// المراجعة النهائية
// ------------------------------------------------------------------
class ReviewStep extends StatelessWidget {
  final WizardData data;
  final Map<String, dynamic> priced; // ناتج priceItems
  final CompanySettings settings;
  final Refresh onChanged;
  const ReviewStep({super.key, required this.data, required this.priced, required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final items = (priced['items'] as List).cast<Map<String, dynamic>>();
    final est = priced['estimate_total'] as int;
    final manual = priced['needs_manual_pricing'] == true;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(k, style: ts(p, size: 12, color: p.muted))),
            Expanded(child: Text(v, style: ts(p, size: 13, w: FontWeight.w600, color: p.fg))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        title: t('ملخص طلبك', 'Your request'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final it in items)
            row(isAr ? '${it['ar']}' : '${it['en']}', it['price'] == null ? t('يُسعَّر لاحقاً', 'Quoted later') : fmtMad(it['price'] as num)),
          if (data.mockups.isNotEmpty) row(t('Mockups', 'Mockups'), '${data.mockups.length}'),
          if (data.style.isNotEmpty) row(t('الأسلوب', 'Style'), Catalog.style(data.style)?.name ?? data.style),
          if (data.colors.where((c) => c.value.isNotEmpty).isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(spacing: 6, runSpacing: 6, children: data.colors.where((c) => c.value.isNotEmpty).map((c) {
                final col = parseColor(c.format, c.value);
                return Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(color: col ?? p.elevated, shape: BoxShape.circle, border: Border.all(color: p.border)),
                );
              }).toList()),
            ),
          if (data.answers.isNotEmpty) row(t('الإجابات', 'Answers'), '${data.answers.length}'),
          if (data.files.isNotEmpty) row(t('الملفات', 'Files'), '${data.files.length}'),
          Divider(color: p.border),
          Row(children: [
            Expanded(child: Text(t('التقدير الأولي', 'Initial estimate'), style: ts(p, size: 13, color: p.muted))),
            Text(est > 0 ? fmtMad(est) : '—', style: ts(p, size: 18, w: FontWeight.w900, color: p.fg)),
          ]),
          if (manual)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(t('يحتوي طلبك على بنود تُسعَّر يدوياً؛ سيرسل لك الفريق عرضاً نهائياً.', 'Your request has manually-priced items; the team will send a final quote.'), style: ts(p, size: 11.5, color: p.amber, height: 1.5))),
        ]),
      ),
      const SizedBox(height: 12),
      MakField(controller: TextEditingController(text: data.note), label: t('ملاحظة أخيرة للفريق (اختياري)', 'Final note for the team (optional)'), maxLines: 3, onChanged: (v) {
        data.note = v.trim();
        onChanged();
      }),
      const SizedBox(height: 12),
      Text(
        t('بإرسال الطلب لن يُخصم منك شيء: سيصلك عرض سعر للموافقة عليه، ثم عقد للتوقيع، وبعدها عربون ${settings.depositPct}%.',
            'Sending is free: you will receive a quote to approve, then a contract to sign, then a ${settings.depositPct}% deposit.'),
        style: ts(p, size: 12, color: p.muted, height: 1.6),
      ),
    ]);
  }
}
