// يعرض أي صور Mockup ناقصة. التشغيل:  dart run tools/check_mockups.dart
import 'dart:convert';
import 'dart:io';

void main() {
  final data = jsonDecode(File('assets/data/mockups.json').readAsStringSync()) as Map<String, dynamic>;
  final items = (data['items'] as List).cast<Map<String, dynamic>>();
  var missing = 0;
  for (final m in items) {
    final key = m['key'];
    final f = File('assets/mockups/$key.png');
    if (!f.existsSync()) {
      missing++;
      stdout.writeln('ناقصة: assets/mockups/$key.png   (${m['ar']})');
    }
  }
  stdout.writeln('\nالمجموع: ${items.length} — موجودة: ${items.length - missing} — ناقصة: $missing');
}
