/// 全局常量
class AppInfo {
  static const String name = '团队通';
  static const String fullName = '团队通 TeamChat';
  static const String version = '1.0.0';
  static const String repoUrl = 'https://github.com/TEAMCHAT_OWNER/team-chat';
}

/// 加密相关常量
class CryptoConst {
  /// Argon2id 参数（KiB / 次数 / 并行度）
  static const int argon2Memory = 19456;
  static const int argon2Iterations = 2;
  static const int argon2Parallelism = 1;

  /// 私钥封装时的附加认证数据前缀
  static const String sealContext = 'teamchat/v1';

  /// 会话密钥封装的 HKDF info
  static const String wrapInfo = 'teamchat/cek-wrap/v1';

  /// 消息 AAD 前缀
  static const String msgAadPrefix = 'teamchat/msg/v1:';

  /// 附件加密文件头魔数 'TCA1'
  static const List<int> fileMagic = [0x54, 0x43, 0x41, 0x31];
  static const int fileVersion = 1;
  static const int chunkSize = 1024 * 1024;
}

/// 认证相关常量
class AuthConst {
  /// 注册时使用的虚拟邮箱域名（服务端不发送邮件）
  static const String emailDomain = 'teamchat.local';

  static String emailFor(String account) =>
      '${account.trim().toLowerCase()}@$emailDomain';
}

/// 分页与同步
class SyncConst {
  static const int pageSize = 50;
  static const Duration sweepInterval = Duration(hours: 1);
}

/// 服务端对象键名（与 SQL / Edge Function 保持一致）
class Db {
  static const String profiles = 'profiles';
  static const String conversations = 'conversations';
  static const String members = 'conversation_members';
  static const String messages = 'messages';
  static const String attachments = 'attachments';
  static const String keyRequests = 'key_requests';
  static const String attachmentBucket = 'attachments';
}
