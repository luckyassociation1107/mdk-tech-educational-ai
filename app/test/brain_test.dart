import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:textbook_video_classroom/brain/ai_brain.dart';
import 'package:textbook_video_classroom/screens/brain_screen.dart';
import 'package:textbook_video_classroom/store.dart';

/// The brain's wire format is copied from the live PDF-teacher website
/// (captured request/response), so these tests pin that contract.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SSE parsing', () {
    test('reads delta content out of a real chunk', () {
      const line =
          'data: {"id":"chatcmpl-1","choices":[{"index":0,"delta":{"content":" Summary"},"finish_reason":null}]}';
      expect(AiBrain.parseSseLine(line), ' Summary');
    });

    test('ignores [DONE], empty lines and keep-alives', () {
      expect(AiBrain.parseSseLine('data: [DONE]'), isNull);
      expect(AiBrain.parseSseLine(''), isNull);
      expect(AiBrain.parseSseLine(': ping'), isNull);
      expect(AiBrain.parseSseLine('data: {"choices":[]}'), isNull);
    });

    test('falls back to message.content when a server sends no delta', () {
      const line =
          'data: {"choices":[{"message":{"content":"full answer"}}]}';
      expect(AiBrain.parseSseLine(line), 'full answer');
    });

    test('survives broken JSON without throwing', () {
      expect(AiBrain.parseSseLine('data: {oops'), isNull);
    });
  });

  group('request bodies', () {
    test('summary request has the system prompt, the level and the text', () {
      final body = AiBrain.summarizeBody('Photosynthesis is how plants eat.', 2);
      expect(body['model'], 'gpt-4o-mini');
      expect(body['stream'], true);
      final messages = body['messages'] as List;
      expect(messages.first['content'], AiBrain.summarizePrompt);
      final joined = messages.map((m) => '${m['content']}').join(' ');
      expect(joined, contains('detailed'));
      expect(joined, contains('Photosynthesis is how plants eat.'));
    });

    test('ask request carries the PDF text and the question', () {
      final body = AiBrain.askBody(
          pdfText: 'Water boils at 100 degrees.', question: 'Why?', previousSummary: 'S');
      final messages = body['messages'] as List;
      final joined = messages.map((m) => '${m['content']}').join(' | ');
      expect(joined, contains('PDF Content: Water boils at 100 degrees.'));
      expect(messages.last['content'], 'Why?');
      expect(messages.any((m) => m['role'] == 'assistant' && m['content'] == 'S'), isTrue);
    });

    test('empty question is refused before any network call', () {
      expect(
        () => AiBrain.ask(pdfText: 'some text here', question: '   '),
        throwsA(isA<BrainException>()),
      );
    });

    test('tiny textbook is refused', () {
      expect(
        () => AiBrain.summarize('too short'),
        throwsA(isA<BrainException>()),
      );
    });
  });

  group('text clipping', () {
    test('short text passes through unchanged', () {
      expect(AiBrain.clip('hello  world'), 'hello world');
    });

    test('huge books are clipped to the request limit', () {
      final big = List.filled(60000, 'a sentence. ').join();
      final clipped = AiBrain.clip(big);
      expect(clipped.length, lessThanOrEqualTo(AiBrain.maxTextChars));
      expect(clipped.endsWith('.'), isTrue,
          reason: 'should cut on a sentence boundary');
    });
  });

  group('brain screen', () {
    testWidgets('renders on a small phone and explains offline mode',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 3.0;
      tester.view.physicalSize = const Size(360 * 3, 640 * 3);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: BrainScreen(
          settings: AppSettings(),
          sessionId: '',
          bookTitle: 'Science — Chapter 1',
          onlineOverride: false,
        ),
      ));
      await tester.pump();
      // _load() touches the filesystem, so let real async run.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('🧠 AI Brain'), findsOneWidget);
      expect(find.text('1 · Summary'), findsOneWidget);
      expect(find.text('2 · Ask the book'), findsOneWidget);
      // Buttons are disabled while offline instead of failing later.
      final summarize = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Summarize this book with AI'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ).first,
      );
      expect(summarize.onPressed, isNull,
          reason: 'offline: the summarize button must be disabled');

      // Scroll down: the offline explanation must be there.
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('No internet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
