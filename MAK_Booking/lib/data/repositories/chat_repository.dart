import 'package:mak_booking/core/config/app_config.dart';
import 'package:mak_booking/data/local/app_database.dart';
import 'package:mak_booking/data/local/connectivity_service.dart';
import 'package:mak_booking/data/remote/supabase_service.dart';
import 'package:mak_booking/models/chat_message.dart';
import 'package:uuid/uuid.dart';

class ChatRepository {
  ChatRepository(this._database, this._connectivity);
  final AppDatabase _database;
  final ConnectivityService _connectivity;

  Stream<List<ChatMessage>> watchMessages(String requestId) async* {
    if (!AppConfig.useBackend) {
      yield await _database.cachedMessages(requestId);
      return;
    }
    try {
      final query = SupabaseService.client
          .from('messages')
          .stream(primaryKey: ['id'])
          .eq('request_id', requestId)
          .order('created_at');
      await for (final rows in query) {
        final messages = rows.map(ChatMessage.fromMap).toList();
        await _database.cacheMessages(messages);
        final pending = (await _database.cachedMessages(requestId))
            .where((message) => message.pendingSync);
        yield [...messages, ...pending];
      }
    } catch (_) {
      yield await _database.cachedMessages(requestId);
    }
  }

  Future<bool> sendMessage(
      String requestId, String senderId, String body) async {
    final message = ChatMessage(
      id: const Uuid().v4(),
      requestId: requestId,
      senderId: senderId,
      body: body.trim(),
      clientRef: const Uuid().v4(),
      createdAt: DateTime.now().toUtc(),
    );
    if (!AppConfig.useBackend) {
      await _database.cacheMessages([message]);
      return false;
    }
    if (!await _connectivity.isOnline) {
      await _queue(message);
      return true;
    }
    try {
      await _send(message);
      return false;
    } catch (_) {
      if (!await _connectivity.isOnline) {
        await _queue(message);
        return true;
      }
      rethrow;
    }
  }

  Future<void> _send(ChatMessage message) async {
    final row = await SupabaseService.client
        .from('messages')
        .upsert(message.toMap(), onConflict: 'sender_id,client_ref')
        .select()
        .single();
    await _database.cacheMessages([ChatMessage.fromMap(row)]);
  }

  Future<void> _queue(ChatMessage message) async {
    final pending = ChatMessage(
      id: message.id,
      requestId: message.requestId,
      senderId: message.senderId,
      body: message.body,
      createdAt: message.createdAt,
      clientRef: message.clientRef,
      pendingSync: true,
    );
    await _database.cacheMessages([pending]);
    await _database.enqueue(message.id, 'message', pending.toJson());
  }
}
