import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../academic_models.dart';
import '../dart_engine.dart';
import '../models.dart';
import '../question_bank.dart';
import '../store.dart';
import '../study_stats.dart';
import '../ui/premium_ui.dart';
import '../widgets.dart';

/// Listening exam — the teacher's voice reads each question and its
/// options; the student answers by tapping. Trains exam listening and is
/// fully usable without looking at long text (accessibility).
class ListeningExamScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final List<SeriesPart> parts;
  const ListeningExamScreen({super.key, required this.settings, required this.book, required this.parts});

  @override
  State<ListeningExamScreen> createState() => _ListeningExamScreenState();
}

class _ListeningExamScreenState extends State<ListeningExamScreen> {
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  List<ExamQuestion> _qs = const [];
  int _i = 0;
  int _right = 0;
  String? _picked;
  bool _revealed = false;
  bool _loading = true;
  bool _speaking = false;
  bool _showText = false;
  bool _done = false;
  int _replays = 0;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    setState(() {
      _loading = true;
      _i = 0;
      _right = 0;
      _picked = null;
      _revealed = false;
      _done = false;
    });
    final points = <String>[];
    for (final p in widget.parts) {
      points.addAll(p.keyPoints);
    }
    if (points.length < 4) {
      final brain = await DartEngine.brainKeyPoints(widget.book.sessionId);
      points.addAll(brain);
    }
    var qs = QuestionBank.generate(
      keyPoints: points,
      bookTitle: widget.book.shortTitle,
      partLabel: 'Listening practice',
      types: {QuestionType.mcq, QuestionType.fill},
      count: 6,
      seed: DateTime.now().millisecondsSinceEpoch % 9973,
    );
    qs = qs.where((q) => q.type == QuestionType.mcq && q.options.length >= 2).toList();
    if (!mounted) return;
    setState(() {
      _qs = qs;
      _loading = false;
    });
    if (qs.isNotEmpty) _speakQuestion();
  }

  String _questionSpeech(ExamQuestion q) {
    final opts = q.options.asMap().entries.map((e) => 'Option ${e.key + 1}. ${e.value}').join('. ');
    return 'Question ${_i + 1}. ${q.prompt} $opts. Tap the correct option.';
  }

  Future<void> _speakQuestion({bool countReplay = false}) async {
    if (_qs.isEmpty || _i >= _qs.length) return;
    if (countReplay) setState(() => _replays++);
    setState(() => _speaking = true);
    await _ttsCh.invokeMethod('speak', {
      'text': _questionSpeech(_qs[_i]),
      'language': 'en-IN',
      'rate': widget.settings.speechRate,
      'pitch': widget.settings.speechPitch,
      'voice': widget.settings.voiceName,
    }).catchError((_) => null);
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _answer(String option) async {
    if (_revealed) return;
    final q = _qs[_i];
    final ok = option.trim().toLowerCase() == q.answer.trim().toLowerCase();
    setState(() {
      _picked = option;
      _revealed = true;
      if (ok) _right++;
    });
    await _ttsCh.invokeMethod('speak', {
      'text': ok ? 'Correct.' : 'The correct answer is ${q.answer}.',
      'language': 'en-IN',
      'rate': widget.settings.speechRate,
    }).catchError((_) => null);
    if (ok) ProgressStore.addXp(widget.book.sessionId, 5);
  }

  Future<void> _next() async {
    if (_i >= _qs.length - 1) {
      await StudyStats.recordActivity(scenes: 1);
      if (!mounted) return;
      setState(() => _done = true);
      return;
    }
    setState(() {
      _i++;
      _picked = null;
      _revealed = false;
    });
    _speakQuestion();
  }

  @override
  void dispose() {
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = (!_loading && !_done && _i < _qs.length) ? _qs[_i] : null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Listening exam', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: _showText ? 'Hide text' : 'Show text',
            onPressed: () => setState(() => _showText = !_showText),
            icon: Icon(_showText ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: AppColors.muted),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _qs.isEmpty
              ? const EmptyState(
                  icon: Icons.headphones_rounded,
                  title: 'No listening questions yet',
                  message: 'Watch a class for this textbook first — its key points become the MCQs.',
                )
              : _done
                  ? _result()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                      children: [
                        Row(children: [
                          Text('Question ${_i + 1} of ${_qs.length}',
                              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                          const Spacer(),
                          Text('$_right correct', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800, fontSize: 12.5)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: (_i + (_revealed ? 1 : 0)) / _qs.length,
                            minHeight: 5,
                            backgroundColor: AppColors.stroke,
                            valueColor: AlwaysStoppedAnimation(AppColors.teal),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(22)),
                          child: Column(children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
                              child: Icon(Icons.headphones_rounded, color: Colors.white, size: 34),
                            ),
                            const SizedBox(height: 12),
                            const Text('Listen carefully',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(_showText ? 'Text shown below' : 'The question is spoken — tap an option to answer',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                            const SizedBox(height: 14),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              FilledButton.icon(
                                onPressed: () => _speakQuestion(countReplay: true),
                                icon: Icon(_speaking ? Icons.graphic_eq_rounded : Icons.replay_rounded, size: 18),
                                label: Text(_replays > 0 ? 'Play again ($_replays)' : 'Play question'),
                                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.indigo),
                              ),
                            ]),
                          ]),
                        ),
                        if (_showText && q != null) ...[
                          const SizedBox(height: 12),
                          GradientCard(
                            child: Text(q.prompt, style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.45, fontWeight: FontWeight.w700)),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (q != null)
                          ...q.options.asMap().entries.map((e) {
                            final option = e.value;
                            final isAnswer = option.trim().toLowerCase() == q.answer.trim().toLowerCase();
                            final chosen = _picked?.trim().toLowerCase() == option.trim().toLowerCase();
                            var border = AppColors.stroke;
                            var bg = AppColors.card;
                            if (_revealed && isAnswer) {
                              border = AppColors.green;
                              bg = AppColors.green.withOpacity(0.13);
                            } else if (_revealed && chosen && !isAnswer) {
                              border = AppColors.red;
                              bg = AppColors.red.withOpacity(0.13);
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: _revealed ? null : () => _answer(option),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: border),
                                  ),
                                  child: Row(children: [
                                    Container(
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.cardLight,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text('${e.key + 1}',
                                          style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w900, fontSize: 12)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(option,
                                          style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
                                    ),
                                    if (_revealed && isAnswer) Icon(Icons.check_circle_rounded, color: AppColors.green, size: 19),
                                    if (_revealed && chosen && !isAnswer) Icon(Icons.cancel_rounded, color: AppColors.red, size: 19),
                                  ]),
                                ),
                              ),
                            );
                          }),
                        if (_revealed && q != null)
                          FilledButton.icon(
                            onPressed: _next,
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: Text(_i >= _qs.length - 1 ? 'Finish' : 'Next question'),
                            style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
                          ),
                      ],
                    ),
    );
  }

  Widget _result() {
    final pct = _qs.isEmpty ? 0 : (_right / _qs.length) * 100;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            Icon(pct >= 40 ? Icons.emoji_events_rounded : Icons.headphones_rounded, color: Colors.white, size: 44),
            const SizedBox(height: 8),
            Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
            Text('$_right of ${_qs.length} correct', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _build,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Listen again'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Done'),
        ),
      ],
    );
  }
}
