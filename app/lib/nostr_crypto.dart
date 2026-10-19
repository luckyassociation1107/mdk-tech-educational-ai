import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/ecc/api.dart';

/// Minimal Nostr (NIP-01) identity + BIP-340 Schnorr signing on
/// secp256k1, implemented on pointycastle EC math. The catalog uses ONE
/// shared keypair: the private key (nsec hex) lives only on teacher
/// devices that publish; every device reads by the public key (npub hex).
/// Entries travel as encoded tokens (see catalog_codec.dart), so relays —
/// which are public infrastructure — never see readable links.
class NostrCrypto {
  static final BigInt _p = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F', radix: 16);
  static final BigInt _n = BigInt.parse('FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141', radix: 16);
  static final ECDomainParameters _params = ECDomainParameters('secp256k1');

  static String hexEncode(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List hexDecode(String hex) {
    final h = hex.trim().toLowerCase().replaceAll(' ', '');
    final out = Uint8List(h.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static bool isHexKey(String s) {
    try {
      return hexDecode(s).length == 32;
    } catch (_) {
      return false;
    }
  }

  static String generateSecretHex() {
    final rnd = Random.secure();
    while (true) {
      final b = Uint8List.fromList(List<int>.generate(32, (_) => rnd.nextInt(256)));
      final d = _intFromBytes(b);
      if (d > BigInt.zero && d < _n) return hexEncode(b);
    }
  }

  static BigInt _intFromBytes(List<int> b) => b.fold<BigInt>(BigInt.zero, (a, x) => (a << 8) | BigInt.from(x));

  static Uint8List _bytes32(BigInt v) {
    final out = Uint8List(32);
    var x = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static ECPoint _point(BigInt x, BigInt y) => _params.curve.createPoint(x, y);

  static ECPoint _liftX(BigInt x) {
    final ySq = (x.modPow(BigInt.from(3), _p) + BigInt.from(7)) % _p;
    var y = ySq.modPow((_p + BigInt.one) ~/ BigInt.from(4), _p);
    if (y.modPow(BigInt.two, _p) != ySq) throw StateError('lift_x failed');
    if (y.isOdd) y = _p - y;
    return _point(x, y);
  }

  static Uint8List _sha(List<int> data) => Uint8List.fromList(crypto.sha256.convert(data).bytes);

  static Uint8List _taggedHash(String tag, List<int> msg) {
    final tagHash = _sha(utf8.encode(tag));
    return _sha([...tagHash, ...tagHash, ...msg]);
  }

  static List<int> _xBytes(ECPoint point) => _bytes32(point.x!.toBigInteger()!);

  /// x-only public key (hex) for a secret key (hex).
  static String pubkeyHex(String secretHex) {
    final d = _intFromBytes(hexDecode(secretHex));
    final point = (_params.G * d)!;
    return hexEncode(_xBytes(point));
  }

  /// BIP-340 Schnorr signature (64 bytes hex) over a 32-byte message.
  static String signBip340(String secretHex, List<int> msg32, {List<int>? auxRand}) {
    final d0 = _intFromBytes(hexDecode(secretHex));
    final pubPoint = (_params.G * d0)!;
    final d = pubPoint.y!.toBigInteger()!.isEven ? d0 : _n - d0;
    final aux = auxRand ?? Uint8List.fromList(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    final t = _bytes32(d ^ _intFromBytes(_taggedHash('BIP0340/aux', aux)));
    final rand = _taggedHash('BIP0340/nonce', [...t, ..._xBytes(pubPoint), ...msg32]);
    final k0 = _intFromBytes(rand) % _n;
    if (k0 == BigInt.zero) throw StateError('nonce is zero');
    final rPoint = (_params.G * k0)!;
    final k = rPoint.y!.toBigInteger()!.isEven ? k0 : _n - k0;
    final e = _intFromBytes(_taggedHash('BIP0340/challenge', [..._xBytes(rPoint), ..._xBytes(pubPoint), ...msg32])) % _n;
    final sig = [..._xBytes(rPoint), ..._bytes32((k + e * d) % _n)];
    return hexEncode(sig);
  }

  static bool verifyBip340(String pubkeyHex, List<int> msg32, String sigHex) {
    try {
      final sig = hexDecode(sigHex);
      if (sig.length != 64) return false;
      final r = _intFromBytes(sig.sublist(0, 32));
      final s = _intFromBytes(sig.sublist(32, 64));
      if (r >= _p || s >= _n) return false;
      final pubPoint = _liftX(_intFromBytes(hexDecode(pubkeyHex)));
      final e = _intFromBytes(_taggedHash('BIP0340/challenge', [...sig.sublist(0, 32), ...hexDecode(pubkeyHex), ...msg32])) % _n;
      final rPoint = ((_params.G * s)! + (pubPoint * (_n - e))!)!;
      if (rPoint.isInfinity) return false;
      return !rPoint.y!.toBigInteger()!.isOdd && rPoint.x!.toBigInteger() == r;
    } catch (_) {
      return false;
    }
  }

  /// NIP-01 event id: sha256 of the canonical serialization.
  static String eventId({required String pubkey, required int createdAt, required int kind, required List<List<String>> tags, required String content}) {
    final serialized = jsonEncode([0, pubkey, createdAt, kind, tags, content]);
    return hexEncode(_sha(utf8.encode(serialized)));
  }

  static Map<String, dynamic> signedEvent({required String secretHex, required int kind, required List<List<String>> tags, required String content, int? createdAt}) {
    final pub = pubkeyHex(secretHex);
    final ts = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = eventId(pubkey: pub, createdAt: ts, kind: kind, tags: tags, content: content);
    final sig = signBip340(secretHex, hexDecode(id));
    return {'id': id, 'pubkey': pub, 'created_at': ts, 'kind': kind, 'tags': tags, 'content': content, 'sig': sig};
  }
}
