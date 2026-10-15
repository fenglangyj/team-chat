import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:team_chat/core/constants.dart';
import 'package:team_chat/core/utils.dart';
import 'package:team_chat/services/chat_crypto.dart';

const _fastParams = {'m': 256, 't': 1, 'p': 1};

void main() {
  group('口令派生与私钥封装', () {
    test('相同口令与盐派生相同 KEK，不同盐则不同', () async {
      final salt = randomBytes(16);
      final k1 = await ChatCrypto.deriveKek('password123', salt, _fastParams);
      final k2 = await ChatCrypto.deriveKek('password123', salt, _fastParams);
      final k3 =
          await ChatCrypto.deriveKek('password123', randomBytes(16), _fastParams);
      expect(k1, equals(k2));
      expect(k1, isNot(equals(k3)));
    });

    test('私钥封装可解封；错误口令抛出认证失败', () async {
      final identity = await ChatCrypto.generateIdentity();
      final seed = await ChatCrypto.encodeKeyPairPrivate(identity);
      final salt = randomBytes(16);
      final kek = await ChatCrypto.deriveKek('hunter2!', salt, _fastParams);
      final sealed = await ChatCrypto.sealPrivateSeed(seed, kek, 'alice');

      final restored = await ChatCrypto.unsealPrivateSeed(sealed, kek, 'alice');
      final restoredPub = await ChatCrypto.publicKeyOf(restored);
      final originalPub = await ChatCrypto.publicKeyOf(identity);
      expect(restoredPub, equals(originalPub));

      // AAD 不一致（换账号）或口令错误都应失败
      expect(
        () => ChatCrypto.unsealPrivateSeed(sealed, kek, 'bob'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final wrongKek = await ChatCrypto.deriveKek('wrong', salt, _fastParams);
      expect(
        () => ChatCrypto.unsealPrivateSeed(sealed, wrongKek, 'alice'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('会话密钥封装', () {
    test('sealed-box 往返成功且仅目标可解封', () async {
      final alice = await ChatCrypto.generateIdentity();
      final bob = await ChatCrypto.generateIdentity();
      final eve = await ChatCrypto.generateIdentity();
      final alicePub = await ChatCrypto.publicKeyOf(alice);
      final bobPub = await ChatCrypto.publicKeyOf(bob);

      final cek = randomBytes(32);
      final wrapped = await ChatCrypto.wrapCek(cek, bobPub);

      final unwrapped = await ChatCrypto.unwrapCek(wrapped, bob);
      expect(unwrapped, equals(cek));

      expect(
        () => ChatCrypto.unwrapCek(wrapped, eve),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // 自我封装同样可行（团队第一位成员建立全员群时使用）
      final selfWrapped = await ChatCrypto.wrapCek(cek, alicePub);
      expect(await ChatCrypto.unwrapCek(selfWrapped, alice), equals(cek));
    });
  });

  group('消息加解密', () {
    test('往返成功；篡改密文无法通过校验', () async {
      final cek = randomBytes(32);
      const convId = '11111111-2222-3333-4444-555555555555';
      final enc = await ChatCrypto.encryptMessage(
          cek, convId, {'t': 'text', 'text': '你好，世界 hello'});
      final payload =
          await ChatCrypto.decryptMessage(cek, convId, enc.ciphertext, enc.nonce);
      expect(payload['text'], '你好，世界 hello');

      // AAD（会话 id）不一致
      expect(
        () => ChatCrypto.decryptMessage(
            cek, 'other-conv', enc.ciphertext, enc.nonce),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );

      // 篡改密文
      final raw = b64Decode(enc.ciphertext);
      raw[3] ^= 0xFF;
      expect(
        () => ChatCrypto.decryptMessage(
            cek, convId, b64Encode(raw), enc.nonce),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('附件分块加解密', () {
    test('多分块文件往返一致（含边界块）', () async {
      final cek = randomBytes(32);
      final dir = await Directory.systemTemp.createTemp('teamchat_test');
      try {
        // 2.5 个分块，覆盖整块与尾块
        const size = CryptoConst.chunkSize * 2 + 12345;
        final plain = File('${dir.path}/plain.bin');
        final bytes = randomBytes(size);
        await plain.writeAsBytes(bytes);

        final encrypted = File('${dir.path}/enc.bin');
        await ChatCrypto.encryptFile(plain, encrypted, cek);
        expect(await encrypted.length(), greaterThan(size));

        final decrypted = File('${dir.path}/dec.bin');
        await ChatCrypto.decryptFile(encrypted, decrypted, cek);
        expect(await decrypted.readAsBytes(), equals(bytes));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('空文件可以往返', () async {
      final cek = randomBytes(32);
      final dir = await Directory.systemTemp.createTemp('teamchat_test');
      try {
        final plain = File('${dir.path}/empty.bin');
        await plain.writeAsBytes(const []);
        final encrypted = File('${dir.path}/enc.bin');
        await ChatCrypto.encryptFile(plain, encrypted, cek);
        final decrypted = File('${dir.path}/dec.bin');
        await ChatCrypto.decryptFile(encrypted, decrypted, cek);
        expect(await decrypted.length(), 0);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('错误密钥解密失败', () async {
      final cek = randomBytes(32);
      final other = randomBytes(32);
      final dir = await Directory.systemTemp.createTemp('teamchat_test');
      try {
        final plain = File('${dir.path}/plain.bin');
        await plain.writeAsBytes(utf8.encode('secret data'));
        final encrypted = File('${dir.path}/enc.bin');
        await ChatCrypto.encryptFile(plain, encrypted, cek);
        final decrypted = File('${dir.path}/dec.bin');
        expect(
          () => ChatCrypto.decryptFile(encrypted, decrypted, other),
          throwsA(anything),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
