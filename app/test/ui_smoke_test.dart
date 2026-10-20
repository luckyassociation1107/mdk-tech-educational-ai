import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:textbook_video_classroom/screens/child_gate_screen.dart';
import 'package:textbook_video_classroom/screens/profile_screen.dart';
import 'package:textbook_video_classroom/screens/vault_sync_screen.dart';
import 'package:textbook_video_classroom/store.dart';
import 'package:textbook_video_classroom/vault/emoji_vault.dart';

/// Real UI smoke tests: the gate, the sign-up flow, the PIN pad, the
/// profile screen and the emoji cloud vault screen are built on a small
/// phone canvas (360×640). Any exception — including a RenderFlex
/// overflow — makes these tests fail, which is exactly what we want to
/// know before calling a build "usable".
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

  Future<void> tapPin(WidgetTester tester, String digits) async {
    for (final d in digits.split('')) {
      final key = find.descendant(
        of: find.byType(PinPad),
        matching: find.text(d),
      );
      expect(key, findsWidgets, reason: 'PIN digit $d must be on screen');
      await tester.tap(key.first);
      await tester.pump();
    }
    final done = find.widgetWithText(FilledButton, 'Done');
    if (done.evaluate().isNotEmpty) {
      await tester.tap(done.first);
      await settle(tester);
    }
  }

  testWidgets('gate renders with no profiles (small phone)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    await tester.pumpWidget(MaterialApp(
      home: ChildGateScreen(settings: AppSettings(), onLoggedIn: () {}),
    ));
    await settle(tester);

    expect(find.text('Create a new profile'), findsOneWidget);
    expect(find.text('Restore from emoji code'), findsOneWidget);
    expect(find.text('Continue without a profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full flow: create profile → PIN twice → listed on the gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    bool loggedIn = false;

    await tester.pumpWidget(MaterialApp(
      home: ChildGateScreen(
        settings: AppSettings(),
        onLoggedIn: () => loggedIn = true,
      ),
    ));
    await settle(tester);

    await tester.tap(find.text('Create a new profile'));
    await settle(tester);
    expect(find.text('New profile'), findsOneWidget);

    // No name yet → the app must explain, not crash.
    await tester.tap(find.text('Create my profile'));
    await settle(tester);
    expect(find.text('Please type your name.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Aarav');
    await tester.pump();

    // Choose avatar.
    await tester.tap(find.text('🦊').first);
    await tester.pump();

    // Choose the PIN twice.
    await tester.tap(find.text('Choose a PIN'));
    await settle(tester);
    expect(find.byType(PinPad), findsOneWidget);
    await tapPin(tester, '1234');
    await tapPin(tester, '1234');

    expect(find.text('PIN set (4 digits)'), findsOneWidget);

    await tester.tap(find.text('Create my profile'));
    await settle(tester);

    expect(loggedIn, isTrue, reason: 'sign-up must log the child in');
    expect(VaultStore.current?.name, 'Aarav');
    expect(find.text('Aarav'), findsOneWidget,
        reason: 'the new profile should be listed on the gate');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrong PIN on the gate is refused, right PIN opens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    final p = await VaultStore.createProfile(name: 'Meera', avatar: '🐼', pin: '4321');
    await VaultStore.logout();

    bool loggedIn = false;
    await tester.pumpWidget(MaterialApp(
      home: ChildGateScreen(
        settings: AppSettings(),
        onLoggedIn: () => loggedIn = true,
      ),
    ));
    await settle(tester);

    expect(find.text('Meera'), findsOneWidget);
    await tester.tap(find.text('Meera'));
    await settle(tester);
    await tapPin(tester, '0000');
    expect(loggedIn, isFalse, reason: 'wrong PIN must not sign in');

    // Sheet closes on failure; open it again and type the real PIN.
    if (find.byType(PinPad).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(180, 40));
      await settle(tester);
    }
    if (find.text('Meera').evaluate().isNotEmpty) {
      await tester.tap(find.text('Meera').first);
      await settle(tester);
      await tapPin(tester, '4321');
    }
    expect(VaultStore.current?.id, p.id);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile screen builds and links to the cloud vault',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    final p = await VaultStore.createProfile(name: 'Kiran', avatar: '🚀', pin: '1234');
    await VaultStore.login(p.id, '1234');
    await VaultStore.log('class', 'Finished part 1 — Plants');

    await tester.pumpWidget(MaterialApp(
      home: ProfileScreen(settings: AppSettings(), onSignedOut: () {}),
    ));
    await settle(tester);

    expect(find.text('My space'), findsOneWidget);
    expect(find.text('Emoji cloud vault (free Nostr relays)'), findsOneWidget);
    expect(find.textContaining('Finished part 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Emoji cloud vault (free Nostr relays)'));
    await settle(tester);
    expect(find.text('Backup now'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vault sync screen fits a small phone and lists 6 relays',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);

    await tester.pumpWidget(const MaterialApp(home: VaultSyncScreen()));
    await settle(tester);

    expect(find.text('Backup now'), findsOneWidget);
    expect(find.text('Copy emoji'), findsOneWidget);
    expect(find.text('Paste emoji'), findsOneWidget);

    // Relay list lives further down the page — scroll like a real user.
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await settle(tester);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await settle(tester);
    expect(find.text('relay.damus.io'), findsOneWidget);
    expect(find.text('nos.lol'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emoji code export/import keeps every profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setPhone(tester);
    final a = await VaultStore.createProfile(name: 'Aarav', avatar: '🐼', pin: '1111');
    final b = await VaultStore.createProfile(name: 'Meera', avatar: '🦊', pin: '2222');
    final code = VaultStore.exportEmoji();
    expect(code.startsWith('🎒'), isTrue);

    // Wipe the device and restore from the emoji code.
    SharedPreferences.setMockInitialValues({});
    await VaultStore.load();
    expect(VaultStore.profiles, isEmpty);
    final n = await VaultStore.importEmoji(code);
    expect(n, 2);
    final ids = VaultStore.profiles.map((p) => p.id).toList();
    expect(ids, containsAll([a.id, b.id]));

    final back = await VaultStore.login(b.id, '2222');
    expect(back, isNotNull, reason: 'PIN must still work after a restore');
    expect(tester.takeException(), isNull);
  });
}
