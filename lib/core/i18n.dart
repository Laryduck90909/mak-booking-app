import 'state.dart';

/// ترجمة مباشرة: t('عربي', 'English')
String t(String ar, String en) => appState.lang == 'ar' ? ar : en;

bool get isAr => appState.lang == 'ar';
