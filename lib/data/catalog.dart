import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../core/i18n.dart';
import '../models/models.dart';

/// بيانات ثابتة من assets/data/*.json (قابلة للتعديل دون لمس الكود).
class Catalog {
  static List<CatalogItem> items = [];
  static List<SimpleDef> mockups = [];
  static List<SimpleDef> styles = [];
  static List<BriefQuestion> briefQuestions = [];
  static Map<String, String> enOptions = {};
  static String contractAr = '';
  static String contractEn = '';

  static Future<void> load() async {
    items = await _list('assets/data/catalog.json', (j) => CatalogItem.fromJson(j));
    items.addAll(await _list('assets/data/extra_services.json', (j) => CatalogItem.fromJson(j)));
    mockups = await _list('assets/data/mockups.json', (j) => SimpleDef.fromJson(j));
    styles = await _list('assets/data/styles.json', (j) => SimpleDef.fromJson(j));
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/data/brief_questions.json')) as Map<String, dynamic>;
      briefQuestions = (raw['items'] as List).map((e) => BriefQuestion.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      final eo = raw['en_options'];
      if (eo is Map) enOptions = eo.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {}
    try {
      contractAr = await rootBundle.loadString('assets/data/contract_ar.txt');
      contractEn = await rootBundle.loadString('assets/data/contract_en.txt');
    } catch (_) {}
  }

  static Future<List<T>> _list<T>(String path, T Function(Map<String, dynamic>) f) async {
    try {
      final raw = jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>;
      return (raw['items'] as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return <T>[];
    }
  }

  static List<CatalogItem> designItems() => items.where((i) => i.group != 'web' && i.group != 'writing').toList();
  static List<CatalogItem> itemsOf(String group) => items.where((i) => i.group == group).toList();

  static String groupLabel(String g) {
    switch (g) {
      case 'print': return t('مطبوعات', 'Print');
      case 'digital': return t('رقمي', 'Digital');
      case 'branding': return t('هوية العلامة', 'Branding');
      case 'merch': return t('منتجات ترويجية', 'Merchandise');
      case 'stationery': return t('قرطاسية', 'Stationery');
      case 'apparel': return t('ملابس', 'Apparel');
      case 'outdoor': return t('إعلانات خارجية', 'Outdoor');
      case 'packaging': return t('تغليف', 'Packaging');
      case 'web': return t('برمجة وويب', 'Web & software');
      case 'writing': return t('كتابة وترجمة', 'Writing');
      default: return g;
    }
  }

  static CatalogItem? item(String key) {
    for (final i in items) {
      if (i.key == key) return i;
    }
    return null;
  }

  static SimpleDef? style(String key) {
    for (final s in styles) {
      if (s.key == key) return s;
    }
    return null;
  }

  static SimpleDef? mockup(String key) {
    for (final s in mockups) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// الخيارات تُخزَّن بالعربية؛ هذه الدالة تعرضها حسب اللغة.
  static String optionLabel(String ar) => isAr ? ar : (enOptions[ar] ?? ar);
}

/// يحسب بنود الطلب والسعر التقديري من أسعار الفئات الحالية.
Map<String, dynamic> priceItems(List<CatalogItem> sel, Map<String, int> tierPrice) {
  var total = 0;
  var manual = false;
  final out = <Map<String, dynamic>>[];
  for (final it in sel) {
    final price = it.tier == null ? null : tierPrice[it.tier];
    if (price == null) {
      manual = true;
    } else {
      total += price;
    }
    out.add({'key': it.key, 'ar': it.nameAr, 'en': it.nameEn, 'tier': it.tier, 'price': price});
  }
  return {'items': out, 'estimate_total': total, 'needs_manual_pricing': manual};
}

String renderTemplate(String body, Map<String, String> vars) {
  var s = body;
  vars.forEach((k, v) {
    s = s.replaceAll('{{$k}}', v);
  });
  return s;
}
