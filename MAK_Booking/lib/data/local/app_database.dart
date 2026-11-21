import 'dart:io' show Platform;

import 'package:mak_booking/models/chat_message.dart';
import 'package:mak_booking/models/design_request.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

class AppDatabase {
  AppDatabase._();
  static final instance = AppDatabase._();
  Database? _db;

  Future<void> init() async {
    if (_db != null) return;
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final directory = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(directory.path, 'mak_booking.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_requests(
            id TEXT PRIMARY KEY,
            client_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cached_messages(
            id TEXT PRIMARY KEY,
            request_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE outbox(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_key TEXT UNIQUE NOT NULL,
            type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Database get db {
    final database = _db;
    if (database == null) throw StateError('Database has not been initialised');
    return database;
  }

  Future<void> cacheRequest(DesignRequest request) async {
    await db.insert(
      'cached_requests',
      {
        'id': request.id,
        'client_id': request.clientId,
        'payload': request.toJson(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> cacheRequests(Iterable<DesignRequest> requests) async {
    final batch = db.batch();
    for (final request in requests) {
      batch.insert(
        'cached_requests',
        {
          'id': request.id,
          'client_id': request.clientId,
          'payload': request.toJson(),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<DesignRequest>> cachedRequests({String? clientId}) async {
    final rows = await db.query(
      'cached_requests',
      where: clientId == null ? null : 'client_id = ?',
      whereArgs: clientId == null ? null : [clientId],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((row) => DesignRequest.fromJson(row['payload'] as String))
        .toList();
  }

  Future<DesignRequest?> cachedRequest(String id) async {
    final rows = await db.query('cached_requests',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty
        ? null
        : DesignRequest.fromJson(rows.first['payload'] as String);
  }

  Future<void> cacheMessages(Iterable<ChatMessage> messages) async {
    final batch = db.batch();
    for (final message in messages) {
      batch.insert(
        'cached_messages',
        {
          'id': message.id,
          'request_id': message.requestId,
          'payload': message.toJson(),
          'created_at': message.createdAt.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatMessage>> cachedMessages(String requestId) async {
    final rows = await db.query(
      'cached_messages',
      where: 'request_id = ?',
      whereArgs: [requestId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => ChatMessage.fromJson(row['payload'] as String))
        .toList();
  }

  Future<void> enqueue(String key, String type, String payload) async {
    await db.insert(
      'outbox',
      {
        'entity_key': key,
        'type': type,
        'payload': payload,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> outbox() =>
      db.query('outbox', orderBy: 'created_at ASC');

  Future<void> removeOutbox(int id) async {
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> pendingCount() async {
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM outbox')) ??
        0;
  }
}
