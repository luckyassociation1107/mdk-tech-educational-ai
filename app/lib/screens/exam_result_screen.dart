import 'package:flutter/material.dart';

import '../academic_models.dart';
import '../widgets.dart';

/// Marks sheet for one attempt: score, grade, remark, unlock status and
/// a full per-question review with model answers.
class ExamResultScreen extends StatelessWidget {
  final ExamResult result;
  final int negativeApplied; // number of wrong MCQs penalised
  const ExamResultScreen({super.key, required this.result, this.negativeApplied = 0});

  @override
  Widget build(BuildContext context) {
    final pct = result.percentage;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title:  Text('Test result', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
        GradientCard(
          gradient: AppColors.heroGradient,
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            ProgressRing(value: pct / 100, size: 118, centerLabel: '${pct.toStringAsFixed(0)}%'),
            const SizedBox(height: 14),
            Text('${_fmt(result.earned)} / ${result.total} marks',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
            const SizedBox(height: 5),
            Text('${result.bookTitle} • ${result.partLabel}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              _Pill(icon: Icons.grade_rounded, label: 'Grade ${result.grade}'),
              _Pill(icon: result.passed ? Icons.lock_open_rounded : Icons.lock_rounded, label: result.passed ? 'Part complete — next unlocked' : 'Score 40% to unlock next'),
              _Pill(icon: Icons.stars_rounded, label: '+${_fmt(result.earned)} XP'),
            ]),
            const SizedBox(height: 12),
            Text(result.remark, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, height: 1.5, fontWeight: FontWeight.w600)),
            if (negativeApplied > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Negative marking applied on $negativeApplied wrong MCQ(s).',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
          ]),
        ),
        const SectionTitle('Answer review'),
        ...result.reviews.map((r) {
          final full = r.awarded >= r.maxMarks;
          final zero = r.awarded == 0;
          final color = full ? AppColors.green : zero ? AppColors.red : AppColors.amber;
          return Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: GradientCard(
              padding: const EdgeInsets.all(15),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(full ? Icons.check_circle_rounded : zero ? Icons.cancel_rounded : Icons.timelapse_rounded, color: color, size: 19),
                  const SizedBox(width: 8),
                  Text(r.typeLabel, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                  const Spacer(),
                  Text('${_fmt(r.awarded)}/${r.maxMarks}', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12.5)),
                ]),
                const SizedBox(height: 9),
                Text(r.prompt, style:  TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, height: 1.45)),
                const SizedBox(height: 8),
                Text('Your answer: ${r.given.isEmpty ? '(not answered)' : r.given}',
                    style: TextStyle(color: zero ? AppColors.red : AppColors.muted, height: 1.45, fontSize: 13)),
                const SizedBox(height: 5),
                Text('Correct: ${r.correct}', style:  TextStyle(color: AppColors.teal, height: 1.45, fontSize: 13, fontWeight: FontWeight.w700)),
                if (r.explanation.isNotEmpty && r.explanation != r.correct) ...[
                  const SizedBox(height: 7),
                  Text('From your textbook: ${r.explanation}', style:  TextStyle(color: AppColors.muted, height: 1.5, fontSize: 12.5)),
                ],
              ]),
            ),
          );
        }),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retake / back'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              icon: const Icon(Icons.home_rounded, size: 18),
              label: const Text('Home'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
         Text('This marks sheet is saved in your Report Card on this phone.', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ]),
      );
}
