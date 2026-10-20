import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:textbook_video_classroom/ai/ai_brain.dart';
import 'package:textbook_video_classroom/screens/brain_screen.dart';
import 'package:textbook_video_classroom/store.dart';

/// v0.24: the brain talks to the teacher's own AI account. These tests pin
/// the text helpers and the offline UI state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(find.textContaining('No AI key'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
