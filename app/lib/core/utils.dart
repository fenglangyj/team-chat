import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final Random _random = Random.secure();

Uint8List randomBytes(int length) =>
    Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

String randomHex(int byteLength) => randomBytes(byteLength)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

String b64Encode(List<int> bytes) => base64Encode(bytes);

Uint8List b64Decode(String text) => base64Decode(text);

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String formatTime(DateTime time) {
  final now = DateTime.now();
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final hm =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  if (that == today) return hm;
  if (that == today.subtract(const Duration(days: 1))) return '昨天 $hm';
  if (local.year == now.year) {
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hm';
  }
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hm';
}

String avatarText(String name) {
  if (name.isEmpty) return '?';
  return String.fromCharCode(name.runes.first).toUpperCase();
}
