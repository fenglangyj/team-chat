import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

import '../core/constants.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/chat_crypto.dart';
import '../services/session.dart';
import 'app_state.dart';

/// 会话列表 / 成员 / 密钥分发 / 实时同步
class ConversationsController extends ChangeNotifier {
  final AppState app;
  ConversationsController(this.app);

  List<Conversation> conversations = [];
  final Map<String, List<ConvMember>> membersByConv = {};
  final Map<String, MemberProfile> profiles = {};
  final Map<String, Message> lastMessages = {};
  final Map<String, String> _groupNames = {};
  final Set<String> _keyFlights = {};

  RealtimeChannel? _convChannel;
  RealtimeChannel? _memberChannel;
  RealtimeChannel? _keyReqChannel;
  RealtimeChannel? _msgChannel;

  UserSession get session => app.session!;
  SupabaseClient get client => session.client;

  // ---------- 加载 ----------

  Future<void> load() async {
    await refreshProfiles();
    await refreshConversations();
    await refreshPreviews();
    _subscribe();
  }

  Future<void> refreshProfiles() async {
    final rows = await client.from(Db.profiles).select();
    profiles.clear();
    for (final r in rows) {
      final p = MemberProfile.fromRow(r);
      profiles[p.id] = p;
    }
    notifyListeners();
  }

  Future<void> refreshConversations() async {
    final convRows = await client
        .from(Db.conversations)
        .select()
        .order('created_at', ascending: true);
    conversations = convRows.map(Conversation.fromRow).toList();

    membersByConv.clear();
    if (conversations.isNotEmpty) {
      final ids = conversations.map((c) => c.id).toList();
      final memRows = await client
          .from(Db.members)
          .select()
          .inFilter('conversation_id', ids);
      for (final r in memRows) {
        final m = ConvMember.fromRow(r);
        membersByConv.putIfAbsent(m.conversationId, () => []).add(m);
      }
    }

    for (final c in conversations) {
      final myRow = myMemberRow(c.id);
      if (myRow != null && myRow.hasKey) {
        await session.unlockCek(c.id, myRow.wrappedKey!);
      }
    }
    await _resolveGroupNames();
    notifyListeners();
  }

  Future<void> refreshPreviews() async {
    if (conversations.isEmpty) return;
    final ids = conversations.map((c) => c.id).toList();
    final rows = await client
        .from(Db.messages)
        .select()
        .inFilter('conversation_id', ids)
        .order('created_at', ascending: false)
        .limit(300);
    lastMessages.clear();
    for (final r in rows) {
      final m = Message.fromRow(r);
      lastMessages.putIfAbsent(m.conversationId, () => m);
    }
    await decryptPreviews();
    notifyListeners();
  }

  Future<void> decryptPreviews() async {
    for (final entry in lastMessages.entries) {
      final cek = session.cek(entry.key);
      if (cek == null || entry.value.payload != null) continue;
      try {
        entry.value.payload = await ChatCrypto.decryptMessage(
          cek,
          entry.key,
          entry.value.ciphertext,
          entry.value.nonce,
        );
      } catch (_) {}
    }
  }

  // ---------- 名称 ----------

  String displayName(Conversation c) {
    if (c.isDefaultGroup) return '全员群';
    if (c.kind == ConversationKind.direct) {
      final peerId = membersByConv[c.id]
          ?.where((m) => m.userId != session.me.id)
          .map((m) => m.userId)
          .firstOrNull;
      if (peerId == null) return '私聊';
      return profiles[peerId]?.nickname ?? '私聊';
    }
    if (_groupNames.containsKey(c.id)) return _groupNames[c.id]!;
    return session.cek(c.id) == null ? '群聊（等待密钥）' : '群聊';
  }

  Future<void> _resolveGroupNames() async {
    for (final c in conversations) {
      if (c.kind != ConversationKind.group || c.nameCipher == null) continue;
      if (_groupNames.containsKey(c.id)) continue;
      final cek = session.cek(c.id);
      if (cek == null) continue;
      try {
        final payload = await ChatCrypto.decryptMessage(
            cek, 'group-name', c.nameCipher!, c.nameNonce!);
        _groupNames[c.id] = (payload['n'] as String?) ?? '群聊';
      } catch (_) {}
    }
  }

  List<Conversation> get sorted {
    final list = [...conversations];
    list.sort((a, b) {
      if (a.isDefaultGroup != b.isDefaultGroup) return a.isDefaultGroup ? -1 : 1;
      final la = lastMessages[a.id]?.createdAt ?? a.createdAt;
      final lb = lastMessages[b.id]?.createdAt ?? b.createdAt;
      return lb.compareTo(la);
    });
    return list;
  }

  // ---------- 成员与密钥 ----------

  ConvMember? myMemberRow(String convId) => membersByConv[convId]
      ?.where((m) => m.userId == session.me.id)
      .firstOrNull;

  List<MemberProfile> membersOf(String convId) => (membersByConv[convId] ?? [])
      .map((m) => profiles[m.userId])
      .whereType<MemberProfile>()
      .toList();

  bool hasKeyFor(String convId) => session.cek(convId) != null;

  /// 请求他人分发密钥（幂等）
  Future<void> requestKeyFor(String convId) async {
    if (hasKeyFor(convId)) return;
    final myRow = myMemberRow(convId);
    if (myRow != null && myRow.hasKey) {
      await session.unlockCek(convId, myRow.wrappedKey!);
      if (hasKeyFor(convId)) {
        notifyListeners();
        return;
      }
    }
    final flightKey = 'req:$convId';
    if (_keyFlights.contains(flightKey)) return;
    _keyFlights.add(flightKey);
    try {
      await client.from(Db.keyRequests).upsert(
        {'conversation_id': convId, 'user_id': session.me.id},
        onConflict: 'conversation_id,user_id',
        ignoreDuplicates: true,
      );
    } catch (_) {
    } finally {
      _keyFlights.remove(flightKey);
    }
  }

  Future<void> _respondToKeyRequest(String convId, String userId) async {
    if (userId == session.me.id) return;
    final cek = session.cek(convId);
    if (cek == null) return;
    final flightKey = 'provide:$convId:$userId';
    if (_keyFlights.contains(flightKey)) return;
    final target = profiles[userId];
    if (target == null) return;
    _keyFlights.add(flightKey);
    try {
      final wrapped = await session.wrapCekFor(cek, target.publicKey);
      await client.rpc('provide_key', params: {
        'conv': convId,
        'target': userId,
        'new_wrapped_key': wrapped,
        'new_key_nonce': '',
      });
    } catch (_) {
    } finally {
      _keyFlights.remove(flightKey);
    }
  }

  // ---------- 创建会话 ----------

  Future<Conversation> startDirect(MemberProfile peer) async {
    final existing = conversations
        .where((c) =>
            c.kind == ConversationKind.direct &&
            (membersByConv[c.id] ?? const []).any((m) => m.userId == peer.id))
        .firstOrNull;
    if (existing != null) {
      await _ensureKey(existing.id);
      return existing;
    }

    final cek = randomBytes(32);
    final wrappedMe = await session.wrapCekFor(cek, session.publicKey);
    final wrappedPeer = await session.wrapCekFor(cek, peer.publicKey);
    final convId = await client.rpc('create_direct_conversation', params: {
      'peer': peer.id,
      'my_wrapped_key': wrappedMe,
      'my_key_nonce': '',
      'peer_wrapped_key': wrappedPeer,
      'peer_key_nonce': '',
    }) as String;
    session.cacheCek(convId, cek);
    await _refreshConversation(convId);
    return conversations.firstWhere((c) => c.id == convId);
  }

  Future<Conversation> createGroup(
    String name,
    List<MemberProfile> selected,
  ) async {
    final cek = randomBytes(32);
    final nameEnc =
        await ChatCrypto.encryptMessage(cek, 'group-name', {'n': name});

    final items = <Map<String, dynamic>>[
      {
        'user_id': session.me.id,
        'wrapped_key': await session.wrapCekFor(cek, session.publicKey),
        'key_nonce': '',
      },
    ];
    for (final m in selected) {
      items.add({
        'user_id': m.id,
        'wrapped_key': await session.wrapCekFor(cek, m.publicKey),
        'key_nonce': '',
      });
    }

    final convId = await client.rpc('create_group_conversation', params: {
      'group_name_cipher': nameEnc.ciphertext,
      'group_name_nonce': nameEnc.nonce,
      'members': items,
    }) as String;
    session.cacheCek(convId, cek);
    _groupNames[convId] = name;
    await _refreshConversation(convId);
    return conversations.firstWhere((c) => c.id == convId);
  }

  Future<String?> addMembers(String convId, List<MemberProfile> users) async {
    final cek = session.cek(convId);
    if (cek == null) return '当前会话密钥尚未就绪';
    try {
      final items = <Map<String, dynamic>>[];
      for (final u in users) {
        items.add({
          'user_id': u.id,
          'wrapped_key': await session.wrapCekFor(cek, u.publicKey),
          'key_nonce': '',
        });
      }
      await client
          .rpc('add_group_members', params: {'conv': convId, 'members': items});
      await _refreshMembers(convId);
      notifyListeners();
      return null;
    } catch (e) {
      return '添加失败：$e';
    }
  }

  Future<void> _refreshConversation(String convId) async {
    if (!conversations.any((c) => c.id == convId)) {
      final row = await client
          .from(Db.conversations)
          .select()
          .eq('id', convId)
          .maybeSingle();
      if (row != null) conversations.add(Conversation.fromRow(row));
    }
    await _refreshMembers(convId);
    await _resolveGroupNames();
    await _ensureKey(convId);
    notifyListeners();
  }

  Future<void> _refreshMembers(String convId) async {
    final rows = await client
        .from(Db.members)
        .select()
        .eq('conversation_id', convId);
    membersByConv[convId] = rows.map(ConvMember.fromRow).toList();
  }

  Future<void> _ensureKey(String convId) async {
    final myRow = myMemberRow(convId);
    if (myRow == null) return;
    if (myRow.hasKey) {
      session.dropCek(convId);
      await session.unlockCek(convId, myRow.wrappedKey!);
    } else if (!hasKeyFor(convId)) {
      await requestKeyFor(convId);
    }
  }

  // ---------- 实时订阅 ----------

  void _subscribe() {
    _convChannel = client
        .channel('teamchat:conversations')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: Db.conversations,
          callback: (payload) async {
            final c = Conversation.fromRow(payload.newRecord);
            if (conversations.any((x) => x.id == c.id)) return;
            conversations.add(c);
            await _refreshMembers(c.id);
            await _ensureKey(c.id);
            await _resolveGroupNames();
            notifyListeners();
          },
        )
        .subscribe();

    _memberChannel = client
        .channel('teamchat:members')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: Db.members,
          callback: _onMemberChanged,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: Db.members,
          callback: _onMemberChanged,
        )
        .subscribe();

    _keyReqChannel = client
        .channel('teamchat:keyreq')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: Db.keyRequests,
          callback: (payload) async {
            final convId = payload.newRecord['conversation_id'] as String?;
            final userId = payload.newRecord['user_id'] as String?;
            if (convId == null || userId == null) return;
            await _respondToKeyRequest(convId, userId);
          },
        )
        .subscribe();

    _msgChannel = client
        .channel('teamchat:previews')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: Db.messages,
          callback: (payload) async {
            final m = Message.fromRow(payload.newRecord);
            lastMessages[m.conversationId] = m;
            await decryptPreviews();
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> _onMemberChanged(PostgresChangePayload payload) async {
    final m = ConvMember.fromRow(payload.newRecord);
    final list = membersByConv.putIfAbsent(m.conversationId, () => []);
    final idx = list.indexWhere((x) => x.userId == m.userId);
    if (idx >= 0) {
      list[idx] = m;
    } else {
      list.add(m);
    }

    if (m.userId == session.me.id && m.hasKey && !hasKeyFor(m.conversationId)) {
      await session.unlockCek(m.conversationId, m.wrappedKey!);
    }
    if (m.userId != session.me.id && !m.hasKey) {
      await _respondToKeyRequest(m.conversationId, m.userId);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final ch in [_convChannel, _memberChannel, _keyReqChannel, _msgChannel]) {
      if (ch != null) {
        client.removeChannel(ch);
      }
    }
    super.dispose();
  }
}
