import 'dart:convert';
import 'dart:typed_data';

import '../core/utils.dart';

/// 后端连接配置（本地保存）
class AppConfig {
  final String url;
  final String anonKey;

  const AppConfig({required this.url, required this.anonKey});

  Map<String, dynamic> toJson() => {'url': url, 'anonKey': anonKey};

  static AppConfig? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final url = json['url'] as String?;
    final key = json['anonKey'] as String?;
    if (url == null || key == null || url.isEmpty || key.isEmpty) return null;
    return AppConfig(url: url, anonKey: key);
  }

  String toStorageString() => jsonEncode(toJson());

  static AppConfig? fromStorageString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

/// 团队成员资料
class MemberProfile {
  final String id;
  final String account;
  final String nickname;
  final Uint8List publicKey;
  final String sealedPrivateKey;
  final String kdfSalt;
  final Map<String, dynamic> kdfParams;

  MemberProfile({
    required this.id,
    required this.account,
    required this.nickname,
    required this.publicKey,
    required this.sealedPrivateKey,
    required this.kdfSalt,
    required this.kdfParams,
  });

  factory MemberProfile.fromRow(Map<String, dynamic> row) => MemberProfile(
        id: row['id'] as String,
        account: row['account'] as String,
        nickname: row['nickname'] as String,
        publicKey: b64Decode(row['public_key'] as String),
        sealedPrivateKey: row['sealed_private_key'] as String,
        kdfSalt: row['kdf_salt'] as String,
        kdfParams: (row['kdf_params'] as Map?)?.cast<String, dynamic>() ??
            const {'m': 19456, 't': 2, 'p': 1},
      );
}

enum ConversationKind { direct, group }

/// 会话
class Conversation {
  final String id;
  final ConversationKind kind;
  final bool isDefaultGroup;
  final String? nameCipher;
  final String? nameNonce;
  final String createdBy;
  final DateTime createdAt;

  Conversation({
    required this.id,
    required this.kind,
    required this.isDefaultGroup,
    required this.nameCipher,
    required this.nameNonce,
    required this.createdBy,
    required this.createdAt,
  });

  factory Conversation.fromRow(Map<String, dynamic> row) => Conversation(
        id: row['id'] as String,
        kind: row['kind'] == 'direct'
            ? ConversationKind.direct
            : ConversationKind.group,
        isDefaultGroup: row['is_default_group'] as bool? ?? false,
        nameCipher: row['name_cipher'] as String?,
        nameNonce: row['name_nonce'] as String?,
        createdBy: row['created_by'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}

/// 会话成员（含我的密钥槽位状态）
class ConvMember {
  final String conversationId;
  final String userId;
  final String? wrappedKey;
  final String? keyNonce;
  final DateTime joinedAt;

  ConvMember({
    required this.conversationId,
    required this.userId,
    required this.wrappedKey,
    required this.keyNonce,
    required this.joinedAt,
  });

  bool get hasKey => wrappedKey != null && wrappedKey!.isNotEmpty;

  factory ConvMember.fromRow(Map<String, dynamic> row) => ConvMember(
        conversationId: row['conversation_id'] as String,
        userId: row['user_id'] as String,
        wrappedKey: row['wrapped_key'] as String?,
        keyNonce: row['key_nonce'] as String?,
        joinedAt: DateTime.parse(row['joined_at'] as String),
      );
}

enum MessageKind { text, image, file }

/// 消息（服务端密文 + 内存中的解密缓存）
class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final MessageKind kind;
  final String ciphertext;
  final String nonce;
  final String? attachmentId;
  final DateTime createdAt;

  /// 仅存在于内存中的解密结果
  Map<String, dynamic>? payload;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    required this.ciphertext,
    required this.nonce,
    required this.attachmentId,
    required this.createdAt,
    this.payload,
  });

  factory Message.fromRow(Map<String, dynamic> row) => Message(
        id: row['id'] as String,
        conversationId: row['conversation_id'] as String,
        senderId: row['sender_id'] as String,
        kind: switch (row['kind'] as String) {
          'image' => MessageKind.image,
          'file' => MessageKind.file,
          _ => MessageKind.text,
        },
        ciphertext: row['ciphertext'] as String,
        nonce: row['nonce'] as String,
        attachmentId: row['attachment_id'] as String?,
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  String get text => (payload?['text'] as String?) ?? '';
  String get fileName => (payload?['name'] as String?) ?? '文件';
  String get fileMime => (payload?['mime'] as String?) ?? 'application/octet-stream';
  int get fileSize => (payload?['size'] as int?) ?? 0;

  /// 消息列表预览文案（未解密时为占位符）
  String get previewText {
    if (payload == null) {
      return switch (kind) {
        MessageKind.text => '🔒 加密消息',
        MessageKind.image => '🖼 [图片]',
        MessageKind.file => '📎 [文件]',
      };
    }
    return switch (kind) {
      MessageKind.text => text,
      MessageKind.image => '[图片]',
      MessageKind.file => '[文件] $fileName',
    };
  }
}
