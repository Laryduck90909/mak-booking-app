import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/colors.dart';
import '../orders/order_files.dart';

class ColorEntry {
  String format;
  final TextEditingController ctl;
  ColorEntry(this.format, String value) : ctl = TextEditingController(text: value);
  String get value => ctl.text.trim();
  bool get valid => validColor(format, value);
  Map<String, dynamic> toJson() => {'format': format, 'value': value};
}

/// كل ما يملؤه العميل في المعالج (يُحفظ كمسودة تلقائياً).
class WizardData {
  final String section;
  List<String> items = [];
  List<String> mockups = [];
  String style = '';
  final List<ColorEntry> colors = [];
  Map<String, dynamic> answers = {};
  Map<String, dynamic> extra = {};
  List<PickedFile> files = [];
  String note = '';

  WizardData(this.section);

  void disposeAll() {
    for (final c in colors) {
      c.ctl.dispose();
    }
  }

  Map<String, dynamic> toDraft() => {
        'items': items, 'mockups': mockups, 'style': style, 'note': note,
        'colors': colors.map((c) => c.toJson()).toList(), 'answers': answers, 'extra': extra,
      };

  void fromDraft(Map<String, dynamic> j) {
    items = (j['items'] is List) ? (j['items'] as List).map((e) => '$e').toList() : [];
    mockups = (j['mockups'] is List) ? (j['mockups'] as List).map((e) => '$e').toList() : [];
    style = '${j['style'] ?? ''}';
    note = '${j['note'] ?? ''}';
    answers = (j['answers'] is Map) ? Map<String, dynamic>.from(j['answers'] as Map) : {};
    extra = (j['extra'] is Map) ? Map<String, dynamic>.from(j['extra'] as Map) : {};
    for (final c in colors) {
      c.ctl.dispose();
    }
    colors.clear();
    if (j['colors'] is List) {
      for (final c in (j['colors'] as List)) {
        if (c is Map) colors.add(ColorEntry('${c['format'] ?? 'hex'}', '${c['value'] ?? ''}'));
      }
    }
  }

  bool get isEmpty => items.isEmpty && mockups.isEmpty && style.isEmpty && answers.isEmpty && extra.isEmpty && colors.every((c) => c.value.isEmpty);
}

class Drafts {
  static String _k(String section) => 'wizard_draft_$section';

  static Future<void> save(WizardData d) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k(d.section), jsonEncode(d.toDraft()));
    } catch (_) {}
  }

  static Future<bool> load(WizardData d) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_k(d.section));
      if (s == null || s.isEmpty) return false;
      d.fromDraft(Map<String, dynamic>.from(jsonDecode(s) as Map));
      return !d.isEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear(String section) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_k(section));
    } catch (_) {}
  }
}

/// تعريف حقل لخطوات الويب والكتابة (قابل للتوسعة بسهولة).
class FieldDef {
  final String key, ar, en;
  final String type; // text | long | choice | multi | date | number
  final List<(String, String)> options; // (عربي, English) — يُخزَّن العربي
  final bool req;
  const FieldDef(this.key, this.ar, this.en, {this.type = 'text', this.options = const [], this.req = false});
}
