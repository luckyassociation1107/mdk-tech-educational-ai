import 'dart:math';

import 'academic_models.dart';

/// Offline question generator. Questions are built ONLY from the part's
/// own key points (which come from real PDF analysis) — never invented
/// textbook facts. When a part has too few key points, it falls back to
/// study questions that point the student back at their own notes.
class QuestionBank {
  static const _stop = {
    'the',
    'a',
    'an',
    'is',
    'are',
    'was',
    'were',
    'of',
    'to',
    'in',
    'on',
    'and',
    'or',
    'for',
    'with',
    'that',
    'this',
    'from',
    'by',
    'as',
    'it',
    'its',
    'be',
    'can',
    'we',
    'you',
    'they',
    'them',
    'then',
    'than',
    'so',
    'such',
    'into',
    'over',
    'under',
    'between',
    'called',
    'known',
    'given',
    'when',
    'where',
    'which',
    'what',
    'how',
    'all',
    'any',
    'each',
    'every',
  };

  static List<String> _sentences(List<String> keyPoints) {
    final out = <String>[];
    for (final kp in keyPoints) {
      for (final s in kp.split(RegExp(r'(?<=[.!?])\s+'))) {
        final t = s.trim();
        if (t.length >= 25 && t.split(' ').length >= 5) out.add(t);
      }
    }
    return out;
  }

  /// The key term of a sentence: "A set is …" → "set";
  /// "The Empty Set contains …" → "Empty Set"; else longest real word.
  static String? _keyTerm(String sentence) {
    final m = RegExp(r"^(.{2,40}?)\s+(?:is|are|was|were|means|refers to)\b",
            caseSensitive: false)
        .firstMatch(sentence);
    if (m != null) {
      var head = m.group(1)!.trim();
      head =
          head.replaceAll(RegExp(r'^(a|an|the)\s+', caseSensitive: false), '');
      final words =
          head.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      if (words.isNotEmpty) {
        // "union of two sets" -> "union"; "roster form of a set" -> "roster form"
        var seg = words;
        final ofIdx = words.indexWhere((w) => w.toLowerCase() == 'of');
        if (ofIdx > 0) seg = words.sublist(0, ofIdx);
        final term = seg.skip(max(0, seg.length - 3)).join(' ');
        if (term.length >= 2 && term.length <= 34) return term;
      }
    }
    final cap =
        RegExp(r'\b[A-Z][a-zA-Z]+(?:\s[A-Z][a-zA-Z]+)+\b').firstMatch(sentence);
    if (cap != null && cap.start > 0) return cap.group(0);
    String? best;
    for (final w in sentence.split(RegExp(r'[^A-Za-z]+'))) {
      final lw = w.toLowerCase();
      if (w.length >= 6 &&
          !_stop.contains(lw) &&
          (best == null || w.length > best.length)) best = w;
    }
    return best;
  }

  static String _blankOut(String sentence, String term) {
    final idx = sentence.toLowerCase().indexOf(term.toLowerCase());
    if (idx < 0) return sentence;
    return '${sentence.substring(0, idx)}______${sentence.substring(idx + term.length)}';
  }

  static List<ExamQuestion> generate({
    required List<String> keyPoints,
    required String bookTitle,
    required String partLabel,
    required Set<QuestionType> types,
    required int count,
    int seed = 7,
  }) {
    final rng = Random(seed + keyPoints.join().length + count);
    final sentences = _sentences(keyPoints);
    final questions = <ExamQuestion>[];

    if (sentences.isEmpty) {
      // Honest fallback: study questions over the student's own notes.
      for (var i = 0; i < count; i++) {
        questions.add(ExamQuestion(
          type: QuestionType.short,
          prompt:
              'Write the main points, definitions and examples covered in $partLabel of "$bookTitle".',
          answer: 'Main points of $partLabel',
          explanation:
              'Compare with your notes for $partLabel: your answer should cover the definitions, worked examples and exercise answers from those pages. Generate/watch the class for this part to get auto-graded MCQ and fill-in questions from its key points.',
          marks: QuestionType.short.defaultMarks,
        ));
      }
      return questions;
    }

    final terms = <String>[];
    final bySentence = <String, String>{};
    for (final s in sentences) {
      final t = _keyTerm(s);
      if (t != null) {
        bySentence[s] = t;
        if (!terms.any((x) => x.toLowerCase() == t.toLowerCase())) terms.add(t);
      }
    }
    final usable = sentences.where((s) => bySentence.containsKey(s)).toList()
      ..shuffle(rng);
    final typeList = types.toList();

    final usedPrompts = <String>{};
    var i = 0;
    while (questions.length < count && usable.isNotEmpty) {
      final s = usable[i % usable.length];
      final term = bySentence[s]!;
      final type = typeList[(questions.length) % typeList.length];
      if (!usedPrompts.add('$type:${_blankOut(s, term)}')) {
        i++;
        if (i > usable.length * 3) break;
        continue;
      }
      switch (type) {
        case QuestionType.mcq:
          final distractors = terms
              .where((t) => t.toLowerCase() != term.toLowerCase())
              .toList()
            ..shuffle(rng);
          final opts = <String>[term, ...distractors.take(3)];
          while (opts.length < 4) {
            opts.add(
                opts.length == 1 ? 'None of the above' : 'All of the above');
          }
          opts.shuffle(rng);
          questions.add(ExamQuestion(
            type: type,
            prompt: _blankOut(s, term),
            options: opts,
            answer: term,
            explanation: s,
            marks: type.defaultMarks,
          ));
        case QuestionType.fill:
          questions.add(ExamQuestion(
            type: type,
            prompt: _blankOut(s, term),
            answer: term,
            explanation: s,
            marks: type.defaultMarks,
          ));
        case QuestionType.short:
          questions.add(ExamQuestion(
            type: type,
            prompt:
                'Explain in your own words: what is "$term"? (from $partLabel)',
            answer: term,
            explanation: s,
            marks: type.defaultMarks,
          ));
      }
      i++;
      if (i > usable.length * 3) break;
    }
    return questions;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Set<String> _keywords(String text) {
    return _norm(text)
        .split(' ')
        .where((w) => w.length >= 4 && !_stop.contains(w))
        .toSet();
  }

  /// Returns marks awarded (0..q.marks). Short answers are graded by key
  /// idea coverage against the model key point — shown openly in review.
  static double grade(ExamQuestion q, String given) {
    final g = _norm(given);
    if (g.isEmpty) return 0;
    switch (q.type) {
      case QuestionType.mcq:
        return _norm(given) == _norm(q.answer) ? q.marks.toDouble() : 0;
      case QuestionType.fill:
        final a = _norm(q.answer);
        if (g == a) return q.marks.toDouble();
        if (a.length >= 4 && (g.contains(a) || a.contains(g)))
          return q.marks.toDouble();
        return 0;
      case QuestionType.short:
        final keys = {..._keywords(q.explanation), ..._keywords(q.answer)};
        if (keys.isEmpty) return 0;
        final givenWords = _norm(given).split(' ').toSet();
        final hits = keys.where((k) => givenWords.contains(k)).length;
        final cov = hits / keys.length;
        if (cov >= 0.7) return q.marks.toDouble();
        if (cov >= 0.5) return roundHalf(q.marks * 0.7);
        if (cov >= 0.3) return roundHalf(q.marks * 0.4);
        if (cov > 0) return roundHalf(q.marks * 0.2);
        return 0;
    }
  }
}
