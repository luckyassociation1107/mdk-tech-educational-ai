import 'dart:convert';
import '../../../ai-textbook-video-classroom/app/lib/vault/emoji_vault.dart';

void main() {
  // 1. emoji roundtrip
  final bytes = utf8.encode('Hello Textbook 🎒 world — 1234');
  final emoji = EmojiCodec.encode(bytes);
  final back = utf8.decode(EmojiCodec.decode(emoji));
  assert(back == 'Hello Textbook 🎒 world — 1234', 'emoji roundtrip broken: $back');
  print('EMOJI ROUNDTRIP OK ($bytes length -> ${emoji.length} chars)');

  // 2. crypto seal/open + wrong key
  final salt = EmojiCodec.encode(List<int>.generate(16, (i) => i));
  final key = VaultCrypto.pbkdf2('1234', [1, 2, 3, 4, 5, 6, 7, 8], rounds: 1000, length: 32);
  final sealed = VaultCrypto.seal('{"marks":[90,80]}', key);
  final opened = VaultCrypto.open(sealed, key);
  assert(opened == '{"marks":[90,80]}', 'open failed: $opened');
  final wrongKey = VaultCrypto.pbkdf2('9999', [1, 2, 3, 4, 5, 6, 7, 8], rounds: 1000, length: 32);
  assert(VaultCrypto.open(sealed, wrongKey) == null, 'wrong key must NOT open');
  print('CRYPTO SEAL/OPEN OK, WRONG PIN REJECTED');

  // 3. pbkdf2 differs by pin
  final a = VaultCrypto.hashPin('1234', base64UrlEncode([9, 9, 9]));
  final b = VaultCrypto.hashPin('1235', base64UrlEncode([9, 9, 9]));
  assert(a != b, 'hash must differ');
  print('PIN HASH OK');

  // 4. alphabet uniqueness
  assert(kEmojiAlphabet.toSet().length == 64, 'emoji alphabet must have 64 unique');
  print('ALPHABET OK (64 unique)');
  print('VAULT ENGINE: ALL OK');
}
