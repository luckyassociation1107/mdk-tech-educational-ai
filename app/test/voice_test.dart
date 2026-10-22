import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:textbook_video_classroom/speech/neural_tts.dart';
import 'package:textbook_video_classroom/speech/online_voice.dart';
import 'package:textbook_video_classroom/translate_service.dart';
import 'package:textbook_video_classroom/ui/media_fit.dart';

void main() {
  group('page is never stretched', () {
    test('a tall A4 page in a wide card keeps its shape', () {
      final s = MediaFit.fitInside(const Size(800, 300), MediaFit.a4);
      // Height limits the page; width shrinks with it.
      expect(s.height, closeTo(300, 0.01));
      expect(s.width / s.height, closeTo(MediaFit.a4, 0.0001));
      expect(s.width, lessThan(800));
    });

    test('a wide picture in a tall card keeps its shape', () {
      final s = MediaFit.fitInside(const Size(300, 800), 2.0);
      expect(s.width, closeTo(300, 0.01));
      expect(s.height, closeTo(150, 0.01));
    });

    test('a page that already fits is not enlarged past the box', () {
      final s = MediaFit.fitInside(const Size(400, 600), 0.5);
      expect(s.width, closeTo(300, 0.01));
      expect(s.height, closeTo(600, 0.01));
    });

    test('PNG header gives the real aspect ratio', () {
      // 3x4 PNG signature + IHDR width/height
      final head = <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52,
        0, 0, 0, 3, // width = 3
        0, 0, 0, 4, // height = 4
      ];
      expect(MediaFit.pngAspect(head), closeTo(0.75, 1e-9));
    });

    test('junk bytes fall back to nothing, so A4 is used', () {
      expect(MediaFit.pngAspect(List<int>.filled(24, 7)), isNull);
      expect(MediaFit.pngAspect(const [0x89, 0x50]), isNull);
    });

    test('zoom is clamped and pan cannot leave the page', () {
      expect(MediaFit.zoomFor(0.01), closeTo(3.4, 1e-9));
      expect(MediaFit.zoomFor(0.9), closeTo(1 + 0.02 / 0.9 - 0.0, 0.3));
      expect(MediaFit.clampPan(9999, 200, 2, 400), closeTo(0, 1e-9));
      expect(MediaFit.clampPan(-9999, 400, 2, 300), closeTo(-250, 1e-9));
    });
  });

  group('neural voice', () {
    test('the security token is stable for a fixed instant', () {
      // Value cross-checked against the reference client at this instant.
      expect(NeuralTts.gecToken(DateTime.utc(2025, 10, 22)),
          '4E19A5C23FFE6D38846F0638AA78A6F1CA2FC784168BBAA05E8B48281274EF60');
    });

    test('request ids have the no-dash uuid shape the service demands', () {
      final id = NeuralTts.requestId();
      expect(id.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
      expect(NeuralTts.requestId(), isNot(id));
    });

    test('SSML carries the voice, speed, pitch and escaped text', () {
      final x = NeuralTts.ssml('1 < 2 & 3 > 2',
          voice: 'te-IN-ShrutiNeural', rate: 0.92, pitch: 1.0);
      expect(x, contains("name='te-IN-ShrutiNeural'"));
      expect(x, contains("rate='-8%'"));
      expect(x, contains("pitch='+0%'"));
      expect(x, contains('&lt;'));
      expect(x, contains('&amp;'));
      expect(x, isNot(contains('1 < 2')));
    });

    test('every offered language has a voice or is a known device-only one', () {
      for (final l in kExplainLanguages) {
        if (const ['or', 'as'].contains(l.code)) {
          expect(OnlineVoice.hasVoice(l.code), isFalse, reason: l.code);
        } else {
          expect(OnlineVoice.hasVoice(l.code), isTrue, reason: l.code);
        }
      }
    });

    test('Telugu has a female and a male teacher', () {
      final v = neuralVoicesFor('te');
      expect(v.length, 2);
      expect(v.map((e) => e.gender).toSet(), {'F', 'M'});
      expect(defaultNeuralVoice('te'), contains('Shruti'));
    });

    test('Sanskrit borrows the Hindi script voice', () {
      expect(neuralVoicesFor('sa').first.name, startsWith('hi-IN'));
      expect(languageHasNeuralVoice('sa'), isTrue);
    });

    test('Odia has no natural voice and says so', () {
      expect(languageHasNeuralVoice('or'), isFalse);
      expect(OnlineVoice.hasVoice('or'), isFalse);
    });
  });

  group('google voice fallback', () {
    test('text is split into speakable pieces', () {
      final parts = OnlineVoice.chunk(
          'First idea here. Second idea is longer, and it continues without a '
          'full stop for quite a while so it must be cut somewhere sensible '
          'inside the sentence. Third one!',
          max: 60);
      expect(parts.length, greaterThanOrEqualTo(3));
      for (final p in parts) {
        expect(p.length, lessThanOrEqualTo(61));
        expect(p.trim(), isNotEmpty);
      }
      expect(parts.first, 'First idea here.');
    });

    test('Telugu danda ends a sentence too', () {
      final parts = OnlineVoice.chunk('భిన్నం అంటే ఏమిటి। రెండు భాగాలు.');
      expect(parts.length, 2);
    });

    test('cache keys differ per voice and per speed', () {
      final a = OnlineVoice.cacheKey('neural', 'te-IN-ShrutiNeural', 0.92, 'hi');
      final b = OnlineVoice.cacheKey('neural', 'te-IN-MohanNeural', 0.92, 'hi');
      final c = OnlineVoice.cacheKey('neural', 'te-IN-ShrutiNeural', 1.2, 'hi');
      expect(a, isNot(b));
      expect(a, isNot(c));
      expect(
          a,
          OnlineVoice.cacheKey(
              'neural', 'te-IN-ShrutiNeural', 0.92, 'hi'));
    });

    test('the url carries the language and the speed the app set', () {
      final u = OnlineVoice.googleUrl('hello', 'te', 0.62);
      expect(u.queryParameters['tl'], 'te');
      expect(u.queryParameters['ttsspeed'], '0.62');
      expect(u.host, 'translate.google.com');
    });
  });
}
