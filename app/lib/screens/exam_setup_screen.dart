import 'package:flutter/material.dart';

import '../academic_models.dart';
import '../engine_gateway.dart';
import '../models.dart';
import '../question_bank.dart';
import '../store.dart';
import '../widgets.dart';
import 'exam_screen.dart';

/// Test configuration: question types, count, timer, negative marking.
/// Questions are generated on-device from the part's own key points.
class ExamSetupScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  final TextbookItem book;
  final SeriesPart part;

  const ExamSetupScreen({super.key, required this.gateway, required this.settings, required this.book, required this.part});

  @override
  State<ExamSetupScreen> createState() => _ExamSetupScreenState();
}

class _ExamSetupScreenState extends State<ExamSetupScreen> {
  final Set<QuestionType> _types = {...QuestionType.values};
  int _count = 10;
  bool _timed = true;
  bool _negative = false;

  int get _minutes => (_count * 1.0).ceil(); // ~1 minute per question

  void _start() {
    if (_types.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one question type.')));
      return;
    }
    final questions = QuestionBank.generate(
      keyPoints: widget.part.keyPoints,
      bookTitle: widget.book.shortTitle,
      partLabel: 'Part ${widget.part.part} • ${widget.part.pageLabel}',
      types: _types,
      count: _count,
      seed: widget.part.part * 31 + _count,
    );
    if (questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not build questions for this part yet.')));
      return;
    }
    final cfg = ExamConfig(
      sessionId: widget.book.sessionId,
      bookTitle: widget.book.shortTitle,
      part: widget.part.part,
      partLabel: 'Part ${widget.part.part} • ${widget.part.pageLabel}',
      types: {..._types},
      count: questions.length,
      timed: _timed,
      minutes: _minutes,
      negativeMarking: _negative,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExamScreen(
        config: cfg,
        questions: questions,
        onPassed: () async {
          await ProgressStore.setPartCompleted(widget.book.sessionId, widget.part.part, true);
          try {
            await widget.gateway.completePart(widget.book.sessionId, widget.part.part,
                brain: widget.settings.brain, brainServerUrl: widget.settings.brainServerUrl);
          } catch (_) {}
        },
      ),
    ));
  }

  Widget _typeChip(QuestionType t, IconData icon) {
    final sel = _types.contains(t);
    return FilterChip(
      avatar: Icon(icon, size: 17, color: sel ? Colors.white : AppColors.muted),
      label: Text(t.label),
      selected: sel,
      onSelected: (v) => setState(() => v ? _types.add(t) : _types.remove(t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPoints = widget.part.keyPoints.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Set up your test', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 30), children: [
        GradientCard(
          gradient: AppColors.heroGradient,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: const [
              Icon(Icons.quiz_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text('Exam mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            Text('${widget.book.shortTitle}\nPart ${widget.part.part} • ${widget.part.pageLabel}',
                style: const TextStyle(color: Colors.white70, height: 1.5)),
            const SizedBox(height: 8),
            const Text('Score 40% or more to mark this part complete and unlock the next class.',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ),
        if (!hasPoints)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.amber.withOpacity(0.12), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.amber.withOpacity(0.5))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_rounded, color: AppColors.amber, size: 19),
              SizedBox(width: 10),
              Expanded(
                child: Text('This part has no key points yet, so questions will be study-type. Generate/watch the class once and tests become fully auto-graded from the textbook.',
                    style: TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.5)),
              ),
            ]),
          ),
        const SectionTitle('Question types'),
        Wrap(spacing: 9, runSpacing: 9, children: [
          _typeChip(QuestionType.mcq, Icons.checklist_rounded),
          _typeChip(QuestionType.fill, Icons.text_fields_rounded),
          _typeChip(QuestionType.short, Icons.edit_note_rounded),
        ]),
        const SectionTitle('Number of questions'),
        Row(children: [
          Expanded(
            child: Slider(
              value: _count.toDouble(),
              min: 5,
              max: 20,
              divisions: 3,
              label: '$_count',
              onChanged: (v) => setState(() => _count = v.round()),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.stroke)),
            child: Text('$_count questions', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
        ]),
        const SectionTitle('Exam rules'),
        GradientCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Timed exam', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
              subtitle: Text(_timed ? 'Auto-submits after $_minutes minutes' : 'No time limit', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              value: _timed,
              onChanged: (v) => setState(() => _timed = v),
            ),
            const Divider(color: AppColors.stroke, height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Negative marking', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
              subtitle: const Text('−0.25 for every wrong MCQ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              value: _negative,
              onChanged: (v) => setState(() => _negative = v),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Start test'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.teal, foregroundColor: const Color(0xFF06231F), padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
        const SizedBox(height: 10),
        const Text('Questions are generated on this phone from this part’s key points — no internet needed. Passing marks this part complete.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
      ]),
    );
  }
}
