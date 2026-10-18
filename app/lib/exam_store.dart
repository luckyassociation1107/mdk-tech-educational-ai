import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'academic_models.dart';

/// All exam history lives on this device (student chose fully-local mode).
class ExamStore {
  static const _key = 'exam_results_v1';

  static Future<List<ExamResult>> loadAll() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List).whereType<Map>().map((e) => ExamResult.fromJson(e.map((k, v) => MapEntry(k.toString(), v)))).toList();
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
    await p.setString(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> clearAll() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
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
