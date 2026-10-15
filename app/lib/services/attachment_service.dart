import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/utils.dart';
import 'chat_crypto.dart';
import 'session.dart';

/// 附件（图片/文件）加密上传与解密下载
class AttachmentService {
  final SupabaseClient Function() client;
  final UserSession Function() session;

  AttachmentService({required this.client, required this.session});

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<Directory> _tmpDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}teamchat');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');

  /// 加密并上传文件，返回附件 id 与随消息发送的载荷
  Future<({String attachmentId, Map<String, dynamic> payload})> uploadEncrypted({
    required String conversationId,
    required String fileName,
    required String mimeType,
    required int size,
    required File source,
    void Function(double progress)? onProgress,
  }) async {
    final s = session();
    final cek = s.cek(conversationId);
    if (cek == null) {
      throw StateError('会话密钥尚未就绪');
    }

    final attachmentId = randomHex(16);
    final path = '$conversationId/$attachmentId.bin';

    await client().from(Db.attachments).insert({
      'id': attachmentId,
      'conversation_id': conversationId,
      'uploader_id': s.me.id,
      'storage_path': path,
    });

    final dir = await _tmpDir();
    final encFile = File('${dir.path}${Platform.pathSeparator}enc_$attachmentId');
    try {
      await ChatCrypto.encryptFile(source, encFile, cek, onProgress: onProgress);
      await client().storage.from(Db.attachmentBucket).upload(
            path,
            encFile,
            fileOptions: const FileOptions(
              contentType: 'application/octet-stream',
              upsert: true,
            ),
          );
    } catch (_) {
      try {
        await client().from(Db.attachments).delete().eq('id', attachmentId);
      } catch (_) {}
      rethrow;
    } finally {
      if (await encFile.exists()) {
        await encFile.delete();
      }
    }

    return (
      attachmentId: attachmentId,
      payload: {'name': fileName, 'mime': mimeType, 'size': size},
    );
  }

  /// 下载并解密为临时文件（调用方负责按需删除/另存）
  Future<File> downloadDecrypted({
    required String conversationId,
    required String attachmentId,
    required String suggestedName,
    void Function(double progress)? onProgress,
  }) async {
    final s = session();
    final cek = s.cek(conversationId);
    if (cek == null) {
      throw StateError('会话密钥尚未就绪');
    }

    final data = await client()
        .storage
        .from(Db.attachmentBucket)
        .download('$conversationId/$attachmentId.bin');

    final dir = await _tmpDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final encFile = File('${dir.path}${Platform.pathSeparator}dl_${stamp}_$attachmentId');
    final outFile = File(
        '${dir.path}${Platform.pathSeparator}${stamp}_${_sanitize(suggestedName)}');
    await encFile.writeAsBytes(data, flush: true);
    try {
      await ChatCrypto.decryptFile(encFile, outFile, cek,
          onProgress: onProgress);
    } catch (_) {
      if (await outFile.exists()) await outFile.delete();
      rethrow;
    } finally {
      if (await encFile.exists()) await encFile.delete();
    }
    return outFile;
  }

  /// 图片：解密到内存后立即删除临时文件
  Future<Uint8List> downloadImageBytes({
    required String conversationId,
    required String attachmentId,
  }) async {
    final file = await downloadDecrypted(
      conversationId: conversationId,
      attachmentId: attachmentId,
      suggestedName: 'image',
    );
    try {
      return await file.readAsBytes();
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// 保存解密后的文件；桌面端弹出另存为对话框
  Future<String?> saveAs(File decrypted, String fileName) async {
    if (_isDesktop) {
      final target = await FilePicker.platform.saveFile(
        dialogTitle: '保存文件',
        fileName: _sanitize(fileName),
      );
      if (target == null) return null;
      await decrypted.copy(target);
      return target;
    }
    return decrypted.path;
  }

  /// 清空会话时删除全部附件（存储对象 + 登记行）
  Future<void> purgeConversation(String conversationId) async {
    try {
      final rows = await client()
          .from(Db.attachments)
          .select('id, storage_path')
          .eq('conversation_id', conversationId);
      final paths =
          rows.map((r) => r['storage_path'] as String).toList(growable: false);
      for (var i = 0; i < paths.length; i += 100) {
        final batch = paths.sublist(
            i, i + 100 > paths.length ? paths.length : i + 100);
        await client().storage.from(Db.attachmentBucket).remove(batch);
      }
      await client()
          .from(Db.attachments)
          .delete()
          .eq('conversation_id', conversationId);
    } catch (_) {
      // 剩余对象由 sweep 兜底清理
    }
  }
}
