import 'package:flutter/material.dart';

import 'theme/themes.dart';

/// Premium design system: deep-navy canvas, indigo→teal gradients,
/// glass cards, soft shadows. No external fonts/assets needed.
class AppColors {
  static AppPalette get palette => ThemeManager.palette;
  static bool get isLight => palette.isLight;

  static Color get bg => palette.bg;
  static Color get bg2 => palette.bg2;
  static Color get card => palette.card;
  static Color get cardLight => palette.cardLight;
  static Color get stroke => palette.stroke;
  static Color get text => palette.text;
  static Color get muted => palette.muted;
  static Color get indigo => palette.primary;
  static Color get violet => palette.secondary;
  static Color get teal => palette.accent;
  static Color get amber => palette.amber;
  static Color get red => palette.red;
  static Color get green => palette.green;

  static LinearGradient get heroGradient => palette.heroGradient;
  static LinearGradient get accentGradient => palette.accentGradient;
}

class GradientCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;
  const GradientCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.gradient, this.onTap, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? AppColors.card : null,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.stroke.withOpacity(0.7)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(AppColors.isLight ? 0.10 : 0.35), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: child,
    );
    return onTap == null ? box : InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: box);
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [
          Text(title, style:  TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
          const Spacer(),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!, style:  TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
        ]),
      );
}

class LockBadge extends StatelessWidget {
  final bool unlocked;
  final bool completed;
  const LockBadge({super.key, required this.unlocked, required this.completed});

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = completed
        ? (Icons.check_circle_rounded, 'Completed', AppColors.green)
        : unlocked
            ? (Icons.lock_open_rounded, 'Unlocked', AppColors.teal)
            : (Icons.lock_rounded, 'Locked', AppColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withOpacity(0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final String? centerLabel;
  const ProgressRing({super.key, required this.value, this.size = 58, this.centerLabel});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CircularProgressIndicator(
            value: value.clamp(0, 1),
            strokeWidth: 6,
            backgroundColor: AppColors.stroke,
            valueColor:  AlwaysStoppedAnimation(AppColors.teal),
          ),
          Text(centerLabel ?? '${(value * 100).round()}%',
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: size * 0.24)),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonLabel;
  final VoidCallback? onButton;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.buttonLabel, this.onButton});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, border: Border.all(color: AppColors.stroke)),
              child: Icon(icon, size: 40, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Text(title, style:  TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style:  TextStyle(color: AppColors.muted, height: 1.45)),
            if (buttonLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onButton, child: Text(buttonLabel!)),
            ],
          ]),
        ),
      );
}

/// Full-screen "teacher is preparing your class" progress experience.
/// The engine call is one-shot, so stages advance on a timer while the
/// real work (analysis → narration → rendering) happens on-device.
class GenerationProgress extends StatefulWidget {
  const GenerationProgress({super.key});
  @override
  State<GenerationProgress> createState() => _GenerationProgressState();
}

class _GenerationProgressState extends State<GenerationProgress> with SingleTickerProviderStateMixin {
  static const stages = [
    ('Analyzing your textbook', Icons.document_scanner_rounded),
    ('Planning the lesson', Icons.account_tree_rounded),
    ('Teacher is writing the board', Icons.draw_rounded),
    ('Recording the voice', Icons.record_voice_over_rounded),
    ('Reading pages with highlights', Icons.menu_book_rounded),
    ('Rendering your video', Icons.movie_creation_rounded),
  ];
  int _stage = 0;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    _advance();
  }

  Future<void> _advance() async {
    while (mounted && _stage < stages.length - 1) {
      await Future.delayed(const Duration(seconds: 14));
      if (mounted) setState(() => _stage++);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.bg.withOpacity(0.97),
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.05).animate(_pulse),
            child: Container(
              padding: const EdgeInsets.all(26),
              decoration:  BoxDecoration(gradient: AppColors.heroGradient, shape: BoxShape.circle),
              child: Icon(stages[_stage].$2, size: 52, color: Colors.white),
            ),
          ),
          const SizedBox(height: 26),
          Text(stages[_stage].$1, style:  TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
          const SizedBox(height: 8),
           Text('Your class is being prepared on this phone.\nDetailed videos can take a few minutes — keep the app open.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.5)),
          const SizedBox(height: 26),
          ...List.generate(stages.length, (i) {
            final done = i < _stage;
            final active = i == _stage;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Icon(done ? Icons.check_circle_rounded : active ? Icons.timelapse_rounded : Icons.circle_outlined,
                    size: 20, color: done ? AppColors.green : active ? AppColors.amber : AppColors.stroke),
                const SizedBox(width: 12),
                Text(stages[i].$1,
                    style: TextStyle(
                        color: done || active ? AppColors.text : AppColors.muted,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
              ]),
            );
          }),
          const SizedBox(height: 22),
          const LinearProgressIndicator(minHeight: 6, borderRadius: BorderRadius.all(Radius.circular(99))),
        ]),
      );
}
