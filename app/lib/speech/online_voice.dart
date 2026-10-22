import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

import 'neural_tts.dart';

/// The teacher's voice, rendered and played inside the app.
///
/// Two engines exist:
///
///  * **device** — the system TTS. Works offline, but a phone only has the
///    voices installed with it, and the old SAPI voice on Windows sounds like
///    a machine.
///  * **online** (this file) — the script is turned into real neural speech
///    (the same reader that powers the browser's Read Aloud) and played with
///    `audioplayers`. 45 languages, a male and a female voice each, no key,
///    no account. If the neural reader is unreachable the free Google speech
///    endpoint is used instead; if that too fails the lesson falls back to the
///    device voice.
///
/// Nothing here is allowed to stop a class: every failure throws and the
/// caller falls back.
class OnlineVoice {
  OnlineVoice._();

  static final OnlineVoice instance = OnlineVoice._();

  /// The Google endpoint speaks about 200 characters per request.
  static const int maxChunk = 170;

  /// Languages the Google fallback has no voice for, mapped to the closest
  /// voice that can read the same script.
  static const Map<String, String> voiceFallback = {
    'sa': 'hi', // Sanskrit, Devanagari → Hindi
    'sd': 'ur', // Sindhi, Arabic script → Urdu
    'as': 'bn', // Assamese, Bengali script → Bengali
    'fa': 'ar', // Persian, Arabic script → Arabic
  };

  /// True when the online engine can speak [lang] at all. Odia has no voice in
  /// either online engine, so those lessons honestly use the device voice.
  static bool hasVoice(String lang) =>
      lang.isNotEmpty &&
      (languageHasNeuralVoice(lang) || !const {'or', 'as'}.contains(lang));

  AudioPlayer? _player;
  AudioPlayer get player => _player ??= AudioPlayer();

  bool _playing = false;
  bool get speaking => _playing;

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final hit = _dir;
    if (hit != null) return hit;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/voice_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Splits narration into sentences the Google fallback accepts.
  /// Pure function — unit tested.
  static List<String> chunk(String text, {int max = maxChunk}) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return const [];
    final sentences = <String>[];
    var buf = StringBuffer();
    for (final ch in clean.split('')) {
      buf.write(ch);
      if (ch == '.' || ch == '!' || ch == '?' || ch == '।' || ch == '॥') {
        final s = buf.toString().trim();
        if (s.isNotEmpty) sentences.add(s);
        buf = StringBuffer();
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) sentences.add(tail);

    final out = <String>[];
    for (final s in sentences) {
      if (s.length <= max) {
        out.add(s);
        continue;
      }
      var rest = s;
      while (rest.length > max) {
        var cut = rest.lastIndexOf(RegExp(r'[,;:]'), max);
        if (cut < max ~/ 2) cut = rest.lastIndexOf(' ', max);
        if (cut < max ~/ 2) cut = max;
        out.add(rest.substring(0, cut + 1).trim());
        rest = rest.substring(cut + 1).trim();
      }
      if (rest.isNotEmpty) out.add(rest);
    }
    return out.where((s) => s.trim().isNotEmpty).toList();
  }

  /// Stable cache file name for a (engine, voice, speed, text) tuple.
  static String cacheKey(String engine, String voice, double rate, String text) {
    final bytes = utf8.encode('$engine|$voice|${rate.toStringAsFixed(2)}|$text');
    return sha1.convert(bytes).toString();
  }

  static Uri googleUrl(String text, String lang, double speed) {
    final sp = speed.clamp(0.24, 1.0).toStringAsFixed(2);
    return Uri.parse('https://translate.google.com/translate_tts'
        '?ie=UTF-8&client=tw-ob&ttsspeed=$sp'
        '&tl=${Uri.encodeQueryComponent(lang)}'
        '&q=${Uri.encodeQueryComponent(text)}');
  }

  /// Downloads (or reuses) the whole scene as one MP3 file.
  ///
  /// [neuralVoice] is the voice picked in Voice Studio; when it is null or the
  /// neural reader fails, the Google voice for [lang] is used.
  Future<File> clip({
    required String text,
    required String lang,
    required double rate,
    required double pitch,
    String? neuralVoice,
  }) async {
    final dir = await _cacheDir();
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) throw const SocketException('nothing to speak');

    // 1) neural reader
    final voice = neuralVoice ??
        defaultNeuralVoice(lang) ??
        (kNeuralVoiceFallback.containsKey(lang)
            ? defaultNeuralVoice(kNeuralVoiceFallback[lang]!)
            : null);
    if (voice != null) {
      final key = cacheKey('neural', voice, rate, clean);
      final f = File('${dir.path}/$key.mp3');
      if (await f.exists() && await f.length() > 1000) return f;
      try {
        final bytes = await NeuralTts.instance.synthRetried(clean,
            voice: voice, rate: rate, pitch: pitch);
        await f.writeAsBytes(bytes, flush: true);
        return f;
      } catch (_) {
        // fall through to the free Google voice
      }
    }

    // 2) Google speech, sentence by sentence
    final gLang = voiceFallback[lang] ?? lang;
    final key = cacheKey('google', gLang, rate, clean);
    final joined = File('${dir.path}/$key.mp3');
    if (await joined.exists() && await joined.length() > 1000) return joined;
    final sink = joined.openWrite();
    for (final part in chunk(clean)) {
      sink.add(await _googleFetch(part, gLang, rate));
    }
    await sink.close();
    return joined;
  }

  /// Downloads a scene's voice while another scene is still playing.
  Future<void> prefetch(
    String text, {
    required String lang,
    required double rate,
    required double pitch,
    String? neuralVoice,
  }) async {
    try {
      await clip(
          text: text,
          lang: lang,
          rate: rate,
          pitch: pitch,
          neuralVoice: neuralVoice);
    } catch (_) {}
  }

  /// Speaks [text] and completes when the audio has finished.
  ///
  /// [onReady] fires the moment sound starts and carries the real length of
  /// the clip, so the board writes in step with the voice.
  Future<Duration?> speak({
    required String text,
    required String lang,
    required double rate,
    double pitch = 1.0,
    String? neuralVoice,
    void Function(Duration? total)? onReady,
  }) async {
    final file = await clip(
        text: text,
        lang: lang,
        rate: rate,
        pitch: pitch,
        neuralVoice: neuralVoice);

    await stop();
    _playing = true;
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(DeviceFileSource(file.path));
      Duration? total;
      try {
        total = await player.getDuration();
      } catch (_) {}
      if (total != null && total.inMilliseconds <= 0) total = null;
      onReady?.call(total);
      final done = Completer<void>();
      late StreamSubscription sub;
      sub = player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
        sub.cancel();
      });
      await done.future.timeout(
          (total ?? const Duration(seconds: 6)) + const Duration(seconds: 10),
          onTimeout: () {});
      return total;
    } finally {
      _playing = false;
    }
  }

  Future<void> stop() async {
    try {
      await player.stop();
    } catch (_) {}
    _playing = false;
  }

  /// Downloads one Google utterance. Throws when the endpoint refuses.
  Future<List<int>> _googleFetch(String text, String lang, double rate) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .getUrl(googleUrl(text, lang, rate))
          .timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Mobile Safari/537.36');
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw HttpException('voice http ${res.statusCode}');
      }
      final bytes = <int>[];
      await for (final part in res) {
        bytes.addAll(part);
      }
      final ok = bytes.length > 1000 &&
          ((bytes[0] == 0x49 && bytes[1] == 0x44) ||
              (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0));
      if (!ok) throw const HttpException('voice: not audio');
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  /// Says plainly whether the online voice works on this device right now.
  Future<String> selfTest(String lang, {String? neuralVoice}) async {
    try {
      final voice = neuralVoice ??
          defaultNeuralVoice(lang) ??
          (kNeuralVoiceFallback.containsKey(lang)
              ? defaultNeuralVoice(kNeuralVoiceFallback[lang]!)
              : null);
      if (voice != null) {
        final bytes = await NeuralTts.instance
            .synth('Hello, this is your teacher.', voice: voice, rate: 0.95);
        return 'OK neural $voice ${bytes.length ~/ 1024} KB';
      }
      final bytes =
          await _googleFetch('Hello', voiceFallback[lang] ?? lang, 0.9);
      return 'OK google ${bytes.length ~/ 1024} KB';
    } catch (e) {
      return 'FAIL $e';
    }
  }
}
