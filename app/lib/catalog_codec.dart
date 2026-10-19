import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// One shared-PDF link in the cloud catalog.
class CatalogEntry {
  final String t; // title
  final String u; // Gofile download page
  final String by; // teacher name
  final String cls; // class or '' for whole school
  final int ts; // epoch millis

  const CatalogEntry({required this.t, required this.u, this.by = '', this.cls = '', required this.ts});

  Map<String, dynamic> toJson() => {'t': t, 'u': u, 'by': by, 'cls': cls, 'ts': ts};

  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        t: (j['t'] ?? '').toString(),
        u: (j['u'] ?? '').toString(),
        by: (j['by'] ?? '').toString(),
        cls: (j['cls'] ?? '').toString(),
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// Entries travel as ONE token string in the catalog:
///
///   MDKENC2.<base64(iv + AES-256-GCM ciphertext)>   (school secret set;
///                                                    key via PBKDF2 200k)
///   MDKENC1.…                                       (legacy key, read-only)
///   MDKCAT1.<base64(gzip(json))>                    (encoded, no secret)
///   MDKRAW1.<base64(json)>                          (encoded, no secret)
///
/// With the school's own catalog secret configured, the entry is really
/// ENCRYPTED (AES-256-GCM, key = SHA-256 of the secret) before it ever
/// leaves the phone. Relays/sheets then store only ciphertext, which
/// nobody can read without the secret. Devices with the secret decrypt
/// and render the catalog beautifully; devices without it simply skip
/// encrypted entries. Older encoded entries stay readable for migration.
class CatalogCodec {
  static const _gzPrefix = 'MDKCAT1.';
  static const _rawPrefix = 'MDKRAW1.';
  static const _encPrefix = 'MDKENC1.';
  static const _enc2Prefix = 'MDKENC2.';
  static final _tokenRe = RegExp(r'MDK(?:CAT1|RAW1|ENC1|ENC2)\.[A-Za-z0-9+/=]+');

  /// Legacy v1 key (single SHA-256) — decrypt-only, for old entries.
  static Uint8List _keyBytesV1(String secret) {
    final d = SHA256Digest();
    return d.process(Uint8List.fromList(utf8.encode('MDK-CATALOG-v1::$secret')));
  }

  static String? _cachedSecret;
  static Uint8List? _cachedKeyV2;

  /// Current key: PBKDF2-HMAC-SHA256, 200k iterations. Ciphertext sits on
  /// public relays forever, so deriving the key must be expensive; the
  /// cost is paid once per app run thanks to this cache.
  static Uint8List _keyBytesV2(String secret) {
    final s = secret.trim();
    if (_cachedKeyV2 != null && _cachedSecret == s) return _cachedKeyV2!;
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(Uint8List.fromList(utf8.encode('MDK-CATALOG-SALT-v2')), 200000, 32));
    final key = derivator.process(Uint8List.fromList(utf8.encode(s)));
    _cachedSecret = s;
    _cachedKeyV2 = key;
    return key;
  }

  static Uint8List _aes(bool forEncryption, Uint8List key, Uint8List iv, Uint8List data) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(forEncryption, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    return cipher.process(data);
  }

  static String encodeEncrypted(CatalogEntry e, String secret) {
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(e.toJson())));
    final iv = Uint8List.fromList(List<int>.generate(12, (_) => Random.secure().nextInt(256)));
    final ct = _aes(true, _keyBytesV2(secret), iv, plain);
    return '$_enc2Prefix${base64.encode([...iv, ...ct])}';
  }

  static String encode(CatalogEntry e, {String catalogSecret = ''}) {
    if (catalogSecret.trim().isNotEmpty) return encodeEncrypted(e, catalogSecret);
    final bytes = utf8.encode(jsonEncode(e.toJson()));
    try {
      final gz = gzip.encode(bytes);
      if (gz.length < bytes.length) return '$_gzPrefix${base64.encode(gz)}';
    } catch (_) {}
    return '$_rawPrefix${base64.encode(bytes)}';
  }

  static CatalogEntry? tryDecode(String? text, {String catalogSecret = ''}) {
    if (text == null) return null;
    final m = _tokenRe.firstMatch(text);
    if (m == null) return null;
    final token = m.group(0)!;
    try {
      final payload = token.substring(token.indexOf('.') + 1);
      final raw = base64.decode(payload);
      final List<int> jsonBytes;
      if (token.startsWith(_enc2Prefix) || token.startsWith(_encPrefix)) {
        final secret = catalogSecret.trim();
        if (secret.isEmpty || raw.length <= 12) return null;
        final iv = Uint8List.fromList(raw.sublist(0, 12));
        final ct = Uint8List.fromList(raw.sublist(12));
        final key = token.startsWith(_enc2Prefix) ? _keyBytesV2(secret) : _keyBytesV1(secret);
        jsonBytes = _aes(false, key, iv, ct);
      } else if (token.startsWith(_gzPrefix)) {
        jsonBytes = gzip.decode(raw);
      } else {
        jsonBytes = raw;
      }
      final j = jsonDecode(utf8.decode(jsonBytes));
      if (j is Map) return CatalogEntry.fromJson(j.map((k, v) => MapEntry(k.toString(), v)));
    } catch (_) {}
    return null;
  }

  /// Parses a Google Sheets gviz JSON response body.
  static List<CatalogEntry> parseSheetBody(String body, {String catalogSecret = ''}) {
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start < 0 || end <= start) return const [];
    try {
      final root = jsonDecode(body.substring(start, end + 1)) as Map<String, dynamic>;
      final rows = (((root['table'] as Map?)?['rows']) as List?) ?? const [];
      final out = <CatalogEntry>[];
      final seen = <String>{};
      for (final r in rows) {
        final cells = ((r as Map)['c'] as List?) ?? const [];
        for (final c in cells) {
          if (c is Map && c['v'] is String) {
            final e = tryDecode(c['v'] as String, catalogSecret: catalogSecret);
            if (e != null && e.u.isNotEmpty && seen.add(e.u)) out.add(e);
          }
        }
      }
      out.sort((a, b) => b.ts.compareTo(a.ts));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Accepts a normal Sheet URL and returns its gviz JSON URL.
  static String sheetToGviz(String url) {
    final u = url.trim();
    if (u.contains('gviz')) return u;
    final m = RegExp(r'/spreadsheets/d/([A-Za-z0-9-_]+)').firstMatch(u);
    if (m == null) return u;
    return 'https://docs.google.com/spreadsheets/d/${m.group(1)}/gviz/tq?tqx=out:json';
  }

  /// Accepts a Form view URL and returns the formResponse endpoint.
  static String formToResponse(String url) {
    var u = url.trim();
    u = u.replaceAll('/viewform', '/formResponse');
    if (u.contains('?')) u = u.substring(0, u.indexOf('?'));
    if (!u.endsWith('/formResponse')) u = '$u/formResponse';
    return u;
  }
}
