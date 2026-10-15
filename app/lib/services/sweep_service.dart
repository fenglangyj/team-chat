import 'dart:async';

import '../core/constants.dart';
import 'supabase_service.dart';

/// 定期触发服务端清扫（24 小时销毁）；即使未配置 pg_cron 也能兜底
class SweepService {
  final SupabaseService supa;
  Timer? _timer;

  SweepService(this.supa);

  void start() {
    stop();
    _trigger();
    _timer = Timer.periodic(SyncConst.sweepInterval, (_) => _trigger());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _trigger() async {
    try {
      await supa.client.functions.invoke('sweep');
    } catch (_) {
      // 清扫失败不影响正常使用，下一轮或下一次启动会重试
    }
  }
}
