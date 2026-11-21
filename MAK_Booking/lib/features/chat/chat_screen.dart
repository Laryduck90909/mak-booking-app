import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mak_booking/core/localization/app_localizations.dart';
import 'package:mak_booking/core/theme/app_theme.dart';
import 'package:mak_booking/models/chat_message.dart';
import 'package:mak_booking/providers/app_providers.dart';
import 'package:mak_booking/shared/widgets/common.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.requestId});
  final String requestId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    final user = ref.read(authControllerProvider).valueOrNull;
    if (body.isEmpty || user == null || _sending) return;
    setState(() => _sending = true);
    try {
      final queued = await ref
          .read(chatRepositoryProvider)
          .sendMessage(widget.requestId, user.id, body);
      _text.clear();
      ref.invalidate(messagesProvider(widget.requestId));
      if (mounted && queued) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.tr('messageQueued'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.requestId));
    final userId = ref.watch(authControllerProvider).valueOrNull?.id;
    ref.listen(messagesProvider(widget.requestId), (_, __) => _scrollDown());
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('chat'))),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ErrorState(
                    error: error,
                    onRetry: () =>
                        ref.invalidate(messagesProvider(widget.requestId))),
                data: (items) {
                  if (items.isEmpty) {
                    return EmptyState(
                      icon: Icons.forum_outlined,
                      title: context.tr('emptyChat'),
                      description: context.tr('designDesc'),
                    );
                  }
                  _scrollDown();
                  return ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _Bubble(
                        message: items[index],
                        mine: items[index].senderId == userId),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: MakColors.surface,
                border: Border(top: BorderSide(color: Color(0xFF28514E))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration:
                          InputDecoration(hintText: context.tr('messageHint')),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    iconSize: 26,
                    style:
                        IconButton.styleFrom(minimumSize: const Size(52, 52)),
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                    tooltip: context.tr('send'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: mine ? MakColors.peach : MakColors.surfaceHigh,
              borderRadius: BorderRadiusDirectional.only(
                topStart: const Radius.circular(18),
                topEnd: const Radius.circular(18),
                bottomStart: Radius.circular(mine ? 18 : 4),
                bottomEnd: Radius.circular(mine ? 4 : 18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message.body,
                    style: TextStyle(
                        color: mine ? MakColors.teal : MakColors.text,
                        height: 1.6)),
                if (message.pendingSync) ...[
                  const SizedBox(height: 4),
                  Icon(Icons.schedule_rounded,
                      size: 15, color: mine ? MakColors.teal : MakColors.muted),
                ],
              ],
            ),
          ),
        ),
      );
}
