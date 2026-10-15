import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'chat_crypto.dart';

/// 一次登录期间的运行态：身份密钥、已解封的会话密钥缓存（仅内存）
class UserSession {
  final SupabaseClient client;
  final SimpleKeyPair identity;
  final Uint8List publicKey;
  MemberProfile me;

  final Map<String, Uint8List> _cekCache = {};

  UserSession({
    required this.client,
    required this.identity,
    required this.publicKey,
    required this.me,
  });

  Uint8List? cek(String conversationId) => _cekCache[conversationId];

  void cacheCek(String conversationId, Uint8List cek) {
    _cekCache[conversationId] = cek;
  }

  void dropCek(String conversationId) => _cekCache.remove(conversationId);

  /// 由自己的 wrapped_key 解封会话密钥
  Future<Uint8List?> unlockCek(String conversationId, String wrappedKey) async {
    final cached = _cekCache[conversationId];
    if (cached != null) return cached;
    try {
      final cek = await ChatCrypto.unwrapCek(wrappedKey, identity);
      _cekCache[conversationId] = cek;
      return cek;
    } catch (_) {
      return null;
    }
  }

  /// 为他人（或自己）封装会话密钥
  Future<String> wrapCekFor(Uint8List cek, Uint8List recipientPublicKey) =>
      ChatCrypto.wrapCek(cek, recipientPublicKey);
}
