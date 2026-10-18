import 'package:shared_preferences/shared_preferences.dart';

/// App settings + learning progress, stored on the device.
class AppSettings {
  String language; // en-IN | te-IN
  String brain; // offline | playwright
  String brainServerUrl;
  String theme; // board theme: auto | green_board | ...
  String resolution; // 1280x720 | 854x480
  int pagesPerPart;

  AppSettings({
    this.language = 'en-IN',
    this.brain = 'offline',
    this.brainServerUrl = '',
    this.theme = 'auto',
    this.resolution = '854x480',
    this.pagesPerPart = 6,
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
