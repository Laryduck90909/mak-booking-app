import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../data/catalog.dart';
import '../../models/models.dart';
import '../orders/order_detail.dart';
import 'wizard_data.dart';
import 'wizard_steps.dart';

/// شاشة اختيار نوع الطلب ثم المعالج.
Future<void> startNewRequest(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NewRequestPage()));
}

class NewRequestPage extends StatelessWidget {
  const NewRequestPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    Widget card(String section, IconData icon, String title, String sub, Color color) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => WizardPage(section: section))),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
          child: Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: color.fade(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: ts(p, size: 16, w: FontWeight.w800, color: p.fg)),
              const SizedBox(height: 3),
              Text(sub, style: ts(p, size: 12, color: p.muted, height: 1.5)),
            ])),
            Icon(isAr ? Icons.chevron_left : Icons.chevron_right, color: p.muted),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(backgroundColor: p.sidebar, title: Text(t('طلب جديد', 'New request'), style: ts(p, size: 15, w: FontWeight.w800, color: p.fg))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(t('ماذا تريد أن تطلب؟', 'What would you like to order?'), style: ts(p, size: 20, w: FontWeight.w800, color: p.fg)),
            const SizedBox(height: 14),
            card('design', Icons.brush, 'MAK DESIGN', t('شعارات، مطبوعات، تغليف، ملابس، هوية بصرية', 'Logos, print, packaging, apparel, brand identity'), p.gold),
            const SizedBox(height: 12),
            card('web', Icons.code, 'MAK WEBS', t('مواقع، متاجر، تطبيقات، أنظمة إدارة', 'Websites, stores, apps, management systems'), p.blue),
            const SizedBox(height: 12),
            card('writing', Icons.edit_note, 'MAK WRITINGS', t('نصوص إعلانية، مقالات، ترجمة، تدقيق', 'Copywriting, articles, translation, proofreading'), p.violet),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------
// حقول الويب والكتابة (يمكن تعديلها هنا بسهولة)
// ------------------------------------------------------------------
const _webStep1 = <FieldDef>[
  FieldDef('project_name', 'اسم المشروع / الشركة', 'Project / company name', req: true),
  FieldDef('web_type', 'نوع المشروع', 'Project type', type: 'choice', req: true, options: [
    ('موقع تعريفي', 'Brochure site'), ('متجر إلكتروني', 'Online store'), ('تطبيق ويب', 'Web app'),
    ('تطبيق موبايل', 'Mobile app'), ('نظام إدارة', 'Management system'), ('صفحة هبوط', 'Landing page'), ('أخرى', 'Other'),
  ]),
  FieldDef('description', 'صف فكرتك وهدفك بالتفصيل', 'Describe your idea and goal', type: 'long', req: true),
];

const _webStep2 = <FieldDef>[
  FieldDef('pages', 'الصفحات / الأقسام المطلوبة', 'Pages / sections', type: 'multi', options: [
    ('الرئيسية', 'Home'), ('من نحن', 'About'), ('الخدمات', 'Services'), ('المنتجات', 'Products'), ('المعرض', 'Gallery'),
    ('المدونة', 'Blog'), ('اتصل بنا', 'Contact'), ('الأسئلة الشائعة', 'FAQ'), ('لوحة العميل', 'Client area'),
  ]),
  FieldDef('features', 'المزايا المطلوبة', 'Required features', type: 'multi', options: [
    ('تسجيل دخول', 'User login'), ('دفع إلكتروني', 'Online payment'), ('لوحة تحكم', 'Admin panel'), ('نموذج تواصل', 'Contact form'),
    ('حجز مواعيد', 'Bookings'), ('إشعارات', 'Notifications'), ('بحث', 'Search'), ('تعدد اللغات', 'Multi-language'), ('تقارير', 'Reports'),
  ]),
  FieldDef('features_other', 'مزايا أخرى أو تفاصيل إضافية', 'Other features or details', type: 'long'),
];

const _webStep3 = <FieldDef>[
  FieldDef('languages', 'لغات الموقع', 'Site languages', type: 'multi', options: [('العربية', 'Arabic'), ('الإنجليزية', 'English'), ('الفرنسية', 'French')]),
  FieldDef('platforms', 'المنصات', 'Platforms', type: 'multi', options: [('ويب', 'Web'), ('أندرويد', 'Android'), ('iOS', 'iOS'), ('سطح المكتب', 'Desktop')]),
  FieldDef('domain', 'هل لديك نطاق (Domain)؟', 'Do you have a domain?', type: 'choice', options: [('نعم', 'Yes'), ('لا', 'No'), ('أحتاج مساعدة', 'Need help')]),
  FieldDef('hosting', 'هل لديك استضافة؟', 'Do you have hosting?', type: 'choice', options: [('نعم', 'Yes'), ('لا', 'No'), ('أحتاج مساعدة', 'Need help')]),
  FieldDef('references', 'مواقع/تطبيقات مشابهة تعجبك (روابط)', 'Similar sites/apps you like (links)', type: 'long'),
  FieldDef('deadline', 'الموعد المطلوب', 'Desired deadline', type: 'date'),
  FieldDef('budget_note', 'ملاحظة عن الميزانية (اختياري)', 'Budget note (optional)'),
];

const _writeStep1 = <FieldDef>[
  FieldDef('writing_type', 'نوع الكتابة', 'Writing type', type: 'choice', req: true, options: [
    ('نص إعلاني', 'Ad copy'), ('مقال', 'Article'), ('محتوى موقع', 'Website copy'), ('ترجمة', 'Translation'),
    ('تدقيق لغوي', 'Proofreading'), ('سيناريو', 'Script'), ('سيرة ذاتية', 'CV'), ('أخرى', 'Other'),
  ]),
  FieldDef('topic', 'الموضوع / العنوان', 'Topic / title', req: true),
  FieldDef('description', 'ماذا تريد بالتفصيل؟', 'What exactly do you need?', type: 'long', req: true),
];

const _writeStep2 = <FieldDef>[
  FieldDef('source_lang', 'لغة المصدر (للترجمة/التدقيق)', 'Source language (translation/proofreading)', type: 'choice', options: [('العربية', 'Arabic'), ('الإنجليزية', 'English'), ('الفرنسية', 'French')]),
  FieldDef('target_lang', 'لغة النص المطلوب', 'Required language', type: 'choice', req: true, options: [('العربية', 'Arabic'), ('الإنجليزية', 'English'), ('الفرنسية', 'French')]),
  FieldDef('words', 'عدد الكلمات التقريبي', 'Approx. word count', type: 'number'),
  FieldDef('tone', 'النبرة', 'Tone', type: 'multi', options: [
    ('رسمية', 'Formal'), ('ودّية', 'Friendly'), ('إبداعية', 'Creative'), ('تسويقية', 'Marketing'), ('أكاديمية', 'Academic'), ('مبسّطة', 'Simple'),
  ]),
  FieldDef('audience', 'الجمهور المستهدف', 'Target audience'),
  FieldDef('keywords', 'كلمات مفتاحية / عبارات يجب ذكرها', 'Keywords / phrases to include', type: 'long'),
  FieldDef('references', 'نصوص أو روابط مرجعية', 'Reference texts or links', type: 'long'),
  FieldDef('deadline', 'الموعد المطلوب', 'Desired deadline', type: 'date'),
];

// ------------------------------------------------------------------
class _Step {
  final String title;
  final Widget Function() build;
  final String? Function() validate;
  const _Step(this.title, this.build, this.validate);
}

class WizardPage extends StatefulWidget {
  final String section; // design | web | writing
  const WizardPage({super.key, required this.section});
  @override
  State<WizardPage> createState() => _WizardPageState();
}

class _WizardPageState extends State<WizardPage> {
  late final WizardData d = WizardData(widget.section);
  bool _loading = true;
  Object? _err;
  int _i = 0;
  bool _sending = false;
  Map<String, int> _tiers = {};
  CompanySettings _settings = CompanySettings();
  List<BriefQuestion> _questions = [];
  List<_Step> _steps = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    d.disposeAll();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final tiers = await repo.getTiers();
      _tiers = {for (final x in tiers) x.code: x.price};
      _settings = await repo.getSettings();
      if (widget.section == 'design') {
        _questions = (await repo.getBriefQuestions()).where((q) => q.active).toList()..sort((a, b) => a.sort.compareTo(b.sort));
      }
      final had = await Drafts.load(d);
      _build();
      if (mounted) {
        setState(() => _loading = false);
        if (had) toast(context, t('تم استرجاع مسودتك السابقة', 'Your previous draft was restored'));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e;
          _loading = false;
        });
      }
    }
  }

  void _save() => Drafts.save(d);

  List<CatalogItem> get _catalog => widget.section == 'design' ? Catalog.designItems() : Catalog.itemsOf(widget.section);

  void _build() {
    final s = <_Step>[];
    switch (widget.section) {
      case 'design':
        s.add(_Step(t('الخدمات المطلوبة', 'Services'), () => ServicesStep(data: d, catalog: _catalog, tierPrice: _tiers, onChanged: _save),
            () => d.items.isEmpty ? t('اختر خدمة واحدة على الأقل', 'Pick at least one service') : null));
        s.add(_Step(t('نماذج العرض', 'Mockups'), () => MockupStep(data: d, onChanged: _save), () => null));
        s.add(_Step(t('الأسلوب', 'Style'), () => StyleStep(data: d, onChanged: _save), () => d.style.isEmpty ? t('اختر أسلوباً', 'Pick a style') : null));
        s.add(_Step(t('ألوان علامتك', 'Brand colors'), () => ColorsStep(data: d, onChanged: _save), () => validateColors(d)));
        final batches = <List<BriefQuestion>>[];
        for (var k = 0; k < _questions.length; k += 10) {
          batches.add(_questions.sublist(k, (k + 10) > _questions.length ? _questions.length : k + 10));
        }
        for (var b = 0; b < batches.length; b++) {
          final batch = batches[b];
          s.add(_Step('${t('أسئلة التصميم', 'Design brief')} ${b + 1}/${batches.length}', () => BriefStep(key: ValueKey('brief$b'), data: d, questions: batch, onChanged: _save), () {
            if (b == 0 && '${d.answers['q01'] ?? ''}'.isEmpty) return t('اكتب اسم العلامة/المشروع', 'Enter the brand/project name');
            return null;
          }));
        }
        break;
      case 'web':
        s.add(_Step(t('الخدمات المطلوبة', 'Services'), () => ServicesStep(data: d, catalog: _catalog, tierPrice: _tiers, onChanged: _save),
            () => d.items.isEmpty ? t('اختر خدمة واحدة على الأقل', 'Pick at least one service') : null));
        s.add(_Step(t('فكرة المشروع', 'Project idea'), () => FieldsStep(data: d, fields: _webStep1, onChanged: _save), () => validateFields(d, _webStep1)));
        s.add(_Step(t('الصفحات والمزايا', 'Pages & features'), () => FieldsStep(data: d, fields: _webStep2, onChanged: _save), () => null));
        s.add(_Step(t('هوية الموقع (اختياري)', 'Site identity (optional)'), () => ColorsStep(data: d, min: 0, onChanged: _save), () {
          if (d.colors.any((c) => c.value.isNotEmpty && !c.valid)) return t('هناك لون بصيغة غير صحيحة', 'A color has an invalid format');
          return null;
        }));
        s.add(_Step(t('التقنية والمراجع', 'Tech & references'), () => FieldsStep(data: d, fields: _webStep3, onChanged: _save), () => null));
        break;
      default:
        s.add(_Step(t('الخدمات المطلوبة', 'Services'), () => ServicesStep(data: d, catalog: _catalog, tierPrice: _tiers, onChanged: _save),
            () => d.items.isEmpty ? t('اختر خدمة واحدة على الأقل', 'Pick at least one service') : null));
        s.add(_Step(t('نوع النص', 'Text type'), () => FieldsStep(data: d, fields: _writeStep1, onChanged: _save), () => validateFields(d, _writeStep1)));
        s.add(_Step(t('المواصفات', 'Specifications'), () => FieldsStep(data: d, fields: _writeStep2, onChanged: _save), () => validateFields(d, _writeStep2)));
    }
    s.add(_Step(t('الملفات', 'Files'), () => FilesStep(data: d), () => null));
    s.add(_Step(t('المراجعة والإرسال', 'Review & send'), () => ReviewStep(data: d, priced: _priced(), settings: _settings, onChanged: _save), () => null));
    _steps = s;
  }

  Map<String, dynamic> _priced() {
    final sel = d.items.map((k) => Catalog.item(k)).whereType<CatalogItem>().toList();
    return priceItems(sel, _tiers);
  }

  String _title() {
    final date = fmtDate(DateTime.now());
    final names = d.items.map((k) => Catalog.item(k)?.name ?? k).toList();
    final svc = names.isEmpty ? '' : (names.length <= 2 ? names.join(' + ') : '${names.take(2).join(' + ')} +${names.length - 2}');
    switch (widget.section) {
      case 'design':
        final brand = '${d.answers['q01'] ?? appState.profile?.display ?? ''}';
        return '${t('تصميم', 'Design')} — $svc — $brand — $date';
      case 'web':
        final nm = '${d.extra['project_name'] ?? appState.profile?.display ?? ''}';
        return '${t('برمجة', 'Web')} — ${d.extra['web_type'] ?? svc} — $nm — $date';
      default:
        final tp = '${d.extra['topic'] ?? ''}';
        return '${t('كتابة', 'Writing')} — ${d.extra['writing_type'] ?? svc} — $tp — $date';
    }
  }

  Map<String, dynamic> _payload() {
    final m = <String, dynamic>{
      ..._priced(),
      'section': widget.section,
      'version': 2,
      'client_note': d.note,
    };
    final cols = d.colors.where((c) => c.value.isNotEmpty).map((c) => c.toJson()).toList();
    if (cols.isNotEmpty) m['colors'] = cols;
    if (widget.section == 'design') {
      m['mockups'] = d.mockups;
      m['style'] = d.style;
      m['brief_answers'] = d.answers;
    } else {
      m.addAll(d.extra);
    }
    return m;
  }

  Future<void> _next() async {
    final err = _steps[_i].validate();
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    await Drafts.save(d);
    if (_i < _steps.length - 1) {
      setState(() => _i++);
    } else {
      await _submit();
    }
  }

  Future<void> _submit() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final o = await repo.createOrder(section: widget.section, title: _title(), payload: _payload());
      if (o != null) {
        for (final f in d.files) {
          try {
            await repo.uploadFile('order-files', o.id, f.name, f.bytes);
          } catch (_) {}
        }
      }
      await Drafts.clear(widget.section);
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (o == null) {
        toast(context, t('لا يوجد اتصال: حُفظ طلبك وسيُرسل تلقائياً عند عودة الإنترنت (أضف الملفات لاحقاً).', 'Offline: your request is saved and will be sent automatically (add files later).'));
        nav.pop();
      } else {
        nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => OrderDetailPage(orderId: o.id)));
        toast(context, t('تم إرسال طلبك ✓ سيصلك عرض السعر قريباً', 'Request sent ✓ a quote will follow soon'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        toast(context, errMsg(e), error: true);
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    if (_loading) {
      return Scaffold(backgroundColor: p.bg, body: Center(child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5)));
    }
    if (_err != null) {
      return Scaffold(backgroundColor: p.bg, appBar: AppBar(backgroundColor: p.sidebar), body: Center(child: Text(errMsg(_err!), style: ts(p, color: p.muted))));
    }
    final step = _steps[_i];
    final last = _i == _steps.length - 1;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.sidebar,
        title: Text('${sectionLabel(widget.section)} — ${_i + 1}/${_steps.length}', style: ts(p, size: 14, w: FontWeight.w800, color: p.fg)),
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: ProgressLine((_i + 1) / _steps.length)),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: SingleChildScrollView(
                key: ValueKey('step$_i'),
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(step.title, style: ts(p, size: 20, w: FontWeight.w800, color: p.fg)),
                  const SizedBox(height: 14),
                  step.build(),
                  const SizedBox(height: 20),
                ]),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.sidebar, border: Border(top: BorderSide(color: p.border))),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Row(children: [
                  if (_i > 0) Expanded(child: MakButton(t('السابق', 'Back'), kind: 'ghost', onPressed: () => setState(() => _i--))),
                  if (_i > 0) const SizedBox(width: 10),
                  Expanded(flex: 2, child: MakButton(last ? t('إرسال الطلب', 'Send request') : t('التالي', 'Next'), icon: last ? Icons.send : null, onPressed: _sending ? null : _next)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// يضمن أن AppConfig مستعمل (حدود المعالج تُقرأ من الإعدادات)
int get wizardMaxColors => AppConfig.maxColors;
