import 'package:audioplayers/audioplayers.dart';

/// 新消息提示音（单例；enabled 由设置页开关控制）
class SoundService {
  SoundService._();

  static final SoundService instance = SoundService._();

  final AudioPlayer _player = AudioPlayer();

  bool enabled = true;

  Future<void> play() async {
    if (!enabled) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/notify.wav'), volume: 0.8);
    } catch (_) {
      // 播放失败（如平台不支持）忽略，不影响正常使用
    }
  }
}
