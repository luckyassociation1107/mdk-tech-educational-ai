// Live probes against the free engines the app uses. They need internet and
// they are skipped unless LIVE=1 is set, so CI stays green offline.
//
//   cd app && LIVE=1 flutter test test/live_voice_test.dart --reporter compact
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:textbook_video_classroom/speech/neural_tts.dart';
import 'package:textbook_video_classroom/speech/online_voice.dart';
import 'package:textbook_video_classroom/translate_service.dart';

void main() {
  final live = Platform.environment['LIVE'] == '1';

  test('translation really lands for every script', () async {
    const line = 'A fraction shows how many equal parts of a whole we have. '
        'The number above the line is the numerator.';
    for (final lang in ['te', 'hi', 'ta', 'kn', 'ml', 'or', 'sa', 'zh-CN', 'ar']) {
      final out = await TranslateService.quick(line, lang);
      // ignore: avoid_print
      print('$lang -> $out');
      expect(out, isNotNull, reason: 'no translator answered for $lang');
      expect(out!.toLowerCase(), isNot(line.toLowerCase()));
    }
  }, timeout: const Timeout(Duration(minutes: 4)), skip: !live);

  test('neural voice returns real audio for each language', () async {
    const cases = {
      'te-IN-ShrutiNeural': 'ఈ పాఠంలో మనం భిన్నాల గురించి నేర్చుకుంటాము.',
      'hi-IN-SwaraNeural': 'इस पाठ में हम भिन्नों के बारे में सीखेंगे।',
      'ta-IN-PallaviNeural': 'இந்த பாடத்தில் பின்னங்களைப் பற்றி கற்போம்.',
      'en-IN-NeerjaNeural': 'This is your teacher voice.',
    };
    for (final e in cases.entries) {
      final bytes = await NeuralTts.instance.synthRetried(e.value, voice: e.key);
      // ignore: avoid_print
      print('${e.key} -> ${bytes.length} bytes');
      expect(bytes.length, greaterThan(4000), reason: e.key);
    }
  }, timeout: const Timeout(Duration(minutes: 3)), skip: !live);

  test('every offered language can be spoken by one of the engines', () {
    for (final l in kExplainLanguages) {
      if (const ['or', 'as'].contains(l.code)) continue; // device voice only
      expect(
        OnlineVoice.hasVoice(l.code),
        isTrue,
        reason: 'no online voice for ${l.code}',
      );
    }
  });
}
