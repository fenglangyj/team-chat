import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;
import 'package:window_manager/window_manager.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import '../models/models.dart';
import '../services/attachment_service.dart';
import '../services/chat_crypto.dart';
import '../services/session.dart';
import '../services/sound_service.dart';
import '../services/supabase_service.dart';
import '../services/sweep_service.dart';
import 'conversations_controller.dart';

enum AppPhase { booting, setup, login, unlock, ready }

/// 桌面端窗口焦点监听：聚焦时清零当前会话未读；失焦时开始计未读并响铃
class _AppFocusListener with WindowListener {
  final AppState app;

  _AppFocusListener(this.app);

  @override
  void onWindowFocus() {
    app.conversations?.markWindowFocused();
  }

  @override
  void onWindowBlur() {
    app.conversations?.markWindowBlurred();
  }
}

/// 应用级状态：配置 -> 登录/解锁 -> 就绪
class AppState extends ChangeNotifier {
  static const String _configKey = 'teamchat.app_config';
  static const String _soundKey = 'teamchat.sound_enabled';

  final SupabaseService supa = SupabaseService();
  late final AttachmentService attachments = AttachmentService(
    client: () => supa.client,
    session: () => session!,
  );

  AppConfig? config;
  AppPhase phase = AppPhase.booting;
  UserSession? session;
  MemberProfile? unlockProfile;
  ConversationsController? conversations;
  SweepService? sweep;
  String? error;
  bool busy = false;
  bool soundEnabled = true;

  // ---------- 启动 ----------

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    soundEnabled = prefs.getBool(_soundKey) ?? true;
    SoundService.instance.enabled = soundEnabled;
    config = AppConfig.fromStorageString(prefs.getString(_configKey));
    if (config == null) {
      phase = AppPhase.setup;
      notifyListeners();
      return;
    }
    try {
      await supa.init(config!.url, config!.anonKey);
    } catch (_) {
      phase = AppPhase.setup;
      error = '初始化失败，请重新填写服务器配置';
      notifyListeners();
      return;
    }
    await _routeAfterInit();
  }

  Future<void> _routeAfterInit() async {
    if (supa.hasPersistedSession) {
      final profile = await _fetchMyProfile();
      if (profile == null) {
        await supa.client.auth.signOut();
        phase = AppPhase.login;
      } else {
        unlockProfile = profile;
        phase = AppPhase.unlock;
      }
    } else {
      phase = AppPhase.login;
    }
    notifyListeners();
  }

  Future<MemberProfile?> _fetchMyProfile() async {
    try {
      final user = supa.client.auth.currentUser;
      if (user == null) return null;
      final row = await supa.client
          .from(Db.profiles)
          .select()
          .eq('id', user.id)
          .maybeSingle();
      if (row == null) return null;
      return MemberProfile.fromRow(row);
    } catch (_) {
      return null;
    }
  }

  // ---------- 第一步：连接服务器 ----------

  Future<String?> connect(AppConfig cfg) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await supa.init(cfg.url, cfg.anonKey);
      await supa.probe();
      config = cfg;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, cfg.toStorageString());
      await _routeAfterInit();
      return null;
    } catch (e) {
      error = _friendly(e);
      return error;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---------- 注册 / 登录 / 解锁 ----------

  Future<String?> register({
    required String account,
    required String password,
    required String nickname,
  }) async {
    final acc = account.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(acc)) {
      return '账号需为 3~32 位字母、数字或下划线';
    }
    if (password.length < 6) return '密码至少 6 位';
    if (nickname.trim().isEmpty) return '请填写昵称';

    busy = true;
    error = null;
    notifyListeners();
    try {
      final identity = await ChatCrypto.generateIdentity();
      final pub = await ChatCrypto.publicKeyOf(identity);
      final salt = randomBytes(16);
      final params = _defaultKdfParams();
      final kek = await ChatCrypto.deriveKek(password, salt, params);
      final sealed = await ChatCrypto.sealPrivateSeed(
        await ChatCrypto.encodeKeyPairPrivate(identity),
        kek,
        acc,
      );

      final res = await supa.client.auth.signUp(
        email: AuthConst.emailFor(acc),
        password: password,
      );
      if (res.user == null) {
        return '注册失败：服务端未返回用户，请确认已正确部署';
      }
      if (res.session == null) {
        await supa.client.auth.signOut();
        return '服务端仍开启了邮箱验证：请在 Supabase 的 Authentication 设置中关闭 Confirm email 后重试';
      }

      try {
        await supa.client.from(Db.profiles).insert({
          'id': res.user!.id,
          'account': acc,
          'nickname': nickname.trim(),
          'public_key': b64Encode(pub),
          'sealed_private_key': sealed,
          'kdf_salt': b64Encode(salt),
          'kdf_params': params,
        });
      } on PostgrestException catch (e) {
        await supa.client.auth.signOut();
        if (e.code == '23505') return '账号已被占用，换一个吧';
        return '创建资料失败：${e.message}';
      }

      session = UserSession(
        client: supa.client,
        identity: identity,
        publicKey: pub,
        me: MemberProfile(
          id: res.user!.id,
          account: acc,
          nickname: nickname.trim(),
          publicKey: pub,
          sealedPrivateKey: sealed,
          kdfSalt: b64Encode(salt),
          kdfParams: params,
        ),
      );
      await _finishLogin();
      return null;
    } catch (e) {
      return _friendly(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> login({
    required String account,
    required String password,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await supa.client.auth.signInWithPassword(
        email: AuthConst.emailFor(account),
        password: password,
      );
      final profile = await _fetchMyProfile();
      if (profile == null) {
        await supa.client.auth.signOut();
        return '账号资料不存在（可能上次注册未完成），请重新注册';
      }
      final identity = await _unseal(profile, password);
      if (identity == null) {
        await supa.client.auth.signOut();
        return '密码错误';
      }
      session = UserSession(
        client: supa.client,
        identity: identity,
        publicKey: profile.publicKey,
        me: profile,
      );
      await _finishLogin();
      return null;
    } on AuthException catch (e) {
      return _friendly(e);
    } catch (e) {
      return _friendly(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 已有会话时，用密码解锁本地私钥
  Future<String?> unlock(String password) async {
    final profile = unlockProfile;
    if (profile == null) return '状态异常，请重新登录';
    busy = true;
    error = null;
    notifyListeners();
    try {
      final identity = await _unseal(profile, password);
      if (identity == null) return '密码错误';
      session = UserSession(
        client: supa.client,
        identity: identity,
        publicKey: profile.publicKey,
        me: profile,
      );
      await _finishLogin();
      return null;
    } catch (e) {
      return _friendly(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<SimpleKeyPair?> _unseal(MemberProfile profile, String password) async {
    final kek = await ChatCrypto.deriveKek(
      password,
      b64Decode(profile.kdfSalt),
      profile.kdfParams,
    );
    try {
      return await ChatCrypto.unsealPrivateSeed(
        profile.sealedPrivateKey,
        kek,
        profile.account,
      );
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  _AppFocusListener? _focusListener;

  void _attachFocusListener() {
    if (!_isDesktop || _focusListener != null) return;
    _focusListener = _AppFocusListener(this);
    try {
      windowManager.addListener(_focusListener!);
    } catch (_) {}
  }

  void _detachFocusListener() {
    final listener = _focusListener;
    if (listener == null) return;
    try {
      windowManager.removeListener(listener);
    } catch (_) {}
    _focusListener = null;
  }

  Future<void> _finishLogin() async {
    try {
      await _ensureDefaultGroup();
    } catch (_) {
      // 全员群建立失败不阻塞登录，重进应用时会重试
    }
    _attachFocusListener();
    sweep = SweepService(supa)..start();
    final controller = ConversationsController(this);
    conversations = controller;
    try {
      await controller.load();
    } catch (e) {
      error = _friendly(e);
    }
    phase = AppPhase.ready;
    notifyListeners();
  }

  /// 加入（必要时创建）全员群，并确保我持有会话密钥
  Future<void> _ensureDefaultGroup() async {
    final s = session!;
    final convId = await s.client.rpc(
      'join_default_group',
      params: {'my_wrapped_key': null, 'my_key_nonce': null},
    ) as String;

    final rows = await s.client
        .from(Db.members)
        .select()
        .eq('conversation_id', convId);
    final list = rows.map(ConvMember.fromRow).toList();
    final mine = list.firstWhere((m) => m.userId == s.me.id);

    if (mine.hasKey) {
      await s.unlockCek(convId, mine.wrappedKey!);
      return;
    }

    final others = list.where((m) => m.userId != s.me.id).toList();
    if (others.isEmpty) {
      // 团队第一位成员：自建会话密钥
      final cek = randomBytes(32);
      final wrapped = await s.wrapCekFor(cek, s.publicKey);
      await s.client.rpc('provide_key', params: {
        'conv': convId,
        'target': s.me.id,
        'new_wrapped_key': wrapped,
        'new_key_nonce': '',
      });
      s.cacheCek(convId, cek);
    } else {
      // 等待在线成员分发
      await s.client.from(Db.keyRequests).upsert(
        {'conversation_id': convId, 'user_id': s.me.id},
        onConflict: 'conversation_id,user_id',
        ignoreDuplicates: true,
      );
    }
  }

  // ---------- 账号操作 ----------

  Future<void> setSoundEnabled(bool value) async {
    soundEnabled = value;
    SoundService.instance.enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundKey, value);
    notifyListeners();
  }

  Future<String?> changeNickname(String nickname) async {
    final s = session;
    if (s == null) return '未登录';
    final name = nickname.trim();
    if (name.isEmpty) return '昵称不能为空';
    try {
      await s.client.from(Db.profiles).update({'nickname': name}).eq('id', s.me.id);
      s.me = MemberProfile(
        id: s.me.id,
        account: s.me.account,
        nickname: name,
        publicKey: s.me.publicKey,
        sealedPrivateKey: s.me.sealedPrivateKey,
        kdfSalt: s.me.kdfSalt,
        kdfParams: s.me.kdfParams,
      );
      await conversations?.refreshProfiles();
      notifyListeners();
      return null;
    } catch (e) {
      return _friendly(e);
    }
  }

  Future<String?> changePassword(String oldPassword, String newPassword) async {
    final s = session;
    if (s == null) return '未登录';
    if (newPassword.length < 6) return '新密码至少 6 位';
    busy = true;
    notifyListeners();
    try {
      final verified = await _unseal(s.me, oldPassword);
      if (verified == null) return '旧密码不正确';

      final salt = randomBytes(16);
      final params = _defaultKdfParams();
      final kek = await ChatCrypto.deriveKek(newPassword, salt, params);
      final sealed = await ChatCrypto.sealPrivateSeed(
        await ChatCrypto.encodeKeyPairPrivate(s.identity),
        kek,
        s.me.account,
      );

      await s.client.auth.updateUser(UserAttributes(password: newPassword));
      await s.client.from(Db.profiles).update({
        'sealed_private_key': sealed,
        'kdf_salt': b64Encode(salt),
        'kdf_params': params,
      }).eq('id', s.me.id);

      s.me = MemberProfile(
        id: s.me.id,
        account: s.me.account,
        nickname: s.me.nickname,
        publicKey: s.me.publicKey,
        sealedPrivateKey: sealed,
        kdfSalt: b64Encode(salt),
        kdfParams: params,
      );
      return null;
    } catch (e) {
      return _friendly(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _detachFocusListener();
    sweep?.stop();
    sweep = null;
    conversations?.dispose();
    conversations = null;
    session = null;
    unlockProfile = null;
    try {
      await supa.client.auth.signOut();
    } catch (_) {}
    phase = AppPhase.login;
    notifyListeners();
  }

  /// 更换后端服务器（切换团队）
  Future<void> resetConfig() async {
    await signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configKey);
    config = null;
    unlockProfile = null;
    phase = AppPhase.setup;
    notifyListeners();
  }

  Map<String, dynamic> _defaultKdfParams() => {
        'algo': 'argon2id',
        'm': CryptoConst.argon2Memory,
        't': CryptoConst.argon2Iterations,
        'p': CryptoConst.argon2Parallelism,
      };

  String _friendly(Object e) {
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) return '账号或密码错误';
      if (m.contains('already registered') || m.contains('already been registered')) {
        return '账号已被占用';
      }
      if (m.contains('email not confirmed')) {
        return '服务端开启了邮箱验证，请在 Supabase 中关闭 Confirm email';
      }
      return e.message;
    }
    if (e is PostgrestException) return '服务端错误：${e.message}';
    final text = e.toString();
    if (text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection refused') ||
        text.contains('ClientException')) {
      return '无法连接服务器，请检查网络与服务器地址';
    }
    return text;
  }
}
