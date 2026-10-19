import 'package:flutter/material.dart';

import 'engine_gateway.dart';
import 'exam_store.dart';
import 'screens/home_screen.dart';
import 'store.dart';
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
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.bg, AppColors.bg2, AppColors.bg]),
        ),
        child: Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(30)),
                child: const Icon(Icons.school_rounded, size: 62, color: Colors.white),
              ),
              const SizedBox(height: 22),
              const Text('AI Textbook Classroom', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.text)),
              const SizedBox(height: 6),
              const Text('Your chapter. Your teacher. Page by page.', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 26),
              const CircularProgressIndicator(),
            ]),
          ),
        ),
      ),
    );
  }
}
