import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Streaks, daily goal, XP level, badges and a full on-device backup.
/// Everything is stored in SharedPreferences on this phone only.
class StudyStats {
  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Registers study activity for today. Safe to call very often.
  static Future<void> recordActivity({int scenes = 0, int seconds = 0}) async {
    final p = await SharedPreferences.getInstance();
    final today = _dayKey(DateTime.now());
    final days = (p.getStringList('study_days') ?? <String>[]).toSet()
      ..add(today);
    await p.setStringList('study_days', days.toList());
    if (scenes > 0)
      await p.setInt('study_scenes_$today',
          (p.getInt('study_scenes_$today') ?? 0) + scenes);
    if (seconds > 0)
      await p.setInt(
          'study_secs_$today', (p.getInt('study_secs_$today') ?? 0) + seconds);
    // keep only 400 days
    if (days.length > 400) {
      final sorted = days.toList()..sort();
      await p.setStringList('study_days', sorted.sublist(sorted.length - 400));
    }
  }

  static Future<void> recordClassFinished() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('study_classes', (p.getInt('study_classes') ?? 0) + 1);
    await recordActivity(scenes: 1);
  }

  static Future<int> classesFinished() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('study_classes') ?? 0;
  }

  /// Consecutive study days ending today (or yesterday, so a day is never
  /// lost just because the app was opened late at night).
  static Future<int> streak() async {
    final p = await SharedPreferences.getInstance();
    final days = (p.getStringList('study_days') ?? const <String>[]).toSet();
    if (days.isEmpty) return 0;
    var cursor = _dateOnly(DateTime.now());
    if (!days.contains(_dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(_dayKey(cursor))) return 0;
    }
    var n = 0;
    while (days.contains(_dayKey(cursor))) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Last 7 days, oldest first, as booleans (did the student study).
  static Future<List<bool>> last7() async {
    final p = await SharedPreferences.getInstance();
    final days = (p.getStringList('study_days') ?? const <String>[]).toSet();
    final now = _dateOnly(DateTime.now());
    return List<bool>.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return days.contains(_dayKey(d));
    });
  }

  static Future<int> scenesToday() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt('study_scenes_${_dayKey(DateTime.now())}') ?? 0;
  }

  static Future<int> minutesToday() async {
    final p = await SharedPreferences.getInstance();
    return ((p.getInt('study_secs_${_dayKey(DateTime.now())}') ?? 0) / 60)
        .floor();
  }

  /// Total XP across every textbook on this phone.
  static Future<int> totalXp() async {
    final p = await SharedPreferences.getInstance();
    var sum = 0;
    for (final k in p.getKeys()) {
      if (k.startsWith('xp_')) sum += p.getInt(k) ?? 0;
    }
    return sum;
  }

  static int levelForXp(int xp) => 1 + (xp ~/ 250);

  static String levelName(int level) {
    const names = [
      'Starter',
      'Learner',
      'Explorer',
      'Achiever',
      'Scholar',
      'Thinker',
      'Topper',
      'Master',
      'Genius',
      'Legend'
    ];
    return names[(level - 1).clamp(0, names.length - 1).toInt()];
  }

  static Future<List<BadgeInfo>> badges() async {
    final p = await SharedPreferences.getInstance();
    final streak = await StudyStats.streak();
    final classes = p.getInt('study_classes') ?? 0;
    final flash = p.getInt('study_flash_reviewed') ?? 0;
    final exams = p.getString('exam_results_learner') ?? '';
    final quizPerfect = p.getInt('study_quiz_perfect') ?? 0;
    final passed = exams.contains('"passed":true') || exams.contains('passed');
    return [
      BadgeInfo('first_class', 'First Class', 'Finish your first class',
          Icons2.school, classes >= 1),
      BadgeInfo('five_classes', 'On a Roll', 'Finish 5 classes', Icons2.fire,
          classes >= 5),
      BadgeInfo('twenty_classes', 'Chapter Explorer', 'Finish 20 classes',
          Icons2.explore, classes >= 20),
      BadgeInfo('streak3', 'Warming Up', 'Study 3 days in a row',
          Icons2.calendar, streak >= 3),
      BadgeInfo('streak7', 'Week Warrior', 'Study 7 days in a row', Icons2.bolt,
          streak >= 7),
      BadgeInfo('streak30', 'Streak Legend', 'Study 30 days in a row',
          Icons2.trophy, streak >= 30),
      BadgeInfo('flash25', 'Word Collector', 'Review 25 flashcards',
          Icons2.cards, flash >= 25),
      BadgeInfo('flash100', 'Memory Master', 'Review 100 flashcards',
          Icons2.brain, flash >= 100),
      BadgeInfo('perfect', 'Perfect Score', 'Score 100% in a test', Icons2.star,
          quizPerfect >= 1),
      BadgeInfo('exam', 'Exam Ready', 'Pass a part test', Icons2.check, passed),
    ];
  }

  static Future<void> bumpPerfectQuiz() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(
        'study_quiz_perfect', (p.getInt('study_quiz_perfect') ?? 0) + 1);
  }

  static Future<void> bumpFlashcards([int n = 1]) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(
        'study_flash_reviewed', (p.getInt('study_flash_reviewed') ?? 0) + n);
  }

  // ---------- backup ----------

  static const _prefixes = [
    'study_',
    'xp_',
    'completed_parts_',
    'exam_results_',
    'flash_',
    'set_',
    'watch_pos_',
  ];

  // ---------- badges model ----------

  static Future<String> exportJson() async {
    final p = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final k in p.getKeys()) {
      if (_prefixes.any(k.startsWith)) {
        final v = p.get(k);
        if (v is String || v is int || v is double || v is bool || v is List) {
          data[k] = v is List ? v.map((e) => e.toString()).toList() : v;
        }
      }
    }
    return jsonEncode({
      'app': 'AI Textbook Classroom',
      'version': 1,
      'saved_at': DateTime.now().toIso8601String(),
      'data': data,
    });
  }

  /// Returns how many keys were restored.
  static Future<int> importJson(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['data'] is! Map)
      throw const FormatException('Not a classroom backup file');
    final data = decoded['data'] as Map;
    final p = await SharedPreferences.getInstance();
    var n = 0;
    for (final entry in data.entries) {
      final k = entry.key.toString();
      if (!_prefixes.any(k.startsWith)) continue;
      final v = entry.value;
      if (v is bool) {
        await p.setBool(k, v);
      } else if (v is int) {
        await p.setInt(k, v);
      } else if (v is double) {
        await p.setDouble(k, v);
      } else if (v is List) {
        await p.setStringList(k, v.map((e) => e.toString()).toList());
      } else {
        await p.setString(k, v.toString());
      }
      n++;
    }
    return n;
  }
}

class BadgeInfo {
  final String id;
  final String title;
  final String description;
  final String icon;
  final bool unlocked;
  const BadgeInfo(
      this.id, this.title, this.description, this.icon, this.unlocked);
}

/// Tiny icon-name constants so this file stays free of Flutter imports.
class Icons2 {
  static const school = 'school';
  static const fire = 'fire';
  static const explore = 'explore';
  static const calendar = 'calendar';
  static const bolt = 'bolt';
  static const trophy = 'trophy';
  static const cards = 'cards';
  static const brain = 'brain';
  static const star = 'star';
  static const check = 'check';
}
