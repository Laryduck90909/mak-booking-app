import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'pdf_service.dart';
import 'signature_pad.dart';

Color contractColor(Palette p, String status) {
  switch (status) {
    case 'signed': return p.green;
    case 'awaiting_client': return p.amber;
    case 'awaiting_admin': return p.violet;
    case 'void': return p.red;
    default: return p.muted;
  }
}

/// يفتح العقد في نافذة (يتحدّث تلقائياً بعد التوقيع/التعديل).
Future<void> showContractDialog(BuildContext context, Contract c) {
  return showPanelDialog<void>(
    context,
    title: '${c.isAddendum ? t('ملحق', 'Addendum') : t('عقد', 'Contract')} ${c.id}',
    width: 760,
    builder: (ctx) => ContractBody(contractId: c.id, orderId: c.orderId, initial: c),
  );
}

class ContractBody extends StatefulWidget {
  final String contractId, orderId;
  final Contract initial;
  const ContractBody({super.key, required this.contractId, required this.orderId, required this.initial});

  @override
  State<ContractBody> createState() => _ContractBodyState();
}

class _ContractBodyState extends State<ContractBody> {
  late bool _ar = isAr;
  bool _agree = false;

  Future<Contract> _load() async {
    final l = await repo.listContracts(orderId: widget.orderId);
    for (final c in l) {
      if (c.id == widget.contractId) return c;
    }
    return widget.initial;
  }

  Future<void> _signClient(Contract c) async {
    final sig = await showSignatureDialog(context, title: t('توقيع العميل', 'Client signature'));
    if (sig == null) return;
    await repo.signAsClient(c.id, sig);
    if (mounted) toast(context, t('تم توقيعك — بانتظار توقيع المدير', 'Signed — awaiting admin signature'));
  }

  Future<void> _signAdmin(Contract c) async {
    final sig = await showSignatureDialog(context, title: t('توقيع M.A.K (المدير)', 'M.A.K signature (Admin)'));
    if (sig == null) return;
    await repo.signAsAdmin(c.id, sig);
    if (mounted) toast(context, t('العقد موقّع من الطرفين — بدأ التنفيذ', 'Fully signed — execution started'));
  }

  Future<void> _edit(Contract c) async {
    final r = await showPanelDialog<({String ar, String en})>(
      context,
      title: t('تعديل نص العقد', 'Edit contract text'),
      width: 820,
      builder: (ctx) => _ContractEditor(ar: c.rendered_ar, en: c.rendered_en),
    );
    if (r == null) return;
    await repo.updateContractText(c.id, r.ar, r.en);
    if (mounted) toast(context, t('تم حفظ التعديل', 'Saved'));
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final role = appState.role;
    final isStaff = role == 'staff' || role == 'admin';
    return AsyncData<Contract>(
      load: _load,
      builder: (context, c) {
        final canClientSign = role == 'client' && c.status == 'awaiting_client';
        final canAdminSign = role == 'admin' && c.status == 'awaiting_admin';
        final editable = isStaff && (c.status == 'draft' || c.status == 'awaiting_client');
        final text = _ar ? c.rendered_ar : c.rendered_en;
        final clientSig = signatureBytes(c.clientSignature);
        final adminSig = signatureBytes(c.adminSignature);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Pill(c.statusText, color: contractColor(p, c.status)),
            if (c.isAddendum) Pill(t('ملحق', 'Addendum'), color: p.blue),
            SelectChip('العربية', selected: _ar, onTap: () => setState(() => _ar = true)),
            SelectChip('English', selected: !_ar, onTap: () => setState(() => _ar = false)),
          ]),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 360),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.input, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
                child: SelectableText(text, style: ts(p, size: 12.5, color: p.fg, height: 1.7)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _SigTile(label: t('توقيع العميل', 'Client'), bytes: clientSig),
            _SigTile(label: t('توقيع M.A.K', 'M.A.K'), bytes: adminSig, when: c.signed ? fmtDateTime(c.signedAt) : null),
          ]),
          const SizedBox(height: 14),
          if (canClientSign) ...[
            InkWell(
              onTap: () => setState(() => _agree = !_agree),
              child: Row(children: [
                Icon(_agree ? Icons.check_box : Icons.check_box_outline_blank, color: p.accent, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(t('قرأتُ العقد بالنسختين وأوافق على جميع موادّه', 'I have read both versions and agree to all articles'), style: ts(p, size: 12.5, color: p.fg))),
              ]),
            ),
            const SizedBox(height: 10),
          ],
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (canClientSign) MakButton(t('وقّع العقد', 'Sign contract'), icon: Icons.draw, onPressed: _agree ? () => _signClient(c) : null),
            if (canAdminSign) MakButton(t('وقّع كمدير', 'Sign as admin'), icon: Icons.verified, onPressed: () => _signAdmin(c)),
            if (editable) MakButton(t('تعديل النص', 'Edit text'), icon: Icons.edit, kind: 'ghost', onPressed: () => _edit(c)),
            if (isStaff && c.status == 'draft')
              MakButton(t('إرسال للعميل', 'Send to client'), icon: Icons.send, onPressed: () async {
                await repo.sendContractToClient(c.id);
                if (context.mounted) toast(context, t('أُرسل العقد للعميل', 'Sent to client'));
              }),
            if (isStaff && c.status != 'signed' && c.status != 'void')
              MakButton(t('إلغاء العقد', 'Void'), icon: Icons.block, kind: 'danger', onPressed: () async {
                if (await confirmDialog(context, t('إلغاء هذا العقد؟', 'Void this contract?'), danger: true)) {
                  await repo.voidContract(c.id);
                }
              }),
            MakButton('PDF', icon: Icons.picture_as_pdf, kind: 'ghost', onPressed: () => shareContractPdf(c)),
          ]),
        ]);
      },
    );
  }
}

class _SigTile extends StatelessWidget {
  final String label;
  final Uint8List? bytes;
  final String? when;
  const _SigTile({required this.label, required this.bytes, this.when});

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Container(
      width: 190, height: 110, padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF333333))),
        Expanded(
          child: Center(
            child: bytes == null
                ? Text(t('— غير موقّع —', '— unsigned —'), style: const TextStyle(fontSize: 11, color: Color(0xFF888888)))
                : Image.memory(bytes!, fit: BoxFit.contain),
          ),
        ),
        if (when != null) Text(when!, style: const TextStyle(fontSize: 9, color: Color(0xFF666666))),
      ]),
    );
  }
}

class _ContractEditor extends StatefulWidget {
  final String ar, en;
  const _ContractEditor({required this.ar, required this.en});
  @override
  State<_ContractEditor> createState() => _ContractEditorState();
}

class _ContractEditorState extends State<_ContractEditor> {
  late final _ar = TextEditingController(text: widget.ar);
  late final _en = TextEditingController(text: widget.en);

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('أي تعديل يخص هذا العقد فقط، ولا يُغيّر القالب العام.', 'Edits apply to this contract only, not the global template.'), style: ts(p, size: 12, color: p.muted)),
      const SizedBox(height: 10),
      MakField(controller: _ar, label: 'العربية', maxLines: 14, dir: TextDirection.rtl),
      const SizedBox(height: 10),
      MakField(controller: _en, label: 'English', maxLines: 14, dir: TextDirection.ltr),
      const SizedBox(height: 14),
      MakButton(t('حفظ', 'Save'), icon: Icons.save, onPressed: () => Navigator.pop(context, (ar: _ar.text, en: _en.text))),
    ]);
  }
}
