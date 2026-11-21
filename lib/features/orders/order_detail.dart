import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/colors.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../data/catalog.dart';
import '../../models/models.dart';
import 'chat.dart';
import 'order_files.dart';
import 'order_workflow.dart';

/// يفتح صفحة الطلب.
Future<void> openOrder(BuildContext context, String orderId, {int tab = 0}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OrderDetailPage(orderId: orderId, initialTab: tab)));
}

class OrderDetailPage extends StatefulWidget {
  final String orderId;
  final int initialTab;
  const OrderDetailPage({super.key, required this.orderId, this.initialTab = 0});
  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.sidebar,
        title: Text(widget.orderId, style: ts(p, size: 15, w: FontWeight.w800, color: p.fg)),
      ),
      body: AsyncData<Order>(
        load: () => repo.getOrder(widget.orderId),
        builder: (context, o) {
          final tabs = [t('التفاصيل', 'Details'), t('المسار', 'Workflow'), t('المحادثة', 'Chat')];
          return Column(children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Header(order: o),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (var i = 0; i < tabs.length; i++) SelectChip(tabs[i], selected: _tab == i, onTap: () => setState(() => _tab = i)),
                      ]),
                      const SizedBox(height: 12),
                      if (_tab == 0) OrderInfo(order: o),
                      if (_tab == 1) _Workflow(order: o),
                      if (_tab == 2) OrderChat(order: o, height: 480),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Order order;
  const _Header({required this.order});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final staff = appState.role != 'client';
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(order.title.isEmpty ? order.id : order.title, style: ts(p, size: 17, w: FontWeight.w800, color: p.fg))),
          StatusPill(order.status),
        ]),
        const SizedBox(height: 6),
        Text('${order.id} · ${sectionLabel(order.section)} · ${fmtDateTime(order.createdAt)}', style: ts(p, size: 12, color: p.muted)),
        if (staff && order.clientName.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text('${t('العميل', 'Client')}: ${order.clientName}${order.clientEmail.isEmpty ? '' : ' — ${order.clientEmail}'}', style: ts(p, size: 12.5, color: p.text))),
        const SizedBox(height: 10),
        ProgressLine(orderProgress(order.status), color: statusColor(p, order.status)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              order.totalMad > 0 ? '${t('السعر', 'Price')}: ${fmtMad(order.totalMad)}' : (order.estimate > 0 ? '${t('تقدير', 'Estimate')}: ~${fmtMad(order.estimate)}' : t('بانتظار التسعير', 'Awaiting quote')),
              style: ts(p, size: 14, w: FontWeight.w800, color: p.fg),
            ),
          ),
          WhatsAppButton(orderId: order.id),
        ]),
      ]),
    );
  }
}

class _Workflow extends StatelessWidget {
  final Order order;
  const _Workflow({required this.order});

  @override
  Widget build(BuildContext context) {
    Widget gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);
    return Column(children: [
      gap(StatusActions(order: order)),
      gap(QuotePanel(order: order)),
      gap(ContractsPanel(order: order)),
      gap(PaymentsPanel(order: order)),
      gap(DeliveryPanels(order: order)),
      gap(ChangeRequestsPanel(order: order)),
      gap(TeamPanel(order: order)),
    ]);
  }
}

// ------------------------------------------------------------------
// تفاصيل الطلب الكاملة (ما يراه الموظف والعميل)
// ------------------------------------------------------------------
const _knownKeys = {
  'items', 'colors', 'mockups', 'brief_answers', 'estimate_total', 'style', 'needs_manual_pricing', 'files', 'draft',
};

class OrderInfo extends StatelessWidget {
  final Order order;
  const OrderInfo({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final o = order;
    final isClient = appState.role == 'client';
    final extras = o.payload.entries.where((e) => !_knownKeys.contains(e.key) && '${e.value}'.isNotEmpty && e.value != null).toList();
    Widget gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 12), child: w);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      gap(_CodePanel(order: o, isClient: isClient)),
      if (o.items.isNotEmpty)
        gap(Panel(
          title: t('الخدمات المطلوبة', 'Requested services'),
          child: Column(children: [
            ...o.items.map((it) {
              final price = it['price'];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Icon(Icons.check_circle_outline, size: 16, color: p.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(isAr ? '${it['ar']}' : '${it['en']}', style: ts(p, size: 13, color: p.fg))),
                  Text(price == null ? t('تسعير يدوي', 'Manual quote') : fmtMad(price as num), style: ts(p, size: 12, w: FontWeight.w700, color: price == null ? p.amber : p.text)),
                ]),
              );
            }),
            if (o.estimate > 0) ...[
              Divider(color: p.border),
              Row(children: [
                Expanded(child: Text(t('التقدير الأولي', 'Initial estimate'), style: ts(p, size: 12.5, color: p.muted))),
                Text(fmtMad(o.estimate), style: ts(p, size: 14, w: FontWeight.w800, color: p.fg)),
              ]),
            ],
          ]),
        )),
      if (o.styleKey.isNotEmpty)
        gap(Panel(title: t('الأسلوب', 'Style'), child: Text(Catalog.style(o.styleKey)?.name ?? o.styleKey, style: ts(p, size: 14, w: FontWeight.w700, color: p.fg)))),
      if (o.mockups.isNotEmpty) gap(Panel(title: t('نماذج العرض (Mockups)', 'Mockups'), child: _MockupGrid(keys: o.mockups))),
      if (o.colors.isNotEmpty) gap(Panel(title: t('ألوان العميل', 'Client colors'), child: _ColorsRow(colors: o.colors))),
      if (extras.isNotEmpty)
        gap(Panel(
          title: t('بيانات الطلب', 'Order details'),
          child: Column(children: extras.map((e) => _kv(p, _niceKey(e.key), _valueText(e.value))).toList()),
        )),
      gap(_BriefPanel(order: o)),
      gap(FilesPanel(
        title: t('ملفات العميل', 'Client files'), bucket: 'order-files', orderId: o.id,
        canUpload: isClient && !o.isClosed, uploadLabel: t('إضافة ملف', 'Add file'),
      )),
    ]);
  }
}

Widget _kv(Palette p, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(k, style: ts(p, size: 12, color: p.muted))),
        Expanded(child: SelectableText(v, style: ts(p, size: 13, color: p.fg, height: 1.5))),
      ]),
    );

String _valueText(dynamic v) {
  if (v is List) return v.map((e) => Catalog.optionLabel('$e')).join('، ');
  if (v is Map) return v.entries.map((e) => '${e.key}: ${e.value}').join(' | ');
  if (v is bool) return v ? t('نعم', 'Yes') : t('لا', 'No');
  return Catalog.optionLabel('$v');
}

String _niceKey(String k) {
  const map = {
    'description': ['الوصف', 'Description'],
    'web_type': ['نوع المشروع', 'Project type'],
    'pages': ['الصفحات', 'Pages'],
    'features': ['المزايا', 'Features'],
    'platforms': ['المنصات', 'Platforms'],
    'languages': ['اللغات', 'Languages'],
    'references': ['مراجع/مواقع مشابهة', 'References'],
    'deadline': ['الموعد المطلوب', 'Deadline'],
    'budget_note': ['ملاحظة الميزانية', 'Budget note'],
    'domain': ['النطاق (Domain)', 'Domain'],
    'hosting': ['الاستضافة', 'Hosting'],
    'writing_type': ['نوع الكتابة', 'Writing type'],
    'words': ['عدد الكلمات', 'Word count'],
    'source_lang': ['لغة المصدر', 'Source language'],
    'target_lang': ['اللغة المطلوبة', 'Target language'],
    'tone': ['النبرة', 'Tone'],
    'audience': ['الجمهور', 'Audience'],
    'topic': ['الموضوع', 'Topic'],
    'keywords': ['كلمات مفتاحية', 'Keywords'],
    'notes': ['ملاحظات', 'Notes'],
    'color_mode': ['نمط ألوان الطباعة', 'Print color mode'],
    'project_name': ['اسم المشروع', 'Project name'],
  };
  final m = map[k];
  if (m == null) return k;
  return t(m[0], m[1]);
}

class _CodePanel extends StatefulWidget {
  final Order order;
  final bool isClient;
  const _CodePanel({required this.order, required this.isClient});
  @override
  State<_CodePanel> createState() => _CodePanelState();
}

class _CodePanelState extends State<_CodePanel> {
  final _ctl = TextEditingController();
  bool? _ok;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final code = widget.order.verificationCode;
    if (code.isEmpty) return const SizedBox();
    if (widget.isClient) {
      return Panel(
        title: t('رمز التحقق الخاص بطلبك', 'Your order verification code'),
        child: Row(children: [
          Text(code, style: ts(p, size: 26, w: FontWeight.w900, color: p.accent)),
          const SizedBox(width: 12),
          Expanded(child: Text(t('لا تشاركه إلا عند طلب الفريق لإثبات هويتك (مثل الإلغاء).', 'Share it only when the team asks to verify you (e.g. cancellation).'), style: ts(p, size: 11.5, color: p.muted))),
          IconBtn(Icons.copy, onTap: () {
            Clipboard.setData(ClipboardData(text: code));
            toast(context, t('تم النسخ', 'Copied'));
          }),
        ]),
      );
    }
    return Panel(
      title: t('التحقق من هوية العميل', 'Verify the client'),
      child: Row(children: [
        SizedBox(
          width: 140,
          child: MakField(controller: _ctl, hint: t('الرمز (5 أرقام)', '5-digit code'), keyboard: TextInputType.number, onChanged: (_) => setState(() => _ok = null)),
        ),
        const SizedBox(width: 10),
        MakButton(t('تحقق', 'Verify'), dense: true, kind: 'soft', onPressed: () => setState(() => _ok = _ctl.text.trim() == code)),
        const SizedBox(width: 10),
        if (_ok != null) Pill(_ok! ? t('مطابق ✓', 'Match ✓') : t('غير مطابق', 'No match'), color: _ok! ? p.green : p.red),
      ]),
    );
  }
}

class _MockupGrid extends StatelessWidget {
  final List<String> keys;
  const _MockupGrid({required this.keys});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return AdaptiveGrid(
      minWidth: 140, gap: 10,
      children: keys.map((k) {
        final def = Catalog.mockup(k);
        return Column(children: [
          AspectRatio(aspectRatio: 1.2, child: mockupImage(p, k)),
          const SizedBox(height: 5),
          Text(def?.name ?? k, style: ts(p, size: 11.5, w: FontWeight.w600, color: p.fg), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]);
      }).toList(),
    );
  }
}

/// صورة mockup من assets/mockups/<key>.png أو مربع بديل إن لم توضع الصورة بعد.
Widget mockupImage(Palette p, String key) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.asset(
      'assets/mockups/$key.png',
      fit: BoxFit.cover,
      errorBuilder: (c, e, s) => Container(
        color: p.elevated,
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.image_outlined, color: p.subtle, size: 30),
          const SizedBox(height: 4),
          Text('$key.png', style: ts(p, size: 9.5, color: p.subtle)),
        ]),
      ),
    ),
  );
}

class _ColorsRow extends StatelessWidget {
  final List<Map<String, dynamic>> colors;
  const _ColorsRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Wrap(spacing: 12, runSpacing: 12, children: colors.map((c) {
      final fmt = '${c['format'] ?? 'hex'}';
      final val = '${c['value'] ?? ''}';
      final col = parseColor(fmt, val) ?? p.elevated;
      return Container(
        width: 150, padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.borderSoft)),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border))),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(colorFormatLabel(fmt), style: ts(p, size: 10, w: FontWeight.w800, color: p.accent)),
            SelectableText(val, style: ts(p, size: 12, w: FontWeight.w600, color: p.fg)),
          ])),
        ]),
      );
    }).toList());
  }
}

class _BriefPanel extends StatelessWidget {
  final Order order;
  const _BriefPanel({required this.order});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final answers = order.briefAnswers;
    if (answers.isEmpty) return const SizedBox();
    return AsyncData<List<BriefQuestion>>(
      load: () => repo.getBriefQuestions(),
      builder: (context, qs) {
        final byKey = {for (final q in qs) q.key: q};
        final groups = <String, List<Widget>>{};
        final used = <String>{};
        for (final q in qs) {
          final v = answers[q.key];
          if (v == null || '$v'.isEmpty || (v is List && v.isEmpty)) continue;
          used.add(q.key);
          groups.putIfAbsent(q.group.isEmpty ? '—' : briefGroupLabel(q.group), () => []).add(_kv(p, q.label, _valueText(v)));
        }
        // إجابات لأسئلة حُذفت/عُطّلت لاحقاً تبقى ظاهرة
        for (final e in answers.entries) {
          if (used.contains(e.key) || byKey.containsKey(e.key)) continue;
          if ('${e.value}'.isEmpty) continue;
          groups.putIfAbsent(t('أخرى', 'Other'), () => []).add(_kv(p, e.key, _valueText(e.value)));
        }
        return Panel(
          title: t('الأسئلة (البريف)', 'Brief'),
          kicker: '${answers.length} ${t('إجابة', 'answers')}',
          child: groups.isEmpty
              ? EmptyState(t('لا توجد إجابات', 'No answers'))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: groups.entries.expand((g) => [
                    Padding(padding: const EdgeInsets.only(top: 8, bottom: 2), child: Text(g.key, style: ts(p, size: 12, w: FontWeight.w800, color: p.accent))),
                    ...g.value,
                  ]).toList()),
        );
      },
    );
  }
}
