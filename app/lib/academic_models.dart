/// Academic layer: exam questions, results, marks, grades and ranks.
/// Everything here is computed on-device from the student's own tests —
/// no server, no invented class data. Ranks are performance bands over
/// the student's own scores (stated openly in the Report Card screen).
import 'dart:math' as math;

enum QuestionType { mcq, fill, short }

extension QuestionTypeX on QuestionType {
  String get label => switch (this) {
        QuestionType.mcq => 'MCQ',
        QuestionType.fill => 'Fill in the blank',
        QuestionType.short => 'Short answer',
      };
  int get defaultMarks => switch (this) {
        QuestionType.mcq => 1,
        QuestionType.fill => 2,
        QuestionType.short => 5,
      };
}

class ExamQuestion {
  final QuestionType type;
  final String prompt;
  final List<String> options; // MCQ only
  final String answer; // correct option / key term / model answer headline
  final String explanation; // full key point or model answer, shown in review
  final int marks;

  const ExamQuestion({
    required this.type,
    required this.prompt,
    this.options = const [],
    required this.answer,
    required this.explanation,
    required this.marks,
  });
}

class ExamConfig {
  final String sessionId;
  final String bookTitle;
  final int part;
  final String partLabel;
  final Set<QuestionType> types;
  final int count;
  final bool timed;
  final int minutes;
  final bool negativeMarking;

  const ExamConfig({
    required this.sessionId,
    required this.bookTitle,
    required this.part,
    required this.partLabel,
    required this.types,
    required this.count,
    required this.timed,
    required this.minutes,
    required this.negativeMarking,
  });

  String get title => part > 0 ? 'Part $part Test' : 'Chapter Test';
}

class ReviewItem {
  final String prompt;
  final String typeLabel;
  final String given;
  final String correct;
  final String explanation;
  final double awarded;
  final int maxMarks;

  const ReviewItem({
    required this.prompt,
    required this.typeLabel,
    required this.given,
    required this.correct,
    required this.explanation,
    required this.awarded,
    required this.maxMarks,
  });

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'type': typeLabel,
        'given': given,
        'correct': correct,
        'explanation': explanation,
        'awarded': awarded,
        'max': maxMarks,
      };

  factory ReviewItem.fromJson(Map<String, dynamic> j) => ReviewItem(
        prompt: (j['prompt'] ?? '').toString(),
        typeLabel: (j['type'] ?? '').toString(),
        given: (j['given'] ?? '').toString(),
        correct: (j['correct'] ?? '').toString(),
        explanation: (j['explanation'] ?? '').toString(),
        awarded: (j['awarded'] as num?)?.toDouble() ?? 0,
        maxMarks: (j['max'] as num?)?.toInt() ?? 0,
      );
}

class ExamResult {
  final String sessionId;
  final String bookTitle;
  final int part;
  final String partLabel;
  final DateTime when;
  final double earned;
  final int total;
  final List<ReviewItem> reviews;

  const ExamResult({
    required this.sessionId,
    required this.bookTitle,
    required this.part,
    required this.partLabel,
    required this.when,
    required this.earned,
    required this.total,
    required this.reviews,
  });

  double get percentage =>
      total == 0 ? 0 : (earned / total * 100).clamp(0, 100);
  bool get passed => percentage >= 40;

  String get grade {
    final p = percentage;
    if (p >= 90) return 'A+';
    if (p >= 80) return 'A';
    if (p >= 70) return 'B+';
    if (p >= 60) return 'B';
    if (p >= 50) return 'C';
    if (p >= 40) return 'D';
    return 'F';
  }

  String get remark {
    final p = percentage;
    if (p >= 90) return 'Outstanding! You have mastered this part.';
    if (p >= 80) return 'Excellent work — almost perfect.';
    if (p >= 70) return 'Very good. Review the few you missed.';
    if (p >= 60) return 'Good. Revise the missed points once more.';
    if (p >= 50) return 'Fair. Rewatch the class, then retake.';
    if (p >= 40) return 'You passed — but revise this part carefully.';
    return 'Not yet. Watch the class again and retry — you can do it.';
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'bookTitle': bookTitle,
        'part': part,
        'partLabel': partLabel,
        'when': when.toIso8601String(),
        'earned': earned,
        'total': total,
        'reviews': reviews.map((r) => r.toJson()).toList(),
      };

  factory ExamResult.fromJson(Map<String, dynamic> j) => ExamResult(
        sessionId: (j['sessionId'] ?? '').toString(),
        bookTitle: (j['bookTitle'] ?? 'Textbook').toString(),
        part: (j['part'] as num?)?.toInt() ?? 0,
        partLabel: (j['partLabel'] ?? '').toString(),
        when: DateTime.tryParse((j['when'] ?? '').toString()) ?? DateTime.now(),
        earned: (j['earned'] as num?)?.toDouble() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        reviews: ((j['reviews'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) =>
                ReviewItem.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
            .toList(),
      );
}

/// Rank bands over the student's own average. [nextAt] is the average
/// needed for the next band (null when at the top).
class RankBand {
  final String rank;
  final String title;
  final double minAvg;
  final double? nextAt;
  const RankBand(this.rank, this.title, this.minAvg, this.nextAt);
}

RankBand rankFor({required double avgPct, required int tests}) {
  if (tests == 0) return const RankBand('—', 'No tests yet', 0, 40);
  if (avgPct >= 90) return const RankBand('Rank 1', 'Gold Scholar', 90, null);
  if (avgPct >= 80) return const RankBand('Rank 2', 'Silver Scholar', 80, 90);
  if (avgPct >= 70) return const RankBand('Rank 3', 'Bronze Scholar', 70, 80);
  if (avgPct >= 60) return const RankBand('Rank 4', 'Rising Scholar', 60, 70);
  if (avgPct >= 50) return const RankBand('Rank 5', 'Achiever', 50, 60);
  if (avgPct >= 40) return const RankBand('Rank 6', 'Learner', 40, 50);
  return const RankBand('Unranked', 'Keep Practising', 0, 40);
}

/// XP = total marks ever earned. Levels grow with effort, not just talent.
const _levelThresholds = [0, 25, 75, 150, 250, 400, 600, 850, 1150, 1500];

({int level, double progress, int nextAt}) levelFor(double xp) {
  var lvl = 1;
  for (var i = 0; i < _levelThresholds.length; i++) {
    if (xp >= _levelThresholds[i]) lvl = i + 1;
  }
  if (lvl >= _levelThresholds.length)
    return (level: lvl, progress: 1, nextAt: _levelThresholds.last);
  final cur = _levelThresholds[lvl - 1];
  final next = _levelThresholds[lvl];
  return (
    level: lvl,
    progress: ((xp - cur) / (next - cur)).clamp(0, 1),
    nextAt: next
  );
}

double roundHalf(double v) => (v * 2).round() / 2;
double maxDouble(double a, double b) => math.max(a, b);
