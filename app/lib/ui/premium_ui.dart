import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'widgets.dart';

/// ─────────────────────────────────────────────────────────────────────
///  High-end UI kit: aurora background, glass surfaces, animated numbers,
///  confetti celebrations and premium page transitions.
///  Pure Flutter — no packages, works offline on phone and desktop.
/// ─────────────────────────────────────────────────────────────────────

/// Live aurora background: three slow gradient blobs drifting behind the
/// content. Cheap to paint (no blur filters, only opacity gradients).
class AuroraBackground extends StatefulWidget {
  final Widget child;
  final bool dense;
  const AuroraBackground({super.key, required this.child, this.dense = false});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: Container(color: const Color(0xFF070B16))),
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: _AuroraPainter(t: _c.value, dense: widget.dense)),
        ),
      ),
      Positioned.fill(child: widget.child),
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final bool dense;
  _AuroraPainter({required this.t, required this.dense});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    void blob(Offset c, double r, Color color, double alpha) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [color.withOpacity(alpha), color.withOpacity(0)]).createShader(Rect.fromCircle(center: c, radius: r))
        ..blendMode = BlendMode.screen;
      canvas.drawCircle(c, r, paint);
    }

    final a1 = 2 * math.pi * t;
    final a2 = 2 * math.pi * t + 2.1;
    final a3 = 2 * math.pi * t + 4.2;
    final k = dense ? 1.0 : 0.72;
    blob(Offset(w * (0.22 + 0.12 * math.sin(a1)), h * (0.16 + 0.10 * math.cos(a1 * 0.8))), w * 0.62 * k,
        const Color(0xFF4F46E5), 0.30);
    blob(Offset(w * (0.82 + 0.10 * math.cos(a2)), h * (0.30 + 0.12 * math.sin(a2 * 0.9))), w * 0.58 * k,
        const Color(0xFF0D9488), 0.26);
    blob(Offset(w * (0.50 + 0.18 * math.sin(a3 * 0.7)), h * (0.86 + 0.06 * math.cos(a3))), w * 0.70 * k,
        const Color(0xFF7C3AED), 0.22);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => old.t != t;
}

/// Frosted glass surface — used for top-level cards instead of flat fills.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? tint;
  final double alpha;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.radius = 22,
    this.tint,
    this.alpha = 0.07,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (tint ?? Colors.white).withOpacity(alpha + 0.05),
            (tint ?? Colors.white).withOpacity(alpha * 0.35),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 26, offset: const Offset(0, 12))],
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: content),
    );
  }
}

/// Number that counts up smoothly when it appears.
class AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  const AnimatedCount(this.value, {super.key, this.style, this.duration = const Duration(milliseconds: 700)});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// Staggered entrance: fade + rise. Wrap list items with an index.
class RiseIn extends StatelessWidget {
  final Widget child;
  final int index;
  final bool enabled;
  const RiseIn({super.key, required this.child, this.index = 0, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final delay = (index.clamp(0, 12)) * 55;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: c),
      ),
      child: child,
    );
  }
}

/// Confetti + sparkle burst for achievements. Shows once, then fades.
Future<void> showCelebration(BuildContext context, {required String title, String? subtitle, bool big = true}) async {
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'celebration',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, a1, a2) => _Celebration(title: title, subtitle: subtitle, big: big),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)), child: child)),
  );
}

class _Celebration extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool big;
  const _Celebration({required this.title, this.subtitle, required this.big});

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 320,
        height: 380,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _ConfettiPainter(_c.value)))),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 14))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.big ? Icons.emoji_events_rounded : Icons.auto_awesome_rounded, color: const Color(0xFFFDE68A), size: 52),
                const SizedBox(height: 10),
                Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(widget.subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
                ],
                const SizedBox(height: 14),
                const Text('tap to continue', style: TextStyle(color: Colors.white38, fontSize: 10.5)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double t;
  _ConfettiPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final rnd = math.Random(7);
    const colors = [Color(0xFFFBBF24), Color(0xFF2DD4BF), Color(0xFFA855F7), Color(0xFFF472B6), Color(0xFF60A5FA), Color(0xFF34D399)];
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 64; i++) {
      final angle = rnd.nextDouble() * math.pi * 2;
      final speed = 90 + rnd.nextDouble() * 170;
      final life = Curves.easeOut.transform((t * 1.5).clamp(0.0, 1.0));
      final p = center + Offset(math.cos(angle), math.sin(angle)) * speed * life + Offset(0, 60 * t * t);
      final paint = Paint()..color = colors[i % colors.length].withOpacity((1 - t).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(angle + t * 6);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 7, height: 4), const Radius.circular(1.5)), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// Premium page transition used by the whole app: soft fade + slight rise.
class PageTransition {
  static Route<T> route<T>(Widget page) => PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, anim, secondary) => page,
        transitionsBuilder: (context, anim, secondary, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
              child: child,
            ),
          );
        },
      );
}

/// Animated gradient headline text.
class GradientText extends StatelessWidget {
  final String text;
  final double size;
  final FontWeight weight;
  final Gradient gradient;
  const GradientText(this.text, {super.key, this.size = 22, this.weight = FontWeight.w900, this.gradient = AppColors.heroGradient});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => gradient.createShader(Rect.fromLTWH(0, 0, rect.width, rect.height)),
      child: Text(text, style: TextStyle(fontSize: size, fontWeight: weight, color: Colors.white, letterSpacing: -0.2)),
    );
  }
}

/// Glowing icon chip used in quick-action grids.
class GlowIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const GlowIcon(this.icon, {super.key, required this.color, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.30),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withOpacity(0.90), color.withOpacity(0.45)]),
        boxShadow: [BoxShadow(color: color.withOpacity(0.42), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }
}
