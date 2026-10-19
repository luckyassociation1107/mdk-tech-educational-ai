import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App settings + learning progress, stored on the device.
class AppSettings {
  /// Long-lived secrets (catalog private key + catalog secret) live in
  /// platform secure storage (Android Keystore / Windows DPAPI), never
  /// in plain SharedPreferences. Older installs migrate on first load.
  static const _secure = FlutterSecureStorage();
  static const _nsecKey = 'sec_catalog_nsec';
  static const _secretKey = 'sec_catalog_secret';

  static Future<String> _secureRead(String key, SharedPreferences p, String legacyPref) async {
    try {
      final v = await _secure.read(key: key);
      if (v != null && v.isNotEmpty) return v;
      final legacy = p.getString(legacyPref) ?? '';
      if (legacy.isNotEmpty) {
        await _secure.write(key: key, value: legacy);
        await p.remove(legacyPref);
        return legacy;
      }
    } catch (_) {}
    return '';
  }

  static Future<void> _secureWrite(String key, String value, SharedPreferences p, String legacyPref) async {
    try {
      if (value.isEmpty) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {}
    await p.remove(legacyPref);
  }

  String language; // en-IN | te-IN
  String brain; // offline | playwright
  String brainServerUrl;
  String theme; // board theme: auto | green_board | ...
  String resolution; // 1280x720 | 854x480
  int pagesPerPart;
  // Cloud link catalog (Google Form write + Sheet read). See catalog_service.dart.
  String catalogFormUrl;
  String catalogEntryId;
  String catalogSheetUrl;
  // Nostr catalog: shared school keypair (hex). nsec only on publishers.
  String catalogNsec;
  String catalogNpub;
  // School catalog secret: entries are AES-256-GCM encrypted with it.
  String catalogSecret;

  AppSettings({
    this.language = 'en-IN',
    this.brain = 'offline',
    this.brainServerUrl = '',
    this.theme = 'auto',
    this.resolution = '854x480',
    this.pagesPerPart = 6,
    this.catalogFormUrl = '',
    this.catalogEntryId = '',
    this.catalogSheetUrl = '',
    this.catalogNsec = '',
    this.catalogNpub = '',
    this.catalogSecret = '',
  });

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      language: p.getString('set_language') ?? 'en-IN',
      brain: p.getString('set_brain') ?? 'offline',
      brainServerUrl: p.getString('set_brain_url') ?? '',
      theme: p.getString('set_theme') ?? 'auto',
      resolution: p.getString('set_resolution') ?? '854x480',
      pagesPerPart: p.getInt('set_pages_per_part') ?? 6,
      catalogFormUrl: p.getString('set_catalog_form') ?? '',
      catalogEntryId: p.getString('set_catalog_entry') ?? '',
      catalogSheetUrl: p.getString('set_catalog_sheet') ?? '',
      catalogNsec: await _secureRead(_nsecKey, p, 'set_catalog_nsec'),
      catalogNpub: p.getString('set_catalog_npub') ?? '',
      catalogSecret: await _secureRead(_secretKey, p, 'set_catalog_secret'),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('set_language', language);
    await p.setString('set_brain', brain);
    await p.setString('set_brain_url', brainServerUrl);
    await p.setString('set_theme', theme);
    await p.setString('set_resolution', resolution);
    await p.setInt('set_pages_per_part', pagesPerPart);
    await p.setString('set_catalog_form', catalogFormUrl);
    await p.setString('set_catalog_entry', catalogEntryId);
    await p.setString('set_catalog_sheet', catalogSheetUrl);
    await p.setString('set_catalog_npub', catalogNpub);
    await _secureWrite(_nsecKey, catalogNsec, p, 'set_catalog_nsec');
    await _secureWrite(_secretKey, catalogSecret, p, 'set_catalog_secret');
  }
}

/// Per-textbook learning progress (mirrors the engine's unlock state so
/// the UI stays truthful even before the series is re-fetched).
class ProgressStore {
  static String _doneKey(String sessionId) => 'completed_parts_$sessionId';
  static String _posKey(String videoPath) => 'watch_pos_$videoPath';

  static Future<Set<int>> completedParts(String sessionId) async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_doneKey(sessionId)) ?? const []).map(int.tryParse).whereType<int>().toSet();
  }

  static Future<void> setPartCompleted(String sessionId, int part, bool done) async {
    final p = await SharedPreferences.getInstance();
    final cur = await completedParts(sessionId);
    done ? cur.add(part) : cur.remove(part);
    await p.setStringList(_doneKey(sessionId), cur.map((e) => '$e').toList());
  }

  static Future<Duration> watchPosition(String videoPath) async {
    final p = await SharedPreferences.getInstance();
    return Duration(milliseconds: p.getInt(_posKey(videoPath)) ?? 0);
  }

  static Future<void> saveWatchPosition(String videoPath, Duration pos) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_posKey(videoPath), pos.inMilliseconds);
  }
}
