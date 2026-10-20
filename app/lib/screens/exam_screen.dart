import 'dart:async';

import 'package:flutter/material.dart';

import '../academic_models.dart';
import '../exam_store.dart';
import '../vault/emoji_vault.dart';
import '../question_bank.dart';
import '../widgets.dart';
import 'exam_result_screen.dart';

/// Full-screen exam player: timer, question palette, MCQ tap / typed
/// answers for fill & short, auto-submit when time runs out.
class ExamScreen extends StatefulWidget {
  final ExamConfig config;
  final List<ExamQuestion> questions;

  /// Called when this was a part test and the student passed (>= 40%):
  /// the caller marks the part complete so the next class unlocks.
  final Future<void> Function()? onPassed;

  const ExamScreen(
      {super.key,
      required this.config,
      required this.questions,
      this.onPassed});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  final Map<int, String> _answers = {};
  final Map<int, TextEditingController> _controllers = {};
  int _index = 0;
  int _secondsLeft = 0;
  Timer? _timer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.questions.length; i++) {
      if (widget.questions[i].type != QuestionType.mcq) {
        _controllers[i] = TextEditingController()
          ..addListener(() => _answers[i] = _controllers[i]!.text);
      }
    }
    if (widget.config.timed) {
      _secondsLeft = widget.config.minutes * 60;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) {
          t.cancel();
          _submit(auto: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _clock {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  int get _answeredCount =>
      _answers.values.where((v) => v.trim().isNotEmpty).length;

  Future<void> _submit({bool auto = false}) async {
    if (_submitting) return;
    if (!auto) {
      final unanswered = widget.questions.length - _answeredCount;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Submit test?',
              style: TextStyle(
                  color: AppColors.text, fontWeight: FontWeight.w800)),
          content: Text(
            unanswered > 0
                ? 'You still have $unanswered unanswered question(s). Submit anyway?'
                : 'You answered everything. Submit for marking?',
            style: TextStyle(color: AppColors.muted),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep writing')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit')),
          ],
        ),
      );
      if (go != true) return;
    }
    if (!mounted) return;
    setState(() => _submitting = true);
    _timer?.cancel();

    var earned = 0.0;
    var total = 0;
    var wrongMcq = 0;
    final reviews = <ReviewItem>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final q = widget.questions[i];
      final given = (_answers[i] ?? '').trim();
      final got = QuestionBank.grade(q, given);
      if (q.type == QuestionType.mcq && given.isNotEmpty && got == 0)
        wrongMcq++;
      earned += got;
      total += q.marks;
      reviews.add(ReviewItem(
        prompt: q.prompt,
        typeLabel: q.type.label,
        given: given,
        correct: q.answer,
        explanation: q.explanation,
        awarded: got,
        maxMarks: q.marks,
      ));
    }
    if (widget.config.negativeMarking && wrongMcq > 0) {
      earned = maxDouble(0, earned - wrongMcq * 0.25);
    }
    earned = roundHalf(earned);

    final result = ExamResult(
      sessionId: widget.config.sessionId,
      bookTitle: widget.config.bookTitle,
      part: widget.config.part,
      partLabel: widget.config.partLabel,
      when: DateTime.now(),
      earned: earned,
      total: total,
      reviews: reviews,
    );
    await ExamStore.addResult(result);
    await VaultStore.log('test', 'Test finished — ${result.earned.toStringAsFixed(0)} of ${result.total} marks');
    if (result.passed && widget.onPassed != null) {
      try {
        await widget.onPassed!();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ExamResultScreen(
          result: result,
          negativeApplied: widget.config.negativeMarking ? wrongMcq : 0),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questions[_index];
    final total = widget.questions.length;
    final lowTime = widget.config.timed && _secondsLeft <= 60;
    return PopScope(
      canPop: false,
      onPopInvoked: (_) async {
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            title: Text('Leave this test?',
                style: TextStyle(
                    color: AppColors.text, fontWeight: FontWeight.w800)),
            content: Text(
                'Your answers will be lost and this attempt will not be marked.',
                style: TextStyle(color: AppColors.muted)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Stay')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Leave')),
            ],
          ),
        );
        if (leave == true && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.config.title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text)),
            Text(widget.config.partLabel,
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
          actions: [
            if (widget.config.timed)
              Container(
                margin: const EdgeInsets.only(right: 14),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (lowTime ? AppColors.red : AppColors.teal)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                      color: (lowTime ? AppColors.red : AppColors.teal)
                          .withOpacity(0.55)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_rounded,
                      size: 16,
                      color: lowTime ? AppColors.red : AppColors.teal),
                  const SizedBox(width: 5),
                  Text(_clock,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: lowTime ? AppColors.red : AppColors.teal)),
                ]),
              ),
          ],
        ),
        body: Column(children: [
          LinearProgressIndicator(
            value: total == 0 ? 0 : _answeredCount / total,
            minHeight: 5,
            backgroundColor: AppColors.stroke,
            valueColor: AlwaysStoppedAnimation(AppColors.teal),
          ),
          // Question palette
          SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              scrollDirection: Axis.horizontal,
              itemCount: total,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (_, i) {
                final answered = (_answers[i] ?? '').trim().isNotEmpty;
                final cur = i == _index;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _index = i),
                  child: Container(
                    width: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cur
                          ? AppColors.indigo
                          : answered
                              ? AppColors.teal.withOpacity(0.25)
                              : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: cur
                              ? AppColors.indigo
                              : answered
                                  ? AppColors.teal
                                  : AppColors.stroke),
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: cur || answered
                                ? Colors.white
                                : AppColors.muted)),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: AppColors.violet.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(99)),
                      child: Text(q.type.label,
                          style: TextStyle(
                              color: AppColors.violet,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    Text('Question ${_index + 1} of $total',
                        style: TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${q.marks} mark${q.marks == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: AppColors.amber,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5)),
                  ]),
                  const SizedBox(height: 16),
                  Text(q.prompt,
                      style: TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                          height: 1.5)),
                  const SizedBox(height: 20),
                  if (q.type == QuestionType.mcq)
                    ...q.options.map((o) {
                      final sel = _answers[_index] == o;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => setState(() => _answers[_index] = o),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 15),
                            decoration: BoxDecoration(
                              color: sel
                                  ? AppColors.indigo.withOpacity(0.28)
                                  : AppColors.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color:
                                      sel ? AppColors.indigo : AppColors.stroke,
                                  width: sel ? 1.6 : 1),
                            ),
                            child: Row(children: [
                              Icon(
                                  sel
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_off_rounded,
                                  color:
                                      sel ? AppColors.indigo : AppColors.muted,
                                  size: 21),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(o,
                                      style: TextStyle(
                                          color: AppColors.text,
                                          fontWeight: sel
                                              ? FontWeight.w800
                                              : FontWeight.w500,
                                          fontSize: 15))),
                            ]),
                          ),
                        ),
                      );
                    })
                  else
                    TextField(
                      controller: _controllers[_index],
                      maxLines: q.type == QuestionType.short ? 6 : 1,
                      style: TextStyle(color: AppColors.text),
                      decoration: InputDecoration(
                        hintText: q.type == QuestionType.fill
                            ? 'Type the missing term…'
                            : 'Write your answer here…',
                      ),
                    ),
                  if (q.type == QuestionType.short)
                    Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                          'Short answers are marked by how many key ideas from the textbook point your answer covers. The model answer is shown after submission.',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              height: 1.45)),
                    ),
                ]),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            decoration: BoxDecoration(
                color: AppColors.bg2,
                border: Border(top: BorderSide(color: AppColors.stroke))),
            child: Row(children: [
              OutlinedButton(
                onPressed: _index > 0 ? () => setState(() => _index--) : null,
                child: const Text('Previous'),
              ),
              const SizedBox(width: 10),
              if (_index < total - 1)
                Expanded(
                  child: FilledButton(
                    onPressed: () => setState(() => _index++),
                    child: const Text('Next question'),
                  ),
                )
              else
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitting ? null : () => _submit(),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.assignment_turned_in_rounded,
                            size: 19),
                    label:
                        Text('Submit test ($_answeredCount/$total answered)'),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        foregroundColor: const Color(0xFF06231F)),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
