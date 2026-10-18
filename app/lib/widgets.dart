import 'package:flutter/material.dart';

/// Premium design system: deep-navy canvas, indigo→teal gradients,
/// glass cards, soft shadows. No external fonts/assets needed.
class AppColors {
  static const bg = Color(0xFF0B1020);
  static const bg2 = Color(0xFF111833);
  static const card = Color(0xFF171F3D);
  static const cardLight = Color(0xFF1F2A52);
  static const stroke = Color(0xFF2A3766);
  static const text = Color(0xFFF2F5FF);
  static const muted = Color(0xFF9AA7D4);
  static const indigo = Color(0xFF6366F1);
  static const violet = Color(0xFFA855F7);
  static const teal = Color(0xFF2DD4BF);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFF87171);
  static const green = Color(0xFF34D399);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4338CA), Color(0xFF7C3AED), Color(0xFF0D9488)],
  );
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [indigo, violet],
  );
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 18, offset: const Offset(0, 8))],
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
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
          const Spacer(),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!, style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w700))),
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
            valueColor: const AlwaysStoppedAnimation(AppColors.teal),
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
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.45)),
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
              decoration: const BoxDecoration(gradient: AppColors.heroGradient, shape: BoxShape.circle),
              child: Icon(stages[_stage].$2, size: 52, color: Colors.white),
            ),
          ),
          const SizedBox(height: 26),
          Text(stages[_stage].$1, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
          const SizedBox(height: 8),
          const Text('Your class is being prepared on this phone.\nDetailed videos can take a few minutes — keep the app open.',
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
