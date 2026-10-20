import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// One way to talk, on every platform.
///
/// Android keeps the native bridge — it reports real spoken-word ranges, so
/// the lesson player can highlight the exact words the voice is saying.
/// Windows has no such bridge, so the same `speak` / `stopTts` calls are
/// served by `flutter_tts` (SAPI on Windows, AVSpeech on Apple platforms).
///
/// The API deliberately mirrors `MethodChannel.invokeMethod` so every screen
/// keeps its existing call sites; nothing here ever throws — narration is a
/// nice-to-have, it must never crash a lesson.
class SpeechChannel {
  const SpeechChannel();

  static const MethodChannel _android =
      MethodChannel('com.mdk.textbook_video/engine');

  static FlutterTts? _tts;
  static FlutterTts get _engine => _tts ??= FlutterTts();

  /// The player listens for `ttsRange` / `ttsDone`; those events only exist
  /// on Android, where the native bridge emits them.
  void setMethodCallHandler(Future<dynamic> Function(MethodCall call)? handler) {
    _android.setMethodCallHandler(handler);
  }

  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    final map = arguments is Map ? arguments : const {};

    if (Platform.isAndroid) {
      try {
        return await _android.invokeMethod<T>(method, arguments);
      } catch (_) {
        // Fall through to the cross-platform engine.
      }
    }

    try {
      switch (method) {
        case 'speak':
        case 'speakTts':
          final text = (map['text'] ?? map['utterance'] ?? '').toString();
          if (text.trim().isEmpty) return null;
          final e = _engine;
          final lang = (map['language'] ?? map['lang'] ?? '').toString();
          if (lang.isNotEmpty) {
            await e.setLanguage(lang);
          }
          final rate = map['rate'];
          if (rate is num) {
            // Android rates are 0.5…2.0; flutter_tts uses 0.0…1.0.
            await e.setSpeechRate(rate > 1.0 ? 0.5 : 0.45);
          }
          final pitch = map['pitch'];
          if (pitch is num) {
            await e.setPitch(pitch.toDouble().clamp(0.5, 2.0));
          }
          await e.awaitSpeakCompletion(false);
          await e.stop();
          await e.speak(text);
          return null;

        case 'stopTts':
        case 'stop':
          await _engine.stop();
          return null;

        case 'checkTts':
          // Best effort: report that a system voice exists, then let the
          // first speak() tell the truth.
          final languages = await _engine.getLanguages;
          final wanted = (map['language'] ?? '').toString().toLowerCase();
          var available = false;
          if (languages is List) {
            available = languages.any((l) => '$l'.toLowerCase().contains(
                wanted.isEmpty ? 'en' : wanted.split('-').first));
          }
          return {'available': available, 'code': available ? 1 : -1} as T?;
      }
    } catch (_) {
      // No TTS on this machine, or the plugin is unavailable in a test.
    }
    return null;
  }
}
