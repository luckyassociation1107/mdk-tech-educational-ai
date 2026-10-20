import 'package:flutter/material.dart';

import 'engine_gateway.dart';
import 'exam_store.dart';
import 'screens/home_screen.dart';
import 'store.dart';
import 'ui/premium_ui.dart';
import 'updater.dart';
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
    return MaterialApp(
      title: 'AI Textbook Classroom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.indigo, brightness: Brightness.dark),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.card,
          labelStyle: const TextStyle(color: AppColors.muted),
          hintStyle: const TextStyle(color: AppColors.muted),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.stroke),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.teal, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: const BorderSide(color: AppColors.stroke),
            foregroundColor: AppColors.text,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.indigo,
          foregroundColor: Colors.white,
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.card,
          selectedColor: AppColors.indigo,
          labelStyle: const TextStyle(color: AppColors.text),
          side: const BorderSide(color: AppColors.stroke),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        }),
        sliderTheme: const SliderThemeData(activeTrackColor: AppColors.teal, thumbColor: AppColors.teal),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.all(AppColors.teal),
          trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.teal.withOpacity(0.35) : AppColors.stroke),
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
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..forward();
    _go();
  }

  Future<void> _go() async {
    final settings = await AppSettings.load();
    ExamStore.scopeUserId = 'learner';
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeScreen(gateway: EngineGateway(), settings: settings)),
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
                  boxShadow: [BoxShadow(color: AppColors.indigo.withOpacity(0.55), blurRadius: 44, spreadRadius: 4)],
                ),
                child: const Icon(Icons.auto_stories_rounded, size: 58, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: CurvedAnimation(parent: _anim, curve: const Interval(0.25, 1, curve: Curves.easeOut)),
              child: const Column(children: [
                GradientText('Textbook Classroom', size: 25),
                SizedBox(height: 7),
                Text('Your chapter. Your teacher. Page by page.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5, letterSpacing: 0.2)),
                SizedBox(height: 30),
                SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.teal)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
