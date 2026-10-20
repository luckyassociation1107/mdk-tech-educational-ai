import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'widgets.dart';

/// Animated concept diagrams drawn live in the class. Each diagram is
/// drawn progressively from the scene progress, so the picture appears
/// exactly while the teacher is speaking about it.
class DiagramView extends StatelessWidget {
  final String type; // cycle | timeline | steps | numberline
  final List<String> labels;
  final double progress; // 0..1
  final Color accent;
  const DiagramView({
    super.key,
    required this.type,
    required this.labels,
    required this.progress,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.stroke),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _DiagramPainter(
              type: type,
              labels: labels,
              t: progress.clamp(0.0, 1.0),
              ink: AppColors.text,
              accent: accent,
              line: AppColors.muted,
              paper: AppColors.cardLight,
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: accent.withOpacity(0.16), borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome_motion_rounded, size: 12, color: accent),
              const SizedBox(width: 5),
              Text(_title(type).toUpperCase(),
                  style: TextStyle(color: accent, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.9)),
            ]),
          ),
        ),
      ]),
    );
  }

  static String _title(String t) => switch (t) {
        'cycle' => 'cycle diagram',
        'timeline' => 'timeline',
        'steps' => 'process flow',
        'numberline' => 'number line',
        _ => 'diagram',
      };
}

class _DiagramPainter extends CustomPainter {
  final String type;
  final List<String> labels;
  final double t;
  final Color ink;
  final Color accent;
  final Color line;
  final Color paper;

  _DiagramPainter({
    required this.type,
    required this.labels,
    required this.t,
    required this.ink,
    required this.accent,
    required this.line,
    required this.paper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final labelsList = labels.isEmpty ? const ['1', '2', '3', '4'] : labels;
    switch (type) {
      case 'timeline':
        _timeline(canvas, size, labelsList);
      case 'numberline':
        _numberLine(canvas, size, labelsList);
      case 'steps':
        _steps(canvas, size, labelsList);
      default:
        _cycle(canvas, size, labelsList);
    }
  }

  void _text(Canvas canvas, String s, Offset center, {Color? color, double size = 11, double maxW = 120, FontWeight weight = FontWeight.w700}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: color ?? ink, fontSize: size, fontWeight: weight, height: 1.15),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxW);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _cycle(Canvas canvas, Size size, List<String> labels) {
    final n = math.max(3, math.min(6, labels.length));
    final c = Offset(size.width / 2, size.height / 2 + 6);
    final r = math.min(size.width, size.height) * 0.30;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    // dashed circle progress
    final shown = (t * (n + 0.4)).clamp(0.0, n.toDouble());
    for (var i = 0; i < n; i++) {
      if (i >= shown) break;
      final a1 = -math.pi / 2 + (2 * math.pi * i / n);
      final a2 = -math.pi / 2 + (2 * math.pi * math.min(i + 1, shown) / n);
      stroke.color = accent.withOpacity(0.55);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a1, a2 - a1, false, stroke);
      // arrow head
      final tip = Offset(c.dx + r * math.cos(a2), c.dy + r * math.sin(a2));
      final dir = a2 + math.pi / 2;
      final head = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - 8 * math.cos(dir - 0.4), tip.dy - 8 * math.sin(dir - 0.4))
        ..lineTo(tip.dx - 8 * math.cos(dir + 0.4), tip.dy - 8 * math.sin(dir + 0.4))
        ..close();
      canvas.drawPath(head, Paint()..color = accent.withOpacity(0.8));
    }
    for (var i = 0; i < n; i++) {
      if (i >= shown) break;
      final a = -math.pi / 2 + (2 * math.pi * i / n);
      final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      canvas.drawCircle(p, 10, Paint()..color = accent.withOpacity(0.18));
      canvas.drawCircle(p, 10, Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 1.6);
      _text(canvas, labels[i], p + Offset(0, 26), size: 10.5, maxW: 96, weight: FontWeight.w800);
    }
    _text(canvas, 'continuous cycle', c + const Offset(0, 2), color: line, size: 10);
  }

  void _timeline(Canvas canvas, Size size, List<String> labels) {
    final y = size.height * 0.55;
    final left = 26.0, right = size.width - 26.0;
    final paint = Paint()
      ..color = line.withOpacity(0.7)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    final n = math.max(2, math.min(6, labels.length));
    final shown = (t * (n + 0.3)).clamp(0.0, n.toDouble());
    for (var i = 0; i < n && i < shown; i++) {
      final x = left + (right - left) * (i / math.max(1, n - 1));
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = accent);
      canvas.drawLine(
        Offset(x, y - 8),
        Offset(x, y - 46),
        Paint()
          ..color = accent.withOpacity(0.55)
          ..strokeWidth = 1.4,
      );
      _text(canvas, labels[i], Offset(x, y - 62), size: 11, maxW: 110, weight: FontWeight.w900);
      _text(canvas, '${i + 1}', Offset(x, y + 20), color: line, size: 9.5);
    }
  }

  void _steps(Canvas canvas, Size size, List<String> labels) {
    final n = math.max(2, math.min(4, labels.length));
    final shown = (t * (n + 0.3)).clamp(0.0, n.toDouble());
    final pad = 14.0;
    final h = (size.height - pad * 2 - 10 * (n - 1)) / n;
    final w = size.width - pad * 2;
    for (var i = 0; i < n && i < shown; i++) {
      final rect = Rect.fromLTWH(pad, pad + i * (h + 10), w, h);
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(11));
      canvas.drawRRect(rr, Paint()..color = accent.withOpacity(i == (shown.floor()).clamp(0, n - 1) ? 0.16 : 0.07));
      canvas.drawRRect(rr, Paint()..color = accent.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1.3);
      canvas.drawCircle(Offset(rect.left + 18, rect.center.dy), 11, Paint()..color = accent);
      _text(canvas, '${i + 1}', Offset(rect.left + 18, rect.center.dy), color: Colors.white, size: 11.5, weight: FontWeight.w900, maxW: 30);
      _text(canvas, labels[i], Offset(rect.left + 18 + (w - 30) / 2 + 6, rect.center.dy), size: 11, maxW: w - 52, weight: FontWeight.w700);
    }
  }

  void _numberLine(Canvas canvas, Size size, List<String> labels) {
    final y = size.height * 0.58;
    final left = 24.0, right = size.width - 24.0;
    canvas.drawLine(Offset(left, y), Offset(right, y), Paint()..color = line.withOpacity(0.8)..strokeWidth = 2.4);
    // arrow tip
    final tip = Path()
      ..moveTo(right + 10, y)
      ..lineTo(right, y - 6)
      ..lineTo(right, y + 6)
      ..close();
    canvas.drawPath(tip, Paint()..color = line.withOpacity(0.8));
    final n = math.max(2, math.min(6, labels.length));
    final shown = (t * (n + 0.3)).clamp(0.0, n.toDouble());
    for (var i = 0; i < n && i < shown; i++) {
      final x = left + (right - left) * (i / math.max(1, n - 1));
      canvas.drawLine(Offset(x, y - 7), Offset(x, y + 7), Paint()..color = line..strokeWidth = 1.6);
      _text(canvas, labels[i], Offset(x, y + 26), size: 11.5, weight: FontWeight.w900, maxW: 110);
    }
    _text(canvas, 'increasing value', Offset(size.width / 2, size.height * 0.18), color: line, size: 10);
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter old) =>
      old.t != t || old.labels != labels || old.accent != accent || old.ink != ink;
}
