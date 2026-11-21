import '../models/models.dart';
import 'catalog.dart';

String _scope(Order o, bool ar) {
  final parts = <String>[];
  final names = o.items.map((e) => '${ar ? e['ar'] : e['en']}').where((e) => e != 'null' && e.isNotEmpty).toList();
  if (names.isNotEmpty) parts.add(ar ? 'الخدمات: ${names.join('، ')}' : 'Services: ${names.join(', ')}');
  if (o.mockups.isNotEmpty) parts.add(ar ? 'عدد نماذج العرض (Mockups): ${o.mockups.length}' : 'Mockups: ${o.mockups.length}');
  final st = Catalog.style(o.styleKey);
  if (st != null) parts.add(ar ? 'الأسلوب: ${st.nameAr}' : 'Style: ${st.nameEn}');
  if (names.isEmpty) {
    final d = o.payload['description'];
    if (d != null && '$d'.isNotEmpty) parts.add('$d');
  }
  if (parts.isEmpty) parts.add(o.title);
  return parts.join(ar ? ' — ' : ' — ');
}

String _note(String section, bool ar) {
  switch (section) {
    case 'web':
      return ar
          ? 'تُسلَّم نسخة تجريبية (Demo) للمعاينة، وبعد الموافقة والتوقيع والسداد تُسلَّم النسخة النهائية.'
          : 'A demo version is delivered for review; after approval, signature and payment the final version is delivered.';
    case 'writing':
      return ar
          ? 'يُسلَّم النص وفق اللغة والمواصفات المطلوبة، وتضمن M.A.K أصالة المحتوى، ويُمنع إعادة توزيعه قبل السداد الكامل.'
          : 'The text is delivered per the requested language and specifications; M.A.K guarantees originality and redistribution before full payment is prohibited.';
    default:
      return ar
          ? 'تُسلَّم معاينة بعلامة مائية أولاً، ثم النسخة النهائية بعد توقيع العقد والسداد الكامل.'
          : 'A watermarked preview is delivered first, then the final version after signature and full payment.';
  }
}

/// يبني نص العقد بالنسختين من القالب (قالب لوحة المدير أو النص الافتراضي في assets).
({String ar, String en}) buildContractTexts({
  required Order order,
  required CompanySettings settings,
  String? templateAr,
  String? templateEn,
  String? addendumTitle,
  String? addendumBody,
}) {
  final today = DateTime.now();
  String d2(int n) => n < 10 ? '0$n' : '$n';
  final date = '${today.year}-${d2(today.month)}-${d2(today.day)}';
  final total = order.totalMad;
  final deposit = (total * settings.depositPct / 100).round();
  String money(int v, bool ar) => '${_fmt(v)} ${ar ? 'د.م.' : 'MAD'}';

  Map<String, String> vars(bool ar) => {
        'ORDER_ID': order.id,
        'DATE': date,
        'COMPANY_NAME': settings.companyName,
        'COMPANY_CITY': settings.city.isEmpty ? (ar ? '________' : '________') : settings.city,
        'COMPANY_EMAIL': settings.email.isEmpty ? '________' : settings.email,
        'CLIENT_NAME': order.clientName.isEmpty ? '________' : order.clientName,
        'CLIENT_EMAIL': order.clientEmail.isEmpty ? '________' : order.clientEmail,
        'SCOPE': _scope(order, ar),
        'SECTION_NOTE': _note(order.section, ar),
        'TOTAL': money(total, ar),
        'DEPOSIT': money(deposit, ar),
        'REVISIONS': '${settings.revisionRounds}',
        'CANCEL_FINE': '${settings.cancelFinePct}',
        'MODIFY_FEE': '${settings.modifyFeePct}',
      };

  if (addendumBody != null) {
    // ملحق: يُحرَّر النص يدوياً من الموظف
    final head = addendumTitle ?? 'ملحق';
    final ar = 'ملحق عقد — {{CONTRACT_ID}}\nالطلب: ${order.id} — التاريخ: $date\n\n$head\n\n$addendumBody\n\nيُعدّ هذا الملحق جزءاً لا يتجزأ من العقد الأصلي، ولا يسري إلا بتوقيع الطرفين.';
    final en = 'Contract Addendum — {{CONTRACT_ID}}\nOrder: ${order.id} — Date: $date\n\n$head\n\n$addendumBody\n\nThis Addendum forms an integral part of the original Agreement and takes effect only upon signature by both parties.';
    return (ar: ar, en: en);
  }

  final ar = renderTemplate(templateAr ?? Catalog.contractAr, vars(true)).replaceAll('{{CONTRACT_ID}}', '{{CONTRACT_ID}}');
  final en = renderTemplate(templateEn ?? Catalog.contractEn, vars(false));
  return (ar: ar, en: en);
}

String _fmt(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
