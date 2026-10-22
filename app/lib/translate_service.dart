import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// One entry of the explanation-language list shown to the student.
class XLang {
  final String code; // ISO-639-1 used by the translators
  final String tts; // Android locale for the voice
  final String english;
  final String native;
  const XLang(this.code, this.tts, this.english, this.native);
}

/// Full list offered in the app (Indian languages first, then world).
const List<XLang> kExplainLanguages = [
  XLang('en', 'en-IN', 'English', 'English'),
  XLang('te', 'te-IN', 'Telugu', 'తెలుగు'),
  XLang('hi', 'hi-IN', 'Hindi', 'हिन्दी'),
  XLang('ta', 'ta-IN', 'Tamil', 'தமிழ்'),
  XLang('kn', 'kn-IN', 'Kannada', 'ಕನ್ನಡ'),
  XLang('ml', 'ml-IN', 'Malayalam', 'മലയാളം'),
  XLang('mr', 'mr-IN', 'Marathi', 'मराठी'),
  XLang('bn', 'bn-IN', 'Bengali', 'বাংলা'),
  XLang('gu', 'gu-IN', 'Gujarati', 'ગુજરાતી'),
  XLang('pa', 'pa-IN', 'Punjabi', 'ਪੰਜਾਬੀ'),
  XLang('or', 'or-IN', 'Odia', 'ଓଡ଼ିଆ'),
  XLang('as', 'as-IN', 'Assamese', 'অসমীয়া'),
  XLang('ur', 'ur-IN', 'Urdu', 'اردو'),
  XLang('ne', 'ne-NP', 'Nepali', 'नेपाली'),
  XLang('si', 'si-LK', 'Sinhala', 'සිංහල'),
  XLang('sa', 'sa-IN', 'Sanskrit', 'संस्कृतम्'),
  XLang('sd', 'sd-IN', 'Sindhi', 'سنڌي'),
  XLang('es', 'es-ES', 'Spanish', 'Español'),
  XLang('fr', 'fr-FR', 'French', 'Français'),
  XLang('de', 'de-DE', 'German', 'Deutsch'),
  XLang('pt', 'pt-BR', 'Portuguese', 'Português'),
  XLang('it', 'it-IT', 'Italian', 'Italiano'),
  XLang('nl', 'nl-NL', 'Dutch', 'Nederlands'),
  XLang('ru', 'ru-RU', 'Russian', 'Русский'),
  XLang('uk', 'uk-UA', 'Ukrainian', 'Українська'),
  XLang('pl', 'pl-PL', 'Polish', 'Polski'),
  XLang('cs', 'cs-CZ', 'Czech', 'Čeština'),
  XLang('ro', 'ro-RO', 'Romanian', 'Română'),
  XLang('hu', 'hu-HU', 'Hungarian', 'Magyar'),
  XLang('el', 'el-GR', 'Greek', 'Ελληνικά'),
  XLang('sv', 'sv-SE', 'Swedish', 'Svenska'),
  XLang('da', 'da-DK', 'Danish', 'Dansk'),
  XLang('nb', 'nb-NO', 'Norwegian', 'Norsk'),
  XLang('fi', 'fi-FI', 'Finnish', 'Suomi'),
  XLang('tr', 'tr-TR', 'Turkish', 'Türkçe'),
  XLang('ar', 'ar-SA', 'Arabic', 'العربية'),
  XLang('fa', 'fa-IR', 'Persian', 'فارسی'),
  XLang('he', 'he-IL', 'Hebrew', 'עברית'),
  XLang('sw', 'sw-KE', 'Swahili', 'Kiswahili'),
  XLang('am', 'am-ET', 'Amharic', 'አማርኛ'),
  XLang('zh-CN', 'zh-CN', 'Chinese (Simplified)', '简体中文'),
  XLang('zh-TW', 'zh-TW', 'Chinese (Traditional)', '繁體中文'),
  XLang('ja', 'ja-JP', 'Japanese', '日本語'),
  XLang('ko', 'ko-KR', 'Korean', '한국어'),
  XLang('vi', 'vi-VN', 'Vietnamese', 'Tiếng Việt'),
  XLang('th', 'th-TH', 'Thai', 'ไทย'),
  XLang('id', 'id-ID', 'Indonesian', 'Bahasa Indonesia'),
  XLang('ms', 'ms-MY', 'Malay', 'Bahasa Melayu'),
  XLang('tl', 'fil-PH', 'Filipino', 'Filipino'),
];

XLang xLang(String code) => kExplainLanguages.firstWhere((l) => l.code == code,
    orElse: () => kExplainLanguages.first);

/// Detects the language the *textbook itself* is written in, so textbook
/// lines are always spoken and shown in the book's own language.
String bookVoiceLocale(String text) {
  int count(String pattern) =>
      RegExp(pattern, unicode: true).allMatches(text).length;
  final total = text.replaceAll(RegExp(r'\s+'), '').length;
  if (total == 0) return 'en-IN';
  final te = count(r'[\u0C00-\u0C7F]');
  final hi = count(r'[\u0900-\u097F]');
  final ta = count(r'[\u0B80-\u0BFF]');
  final kn = count(r'[\u0C80-\u0CFF]');
  final ml = count(r'[\u0D00-\u0D7F]');
  final bn = count(r'[\u0980-\u09FF]');
  final gu = count(r'[\u0A80-\u0AFF]');
  final pa = count(r'[\u0A00-\u0A7F]');
  final or = count(r'[\u0B00-\u0B7F]');
  final ar = count(r'[\u0600-\u06FF]');
  final zh = count(r'[\u4E00-\u9FFF]');
  final ja = count(r'[\u3040-\u30FF]');
  final ko = count(r'[\uAC00-\uD7AF]');
  final best = [
    MapEntry('te-IN', te),
    MapEntry('hi-IN', hi),
    MapEntry('ta-IN', ta),
    MapEntry('kn-IN', kn),
    MapEntry('ml-IN', ml),
    MapEntry('bn-IN', bn),
    MapEntry('gu-IN', gu),
    MapEntry('pa-IN', pa),
    MapEntry('or-IN', or),
    MapEntry('ar-SA', ar),
    MapEntry('zh-CN', zh),
    MapEntry('ja-JP', ja),
    MapEntry('ko-KR', ko),
  ]..sort((a, b) => b.value.compareTo(a.value));
  if (best.first.value >= total * 0.18) return best.first.key;
  return 'en-IN';
}

/// Translates ONLY the app's own explanation text (never the textbook
/// lines) into the student's chosen language, keeping the main/technical
/// words in English so notes stay easy to prepare.
///
/// Engines are free and need no API key. Results are cached per language
/// inside the app's documents folder, so a class that was translated once
/// replays offline.
class TranslateService {
  static final Map<String, String> _mem = {};
  static Future<File>? _cacheFile;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/classroom');
    if (!await d.exists()) await d.create(recursive: true);
    return _cacheFile ??=
        Future.value(File('${d.path}/translation_cache.json'));
  }

  static String _key(String lang, String text) =>
      '$lang::${text.hashCode}::${text.length}';

  static Future<Map<String, String>> _loadCache() async {
    if (_mem.isNotEmpty) return _mem;
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) m.forEach((k, v) => _mem['$k'] = '$v');
      }
    } catch (_) {}
    return _mem;
  }

  static Future<void> _saveCache() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(_mem));
    } catch (_) {}
  }

  /// Terms that should stay in English: capitalised phrases and the
  /// textbook's own key words.
  static List<String> keyTerms(String text, [List<String> known = const []]) {
    final out = <String>{...known};
    for (final m in RegExp(r'\b[A-Z][a-zA-Z]{2,}(?:\s[A-Z][a-zA-Z]{2,}){0,2}\b')
        .allMatches(text)) {
      final t = m.group(0)!.trim();
      if (t.length >= 3 &&
          !const {
            'The',
            'This',
            'That',
            'These',
            'Those',
            'When',
            'Where',
            'What',
            'Which',
            'From',
            'With',
            'Your'
          }.contains(t)) {
        out.add(t);
      }
    }
    return out.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  static String _protect(String text, List<String> terms, List<String> store) {
    var t = text;
    for (final term in terms) {
      if (term.length < 3) continue;
      final re = RegExp(RegExp.escape(term), caseSensitive: false);
      t = t.replaceAllMapped(re, (m) {
        store.add(m.group(0)!);
        return ' qz${store.length - 1}qz ';
      });
    }
    return t;
  }

  static String _restore(String text, List<String> store) {
    var t = text;
    for (var i = 0; i < store.length; i++) {
      t = t.replaceAll(RegExp('qz\\s*$i\\s*qz'), store[i]);
    }
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Google's dictionary client — the endpoint that actually answers from
  /// phones, school Wi-Fi and hosting IPs alike. This is the primary engine.
  static Future<String?> _clients5(String text, String lang) async {
    final body = await _http(
      Uri.parse('https://clients5.google.com/translate_a/t'
          '?client=dict-chrome-ex&sl=en&tl=$lang'),
      body: {'q': text},
      timeout: const Duration(seconds: 10),
    );
    if (body == null) return null;
    try {
      final data = jsonDecode(body);
      if (data is String) return data.trim().isEmpty ? null : data.trim();
      if (data is List) {
        final parts = <String>[];
        for (final e in data) {
          if (e is String) parts.add(e);
          if (e is List) {
            for (final x in e) {
              if (x is String) parts.add(x);
            }
          }
        }
        final out = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        return out.isEmpty ? null : out;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _google(String text, String lang) async {
    final url = Uri.parse('https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=en&tl=$lang&dt=t&q=${Uri.encodeQueryComponent(text)}');
    final body = await _get(url, timeout: const Duration(seconds: 9));
    if (body == null) return null;
    try {
      final data = jsonDecode(body);
      if (data is List && data.isNotEmpty && data[0] is List) {
        final sb = StringBuffer();
        for (final seg in (data[0] as List)) {
          if (seg is List && seg.isNotEmpty) sb.write('${seg[0]}');
        }
        final out = sb.toString().trim();
        return out.isEmpty ? null : out;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _myMemory(String text, String lang) async {
    // The free tier refuses anything over ~500 characters, so long lines are
    // sent sentence by sentence and joined back.
    final pieces = text.length <= 450 ? [text] : _splitLong(text, 400);
    final out = <String>[];
    for (final piece in pieces) {
      final url = Uri.parse('https://api.mymemory.translated.net/get'
          '?q=${Uri.encodeQueryComponent(piece)}&langpair=en|$lang');
      final body = await _get(url, timeout: const Duration(seconds: 9));
      if (body == null) return null;
      try {
        final data = jsonDecode(body);
        final t = '${data['responseData']?['translatedText'] ?? ''}'.trim();
        if (t.isEmpty || t.toUpperCase().contains('MYMEMORY WARNING')) {
          return null;
        }
        out.add(t);
      } catch (_) {
        return null;
      }
    }
    return out.join(' ').trim();
  }

  /// Splits on sentence ends, then on spaces, keeping pieces under [max].
  static List<String> _splitLong(String text, int max) {
    final out = <String>[];
    final buf = StringBuffer();
    for (final word in text.split(' ')) {
      if (buf.length + word.length + 1 > max && buf.isNotEmpty) {
        out.add(buf.toString().trim());
        buf.clear();
      }
      buf.write(word);
      buf.write(' ');
    }
    if (buf.toString().trim().isNotEmpty) out.add(buf.toString().trim());
    return out;
  }

  static Future<String?> _lingva(String text, String lang) async {
    final url = Uri.parse(
        'https://lingva.ml/api/v1/en/$lang/${Uri.encodeComponent(text)}');
    final body = await _get(url, timeout: const Duration(seconds: 8));
    if (body == null) return null;
    try {
      final out = '${jsonDecode(body)['translation'] ?? ''}'.trim();
      if (out.isEmpty) return null;
      // lingva often answers with the English text unchanged — that is a
      // silent failure, not a translation.
      if (out.toLowerCase() == text.toLowerCase()) return null;
      return out;
    } catch (_) {}
    return null;
  }

  static Future<String?> _http(Uri url,
      {Map<String, String>? body,
      required Duration timeout}) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      final req = body == null
          ? await client.getUrl(url).timeout(timeout)
          : await client.postUrl(url).timeout(timeout);
      req.headers
          .set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36');
      if (body != null) {
        req.headers.set('Content-Type',
            'application/x-www-form-urlencoded;charset=UTF-8');
        req.write(body.entries
            .map((e) =>
                '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
            .join('&'));
      }
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join().timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// True when [out] really is a translation of [input] into [lang].
  static bool _plausible(String input, String out, String lang) {
    final a = input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
    final b = out.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').trim();
    if (out.trim().isEmpty) return false;
    if (lang != 'en' && a.isNotEmpty && a == b) return false;
    return true;
  }

  static Future<String?> _get(Uri url, {required Duration timeout}) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      final req = await client.getUrl(url).timeout(timeout);
      req.headers
          .set('User-Agent', 'Mozilla/5.0 (Android) AI-Textbook-Classroom');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join().timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Translate one explanation. Returns null when every engine fails
  /// (offline first run) so the caller can honestly fall back to English.
  static Future<String?> translate(String text, String lang,
      {List<String> knownTerms = const []}) async {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty || lang == 'en') return clean;
    final cache = await _loadCache();
    final ck = _key(lang, clean);
    if (cache.containsKey(ck)) return cache[ck];

    final store = <String>[];
    final protectedText = _protect(clean, keyTerms(clean, knownTerms), store);
    final out = await _chain(protectedText, clean, lang);
    if (out == null) return null;
    final restored = _restore(out, store);
    final finalOut = restored.isEmpty ? null : restored;
    if (finalOut != null) {
      _mem[ck] = finalOut;
      unawaited(_saveCache());
    }
    return finalOut;
  }

  /// Tries every engine until one really returns a translation of [text].
  ///
  /// Order matters: the Google dictionary client answers almost always, the
  /// memory API is the backup, the rest are last resorts. Each engine gets two
  /// tries because a single 429 / timeout is common on school Wi-Fi.
  static Future<String?> _chain(
      String protectedText, String text, String lang) async {
    for (final engine in [_clients5, _myMemory, _google, _lingva]) {
      for (var attempt = 0; attempt < 2; attempt++) {
        String? out;
        try {
          out = await engine(protectedText, lang);
        } catch (_) {
          out = null;
        }
        if (out != null && _plausible(text, out, lang)) return out;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    return null;
  }

  /// One-off translation that skips the on-device cache. Used by the settings
  /// self-check and by the tests, so a teacher can see plainly whether
  /// translation works right now.
  static Future<String?> quick(String text, String lang) async {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return clean;
    if (lang == 'en') return clean;
    final store = <String>[];
    final protectedText = _protect(clean, keyTerms(clean), store);
    final out = await _chain(protectedText, clean, lang);
    if (out == null) return null;
    return _restore(out, store);
  }

  /// Translate a whole list of explanations in parallel (max 4 at once).
  static Future<Map<int, String>> translateAll(List<String> texts, String lang,
      {List<String> knownTerms = const []}) async {
    final out = <int, String>{};
    if (lang == 'en') return out;
    final cache = await _loadCache();
    final todo = <int>[];
    for (var i = 0; i < texts.length; i++) {
      final ck = _key(lang, texts[i].replaceAll(RegExp(r'\s+'), ' ').trim());
      if (cache.containsKey(ck)) {
        out[i] = cache[ck]!;
      } else {
        todo.add(i);
      }
    }
    for (var i = 0; i < todo.length; i += 4) {
      final batch = todo.skip(i).take(4).toList();
      await Future.wait(batch.map((idx) async {
        final t = await translate(texts[idx], lang, knownTerms: knownTerms);
        if (t != null) out[idx] = t;
      }));
    }
    return out;
  }
}

/// Small helper widget used by the language picker.
Future<XLang?> pickExplainLanguage(BuildContext context, String current) {
  return showModalBottomSheet<XLang>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0F172A),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99))),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Explanation language',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                'Only the explanation is translated. Textbook points always stay in the book\'s own language, and main words stay in English.',
                style: TextStyle(
                    color: Colors.white70, fontSize: 12.5, height: 1.35),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: kExplainLanguages.length,
                itemBuilder: (ctx, i) {
                  final l = kExplainLanguages[i];
                  final sel = l.code == current;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundColor:
                          sel ? const Color(0xFF0EA5A4) : Colors.white10,
                      child: Text(l.code.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900)),
                    ),
                    title: Text('${l.english}  •  ${l.native}',
                        style: TextStyle(
                            color: sel ? const Color(0xFF5EEAD4) : Colors.white,
                            fontWeight: sel ? FontWeight.w900 : FontWeight.w600,
                            fontSize: 14)),
                    trailing: sel
                        ? const Icon(Icons.check_circle_rounded,
                            color: Color(0xFF5EEAD4), size: 20)
                        : null,
                    onTap: () => Navigator.of(ctx).pop(l),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}
