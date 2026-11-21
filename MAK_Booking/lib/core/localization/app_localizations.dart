import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLocalizations {
  AppLocalizations(this.locale, this._values);
  final Locale locale;
  final Map<String, String> _values;

  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  String get(String key) => _values[key] ?? key;

  static Future<AppLocalizations> load(Locale locale) async {
    final code = locale.languageCode == 'en' ? 'en' : 'ar';
    final source =
        await rootBundle.loadString('assets/translations/$code.json');
    final values = (jsonDecode(source) as Map<String, dynamic>)
        .map((key, value) => MapEntry(key, value.toString()));
    return AppLocalizations(Locale(code), values);
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) => AppLocalizations.load(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension Translate on BuildContext {
  String tr(String key) => AppLocalizations.of(this).get(key);
  String get localeCode => Localizations.localeOf(this).languageCode;
}

final localeProvider = StateNotifierProvider<LocaleController, Locale>((ref) {
  return LocaleController();
});

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(const Locale('ar')) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale');
    if (code == 'ar' || code == 'en') state = Locale(code!);
  }

  Future<void> toggle() async {
    state =
        state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', state.languageCode);
  }
}
