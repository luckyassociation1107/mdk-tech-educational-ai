import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:textbook_video_classroom/screens/home_screen.dart';
import 'package:textbook_video_classroom/screens/profile_screen.dart';
import 'package:textbook_video_classroom/engine_gateway.dart';
import 'package:textbook_video_classroom/store.dart';
import 'package:textbook_video_classroom/vault/emoji_vault.dart';

/// Real UI smoke tests. There is **no sign-up and no login** in this app: the
/// learner is opened silently, so these tests prove the app is usable without
/// a single credential — and that the screens that remain (home, profile,
/// cloud vault) fit a small phone without a RenderFlex overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setPhone(WidgetTester tester, {double w = 360, double h = 640}) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = Size(w * 3, h * 3);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// AuroraBackground animates forever, so pumpAndSettle() would time out.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the app opens one learner without any sign-up or login',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final profile = await VaultStore.openLocal();
    expect(profile.name, isNotEmpty);
    expect(VaultStore.current?.id, profile.id);
    expect(VaultStore.profiles.length, 1);

    // A second launch reopens the same learner — no new profile, no screen.
    final again = await VaultStore.openLocal();
    expect(again.id, profile.id);
    expect(VaultStore.profiles.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen builds straight away (small phone)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    await VaultStore.openLocal();

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(gateway: EngineGateway(), settings: AppSettings()),
    ));
    await settle(tester);
    await settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Good '), findsWidgets,
        reason: 'the greeting greets the local learner');
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Sign up'), findsNothing);
    expect(find.text('Create a new profile'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the vault still seals and reopens the learner data',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await VaultStore.openLocal();
    await VaultStore.log('class', 'Finished part 1 — Plants');

    // Simulate a cold start: nothing in memory, the same device storage.
    VaultStore.current = null;
    await VaultStore.load();
    expect(VaultStore.current, isNull);
    final reopened = await VaultStore.openLocal();
    expect(reopened.id, isNotNull);
    expect(VaultStore.logs.any((l) => '${l['msg']}'.contains('Finished part 1')),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile screen builds and links to the emoji backup',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    final p = await VaultStore.createProfile(name: 'Kiran', avatar: '🚀', pin: '1234');
    await VaultStore.login(p.id, '1234');
    await VaultStore.log('class', 'Finished part 1 — Plants');

    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(settings: AppSettings()),
    ));
    await settle(tester);

    expect(find.text('My space'), findsOneWidget);
    expect(find.text('Emoji backup'), findsOneWidget);
    expect(find.textContaining('cloud'), findsNothing,
        reason: 'there is no cloud sync any more');
    expect(find.textContaining('Finished part 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Emoji backup'));
    await settle(tester);
    expect(find.text('Your encrypted backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emoji backup restores the learner on a fresh phone',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    final me = await VaultStore.openLocal();
    await VaultStore.updateProfile(name: 'Aarav');
    await VaultStore.log('class', 'Finished part 1 — Plants');
    final code = VaultStore.exportEmoji();
    expect(code.startsWith('🎒'), isTrue);

    // A new phone: no prefs, nothing in memory, no login screen to help.
    SharedPreferences.setMockInitialValues({});
    VaultStore.current = null;
    await VaultStore.load();
    expect(VaultStore.profiles, isEmpty);

    final n = await VaultStore.importEmoji(code);
    expect(n, 1);
    final reopened = await VaultStore.openLocal();
    expect(reopened.id, me.id, reason: 'the same learner must come back');
    expect(reopened.name, 'Aarav');
    expect(
        VaultStore.logs.any((l) => '${l['msg']}'.contains('Finished part 1')),
        isTrue,
        reason: 'the encrypted log must survive the round trip');
    expect(tester.takeException(), isNull);
  });
}
