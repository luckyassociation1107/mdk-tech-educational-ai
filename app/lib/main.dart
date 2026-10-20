import 'package:flutter/material.dart';

import 'ai/ai_config.dart';
import 'ui/web_ai_host.dart';
import 'engine_gateway.dart';
import 'exam_store.dart';
import 'screens/child_gate_screen.dart';
import 'screens/home_screen.dart';
import 'store.dart';
import 'theme/themes.dart';
import 'ui/premium_ui.dart';
import 'vault/emoji_vault.dart';
import 'widgets.dart';

void main() {
  runApp(const TextbookClassroomApp());
}

/// Student-only app: no logins, no roles. One learner opens the app,
/// adds a textbook PDF and learns — lessons, chat, tests and progress
/// all live on this device.
class TextbookClassroomApp extends StatelessWidget {
  const TextbookClassroomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ThemeManager.revision,
      builder: (context, _, __) => _app(),
    );
  }

  Widget _app() {
    final p = AppColors.palette;
    return MaterialApp(
      title: 'AI Textbook Classroom',
      builder: (context, child) => WebAiHost(child: child ?? const SizedBox()),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: p.isLight ? Brightness.light : Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.indigo,
          brightness: p.isLight ? Brightness.light : Brightness.dark,
          surface: AppColors.card,
          primary: AppColors.indigo,
          secondary: AppColors.teal,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.text,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 16),
        ),
        dialogTheme: DialogTheme(backgroundColor: AppColors.card),
        bottomSheetTheme: BottomSheetThemeData(backgroundColor: AppColors.card),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.card,
          labelStyle: TextStyle(color: AppColors.muted),
          hintStyle: TextStyle(color: AppColors.muted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.stroke),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: AppColors.teal, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: BorderSide(color: AppColors.stroke),
            foregroundColor: AppColors.text,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.indigo,
          foregroundColor: Colors.white,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.card,
          selectedColor: AppColors.indigo,
          labelStyle: TextStyle(color: AppColors.text),
          side: BorderSide(color: AppColors.stroke),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        }),
        sliderTheme: SliderThemeData(
            activeTrackColor: AppColors.teal, thumbColor: AppColors.teal),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(AppColors.teal),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AppColors.teal.withOpacity(0.35)
                  : AppColors.stroke),
        ),
      ),
      home: const _Splash(),
    );
  }
}

class _Splash extends StatefulWidget {
  const _Splash();
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..forward();
    _go();
  }

  Future<void> _go() async {
    await ThemeManager.load();
    await AiConfig.load();
    final settings = await AppSettings.load();
    await VaultStore.load();
    ExamStore.scopeUserId = 'learner';
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    // Child profiles live in the encrypted emoji vault.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ChildGateScreen(
          settings: settings,
          onLoggedIn: () {
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => HomeScreen(gateway: EngineGateway(), settings: settings)),
              (_) => false,
            );
          },
        ),
      ),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B16),
      body: AuroraBackground(
        dense: true,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ScaleTransition(
              scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
              child: Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(34),
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.indigo.withOpacity(0.55),
                        blurRadius: 44,
                        spreadRadius: 4)
                  ],
                ),
                child: const Icon(Icons.auto_stories_rounded,
                    size: 58, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: CurvedAnimation(
                  parent: _anim,
                  curve: const Interval(0.25, 1, curve: Curves.easeOut)),
              child: Column(children: [
                GradientText('Textbook Classroom', size: 25),
                SizedBox(height: 7),
                Text('Your chapter. Your teacher. Page by page.',
                    style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                        letterSpacing: 0.2)),
                SizedBox(height: 30),
                SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.teal)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
