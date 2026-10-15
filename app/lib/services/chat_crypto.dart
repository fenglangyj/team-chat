import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/constants.dart';
import '../core/utils.dart';

/// 端到端加密核心：
/// - X25519 身份密钥对；私钥种子经 Argon2id 派生的 KEK 封装后存储
/// - 会话密钥 CEK 以 sealed-box 方式按成员公钥封装
/// - 消息与附件均使用 XChaCha20-Poly1305
class ChatCrypto {
  static final _x25519 = X25519();
  static final _aead = Xchacha20.poly1305Aead();
  static const int _macLength = 16;

  // ---------- 口令 -> KEK ----------

  static Future<Uint8List> deriveKek(
    String password,
    Uint8List salt,
    Map<String, dynamic> params,
  ) async {
    final argon2 = Argon2id(
      memory: (params['m'] as num?)?.toInt() ?? CryptoConst.argon2Memory,
      iterations: (params['t'] as num?)?.toInt() ?? CryptoConst.argon2Iterations,
      parallelism: (params['p'] as num?)?.toInt() ?? CryptoConst.argon2Parallelism,
      hashLength: 32,
    );
    final key = await argon2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  // ---------- 身份密钥 ----------

  static Future<SimpleKeyPair> generateIdentity() => _x25519.newKeyPair();

  static Future<Uint8List> encodeKeyPairPrivate(SimpleKeyPair pair) async =>
      Uint8List.fromList(await pair.extractPrivateKeyBytes());

  static Future<Uint8List> publicKeyOf(SimpleKeyPair pair) async =>
      Uint8List.fromList((await pair.extractPublicKey()).bytes);

  /// 用 KEK 封装私钥种子：输出 b64(nonce24 || ct || mac16)
  static Future<String> sealPrivateSeed(
    Uint8List seed,
    Uint8List kek,
    String account,
  ) async {
    final nonce = randomBytes(24);
    final box = await _aead.encrypt(
      seed,
      secretKey: SecretKey(kek),
      nonce: nonce,
      aad: utf8.encode('${CryptoConst.sealContext}:$account'),
    );
    return b64Encode([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// 解封私钥种子并还原身份密钥对
  static Future<SimpleKeyPair> unsealPrivateSeed(
    String sealed,
    Uint8List kek,
    String account,
  ) async {
    final raw = b64Decode(sealed);
    final nonce = raw.sublist(0, 24);
    final ct = raw.sublist(24, raw.length - _macLength);
    final mac = raw.sublist(raw.length - _macLength);
    final seed = await _aead.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(kek),
      aad: utf8.encode('${CryptoConst.sealContext}:$account'),
    );
    return _x25519.newKeyPairFromSeed(seed);
  }

  // ---------- 会话密钥封装（sealed box） ----------

  /// 输出 b64(ephPub32 || nonce24 || ct || mac16)
  static Future<String> wrapCek(Uint8List cek, Uint8List recipientPub) async {
    final ephemeral = await _x25519.newKeyPair();
    final ephPub =
        Uint8List.fromList((await ephemeral.extractPublicKey()).bytes);
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(recipientPub, type: KeyPairType.x25519),
    );
    final nonce = randomBytes(24);
    final wrapKey = await _deriveWrapKey(shared, nonce);
    final box = await _aead.encrypt(
      cek,
      secretKey: wrapKey,
      nonce: nonce,
      aad: recipientPub,
    );
    return b64Encode([...ephPub, ...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> unwrapCek(
    String wrapped,
    SimpleKeyPair myKeyPair,
  ) async {
    final raw = b64Decode(wrapped);
    final ephPub = raw.sublist(0, 32);
    final nonce = raw.sublist(32, 56);
    final ct = raw.sublist(56, raw.length - _macLength);
    final mac = raw.sublist(raw.length - _macLength);
    final myPub =
        Uint8List.fromList((await myKeyPair.extractPublicKey()).bytes);
    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519),
    );
    final wrapKey = await _deriveWrapKey(shared, nonce);
    final cek = await _aead.decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: wrapKey,
      aad: myPub,
    );
    return Uint8List.fromList(cek);
  }

  static Future<SecretKey> _deriveWrapKey(
    SecretKey shared,
    List<int> salt,
  ) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    return hkdf.deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode(CryptoConst.wrapInfo),
    );
  }

  // ---------- 消息加解密 ----------

  static Future<({String ciphertext, String nonce})> encryptMessage(
    Uint8List cek,
    String conversationId,
    Map<String, dynamic> payload,
  ) async {
    final nonce = randomBytes(24);
    final box = await _aead.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: SecretKey(cek),
      nonce: nonce,
      aad: utf8.encode('${CryptoConst.msgAadPrefix}$conversationId'),
    );
    return (
      ciphertext: b64Encode([...box.cipherText, ...box.mac.bytes]),
      nonce: b64Encode(nonce),
    );
  }

  static Future<Map<String, dynamic>> decryptMessage(
    Uint8List cek,
    String conversationId,
    String ciphertext,
    String nonce,
  ) async {
    final ctWithMac = b64Decode(ciphertext);
    final plain = await _aead.decrypt(
      SecretBox(
        ctWithMac.sublist(0, ctWithMac.length - _macLength),
        nonce: b64Decode(nonce),
        mac: Mac(ctWithMac.sublist(ctWithMac.length - _macLength)),
      ),
      secretKey: SecretKey(cek),
      aad: utf8.encode('${CryptoConst.msgAadPrefix}$conversationId'),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  // ---------- 附件分块加解密 ----------

  /// 文件头：magic(4) || version(1) || chunkSize(4, big endian) || fileId(16)
  static const int _headerLength = 25;

  static Uint8List _buildHeader(Uint8List fileId) {
    final header = BytesBuilder();
    header.add(CryptoConst.fileMagic);
    header.addByte(CryptoConst.fileVersion);
    final size = ByteData(4)..setUint32(0, CryptoConst.chunkSize, Endian.big);
    header.add(size.buffer.asUint8List());
    header.add(fileId);
    return header.toBytes();
  }

  static Uint8List _chunkNonce(Uint8List fileId, int index) {
    final nonce = Uint8List(24);
    nonce.setRange(0, 16, fileId);
    final counter = ByteData(8)..setUint64(0, index, Endian.big);
    nonce.setRange(16, 24, counter.buffer.asUint8List());
    return nonce;
  }

  static Uint8List _chunkAad(Uint8List header, int index) {
    final counter = ByteData(4)..setUint32(0, index, Endian.big);
    return Uint8List.fromList([...header, ...counter.buffer.asUint8List()]);
  }

  /// 加密 [input] 到 [output]（流式，1MiB 分块）
  static Future<void> encryptFile(
    File input,
    File output,
    Uint8List cek, {
    void Function(double progress)? onProgress,
  }) async {
    final fileId = randomBytes(16);
    final header = _buildHeader(fileId);
    final total = await input.length();
    final reader = await input.open();
    final writer = await output.open(mode: FileMode.write);
    try {
      await writer.writeFrom(header);
      var index = 0;
      var done = 0;
      while (true) {
        final chunk = await reader.read(CryptoConst.chunkSize);
        if (chunk.isEmpty) break;
        final box = await _aead.encrypt(
          chunk,
          secretKey: SecretKey(cek),
          nonce: _chunkNonce(fileId, index),
          aad: _chunkAad(header, index),
        );
        await writer.writeFrom(box.cipherText);
        await writer.writeFrom(box.mac.bytes);
        done += chunk.length;
        index++;
        onProgress?.call(total == 0 ? 1 : done / total);
      }
    } finally {
      await reader.close();
      await writer.close();
    }
  }

  /// 解密 [input] 到 [output]，校验文件头与每块完整性
  static Future<void> decryptFile(
    File input,
    File output,
    Uint8List cek, {
    void Function(double progress)? onProgress,
  }) async {
    final total = await input.length();
    final reader = await input.open();
    final writer = await output.open(mode: FileMode.write);
    try {
      final header = await reader.read(_headerLength);
      if (header.length != _headerLength ||
          !_listEquals(header.sublist(0, 4), CryptoConst.fileMagic)) {
        throw const FormatException('无效的加密文件');
      }
      final version = header[4];
      if (version != CryptoConst.fileVersion) {
        throw const FormatException('不支持的加密文件版本');
      }
      final chunkSize =
          ByteData.sublistView(header, 5, 9).getUint32(0, Endian.big);
      final fileId = header.sublist(9, 25);
      var index = 0;
      var done = _headerLength;
      while (true) {
        final cipherLen = total - done;
        if (cipherLen <= 0) break;
        final toRead = cipherLen <= chunkSize + _macLength
            ? cipherLen
            : chunkSize + _macLength;
        final blob = await reader.read(toRead);
        if (blob.length != toRead) throw const FormatException('文件已损坏');
        final plain = await _aead.decrypt(
          SecretBox(
            blob.sublist(0, blob.length - _macLength),
            nonce: _chunkNonce(fileId, index),
            mac: Mac(blob.sublist(blob.length - _macLength)),
          ),
          secretKey: SecretKey(cek),
          aad: _chunkAad(header, index),
        );
        await writer.writeFrom(plain);
        done += blob.length;
        index++;
        onProgress?.call(total == 0 ? 1 : done / total);
        if (blob.length < chunkSize + _macLength) break;
      }
    } finally {
      await reader.close();
      await writer.close();
    }
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
