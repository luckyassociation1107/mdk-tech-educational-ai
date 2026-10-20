import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// ─────────────────────────────────────────────────────────────────────
///  Minimal secp256k1 + BIP-340 Schnorr signatures, pure Dart.
///
///  Needed only so the app can sign Nostr events (Nostr relays reject any
///  event whose id/signature does not verify). No native code, no extra
///  dependency — just BigInt arithmetic and SHA-256.
///
///  Verified against the official BIP-340 test vectors (see the test
///  harness) before shipping.
/// ─────────────────────────────────────────────────────────────────────
class Secp256k1 {
  static final BigInt p = BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
      radix: 16);
  static final BigInt n = BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
      radix: 16);
  static final BigInt gx = BigInt.parse(
      '79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798',
      radix: 16);
  static final BigInt gy = BigInt.parse(
      '483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8',
      radix: 16);

  static final _Point g = _Point(gx, gy);

  /// Compressed? No — Nostr uses the raw 32-byte x coordinate only.
  static Uint8List publicKeyX(Uint8List secret32) {
    final pnt = _mul(_fromBytes(secret32), g);
    if (pnt == null) throw StateError('invalid secret key');
    return _to32(pnt.x);
  }

  static bool hasEvenY(Uint8List secret32) {
    final pnt = _mul(_fromBytes(secret32), g);
    if (pnt == null) throw StateError('invalid secret key');
    return pnt.y.isEven;
  }

  static BigInt _fromBytes(Uint8List b) {
    var v = BigInt.zero;
    for (final x in b) {
      v = (v << 8) | BigInt.from(x);
    }
    return v;
  }

  static Uint8List _to32(BigInt v) {
    final out = Uint8List(32);
    var t = v;
    for (var i = 31; i >= 0; i--) {
      out[i] = (t & BigInt.from(0xFF)).toInt();
      t = t >> 8;
    }
    return out;
  }

  static Uint8List _taggedHash(String tag, List<int> msg) {
    final t = sha256.convert(tag.codeUnits).bytes;
    return Uint8List.fromList(
        sha256.convert([...t, ...t, ...msg]).bytes);
  }

  /// BIP-340 sign. `aux` is 32 random bytes (or 32 zero bytes).
  static Uint8List schnorrSign(
      Uint8List secret32, Uint8List msg32, Uint8List aux32) {
    var d0 = _fromBytes(secret32);
    if (d0 <= BigInt.zero || d0 >= n) throw StateError('bad secret key');
    final pub = _mul(d0, g)!;
    final d = pub.y.isEven ? d0 : n - d0;
    final px = _to32(pub.x);

    final t = Uint8List.fromList(secret32);
    final auxHash = _taggedHash('BIP0340/aux', aux32);
    for (var i = 0; i < 32; i++) {
      t[i] ^= auxHash[i];
    }
    final rand = _taggedHash('BIP0340/nonce', [...t, ...px, ...msg32]);
    var k0 = _fromBytes(rand) % n;
    if (k0 == BigInt.zero) throw StateError('bad nonce');
    final rp = _mul(k0, g)!;
    final k = rp.y.isEven ? k0 : n - k0;
    final rx = _to32(rp.x);

    final e = _fromBytes(
            _taggedHash('BIP0340/challenge', [...rx, ...px, ...msg32])) %
        n;
    final s = (k + e * d) % n;

    final out = Uint8List(64);
    out.setRange(0, 32, rx);
    out.setRange(32, 64, _to32(s));
    return out;
  }

  /// BIP-340 verify (used by the self-test screen and tests).
  static bool schnorrVerify(
      Uint8List pubX32, Uint8List msg32, Uint8List sig64) {
    try {
      final px = _fromBytes(pubX32);
      if (px >= p) return false;
      final pt = _liftX(px);
      if (pt == null) return false;
      final rx = _fromBytes(sig64.sublist(0, 32));
      final s = _fromBytes(sig64.sublist(32, 64));
      if (rx >= p || s >= n) return false;
      final e = _fromBytes(
              _taggedHash('BIP0340/challenge', [...sig64.sublist(0, 32), ...pubX32, ...msg32])) %
          n;
      final r = _add(_mul(s, g), _mul(n - e, pt));
      if (r == null) return false;
      return r.y.isEven && r.x == rx;
    } catch (_) {
      return false;
    }
  }

  static _Point? _liftX(BigInt x) {
    final c = (x.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
    var y = c.modPow((p + BigInt.one) >> 2, p);
    if ((y * y) % p != c) return null;
    if (!y.isEven) y = p - y;
    return _Point(x, y);
  }

  static _Point? _add(_Point? a, _Point? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a.x == b.x) {
      if ((a.y + b.y) % p == BigInt.zero) return null;
      final lam =
          (BigInt.from(3) * a.x * a.x) % p * _inv(BigInt.two * a.y % p) % p;
      final x = (lam * lam - BigInt.two * a.x) % p;
      return _Point(x, (lam * (a.x - x) - a.y) % p);
    }
    final lam = (b.y - a.y) % p * _inv((b.x - a.x) % p) % p;
    final x = (lam * lam - a.x - b.x) % p;
    return _Point(x, (lam * (a.x - x) - a.y) % p);
  }

  static _Point? _mul(BigInt k, _Point pnt) {
    var e = k % n;
    if (e == BigInt.zero) return null;
    _Point? r;
    var base = pnt;
    while (e > BigInt.zero) {
      if ((e & BigInt.one) == BigInt.one) r = _add(r, base);
      base = _add(base, base)!;
      e = e >> 1;
    }
    return r;
  }

  static BigInt _inv(BigInt a) => a.modInverse(p);
}

class _Point {
  final BigInt x;
  final BigInt y;
  _Point(this.x, this.y);
}
