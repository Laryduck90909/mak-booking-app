import 'dart:typed_data';

import 'package:storage_client/storage_client.dart' show FileOptions;

import 'package:mak_booking/core/config/app_config.dart';
import 'package:mak_booking/data/local/app_database.dart';
import 'package:mak_booking/data/local/connectivity_service.dart';
import 'package:mak_booking/data/remote/supabase_service.dart';
import 'package:mak_booking/models/app_user.dart';
import 'package:mak_booking/models/chat_message.dart';
import 'package:mak_booking/models/contract.dart';
import 'package:mak_booking/models/design_request.dart';

class RequestRepository {
  RequestRepository(this._database, this._connectivity);
  final AppDatabase _database;
  final ConnectivityService _connectivity;

  Future<bool> submitRequest(DesignRequest request) async {
    if (!AppConfig.useBackend) {
      await _database.cacheRequest(request);
      return false;
    }
    if (!await _connectivity.isOnline) {
      await _queueRequest(request);
      return true;
    }
    try {
      await _sendRequest(request);
      return false;
    } catch (_) {
      if (!await _connectivity.isOnline) {
        await _queueRequest(request);
        return true;
      }
      rethrow;
    }
  }

  Future<void> _queueRequest(DesignRequest request) async {
    final pending = request.copyWith(pendingSync: true);
    await _database.cacheRequest(pending);
    await _database.enqueue(request.id, 'request', pending.toJson());
  }

  Future<DesignRequest> _sendRequest(DesignRequest request) async {
    final payload = request.toSupabase()
      ..['status'] = 'draft'
      ..['submitted_at'] = null;
    await SupabaseService.client
        .from('requests')
        .upsert(payload, onConflict: 'id');
    final items = request.items
        .map((item) => {'request_id': request.id, ...item.toMap()})
        .toList();
    if (items.isNotEmpty) {
      await SupabaseService.client
          .from('request_items')
          .upsert(items, onConflict: 'request_id,item_key');
    }
    final result = await SupabaseService.client.rpc(
      'submit_request',
      params: {'p_request_id': request.id},
    );
    final saved =
        DesignRequest.fromMap(Map<String, dynamic>.from(result as Map));
    await _database.cacheRequest(saved);
    return saved;
  }

  Stream<List<DesignRequest>> watchRequests(AppUser user) async* {
    if (!AppConfig.useBackend) {
      yield await _database.cachedRequests();
      return;
    }
    try {
      final stream =
          SupabaseService.client.from('requests').stream(primaryKey: ['id']);
      final query = user.isAdmin
          ? stream.order('created_at')
          : stream.eq('client_id', user.id).order('created_at');
      await for (final rows in query) {
        final requests = rows.map(DesignRequest.fromMap).toList();
        await _database.cacheRequests(requests);
        final pending = (await _database.cachedRequests(
                clientId: user.isAdmin ? null : user.id))
            .where((request) => request.pendingSync);
        yield [...requests, ...pending];
      }
    } catch (_) {
      yield await _database.cachedRequests(
          clientId: user.isAdmin ? null : user.id);
    }
  }

  Future<DesignRequest?> getRequest(String id) async {
    if (AppConfig.useBackend && await _connectivity.isOnline) {
      try {
        final row = await SupabaseService.client
            .from('requests')
            .select('*, profiles(full_name)')
            .eq('id', id)
            .single();
        final request = DesignRequest.fromMap(row);
        await _database.cacheRequest(request);
        return request;
      } catch (_) {
        return _database.cachedRequest(id);
      }
    }
    return _database.cachedRequest(id);
  }

  Future<int> syncPending() async {
    if (!AppConfig.useBackend || !await _connectivity.isOnline) return 0;
    var synced = 0;
    for (final row in await _database.outbox()) {
      final id = row['id'] as int;
      try {
        if (row['type'] == 'request') {
          final request = DesignRequest.fromJson(row['payload'] as String);
          await _sendRequest(request);
        } else if (row['type'] == 'message') {
          final message = ChatMessage.fromJson(row['payload'] as String);
          final result = await SupabaseService.client
              .from('messages')
              .upsert(message.toMap(), onConflict: 'sender_id,client_ref')
              .select()
              .single();
          await _database.cacheMessages([ChatMessage.fromMap(result)]);
        }
        await _database.removeOutbox(id);
        synced++;
      } catch (_) {
        break;
      }
    }
    return synced;
  }

  Future<MakContract?> getContract(DesignRequest request) async {
    if (!AppConfig.useBackend) return demoContract(request);
    final row = await SupabaseService.client
        .from('contracts')
        .select()
        .eq('request_id', request.id)
        .maybeSingle();
    return row == null ? null : MakContract.fromMap(row);
  }

  Future<MakContract> createAndSendContract(DesignRequest request) async {
    if (!AppConfig.useBackend) return demoContract(request);
    final body = contractBodies(request);
    final row = await SupabaseService.client
        .from('contracts')
        .upsert({
          'request_id': request.id,
          'version': 1,
          'body_ar': body.$1,
          'body_en': body.$2,
          'total': request.total,
          'deposit_amount': request.deposit,
          'currency': 'MAD',
          'status': 'sent',
        }, onConflict: 'request_id')
        .select()
        .single();
    await SupabaseService.client
        .from('requests')
        .update({'status': 'awaiting_contract'}).eq('id', request.id);
    return MakContract.fromMap(row);
  }

  Future<MakContract> signContract(
    MakContract contract,
    DesignRequest request,
    Uint8List signature,
  ) async {
    if (!AppConfig.useBackend) {
      return MakContract(
        id: contract.id,
        requestId: contract.requestId,
        bodyAr: contract.bodyAr,
        bodyEn: contract.bodyEn,
        total: contract.total,
        deposit: contract.deposit,
        status: 'signed',
        signedAt: DateTime.now(),
      );
    }
    final path = '${request.id}/signature.png';
    await SupabaseService.client.storage
        .from('contract-signatures')
        .uploadBinary(
          path,
          signature,
          fileOptions:
              const FileOptions(contentType: 'image/png', upsert: true),
        );
    final result = await SupabaseService.client.rpc(
      'sign_contract',
      params: {'p_contract_id': contract.id, 'p_signature_path': path},
    );
    return MakContract.fromMap(Map<String, dynamic>.from(result as Map));
  }

  static MakContract demoContract(DesignRequest request) {
    final body = contractBodies(request);
    return MakContract(
      id: '00000000-0000-4000-8000-000000000010',
      requestId: request.id,
      bodyAr: body.$1,
      bodyEn: body.$2,
      total: request.total,
      deposit: request.deposit,
      status: 'sent',
    );
  }

  static (String, String) contractBodies(DesignRequest request) => (
        '''عقد خدمات تصميم — M.A.K\n\nرقم الطلب: ${request.displayNumber}\n\nتلتزم M.A.K بتنفيذ خدمات التصميم الموضحة في الطلب وفق البريف المعتمد، وتلتزم الجهة الطالبة بتقديم المحتوى والاعتمادات في وقتها.\n\nقيمة المشروع: ${request.total.toStringAsFixed(2)} درهم مغربي.\nالعربون: ${request.deposit.toStringAsFixed(2)} درهم مغربي (10٪)، وهو مطلوب لبدء التنفيذ وغير قابل للاسترداد بعد بدء العمل.\nالمتبقي: ${request.remaining.toStringAsFixed(2)} درهم مغربي ويستحق قبل تسليم الملفات النهائية.\n\nيشمل العرض جولتي تعديلات معقولتين ضمن البريف. أي توسع في النطاق يُسعّر ويُعتمد كتابياً. لا تُسلّم الملفات المصدرية قبل سداد كامل المبلغ. بتوقيع هذا العقد يقر الطرفان بالاطلاع على البنود والموافقة عليها.''',
        '''M.A.K Design Services Agreement\n\nRequest: ${request.displayNumber}\n\nM.A.K will deliver the design services listed in the approved request and brief. The client will provide content and approvals on time.\n\nProject value: MAD ${request.total.toStringAsFixed(2)}.\nDeposit: MAD ${request.deposit.toStringAsFixed(2)} (10%), required to begin and non-refundable after work starts.\nBalance: MAD ${request.remaining.toStringAsFixed(2)}, due before final file delivery.\n\nThis quote includes two reasonable revision rounds within the brief. Scope expansion must be quoted and approved in writing. Source files are delivered after full payment. By signing, both parties confirm that they have read and accepted these terms.'''
      );
}
