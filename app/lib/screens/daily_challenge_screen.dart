import 'package:flutter/material.dart';

import '../academic_models.dart';
import '../engine_gateway.dart';
import '../models.dart';
import '../question_bank.dart';
import '../store.dart';
import '../study_stats.dart';
import '../ui/premium_ui.dart';
import '../widgets.dart';

/// Daily challenge — 5 mixed questions from every textbook on the phone,
/// the same set for the whole day, with a streak and bonus XP.
class DailyChallengeScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  final List<TextbookItem> books;
  const DailyChallengeScreen({super.key, required this.gateway, required this.settings, required this.books});

  @override
  State<DailyChallengeScreen> createState() => _DailyChallengeScreenState();
}

class _DailyChallengeScreenState extends State<DailyChallengeScreen> {
  List<ExamQuestion> _qs = const [];
  int _i = 0;
  int _right = 0;
  String? _picked;
  bool _revealed = false;
  bool _loading = true;
  bool _done = false;
  String _bookTitle = '';

  int get _seed {
    final now = DateTime.now();
    return now.year * 10000 + now.month * 100 + now.day;
  }

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    setState(() => _loading = true);
    final allPoints = <String>[];
    var pickedTitle = '';
    for (final b in widget.books.take(4)) {
      try {
        final s = await widget.gateway.chapterSeries(
          b.sessionId,
          pagesPerPart: widget.settings.pagesPerPart,
          brain: widget.settings.brain,
          brainServerUrl: widget.settings.brainServerUrl,
        );
        final parts = ((s['parts'] as List?) ?? const []).whereType<Map>().map(SeriesPart.fromMap).toList();
        final pts = parts.expand((p) => p.keyPoints).toList();
        if (pts.isNotEmpty) {
          allPoints.addAll(pts);
          pickedTitle = pickedTitle.isEmpty ? b.shortTitle : '$pickedTitle • ${b.shortTitle}';
        }
      } catch (_) {}
    }
    final qs = QuestionBank.generate(
      keyPoints: allPoints,
      bookTitle: 'Daily challenge',
      partLabel: 'Today',
      types: {QuestionType.mcq, QuestionType.fill},
      count: 5,
      seed: _seed,
    );
    if (!mounted) return;
    setState(() {
      _qs = qs;
      _bookTitle = pickedTitle.isEmpty ? 'Add a textbook first' : pickedTitle;
      _loading = false;
    });
  }

  void _answer(String given) {
    if (_revealed) return;
    final q = _qs[_i];
    final ok = q.type == QuestionType.mcq
        ? given.trim().toLowerCase() == q.answer.trim().toLowerCase()
        : QuestionBank.grade(q, given) >= 0.5;
    setState(() {
      _picked = given;
      _revealed = true;
      if (ok) _right++;
    });
  }

  Future<void> _next() async {
    if (_i >= _qs.length - 1) {
      final pct = (_right / _qs.length) * 100;
      if (widget.books.isNotEmpty) {
        await ProgressStore.addXp(widget.books.first.sessionId, pct >= 80 ? 60 : pct >= 40 ? 30 : 10);
      }
      await StudyStats.recordActivity(scenes: 1);
      if (!mounted) return;
      setState(() => _done = true);
      if (pct >= 80) {
        await showCelebration(context, title: 'Daily challenge cleared!', subtitle: '+60 XP — come back tomorrow for a new set.');
      }
      return;
    }
    setState(() {
      _i++;
      _picked = null;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Daily challenge', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _qs.isEmpty
              ? const EmptyState(
                  icon: Icons.bolt_rounded,
                  title: 'Nothing to challenge yet',
                  message: 'Add a textbook and watch one class — the daily challenge is built from your own key points.',
                )
              : _done
                  ? _result()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: AppColors.heroGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(children: [
                            const Icon(Icons.bolt_rounded, color: Colors.white, size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text("Today's 5 questions",
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                                Text(_bookTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                              ]),
                            ),
                            Text('${_i + 1}/${_qs.length}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                          ]),
                        ),
                        const SizedBox(height: 14),
                        GradientCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: AppColors.indigo.withOpacity(0.18), borderRadius: BorderRadius.circular(99)),
                                child: Text(_qs[_i].type.label,
                                    style: TextStyle(color: AppColors.teal, fontSize: 10, fontWeight: FontWeight.w900)),
                              ),
                              const Spacer(),
                              Text('$_right right', style: TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ]),
                            const SizedBox(height: 10),
                            Text(_qs[_i].prompt,
                                style: TextStyle(color: AppColors.text, fontSize: 16, height: 1.45, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 14),
                            if (_qs[_i].type == QuestionType.mcq)
                              ..._qs[_i].options.map((o) {
                                final isAnswer = o.trim().toLowerCase() == _qs[_i].answer.trim().toLowerCase();
                                final chosen = _picked?.trim().toLowerCase() == o.trim().toLowerCase();
                                final color = _revealed && isAnswer
                                    ? AppColors.green
                                    : (_revealed && chosen ? AppColors.red : AppColors.stroke);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: _revealed ? null : () => _answer(o),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _revealed && isAnswer
                                            ? AppColors.green.withOpacity(0.12)
                                            : (_revealed && chosen ? AppColors.red.withOpacity(0.12) : AppColors.cardLight),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: color),
                                      ),
                                      child: Text(o, style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                );
                              })
                            else
                              _FillAnswer(
                                revealed: _revealed,
                                onCheck: _answer,

                              ),
                            if (_revealed) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.amber.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.amber.withOpacity(0.4)),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Answer: ${_qs[_i].answer}',
                                      style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w900, fontSize: 12.5)),
                                  const SizedBox(height: 4),
                                  Text(_qs[_i].explanation, style: TextStyle(color: AppColors.text, fontSize: 12.5, height: 1.45)),
                                ]),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _next,
                                  icon: Icon(_i >= _qs.length - 1 ? Icons.flag_rounded : Icons.arrow_forward_rounded),
                                  label: Text(_i >= _qs.length - 1 ? 'See result' : 'Next'),
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 13)),
                                ),
                              ),
                            ],
                          ]),
                        ),
                      ],
                    ),
    );
  }

  Widget _result() {
    final pct = (_right / _qs.length) * 100;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            Icon(pct >= 80 ? Icons.emoji_events_rounded : Icons.bolt_rounded, color: Colors.white, size: 46),
            const SizedBox(height: 8),
            Text('$_right / ${_qs.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
            Text(pct >= 80 ? 'Excellent! +60 XP' : pct >= 40 ? 'Good — +30 XP' : 'Keep going — +10 XP',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check_rounded),
          label: const Text('Done'),
        ),
      ],
    );
  }
}

class _FillAnswer extends StatefulWidget {
  final bool revealed;
  final ValueChanged<String> onCheck;
  const _FillAnswer({required this.revealed, required this.onCheck});

  @override
  State<_FillAnswer> createState() => _FillAnswerState();
}

class _FillAnswerState extends State<_FillAnswer> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(
        controller: _c,
        enabled: !widget.revealed,
        style: TextStyle(color: AppColors.text),
        decoration: const InputDecoration(hintText: 'Type the missing word'),
        onSubmitted: widget.onCheck,
      ),
      if (!widget.revealed) ...[
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: () => widget.onCheck(_c.text), child: const Text('Check')),
        ),
      ],
    ]);
  }
}
