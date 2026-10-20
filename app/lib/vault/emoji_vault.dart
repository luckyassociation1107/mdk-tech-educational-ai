import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────
///  EmojiVault — an on-device, encrypted, emoji-encoded database.
///
///  • Every child profile (name, avatar, PIN) lives in this vault.
///  • The child's own data (marks, logs, results) is encrypted with a key
///    derived from THEIR PIN (PBKDF2-HMAC-SHA256, 120 000 rounds) and
///    sealed with an HMAC-SHA256 tag, so without the PIN the blob is
///    unreadable — even if the file is copied off the phone.
///  • The whole vault is written as an EMOJI string (base64 → 64-emoji
///    alphabet). It can be exported as one emoji "code" and imported on
///    another phone — same idea as an encrypted backup made of emojis.
///
///  Free, unlimited (phone storage), fully offline and stable.
///  Honest limit: this is local storage + portable encrypted backup; it is
///  not a cloud database — copying requires the emoji code.
/// ─────────────────────────────────────────────────────────────────────

/// 64 distinct emojis = one per base64 symbol.
const List<String> kEmojiAlphabet = [
  '🍎', '🍌', '🍇', '🍓', '🍑', '🍍', '🥭', '🍊',
  '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
  '🌵', '🌲', '🌳', '🌴', '🌱', '🌿', '🍀', '🍁',
  '🚀', '🛸', '🚁', '🚂', '🚗', '🚌', '🚲', '⛵',
  '⭐', '🌟', '✨', '⚡', '🔥', '🌈', '☀️', '🌙',
  '🎈', '🎉', '🎁', '🎨', '🎵', '🎮', '🏆', '⚽',
  '📚', '📖', '✏️', '🖍️', '📐', '🔬', '🧪', '🧠',
  '💙', '💚', '💛', '🧡', '💜', '🤍', '🖤', '🤎',
];

class EmojiCodec {
  static final Map<String, int> _index = {
    for (var i = 0; i < kEmojiAlphabet.length; i++) kEmojiAlphabet[i]: i,
  };

  static const _header = '🎒';

  /// bytes → emoji string (prefixed with 🎒 so it is recognisable).
  static String encode(List<int> bytes) {
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    final sb = StringBuffer(_header);
    for (final ch in b64.split('')) {
      final i = _b64Index(ch);
      if (i < 0) continue;
      sb.write(kEmojiAlphabet[i]);
    }
    return sb.toString();
  }

  static Uint8List decode(String emojiText) {
    final trimmed = emojiText.replaceAll(RegExp(r'\s+'), '');
    final start = trimmed.startsWith(_header) ? _header.length : 0;
    // Walk by runes so multi-codepoint emojis stay intact.
    final runes = trimmed.substring(start).runes.toList();
    final sb = StringBuffer();
    // Re-group runes into emoji glyphs by checking the alphabet.
    var i = 0;
    while (i < runes.length) {
      var matched = false;
      for (var len = 3; len >= 1 && !matched; len--) {
        if (i + len > runes.length) continue;
        final glyph = String.fromCharCodes(runes.sublist(i, i + len));
        final idx = _index[glyph];
        if (idx != null) {
          sb.write(_b64Char(idx));
          i += len;
          matched = true;
        }
      }
      if (!matched) i++;
    }
    var b64 = sb.toString();
    final pad = b64.length % 4;
    if (pad != 0) b64 = b64.padRight(b64.length + (4 - pad), '=');
    return base64Url.decode(b64);
  }

  static int _b64Index(String ch) => _b64.indexOf(ch);

  static const _b64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static String _b64Char(int i) => _b64[i % 64];
}

/// Minimal, dependency-free crypto helpers (PBKDF2 + HMAC-sealed payload).
class VaultCrypto {
  static Uint8List pbkdf2(String password, List<int> salt, {int rounds = 120000, int length = 32}) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final blocks = (length / 32).ceil();
    final out = BytesBuilder();
    for (var block = 1; block <= blocks; block++) {
      final blockSalt = Uint8List.fromList([...salt, (block >> 24) & 0xFF, (block >> 16) & 0xFF, (block >> 8) & 0xFF, block & 0xFF]);
      var u = hmac.convert(blockSalt).bytes;
      final acc = List<int>.from(u);
      for (var i = 1; i < rounds; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < acc.length; j++) {
          acc[j] ^= u[j];
        }
      }
      out.add(acc);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  /// SHA-256 based stream cipher + HMAC tag. This is a one-time keystream
  /// derived from the PIN key; never reused for two different payloads
  /// because every save generates a fresh random nonce.
  static Map<String, String> seal(String plaintext, Uint8List key) {
    final rnd = math.Random.secure();
    final nonce = Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
    final stream = _keystream(key, nonce, utf8.encode(plaintext).length);
    final body = utf8.encode(plaintext);
    for (var i = 0; i < body.length; i++) {
      body[i] ^= stream[i];
    }
    final mac = Hmac(sha256, key).convert([...nonce, ...body]).bytes;
    return {
      'n': base64UrlEncode(nonce),
      'c': base64UrlEncode(body),
      't': base64UrlEncode(mac.sublist(0, 16)),
    };
  }

  static String? open(Map sealed, Uint8List key) {
    try {
      final nonce = base64Url.decode('${sealed['n']}');
      final body = base64Url.decode('${sealed['c']}');
      final tag = base64Url.decode('${sealed['t']}');
      final mac = Hmac(sha256, key).convert([...nonce, ...body]).bytes.sublist(0, 16);
      for (var i = 0; i < 16; i++) {
        if (mac[i] != tag[i]) return null; // wrong PIN or tampered
      }
      final stream = _keystream(key, Uint8List.fromList(nonce), body.length);
      final out = List<int>.from(body);
      for (var i = 0; i < out.length; i++) {
        out[i] ^= stream[i];
      }
      return utf8.decode(out);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _keystream(Uint8List key, Uint8List nonce, int length) {
    final hmac = Hmac(sha256, key);
    final out = BytesBuilder();
    var counter = 0;
    while (out.length < length) {
      out.add(hmac.convert([...nonce, counter & 0xFF, (counter >> 8) & 0xFF, (counter >> 16) & 0xFF, (counter >> 24) & 0xFF]).bytes);
      counter++;
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  static String hashPin(String pin, String saltB64) => base64UrlEncode(
        pbkdf2(pin, base64Url.decode(saltB64), rounds: 60000, length: 16),
      );
}

/// One child account.
class ChildProfile {
  final String id;
  final String name;
  final String avatar;
  final String salt; // base64
  final String verifier; // PBKDF2(pin) hash for fast check
  final int createdAt;
  int lastLogin;
  int loginCount;
  Map<String, dynamic> data; // decrypted only while logged in

  ChildProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.salt,
    required this.verifier,
    required this.createdAt,
    this.lastLogin = 0,
    this.loginCount = 0,
    Map<String, dynamic>? data,
  }) : data = data ?? {};

  Map<String, dynamic> toMeta() => {
        'id': id,
        'name': name,
        'avatar': avatar,
        'salt': salt,
        'verifier': verifier,
        'createdAt': createdAt,
        'lastLogin': lastLogin,
        'loginCount': loginCount,
      };

  static ChildProfile fromMeta(Map m, {Map<String, dynamic>? data}) => ChildProfile(
        id: '${m['id']}',
        name: '${m['name'] ?? 'Learner'}',
        avatar: '${m['avatar'] ?? '🐼'}',
        salt: '${m['salt']}',
        verifier: '${m['verifier']}',
        createdAt: (m['createdAt'] as num?)?.toInt() ?? 0,
        lastLogin: (m['lastLogin'] as num?)?.toInt() ?? 0,
        loginCount: (m['loginCount'] as num?)?.toInt() ?? 0,
        data: data,
      );
}

class VaultStore {
  static const _kBlob = 'emoji_vault_blob';
  static const _kActive = 'emoji_vault_active_profile';

  static String? _emojiBlob;
  static List<Map<String, dynamic>> _profilesMeta = [];
  static Map<String, Map<String, dynamic>> _sealedData = {};
  static Map<String, dynamic> _settings = {};
  static ChildProfile? current;
  static Uint8List? _currentKey;

  static String get emojiBlob => _emojiBlob ?? '';
  static List<ChildProfile> get profiles => _profilesMeta.map((m) => ChildProfile.fromMeta(m)).toList();
  static bool get hasProfiles => _profilesMeta.isNotEmpty;
  static String? get activeProfileId => current?.id;

  /// Root JSON that gets emoji-encoded.
  static Map<String, dynamic> _root() => {
        'app': 'AI Textbook Classroom',
        'kind': 'emoji-vault',
        'version': 1,
        'profiles': _profilesMeta,
        'vault': _sealedData, // id -> sealed child data
        'settings': _settings,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _emojiBlob = await p.getString(_kBlob);
    _profilesMeta = [];
    _sealedData = {};
    _settings = {};
    if (_emojiBlob == null || _emojiBlob!.isEmpty) return;
    try {
      final raw = utf8.decode(EmojiCodec.decode(_emojiBlob!));
      final root = jsonDecode(raw);
      if (root is! Map) return;
      _profilesMeta = ((root['profiles'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      final vault = root['vault'];
      if (vault is Map) {
        _sealedData = {
          for (final e in vault.entries)
            '${e.key}': (e.value as Map).map((k, v) => MapEntry(k.toString(), v)),
        };
      }
      final st = root['settings'];
      if (st is Map) _settings = st.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      // Corrupt vault: start fresh rather than crash.
      _profilesMeta = [];
      _sealedData = {};
    }
  }

  static Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    _emojiBlob = EmojiCodec.encode(utf8.encode(jsonEncode(_root())));
    await p.setString(_kBlob, _emojiBlob!);
  }

  static String _newId() => 'child_${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(999)}';

  static String _newSalt() {
    final rnd = math.Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
  }

  static bool pinLooksValid(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  static Future<ChildProfile> createProfile({
    required String name,
    required String avatar,
    required String pin,
  }) async {
    if (!pinLooksValid(pin)) throw const FormatException('PIN must be 4–6 digits');
    await load();
    final salt = _newSalt();
    final profile = ChildProfile(
      id: _newId(),
      name: name.trim().isEmpty ? 'Learner' : name.trim(),
      avatar: avatar,
      salt: salt,
      verifier: VaultCrypto.hashPin(pin, salt),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      data: {
        'logs': <Map<String, dynamic>>[],
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
    _profilesMeta.add(profile.toMeta());
    await _sealFor(profile, pin);
    await _save();
    return profile;
  }

  static Uint8List _keyFor(ChildProfile profile, String pin) =>
      VaultCrypto.pbkdf2(pin, base64Url.decode(profile.salt), rounds: 120000, length: 32);

  static Future<void> _sealFor(ChildProfile profile, String pin) async {
    final key = _keyFor(profile, pin);
    _sealedData[profile.id] = VaultCrypto.seal(jsonEncode(profile.data), key);
  }

  /// Returns the profile on success, null on a wrong PIN.
  static Future<ChildProfile?> login(String id, String pin) async {
    await load();
    final idx = _profilesMeta.indexWhere((m) => '${m['id']}' == id);
    if (idx < 0) return null;
    final meta = _profilesMeta[idx];
    final base = ChildProfile.fromMeta(meta);
    if (VaultCrypto.hashPin(pin, base.salt) != base.verifier) {
      return null;
    }
    final key = _keyFor(base, pin);
    final sealed = _sealedData[id];
    final plain = sealed == null ? '{}' : VaultCrypto.open(sealed, key);
    if (plain == null) return null;
    final profile = ChildProfile.fromMeta(meta, data: jsonDecode(plain) as Map<String, dynamic>);
    profile.lastLogin = DateTime.now().millisecondsSinceEpoch;
    profile.loginCount += 1;
    _profilesMeta[idx] = profile.toMeta();
    current = profile;
    _currentKey = key;
    _log('login', 'PIN verified • session started');
    await _persistCurrent();
    return profile;
  }

  static Future<void> _persistCurrent() async {
    final c = current;
    final key = _currentKey;
    if (c == null || key == null) return;
    _sealedData[c.id] = VaultCrypto.seal(jsonEncode(c.data), key);
    await _save();
  }

  static Future<void> _saveCurrentMeta() async {
    final c = current;
    if (c == null) return;
    final idx = _profilesMeta.indexWhere((m) => '${m['id']}' == c.id);
    if (idx >= 0) _profilesMeta[idx] = c.toMeta();
  }

  static void _log(String type, String message) {
    final c = current;
    if (c == null) return;
    final logs = (c.data['logs'] as List?) ?? <dynamic>[];
    logs.insert(0, {
      'at': DateTime.now().millisecondsSinceEpoch,
      'type': type,
      'msg': message,
    });
    if (logs.length > 200) logs.removeRange(200, logs.length);
    c.data['logs'] = logs;
  }

  /// Activity log while a child is logged in.
  static Future<void> log(String type, String message) async {
    if (current == null) return;
    _log(type, message);
    await _saveCurrentMeta();
    await _persistCurrent();
  }

  static Future<void> put(String key, dynamic value) async {
    final c = current;
    if (c == null) return;
    c.data[key] = value;
    await _persistCurrent();
  }

  static dynamic get(String key) => current?.data[key];

  static Future<void> changePin(String oldPin, String newPin) async {
    if (!pinLooksValid(newPin)) throw const FormatException('PIN must be 4–6 digits');
    final c = current;
    if (c == null) return;
    final salt = _newSalt();
    final meta = {'salt': salt, 'verifier': VaultCrypto.hashPin(newPin, salt)};
    final profile = ChildProfile(
      id: c.id,
      name: c.name,
      avatar: c.avatar,
      salt: salt,
      verifier: meta['verifier']!,
      createdAt: c.createdAt,
      lastLogin: c.lastLogin,
      loginCount: c.loginCount,
      data: c.data,
    );
    current = profile;
    _currentKey = _keyFor(profile, newPin);
    await _sealFor(profile, newPin);
    await _saveCurrentMeta();
    await _save();
    _log('pin', 'PIN changed');
    await _persistCurrent();
  }

  static Future<void> logout() async {
    final c = current;
    if (c != null) {
      _log('logout', 'Session closed');
      await _persistCurrent();
    }
    current = null;
    _currentKey = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kActive);
  }

  static Future<void> deleteProfile(String id) async {
    _profilesMeta.removeWhere((m) => '${m['id']}' == id);
    _sealedData.remove(id);
    if (current?.id == id) {
      current = null;
      _currentKey = null;
    }
    await _save();
  }

  /// Rename / change avatar while logged in.
  static Future<void> updateProfile({String? name, String? avatar}) async {
    final c = current;
    if (c == null) return;
    final updated = ChildProfile(
      id: c.id,
      name: (name != null && name.trim().isNotEmpty) ? name.trim() : c.name,
      avatar: avatar ?? c.avatar,
      salt: c.salt,
      verifier: c.verifier,
      createdAt: c.createdAt,
      lastLogin: c.lastLogin,
      loginCount: c.loginCount,
      data: c.data,
    );
    current = updated;
    await _saveCurrentMeta();
    await _persistCurrent();
  }

  // ---------- backup / transfer ----------

  static String exportEmoji() {
    _emojiBlob = EmojiCodec.encode(utf8.encode(jsonEncode(_root())));
    return _emojiBlob!;
  }

  static Future<int> importEmoji(String emojiText) async {
    final raw = utf8.decode(EmojiCodec.decode(emojiText));
    final root = jsonDecode(raw);
    if (root is! Map || '${root['kind']}' != 'emoji-vault') {
      throw const FormatException('This is not a classroom vault code');
    }
    final profiles = ((root['profiles'] as List?) ?? const []).whereType<Map>().map((m) => m.map((k, v) => MapEntry(k.toString(), v))).toList();
    final vault = root['vault'];
    final sealed = <String, Map<String, dynamic>>{};
    if (vault is Map) {
      for (final e in vault.entries) {
        sealed['${e.key}'] = (e.value as Map).map((k, v) => MapEntry(k.toString(), v));
      }
    }
    _profilesMeta = profiles;
    _sealedData = sealed;
    await _save();
    return profiles.length;
  }

  // ---------- root access (for the emoji table packet / Nostr sync) ----------

  static Map<String, dynamic> exportRoot() => _root();

  static Future<void> applyRoot(Map root) async {
    _profilesMeta = ((root['profiles'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    final vault = root['vault'];
    _sealedData = {};
    if (vault is Map) {
      for (final e in vault.entries) {
        if (e.value is Map) {
          _sealedData['${e.key}'] =
              (e.value as Map).map((k, v) => MapEntry(k.toString(), v));
        }
      }
    }
    final st = root['settings'];
    _settings = st is Map
        ? st.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    await _save();
  }

  /// The Nostr identity key of this device, generated once and then kept
  /// INSIDE the vault — so the emoji backup code also carries it and a new
  /// phone can find the same relay events again.
  static Future<String> nostrSecret() async {
    final existing = _settings['nostr_sk'];
    if (existing is String && existing.length == 64) return existing;
    final rnd = math.Random.secure();
    final hex = List<int>.generate(32, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    _settings['nostr_sk'] = hex;
    await _save();
    return hex;
  }

  static String? get nostrSecretCached {
    final v = _settings['nostr_sk'];
    return v is String && v.length == 64 ? v : null;
  }

  static Future<void> setRelays(List<String> relays) async {
    _settings['nostr_relays'] = relays;
    await _save();
  }

  static List<String> get savedRelays {
    final r = _settings['nostr_relays'];
    if (r is List) return r.map((e) => '$e').toList();
    return const [];
  }

  /// Auto-backup switch (relay sync after each finished class/test).
  static bool get autoBackup => '${_settings['nostr_auto'] ?? 'true'}' == 'true';

  static Future<void> setAutoBackup(bool on) async {
    _settings['nostr_auto'] = on ? 'true' : 'false';
    await _save();
  }

  static Future<void> setLastSync(int ms, String eventId) async {
    _settings['last_sync'] = ms;
    _settings['last_event'] = eventId;
    await _save();
  }

  static int get lastSync => (_settings['last_sync'] as num?)?.toInt() ?? 0;
  static String get lastEventId => '${_settings['last_event'] ?? ''}';

  /// Unlocked data of the logged-in child (for the activity screen).
  static List<Map<String, dynamic>> get logs {
    final c = current;
    if (c == null) return [];
    return ((c.data['logs'] as List?) ?? const []).whereType<Map>().map((m) => m.map((k, v) => MapEntry(k.toString(), v))).toList();
  }
}
