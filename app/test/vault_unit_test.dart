import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:textbook_video_classroom/vault/emoji_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('emoji codec', () {
    test('64 unique emojis in the alphabet', () {
      expect(kEmojiAlphabet.toSet().length, 64);
    });

    test('bytes round-trip through emojis', () {
      final bytes = utf8.encode('hello world, this is a classroom vault');
      final emoji = EmojiCodec.encode(bytes);
      expect(emoji.startsWith('🎒'), isTrue);
      expect(EmojiCodec.decode(emoji), bytes);
    });

    test('emoji strings with spaces/newlines still decode', () {
      final emoji = EmojiCodec.encode(utf8.encode('spacing test'));
      final messy = emoji.split('').join(' ');
      expect(EmojiCodec.decode(messy), utf8.encode('spacing test'));
    });
  });

  group('crypto', () {
    test('seal/open with the right key, reject with the wrong one', () {
      final salt = List<int>.filled(16, 7);
      final key = VaultCrypto.pbkdf2('1234', salt, rounds: 1000);
      final other = VaultCrypto.pbkdf2('9999', salt, rounds: 1000);
      final sealed = VaultCrypto.seal('marks: 18/25', key);
      expect(VaultCrypto.open(sealed, key), 'marks: 18/25');
      expect(VaultCrypto.open(sealed, other), isNull);
    });

    test('a flipped ciphertext byte is rejected', () {
      final key = VaultCrypto.pbkdf2('1234', List<int>.filled(16, 1), rounds: 1000);
      final sealed = VaultCrypto.seal('secret data here', key);
      final c = base64Url.decode(sealed['c']!);
      c[0] ^= 1;
      final tampered = {...sealed, 'c': base64UrlEncode(c)};
      expect(VaultCrypto.open(tampered, key), isNull);
    });

    test('same PIN on two profiles gives different verifiers (salt works)', () {
      final a = VaultCrypto.hashPin('1234', base64UrlEncode(List<int>.filled(16, 1)));
      final b = VaultCrypto.hashPin('1234', base64UrlEncode(List<int>.filled(16, 2)));
      expect(a, isNot(b));
    });
  });

  group('vault profiles', () {
    test('signup → wrong PIN rejected → right PIN logs in', () async {
      final p = await VaultStore.createProfile(name: 'Aarav', avatar: '🐼', pin: '4321');
      expect(p.name, 'Aarav');

      final bad = await VaultStore.login(p.id, '0000');
      expect(bad, isNull, reason: 'wrong PIN must not open the vault');

      final good = await VaultStore.login(p.id, '4321');
      expect(good, isNotNull);
      expect(good!.name, 'Aarav');
      expect(VaultStore.current?.id, p.id);
    });

    test('data survives logout + login (sealed and re-opened)', () async {
      final p = await VaultStore.createProfile(name: 'Meera', avatar: '🦊', pin: '1111');
      await VaultStore.login(p.id, '1111');
      await VaultStore.log('class', 'Finished part 3 — Photosynthesis');
      await VaultStore.put('xp_s2', 140);
      await VaultStore.logout();

      expect(VaultStore.current, isNull);
      final again = await VaultStore.login(p.id, '1111');
      expect(again, isNotNull);
      expect(VaultStore.get('xp_s2'), 140);
      final messages = VaultStore.logs.map((l) => '${l['msg']}').toList();
      expect(messages, contains('Finished part 3 — Photosynthesis'),
          reason: 'the class log written before logout must survive');
    });

    test('PIN change keeps the data and kills the old PIN', () async {
      final p = await VaultStore.createProfile(name: 'Kiran', avatar: '🚀', pin: '1234');
      await VaultStore.login(p.id, '1234');
      await VaultStore.put('xp_s5', 90);
      await VaultStore.changePin('1234', '987654');
      await VaultStore.logout();

      expect(await VaultStore.login(p.id, '1234'), isNull);
      final ok = await VaultStore.login(p.id, '987654');
      expect(ok, isNotNull);
      expect(VaultStore.get('xp_s5'), 90);
    });

    test('rejects short / non-numeric PINs', () async {
      expect(VaultStore.pinLooksValid('12'), isFalse);
      expect(VaultStore.pinLooksValid('abcd'), isFalse);
      expect(VaultStore.pinLooksValid('1234'), isTrue);
      expect(VaultStore.pinLooksValid('123456'), isTrue);
      expect(VaultStore.pinLooksValid('1234567'), isFalse);
    });
  });

}
