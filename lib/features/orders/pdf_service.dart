import 'dart:convert';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/i18n.dart';
import '../../core/util.dart';
import '../../models/models.dart';

/// يفك ترميز توقيع محفوظ (base64 خام أو data URL). يعيد null إن لم يصلح.
Uint8List? signatureBytes(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final i = s.indexOf('base64,');
    final raw = i >= 0 ? s.substring(i + 7) : s;
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

bool _isHeading(String line, bool ar) {
  final l = line.trim();
  if (ar) return l.startsWith('المادة ') || l.startsWith('عقد ') || l.startsWith('ملحق عقد');
  return l.startsWith('Article ') || l.startsWith('Service Agreement') || l.startsWith('Contract Addendum');
}

List<pw.Widget> _textBlock(String text, bool ar, pw.Font reg, pw.Font bold) {
  final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final align = ar ? pw.TextAlign.right : pw.TextAlign.left;
  final out = <pw.Widget>[];
  for (final raw in text.split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) {
      out.add(pw.SizedBox(height: 6));
      continue;
    }
    final h = _isHeading(line, ar);
    out.add(pw.Padding(
      padding: pw.EdgeInsets.only(top: h ? 8 : 0, bottom: 2),
      child: pw.Text(
        line,
        textDirection: dir,
        textAlign: align,
        style: pw.TextStyle(font: h ? bold : reg, fontSize: h ? 12.5 : 10.5, lineSpacing: 2.5),
      ),
    ));
  }
  return out;
}

pw.Widget _sigBox(String label, String? sig, pw.Font reg, pw.Font bold, {required bool ar, String? when}) {
  final bytes = signatureBytes(sig);
  final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  return pw.Container(
    width: 220,
    height: 110,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: 0.8)),
    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(label, textDirection: dir, style: pw.TextStyle(font: bold, fontSize: 10)),
      pw.Expanded(
        child: pw.Center(
          child: bytes == null
              ? pw.Text(ar ? '— غير موقّع —' : '— unsigned —', textDirection: dir, style: pw.TextStyle(font: reg, fontSize: 9, color: PdfColors.grey600))
              : pw.Image(pw.MemoryImage(bytes), height: 60, fit: pw.BoxFit.contain),
        ),
      ),
      if (when != null) pw.Text(when, style: pw.TextStyle(font: reg, fontSize: 8, color: PdfColors.grey700)),
    ]),
  );
}

/// ينشئ PDF للعقد: النسخة العربية ثم الإنجليزية، وفي آخر كل نسخة مربعا التوقيع.
Future<Uint8List> buildContractPdf(Contract c) async {
  final reg = await PdfGoogleFonts.cairoRegular();
  final bold = await PdfGoogleFonts.cairoBold();
  final doc = pw.Document(title: c.id, author: 'M.A.K');

  Future<void> addSection(String text, bool ar) async {
    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 44, 40, 44),
        theme: pw.ThemeData.withFont(base: reg, bold: bold),
      ),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text('${c.id}  •  ${ctx.pageNumber}/${ctx.pagesCount}', style: pw.TextStyle(font: reg, fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (ctx) => [
        ..._textBlock(text, ar, reg, bold),
        pw.SizedBox(height: 18),
        pw.Wrap(spacing: 14, runSpacing: 10, children: [
          _sigBox(ar ? 'توقيع العميل' : 'Client signature', c.clientSignature, reg, bold, ar: ar),
          _sigBox(ar ? 'توقيع M.A.K (المدير)' : 'M.A.K signature (Admin)', c.adminSignature, reg, bold, ar: ar, when: c.signed ? fmtDateTime(c.signedAt) : null),
        ]),
      ],
    ));
  }

  if (c.rendered_ar.trim().isNotEmpty) await addSection(c.rendered_ar, true);
  if (c.rendered_en.trim().isNotEmpty) await addSection(c.rendered_en, false);
  return doc.save();
}

Future<void> shareContractPdf(Contract c) async {
  final bytes = await buildContractPdf(c);
  await Printing.sharePdf(bytes: bytes, filename: '${c.id}.pdf');
}

/// فاتورة PDF بسيطة.
Future<Uint8List> buildInvoicePdf(Invoice inv, CompanySettings s) async {
  final reg = await PdfGoogleFonts.cairoRegular();
  final bold = await PdfGoogleFonts.cairoBold();
  final doc = pw.Document(title: inv.id, author: s.companyName);
  final ar = isAr;
  final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final align = ar ? pw.TextAlign.right : pw.TextAlign.left;

  pw.Widget cell(String txt, {bool b = false, pw.TextAlign? a}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(txt, textDirection: dir, textAlign: a ?? align, style: pw.TextStyle(font: b ? bold : reg, fontSize: 10.5)),
      );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [cell(t('البيان', 'Description'), b: true), cell(t('المبلغ', 'Amount'), b: true)],
    ),
    for (final l in inv.lines)
      pw.TableRow(children: [
        cell('${l['description'] ?? l['label'] ?? l['ar'] ?? ''}'),
        cell(fmtMad(num.tryParse('${l['amount_mad'] ?? l['amount'] ?? 0}') ?? 0)),
      ]),
  ];

  doc.addPage(pw.Page(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      theme: pw.ThemeData.withFont(base: reg, bold: bold),
    ),
    build: (ctx) => pw.Column(crossAxisAlignment: ar ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start, children: [
      pw.Text(s.companyName, textDirection: dir, style: pw.TextStyle(font: bold, fontSize: 20)),
      if (s.city.isNotEmpty) pw.Text(s.city, textDirection: dir, style: pw.TextStyle(font: reg, fontSize: 10)),
      if (s.email.isNotEmpty) pw.Text(s.email, style: pw.TextStyle(font: reg, fontSize: 10)),
      if (s.taxId.isNotEmpty) pw.Text('ICE/IF: ${s.taxId}', style: pw.TextStyle(font: reg, fontSize: 10)),
      pw.SizedBox(height: 18),
      pw.Text('${t('فاتورة', 'Invoice')} ${inv.id}', textDirection: dir, style: pw.TextStyle(font: bold, fontSize: 15)),
      pw.Text('${t('التاريخ', 'Date')}: ${fmtDate(inv.issuedAt)}', textDirection: dir, style: pw.TextStyle(font: reg, fontSize: 10)),
      pw.Text('${t('العميل', 'Client')}: ${inv.clientName}', textDirection: dir, style: pw.TextStyle(font: reg, fontSize: 10)),
      if (inv.orderId != null) pw.Text('${t('الطلب', 'Order')}: ${inv.orderId}', textDirection: dir, style: pw.TextStyle(font: reg, fontSize: 10)),
      pw.SizedBox(height: 14),
      pw.Table(border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6), children: rows),
      pw.SizedBox(height: 10),
      pw.Text('${t('الإجمالي', 'Total')}: ${fmtMad(inv.total)}', textDirection: dir, style: pw.TextStyle(font: bold, fontSize: 14)),
      pw.Text('${t('الحالة', 'Status')}: ${inv.status == 'paid' ? t('مدفوعة', 'Paid') : t('غير مدفوعة', 'Unpaid')}', textDirection: dir, style: pw.TextStyle(font: reg, fontSize: 10)),
    ]),
  ));
  return doc.save();
}

Future<void> shareInvoicePdf(Invoice inv, CompanySettings s) async {
  final bytes = await buildInvoicePdf(inv, s);
  await Printing.sharePdf(bytes: bytes, filename: '${inv.id}.pdf');
}
