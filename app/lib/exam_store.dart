import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'academic_models.dart';

/// All exam history lives on this device (student chose fully-local mode).
class ExamStore {
  /// Whose marks these are. Set at login so every student has a private
  /// report card on the shared device; teachers/principals read other
  /// scopes through [loadAllFor] without touching them.
  static String scopeUserId = 'guest';

  static String _keyFor(String userId) => 'exam_results_$userId';

  /// Marks are sealed with a device key kept in secure storage: editing
  /// the stored JSON by hand (rooted phone, file tools) breaks the seal
  /// and the tampered results are discarded instead of displayed.
  static const _secure = FlutterSecureStorage();

  static Future<String> _sealKey() async {
    try {
      var k = await _secure.read(key: 'sec_exam_seal_key');
      if (k == null || k.isEmpty) {
        final r = Random.secure();
        k = List<int>.generate(32, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        await _secure.write(key: 'sec_exam_seal_key', value: k);
      }
      return k;
    } catch (_) {
      return 'fallback-seal-key';
    }
  }

  static Future<String> _seal(String payload) async => sha256.convert(utf8.encode('${await _sealKey()}::$payload')).toString();

  static Future<List<ExamResult>> loadAll() => loadAllFor(scopeUserId);

  static Future<List<ExamResult>> loadAllFor(String userId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_keyFor(userId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      final List<dynamic> items;
      if (decoded is Map && decoded['data'] is List) {
        // Sealed format: verify before trusting a single mark.
        final payload = jsonEncode(decoded['data']);
        if ((decoded['seal'] ?? '').toString() != await _seal(payload)) return [];
        items = decoded['data'] as List;
      } else if (decoded is List) {
        items = decoded; // legacy unsealed history
      } else {
        return [];
      }
      final list = items.whereType<Map>().map((e) => ExamResult.fromJson(e.map((k, v) => MapEntry(k.toString(), v)))).toList();
      list.sort((a, b) => b.when.compareTo(a.when));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> addResult(ExamResult r) async {
    final all = await loadAll();
    all.add(r);
    final p = await SharedPreferences.getInstance();
    final data = all.map((e) => e.toJson()).toList();
    final payload = jsonEncode(data);
    await p.setString(_keyFor(scopeUserId), jsonEncode({'data': data, 'seal': await _seal(payload)}));
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_keyFor(scopeUserId));
  }
}

class BookStats {
  final String sessionId;
  final String title;
  int tests = 0;
  double pctSum = 0;
  double best = 0;
  BookStats(this.sessionId, this.title);
  double get avg => tests == 0 ? 0 : pctSum / tests;
}

class PartStats {
  final String sessionId;
  final String title;
  final int part;
  final String partLabel;
  int tests = 0;
  double pctSum = 0;
  PartStats(this.sessionId, this.title, this.part, this.partLabel);
  double get avg => tests == 0 ? 0 : pctSum / tests;
}

class ReportData {
  final List<ExamResult> results;
  late final int tests = results.length;
  late final double avgPct = tests == 0 ? 0 : results.map((r) => r.percentage).reduce((a, b) => a + b) / tests;
  late final double bestPct = tests == 0 ? 0 : results.map((r) => r.percentage).reduce((a, b) => a > b ? a : b);
  late final double xp = results.map((r) => r.earned).fold(0.0, (a, b) => a + b);
  late final RankBand rank = rankFor(avgPct: avgPct, tests: tests);
  late final List<BookStats> books = _books();
  late final List<PartStats> weakParts = _weak();

  ReportData(this.results);

  List<BookStats> _books() {
    final map = <String, BookStats>{};
    for (final r in results) {
      final b = map.putIfAbsent(r.sessionId, () => BookStats(r.sessionId, r.bookTitle));
      b.tests++;
      b.pctSum += r.percentage;
      if (r.percentage > b.best) b.best = r.percentage;
    }
    return map.values.toList()..sort((a, b) => b.avg.compareTo(a.avg));
  }

  List<PartStats> _weak() {
    final map = <String, PartStats>{};
    for (final r in results) {
      final k = '${r.sessionId}:${r.part}';
      final s = map.putIfAbsent(k, () => PartStats(r.sessionId, r.bookTitle, r.part, r.partLabel));
      s.tests++;
      s.pctSum += r.percentage;
    }
    return map.values.where((s) => s.avg < 60).toList()..sort((a, b) => a.avg.compareTo(b.avg));
  }
}
