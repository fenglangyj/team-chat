import 'package:supabase_flutter/supabase_flutter.dart';

/// 包装 Supabase 客户端的初始化与切换
class SupabaseService {
  bool _initialized = false;

  bool get initialized => _initialized;

  Future<void> init(String url, String anonKey) async {
    if (_initialized) {
      try {
        await Supabase.instance.dispose();
      } catch (_) {
        // 已在关闭中的实例无需处理
      }
    }
    await Supabase.initialize(
      url: url,
      // 参数同时接受新版 Publishable key 与旧版 anon public key；
      // 保留 anonKey 以兼容较旧的 supabase_flutter（鸿蒙分支等）。
      // ignore: deprecated_member_use
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );
    _initialized = true;
  }

  SupabaseClient get client => Supabase.instance.client;

  bool get hasPersistedSession {
    if (!_initialized) return false;
    return client.auth.currentSession != null;
  }

  /// 连通性自检：地址或 KEY 无效会抛异常
  Future<void> probe() async {
    await Supabase.instance.client
        .from('profiles')
        .select('id')
        .limit(1);
  }
}
