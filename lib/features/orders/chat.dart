import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/i18n.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../core/util.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import 'order_files.dart';

/// محادثة طلب واحد (لحظية عبر Realtime).
class OrderChat extends StatefulWidget {
  final Order order;
  final double height;
  const OrderChat({super.key, required this.order, this.height = 420});

  @override
  State<OrderChat> createState() => _OrderChatState();
}

class _OrderChatState extends State<OrderChat> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;
  late final Stream<List<ChatMsg>> _stream = repo.watchMessages(widget.order.id);

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send({String? attachment}) async {
    final txt = _ctl.text.trim();
    if (txt.isEmpty && attachment == null) return;
    _ctl.clear();
    await repo.sendMessage(widget.order.id, txt, attachmentPath: attachment);
  }

  Future<void> _attach() async {
    final files = await pickFiles(context, multiple: false);
    if (files.isEmpty) return;
    final path = await repo.uploadFile('order-files', widget.order.id, files.first.name, files.first.bytes);
    await _send(attachment: path);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = P(context);
    final me = repo.userId;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      child: Column(children: [
        Expanded(
          child: StreamBuilder<List<ChatMsg>>(
            stream: _stream,
            builder: (context, snap) {
              final msgs = snap.data ?? <ChatMsg>[];
              if (msgs.length != _lastCount) {
                _lastCount = msgs.length;
                _toBottom();
              }
              if (!snap.hasData) return Center(child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5));
              if (msgs.isEmpty) return EmptyState(t('ابدأ المحادثة', 'Start the conversation'), icon: Icons.chat_bubble_outline);
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: msgs.length,
                itemBuilder: (context, i) {
                  final m = msgs[i];
                  final mine = m.senderId == me;
                  final isStaff = m.senderRole == 'staff' || m.senderRole == 'admin';
                  return Align(
                    alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      constraints: const BoxConstraints(maxWidth: 420),
                      decoration: BoxDecoration(
                        color: mine ? p.accent.fade(0.18) : p.surfaceHi,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: mine ? p.accent.fade(0.4) : p.borderSoft),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (!mine)
                          Text(
                            '${m.senderName ?? ''}${isStaff ? ' · M.A.K' : ''}',
                            style: ts(p, size: 10.5, w: FontWeight.w700, color: isStaff ? p.gold : p.muted),
                          ),
                        if (m.body.isNotEmpty) Text(m.body, style: ts(p, size: 13, color: p.fg)),
                        if (m.attachmentPath != null)
                          InkWell(
                            onTap: () => openStoredFile(context, 'order-files', m.attachmentPath!),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.attach_file, size: 15, color: p.accent),
                                const SizedBox(width: 4),
                                Flexible(child: Text(shortName(m.attachmentPath!), style: ts(p, size: 12, color: p.accent, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                              ]),
                            ),
                          ),
                        const SizedBox(height: 2),
                        Text(relTime(m.createdAt), style: ts(p, size: 9.5, color: p.subtle)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Divider(height: 1, color: p.border),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            IconBtn(Icons.attach_file, onTap: () async {
              try {
                await _attach();
              } catch (e) {
                if (mounted) toast(context, errMsg(e), error: true);
              }
            }),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ctl,
                minLines: 1,
                maxLines: 3,
                style: ts(p, size: 13, color: p.fg),
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: t('اكتب رسالة…', 'Type a message…'), hintStyle: ts(p, size: 12.5, color: p.subtle),
                  isDense: true, filled: true, fillColor: p.input,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.accent)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            MakButton(t('إرسال', 'Send'), icon: Icons.send, dense: true, onPressed: () => _send()),
          ]),
        ),
      ]),
    );
  }
}

/// زر واتساب (إن وُضع رقم في الإعدادات).
class WhatsAppButton extends StatelessWidget {
  final String orderId;
  const WhatsAppButton({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    return AsyncData<CompanySettings>(
      load: () => repo.getSettings(),
      builder: (context, s) {
        final phone = s.whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
        if (phone.isEmpty) return const SizedBox();
        return MakButton(t('واتساب', 'WhatsApp'), icon: Icons.chat, kind: 'ghost', dense: true, onPressed: () async {
          final msg = Uri.encodeComponent('${t('بخصوص الطلب', 'Regarding order')} $orderId');
          await launchUrl(Uri.parse('https://wa.me/$phone?text=$msg'), mode: LaunchMode.externalApplication);
        });
      },
    );
  }
}
