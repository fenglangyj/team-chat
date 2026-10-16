import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/constants.dart';
import '../models/models.dart';
import '../services/chat_crypto.dart';
import 'app_state.dart';

/// 单个会话的聊天控制器：内存缓存 + 懒加载分页 + 实时消息
class ChatController extends ChangeNotifier {
  final AppState app;
  final String conversationId;

  ChatController(this.app, this.conversationId);

  /// 从旧到新
  final List<Message> messages = [];
  bool hasMore = true;
  bool loading = false;
  bool sending = false;
  double? uploadProgress;
  String? uploadName;
  String? error;

  RealtimeChannel? _channel;
  bool _disposed = false;

  SupabaseClient get client => app.session!.client;

  bool get waitingKey => app.session!.cek(conversationId) == null;

  // ---------- 生命周期 ----------

  Future<void> init() async {
    if (waitingKey) {
      await app.conversations?.requestKeyFor(conversationId);
    }
    await loadMore(initial: true);
    _subscribe();
  }

  Future<void> loadMore({bool initial = false}) async {
    if (loading || (!hasMore && !initial)) return;
    loading = true;
    error = null;
    _safeNotify();
    try {
      final cursor = messages.isEmpty ? null : messages.first;
      var query = client
          .from(Db.messages)
          .select()
          .eq('conversation_id', conversationId);
      if (cursor != null) {
        query = query.lt('created_at', cursor.createdAt.toUtc().toIso8601String());
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(SyncConst.pageSize);
      final page = rows.map(Message.fromRow).toList();
      hasMore = page.length == SyncConst.pageSize;

      final known = messages.map((m) => m.id).toSet();
      final fresh = page.where((m) => !known.contains(m.id)).toList();
      messages.insertAll(0, fresh.reversed);
      await _decryptMessages(fresh);
    } catch (e) {
      error = '加载失败：$e';
    } finally {
      loading = false;
      _safeNotify();
    }
  }

  Future<void> _decryptMessages(List<Message> list) async {
    final cek = app.session!.cek(conversationId);
    if (cek == null) return;
    for (final m in list) {
      if (m.payload != null) continue;
      try {
        m.payload = await ChatCrypto.decryptMessage(
            cek, conversationId, m.ciphertext, m.nonce);
      } catch (_) {
        // 解密失败保持占位符显示
      }
    }
  }

  Future<void> retryDecrypt() async {
    await _decryptMessages(messages);
    _safeNotify();
  }

  // ---------- 发送 ----------

  Future<String?> sendText(String text) async {
    final content = text.trim();
    if (content.isEmpty || sending) return null;
    final cek = app.session!.cek(conversationId);
    if (cek == null) return '会话密钥尚未就绪，请稍候再试';

    sending = true;
    _safeNotify();
    try {
      final enc = await ChatCrypto.encryptMessage(
          cek, conversationId, {'t': 'text', 'text': content});
      final row = await client
          .from(Db.messages)
          .insert({
            'conversation_id': conversationId,
            'sender_id': app.session!.me.id,
            'kind': 'text',
            'ciphertext': enc.ciphertext,
            'nonce': enc.nonce,
          })
          .select()
          .single();
      final msg = Message.fromRow(row);
      msg.payload = {'t': 'text', 'text': content};
      _append(msg);
      return null;
    } catch (e) {
      return '发送失败：$e';
    } finally {
      sending = false;
      _safeNotify();
    }
  }

  Future<String?> sendFile({
    required File file,
    required String name,
    required String mime,
    required int size,
    required bool isImage,
  }) async {
    if (sending) return null;
    final cek = app.session!.cek(conversationId);
    if (cek == null) return '会话密钥尚未就绪，请稍候再试';

    sending = true;
    uploadProgress = 0;
    uploadName = name;
    _safeNotify();
    try {
      final upload = await app.attachments.uploadEncrypted(
        conversationId: conversationId,
        fileName: name,
        mimeType: mime,
        size: size,
        source: file,
        onProgress: (p) {
          uploadProgress = p;
          _safeNotify();
        },
      );
      final enc = await ChatCrypto.encryptMessage(
          cek, conversationId, {'t': 'attach', ...upload.payload});
      final row = await client
          .from(Db.messages)
          .insert({
            'conversation_id': conversationId,
            'sender_id': app.session!.me.id,
            'kind': isImage ? 'image' : 'file',
            'ciphertext': enc.ciphertext,
            'nonce': enc.nonce,
            'attachment_id': upload.attachmentId,
          })
          .select()
          .single();
      final msg = Message.fromRow(row);
      msg.payload = upload.payload;
      _append(msg);

      await client
          .from(Db.attachments)
          .update({'message_id': row['id']}).eq('id', upload.attachmentId);
      return null;
    } catch (e) {
      return '发送失败：$e';
    } finally {
      sending = false;
      uploadProgress = null;
      uploadName = null;
      _safeNotify();
    }
  }

  // ---------- 清空 ----------

  Future<String?> clearHistory() async {
    try {
      await client.rpc('clear_conversation', params: {'conv': conversationId});
      messages.clear();
      hasMore = false;
      _safeNotify();
      // 附件清理在后台进行（失败由 sweep 兜底）
      await app.attachments.purgeConversation(conversationId);
      return null;
    } catch (e) {
      return '清空失败：$e';
    }
  }

  // ---------- 实时 ----------

  void _subscribe() {
    _channel = client
        .channel('teamchat:chat:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: Db.messages,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) async {
            final m = Message.fromRow(payload.newRecord);
            if (m.conversationId != conversationId) return;
            if (messages.any((x) => x.id == m.id)) return;
            await _decryptMessages([m]);
            _append(m);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: Db.messages,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final id = payload.oldRecord['id'] as String?;
            if (id == null) return;
            messages.removeWhere((m) => m.id == id);
            _safeNotify();
          },
        )
        .subscribe();
  }

  void _append(Message m) {
    if (messages.any((x) => x.id == m.id)) return;
    messages.add(m);
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_channel != null) {
      client.removeChannel(_channel!);
    }
    super.dispose();
  }
}
