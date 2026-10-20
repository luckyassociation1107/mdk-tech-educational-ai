import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../academic_models.dart';
import '../dart_engine.dart';
import '../models.dart';
import '../question_bank.dart';
import '../store.dart';
import '../study_stats.dart';
import '../widgets.dart';

/// Fun, instant-feedback quiz built ONLY from the part's own key points.
/// Every question shows its correct answer + the textbook line immediately,
/// and passing (40%) earns XP and keeps the next part unlocked.
class QuizScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final List<SeriesPart> parts;
  const QuizScreen({super.key, required this.settings, required this.book, required this.parts});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  int _partIdx = 0;
  List<ExamQuestion> _qs = const [];
  int _i = 0;
  String? _picked;
  bool _revealed = false;
  int _right = 0;
  int _wrong = 0;
  bool _done = false;
  bool _loading = true;
  int _xp = 0;
  int _streak = 0;
  int _bestStreak = 0;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _start(0);
  }

  Future<void> _start(int partIdx) async {
    setState(() {
      _loading = true;
      _partIdx = partIdx;
      _i = 0;
      _right = 0;
      _wrong = 0;
      _done = false;
      _picked = null;
      _revealed = false;
      _streak = 0;
      _bestStreak = 0;
      _qs = const [];
    });
    if (widget.parts.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final part = widget.parts[partIdx];
    List<String> kp = part.keyPoints;
    if (kp.length < 3) {
      final brain = await DartEngine.brainKeyPoints(widget.book.sessionId);
      kp = [...kp, ...brain];
    }
    final qs = QuestionBank.generate(
      keyPoints: kp,
      bookTitle: widget.book.shortTitle,
      partLabel: 'Part ${part.part} (${part.pageLabel})',
      types: {QuestionType.mcq, QuestionType.fill},
      count: 8,
      seed: 11 + part.part,
    );
    final xp = await ProgressStore.xpOf(widget.book.sessionId);
    if (!mounted) return;
    setState(() {
      _qs = qs;
      _loading = false;
      _xp = xp;
    });
  }

  void _check(String given) {
    if (_revealed) return;
    final q = _qs[_i];
    final ok = q.type == QuestionType.mcq
        ? given.trim().toLowerCase() == q.answer.trim().toLowerCase()
        : QuestionBank.grade(q, given) >= 0.5;
    setState(() {
      _picked = given;
      _revealed = true;
      if (ok) {
        _right++;
        _streak++;
        _bestStreak = math.max(_bestStreak, _streak);
      } else {
        _wrong++;
        _streak = 0;
      }
    });
    if (ok) {
      ProgressStore.addXp(widget.book.sessionId, 5).then((v) {
        if (mounted) setState(() => _xp = v);
      });
    }
  }

  void _next() {
    if (_i >= _qs.length - 1) {
      _finish();
      return;
    }
    setState(() {
      _i++;
      _picked = null;
      _revealed = false;
      _ctrl.clear();
    });
  }

  Future<void> _finish() async {
    final pct = _qs.isEmpty ? 0 : (_right / _qs.length) * 100;
    if (pct >= 40) {
      await ProgressStore.addXp(widget.book.sessionId, 25);
    }
    if (_qs.isNotEmpty && _right == _qs.length) {
      await StudyStats.bumpPerfectQuiz();
    }
    await StudyStats.recordActivity(scenes: 1);
    if (mounted) setState(() => _done = true);
  }

  void _speak(String text) {
    _ttsCh.invokeMethod('speak', {'text': text, 'language': 'en-IN', 'rate': 0.9}).catchError((_) => null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Quiz — answers shown', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: AppColors.teal.withOpacity(0.15), borderRadius: BorderRadius.circular(99)),
                child: Text('$_xp XP', style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w900, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : widget.parts.isEmpty
              ? const EmptyState(icon: Icons.quiz_rounded, title: 'No parts yet', message: 'Open a textbook first.')
              : _done
                  ? _resultView()
                  : _questionView(),
    );
  }

  Widget _questionView() {
    if (_qs.isEmpty) {
      return const EmptyState(icon: Icons.quiz_rounded, title: 'No questions', message: 'This part has no key points yet — watch the class first.');
    }
    final q = _qs[_i];
    final isMcq = q.type == QuestionType.mcq;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(children: [
          Expanded(
            child: DropdownButton<int>(
              value: _partIdx.clamp(0, math.max(0, widget.parts.length - 1)),
              isExpanded: true,
              dropdownColor: AppColors.card,
              underline: Container(height: 1, color: AppColors.stroke),
              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
              items: [
                for (var i = 0; i < widget.parts.length; i++)
                  DropdownMenuItem(value: i, child: Text('Part ${widget.parts[i].part} — ${widget.parts[i].pageLabel}')),
              ],
              onChanged: (v) {
                if (v != null) _start(v);
              },
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text('Question ${_i + 1} of ${_qs.length}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
          const Spacer(),
          if (_streak >= 2)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.amber.withOpacity(0.16), borderRadius: BorderRadius.circular(99)),
              child: Text('🔥 $_streak streak', style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 11.5)),
            ),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: (_i + (_revealed ? 1 : 0)) / _qs.length,
            minHeight: 5,
            backgroundColor: AppColors.stroke,
            valueColor: const AlwaysStoppedAnimation(AppColors.teal),
          ),
        ),
        const SizedBox(height: 14),
        GradientCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.indigo.withOpacity(0.18), borderRadius: BorderRadius.circular(99)),
                child: Text(q.type.label, style: const TextStyle(color: AppColors.teal, fontSize: 10.5, fontWeight: FontWeight.w900)),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _speak(q.prompt),
                icon: const Icon(Icons.volume_up_rounded, size: 18, color: AppColors.teal),
              ),
            ]),
            const SizedBox(height: 8),
            Text(q.prompt, style: const TextStyle(color: AppColors.text, fontSize: 16, height: 1.45, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            if (isMcq)
              ...q.options.map((o) {
                final isAnswer = o.trim().toLowerCase() == q.answer.trim().toLowerCase();
                final chosen = _picked?.trim().toLowerCase() == o.trim().toLowerCase();
                Color border = AppColors.stroke;
                Color bg = AppColors.cardLight;
                if (_revealed && isAnswer) {
                  border = AppColors.green;
                  bg = AppColors.green.withOpacity(0.14);
                } else if (_revealed && chosen && !isAnswer) {
                  border = AppColors.red;
                  bg = AppColors.red.withOpacity(0.14);
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _revealed ? null : () => _check(o),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
                      child: Row(children: [
                        Expanded(child: Text(o, style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600))),
                        if (_revealed && isAnswer) const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 19),
                        if (_revealed && chosen && !isAnswer) const Icon(Icons.cancel_rounded, color: AppColors.red, size: 19),
                      ]),
                    ),
                  ),
                );
              })
            else ...[
              TextField(
                controller: _ctrl,
                enabled: !_revealed,
                style: const TextStyle(color: AppColors.text),
                decoration: InputDecoration(
                  hintText: 'Type the missing word',
                  hintStyle: const TextStyle(color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.cardLight,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.stroke)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.stroke)),
                ),
                onSubmitted: _check,
              ),
              const SizedBox(height: 10),
              if (!_revealed)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: () => _check(_ctrl.text), child: const Text('Check answer')),
                ),
            ],
            if (_revealed) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_picked != null && _isRight(q)) ? AppColors.green.withOpacity(0.10) : AppColors.amber.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (_picked != null && _isRight(q)) ? AppColors.green.withOpacity(0.5) : AppColors.amber.withOpacity(0.5)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon((_picked != null && _isRight(q)) ? Icons.emoji_events_rounded : Icons.lightbulb_rounded,
                        size: 17, color: (_picked != null && _isRight(q)) ? AppColors.green : AppColors.amber),
                    const SizedBox(width: 6),
                    Text((_picked != null && _isRight(q)) ? 'Correct! +5 XP' : 'Answer: ${q.answer}',
                        style: TextStyle(
                            color: (_picked != null && _isRight(q)) ? AppColors.green : AppColors.amber,
                            fontWeight: FontWeight.w900,
                            fontSize: 13)),
                  ]),
                  const SizedBox(height: 6),
                  Text(q.explanation, style: const TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.45)),
                ]),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _next,
                  icon: Icon(_i >= _qs.length - 1 ? Icons.flag_rounded : Icons.arrow_forward_rounded),
                  label: Text(_i >= _qs.length - 1 ? 'See my score' : 'Next question'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }

  bool _isRight(ExamQuestion q) {
    if (_picked == null) return false;
    return q.type == QuestionType.mcq
        ? _picked!.trim().toLowerCase() == q.answer.trim().toLowerCase()
        : QuestionBank.grade(q, _picked!) >= 0.5;
  }

  Widget _resultView() {
    final pct = _qs.isEmpty ? 0 : (_right / _qs.length) * 100;
    final pass = pct >= 40;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: pass ? AppColors.heroGradient : const LinearGradient(colors: [Color(0xFF7C2D12), Color(0xFF111833)]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(children: [
            Icon(pass ? Icons.emoji_events_rounded : Icons.school_rounded, color: Colors.white, size: 46),
            const SizedBox(height: 8),
            Text(pass ? 'Pass! Part cleared' : 'Not yet — 40% needed',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${pct.toStringAsFixed(0)}%  •  $_right right, $_wrong wrong  •  best streak $_bestStreak',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              pass
                  ? 'Next class is unlocked. Take the full test for marks, or run this quiz again to go for 100%.'
                  : 'Watch the class once more, then retry — your key points and mind map are ready.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _start(_partIdx),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Done'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        const SectionTitle('Answer key'),
        ...List.generate(_qs.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GradientCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ${_qs[i].prompt}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13, height: 1.4)),
                  const SizedBox(height: 5),
                  Text('Answer: ${_qs[i].answer}', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w900, fontSize: 12.5)),
                ]),
              ),
            )),
      ],
    );
  }
}
