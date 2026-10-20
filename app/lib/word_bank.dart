import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Personal word bank: every word a student taps in Word help is saved
/// with the textbook sentence it came from and its translation, so it can
/// be revised later like a mini dictionary.
class WordBank {
  static String _key(String sessionId) => 'word_bank_$sessionId';

  static Future<List<WordEntry>> load(String sessionId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(sessionId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.whereType<Map>().map((m) => WordEntry.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(String sessionId, WordEntry e) async {
    final all = await load(sessionId);
    final i =
        all.indexWhere((x) => x.word.toLowerCase() == e.word.toLowerCase());
    if (i >= 0) {
      all[i] = e;
    } else {
      all.insert(0, e);
    }
    final trimmed = all.take(400).toList();
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key(sessionId), jsonEncode(trimmed.map((x) => x.toMap()).toList()));
  }

  static Future<void> remove(String sessionId, String word) async {
    final all = await load(sessionId);
    all.removeWhere((x) => x.word.toLowerCase() == word.toLowerCase());
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _key(sessionId), jsonEncode(all.map((x) => x.toMap()).toList()));
  }

  static Future<void> clear(String sessionId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(sessionId));
  }
}

class WordEntry {
  final String word;
  final String context;
  final String translation;
  final String page;
  final int when;

  const WordEntry({
    required this.word,
    this.context = '',
    this.translation = '',
    this.page = '',
    required this.when,
  });

  Map<String, dynamic> toMap() => {
        'w': word,
        'c': context,
        't': translation,
        'p': page,
        'at': when,
      };

  factory WordEntry.fromMap(Map m) => WordEntry(
        word: '${m['w'] ?? ''}',
        context: '${m['c'] ?? ''}',
        translation: '${m['t'] ?? ''}',
        page: '${m['p'] ?? ''}',
        when: (m['at'] as num?)?.toInt() ?? 0,
      );
}
