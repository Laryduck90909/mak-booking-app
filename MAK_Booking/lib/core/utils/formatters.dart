import 'package:intl/intl.dart';

String money(num value, String locale) {
  final formatted = NumberFormat('#,##0.##', locale).format(value);
  return locale == 'ar' ? '$formatted د.م.' : '$formatted MAD';
}

String shortDate(DateTime value, String locale) =>
    DateFormat.yMMMd(locale).add_Hm().format(value.toLocal());
