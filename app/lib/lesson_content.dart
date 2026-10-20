import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'dart_engine.dart';
import 'subject_engine.dart';

/// One scene of a class. Shared by the video-style lesson player and
/// the audio podcast player, so both teach identically.
class LessonScene {
  final String kind; // title | board | reading | zoom | steps | daily | vocab | practice | timeline | safety | lab | quick | diagram | end
  final String heading;
  final String narration; // what the voice speaks (sync source of truth)
  final String? boardText; // explicit board content (textbook lists)
  final String? explain; // the app's own English explanation (translatable)
  final String? source; // textbook excerpt — NEVER translated
  final String? extra; // e.g. practice answer, revealed late in the scene
  final List<String> labels; // figure labels shown on zoom scenes
  final List<String> options; // quick-check options
  final String? answer; // quick-check correct option
  final int? page;
  final Rect? zone; // normalized focus region for zoom scenes
  final String boardTheme;
  final bool formula;
  const LessonScene(this.kind, this.heading, this.narration,
      {this.boardText,
      this.explain,
      this.source,
      this.extra,
      this.labels = const [],
      this.options = const [],
      this.answer,
      this.page,
      this.zone,
      this.boardTheme = 'green',
      this.formula = false});

  LessonScene copyWith({String? narration}) => LessonScene(kind, heading, narration ?? this.narration,
      boardText: boardText, explain: explain, source: source, extra: extra, labels: labels, options: options,
      answer: answer, page: page, zone: zone, boardTheme: boardTheme, formula: formula);

  /// What the board shows. When an explanation was translated, only the
  /// explanation changes — the textbook excerpt stays in the book's language.
  String boardFor(String? translatedExplain) {
    if (boardText != null) return boardText!;
    final e = translatedExplain ?? explain;
    if (e != null && source != null && source!.trim().isNotEmpty) return '$e\n\n\u{1F4D6} $source';
    return e ?? source ?? narration;
  }

  /// The text the voice should speak for this scene.
  String voiceFor(String? translatedExplain) => translatedExplain ?? narration;
}

/// Builds the full scene list for one part: textbook-referenced,
/// subject-styled, with figure zooms, labs, daily-life connects and
/// interactive quick checks.
class LessonContent {
  static List<String> sentences(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  static ({String theme, bool formula}) styleFor(String text, int i, String themeSetting) {
    final forced = themeSetting;
    if (forced.contains('green')) return (theme: 'green', formula: false);
    if (forced.contains('black')) return (theme: 'black', formula: false);
    if (forced.contains('white')) return (theme: 'white', formula: false);
    if (forced.contains('ruled')) return (theme: 'ruled', formula: false);
    if (forced.contains('graph')) return (theme: 'graph', formula: true);
    final t = text.toLowerCase();
    final mathHits = RegExp(r'[=+×÷√π%^<>]').allMatches(text).length + RegExp(r'\d').allMatches(text).length;
    if (mathHits >= 4) return (theme: 'graph', formula: true);
    if (t.contains('example') || t.contains('for instance')) return (theme: 'white', formula: false);
    if (t.contains('is called') || t.contains(' is defined ') || t.contains('means ') || t.contains('definition')) {
      return (theme: 'green', formula: false);
    }
    if (text.length > 240) return (theme: 'ruled', formula: false);
    const cycle = ['green', 'black', 'white', 'ruled', 'graph'];
    return (theme: cycle[i % cycle.length], formula: false);
  }

  static List<Rect> imageZones(DartPage page) {
    final bands = page.blocks.where((b) => b.bbox.length == 4).toList()..sort((a, b) => a.bbox[1].compareTo(b.bbox[1]));
    if (bands.isEmpty) return const [];
    final zones = <Rect>[];
    var prevBottom = bands.first.bbox[3];
    for (var i = 1; i < bands.length; i++) {
      final top = bands[i].bbox[1];
      if (top - prevBottom > 0.13) {
        zones.add(Rect.fromLTRB(0.05, prevBottom + 0.015, 0.95, top - 0.015));
      }
      prevBottom = math.max(prevBottom, bands[i].bbox[3]);
    }
    if (prevBottom < 0.84) zones.add(Rect.fromLTRB(0.05, prevBottom + 0.015, 0.95, 0.97));
    zones.sort((a, b) => b.height.compareTo(a.height));
    return zones.take(1).toList();
  }

  static ({String caption, List<String> labels}) captionNear(DartPage page, Rect zone) {
    DartBlock? caption;
    DartBlock? after;
    final labels = <String>[];
    for (final b in page.blocks) {
      if (b.bbox.length != 4) continue;
      final t = b.text.trim();
      final tl = t.toLowerCase();
      final inside = b.bbox[1] >= zone.top - 0.05 && b.bbox[1] <= zone.bottom + 0.08;
      if (inside && t.length >= 2 && t.length <= 42 && labels.length < 5 && !labels.contains(t)) labels.add(t);
      if (tl.contains('fig') || tl.contains('diagram') || tl.contains('table') || tl.contains('picture')) {
        caption ??= b;
      }
      if (b.bbox[1] >= zone.bottom - 0.02) after ??= b;
    }
    var c = (caption ?? after)?.text.trim() ?? '';
    if (c.length > 200) c = c.substring(0, 200);
    return (caption: c, labels: labels);
  }

  static LessonScene? _quickCheck(List<String> pool, int seed) {
    final usable = pool.where((s) => s.length > 45).toList();
    if (usable.length < 2) return null;
    final src = usable[seed % usable.length];
    final words = src.split(RegExp(r'\s+')).map((w) => w.replaceAll(RegExp(r'[^A-Za-z\-]'), '')).where((w) => w.length >= 5).toList();
    if (words.isEmpty) return null;
    final answer = words.reduce((a, b) => a.length >= b.length ? a : b);
    final distract = <String>[];
    for (final s in usable) {
      for (final w in s.split(RegExp(r'\s+'))) {
        final c = w.replaceAll(RegExp(r'[^A-Za-z\-]'), '');
        if (c.length >= 5 && c != answer && !distract.contains(c)) distract.add(c);
        if (distract.length >= 2) break;
      }
      if (distract.length >= 2) break;
    }
    if (distract.length < 2) return null;
    final options = [answer, ...distract]..shuffle(math.Random(seed * 31 + 7));
    final blanked = src.replaceAll(answer, '________');
    return LessonScene('quick', 'Quick check', 'Quick check! Complete this line from your book. $blanked. Choose the right word.',
        explain: 'Quick check! One word is missing from this line of your book. Choose the right word.',
        source: blanked, options: options, answer: answer, boardTheme: 'white');
  }


  /// One animated diagram per part, chosen from the subject and the
  /// book's own words. Nodes are short phrases taken from the text.
  static LessonScene? diagramFor({
    required String subject,
    required String pageText,
    required List<String> keyPoints,
    required int pageNo,
  }) {
    List<String> shorten(List<String> src, int max) {
      final out = <String>[];
      for (final s in src) {
        final words = s.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
        if (words.isEmpty || words.first.isEmpty) continue;
        var t = words.take(4).join(' ');
        t = t.replaceAll(RegExp(r'[.,;:]+$'), '');
        if (t.length < 3 || t.length > 34) continue;
        if (out.any((x) => x.toLowerCase() == t.toLowerCase())) continue;
        out.add(t);
        if (out.length >= max) break;
      }
      return out;
    }

    final sents = sentences(pageText);
    final years = SubjectEngine.yearsIn(pageText);

    if (subject == 'social' && years.length >= 2) {
      return LessonScene('diagram', 'Timeline diagram',
          'Here is the timeline. Follow it from left to right: ${years.join(', then ')}. Each point marks a change you must remember.',
          boardTheme: 'black', extra: 'timeline', labels: years.take(6).map((y) => '$y').toList());
    }
    if (subject == 'maths') {
      final nums = RegExp(r'\b\d+(?:\.\d+)?\b').allMatches(pageText).map((m) => m.group(0)!).toSet().take(5).toList();
      if (nums.length >= 2) {
        return LessonScene('diagram', 'Number line',
            'Picture these values on a number line: ${nums.join(', ')}. Numbers grow to the right, so you can compare them by position.',
            boardTheme: 'graph', formula: true, extra: 'numberline', labels: nums);
      }
    }
    if (subject == 'science') {
      final nodes = shorten(keyPoints.isEmpty ? sents : keyPoints, 4);
      if (nodes.length >= 3) {
        return LessonScene('diagram', 'Cycle diagram',
            'This cycle links the ideas on page $pageNo: ${nodes.join(', then ')}. Follow the arrows — each stage leads to the next.',
            boardTheme: 'green', extra: 'cycle', labels: nodes);
      }
    }
    if (subject == 'vocational') {
      final steps = shorten(SubjectEngine.stepsFrom(sents, max: 4), 4);
      if (steps.length >= 2) {
        return LessonScene('diagram', 'Process flow',
            'Follow this flow while you work: ${steps.join(', then ')}. Do not skip a step.',
            boardTheme: 'ruled', extra: 'steps', labels: steps);
      }
    }
    final nodes = shorten(keyPoints.isEmpty ? sents : keyPoints, 4);
    if (nodes.length >= 3) {
      return LessonScene('diagram', 'Idea map',
          'Here is how the ideas on page $pageNo connect: ${nodes.join(', then ')}.',
          boardTheme: 'white', extra: 'steps', labels: nodes);
    }
    return null;
  }

  static List<LessonScene> build({
    required DartPdfIndex index,
    required List<int> pages,
    required int partNumber,
    required String title,
    required String subject,
    required List<String> brainPoints,
    required String themeSetting,
  }) {
    final scenes = <LessonScene>[
      LessonScene('title', title,
          'Part $partNumber. Pages ${pages.isEmpty ? '' : '${pages.first} to ${pages.last}'}. Let us learn this part step by step, page by page.',
          explain: 'Welcome to part $partNumber, pages ${pages.isEmpty ? '' : '${pages.first} to ${pages.last}'}. '
              'We will read the book together, look closely at every figure, and connect each idea to daily life. '
              'Main words are kept in English so your notes stay easy to prepare.'),
    ];
    final keyPoints = <String>[...brainPoints];
    for (final pg in pages) {
      for (final s in sentences(index.pageText(pg))) {
        if (s.length > 40 && !s.toLowerCase().contains('click here') && keyPoints.length < 10) keyPoints.add(s);
      }
    }
    var kp = 0;
    var styleIdx = 0;
    final partTexts = pages.map((pg) => index.pageText(pg)).toList();
    final allSents = partTexts.expand(sentences).where((x) => x.length > 25).toList();
    final vocab = subject == 'language' ? SubjectEngine.vocabWords(partTexts) : const [];
    final rules = subject == 'language' ? SubjectEngine.grammarRules(allSents) : const <String>[];
    var vocabIdx = 0, ruleIdx = 0;
    var contentCount = 0;
    var diagramAdded = false;
    for (final pg in pages) {
      final page = index.pages[pg - 1];
      final sents = sentences(index.pageText(pg)).where((s) => s.length > 30).take(2).toList();
      final narration = sents.isEmpty ? 'Read this page carefully and notice the highlighted lines.' : sents.join(' ');
      scenes.add(LessonScene('reading', 'Page $pg', narration.length > 460 ? narration.substring(0, 460) : narration, page: pg));
      contentCount++;
      for (final zone in imageZones(page)) {
        final cap = captionNear(page, zone);
        final labelSpeech = cap.labels.isNotEmpty ? ' The labels here are: ${cap.labels.join(', ')}.' : '';
        final framing = 'Look carefully at this figure on page $pg. Notice every label and part — the explanation is below, '
            'while the textbook caption stays exactly as printed.$labelSpeech';
        scenes.add(LessonScene('zoom', 'Figure • Page $pg', framing,
            explain: framing, source: cap.caption, page: pg, zone: zone, labels: [cap.caption, ...cap.labels]));
        contentCount++;
      }
      String? point;
      if (kp < keyPoints.length) {
        point = keyPoints[kp];
        final st = styleFor(point, styleIdx++, themeSetting);
        scenes.add(LessonScene('board', kp < brainPoints.length ? 'Brain key point' : 'Key point',
            point.length > 320 ? point.substring(0, 320) : point,
            boardTheme: st.theme, formula: st.formula));
        kp++;
        contentCount++;
      }
      switch (subject) {
        case 'maths':
        case 'vocational':
          final steps = SubjectEngine.stepsFrom(sentences(index.pageText(pg)), max: 3);
          if (steps.isNotEmpty) {
            final numbered = [for (var i = 0; i < steps.length; i++) 'Step ${i + 1}. ${steps[i]}'];
            scenes.add(LessonScene('steps', subject == 'maths' ? 'Solve it step by step' : 'Do it step by step',
                'Let us do this step by step. ${numbered.join(' ')}',
                boardText: numbered.join('\n\n'),
                boardTheme: subject == 'maths' ? 'graph' : 'ruled', formula: subject == 'maths'));
            contentCount++;
          }
          if (subject == 'vocational') {
            final safety = sentences(index.pageText(pg))
                .where((x) => RegExp(r'safety|careful|warning|danger|switch off|protect', caseSensitive: false).hasMatch(x))
                .take(2)
                .toList();
            if (safety.isNotEmpty) {
              scenes.add(LessonScene('safety', 'Safety first', 'Safety first. ${safety.join(' ')}', boardTheme: 'black'));
              contentCount++;
            }
          }
        case 'science':
          final pageSents = sentences(index.pageText(pg));
          if (LabEngine2.looksLikeLab(pageSents)) {
            final lab = LabEngine2.parse(pageSents);
            final sub = LabEngine2.subSubjectOf(index.pageText(pg));
            if (lab.aim.isNotEmpty) {
              scenes.add(LessonScene('lab', 'Experiment aim', 'Today\'s experiment. ${lab.aim}', boardTheme: 'green'));
              contentCount++;
            }
            if (lab.materials.isNotEmpty) {
              scenes.add(LessonScene('lab', 'Materials needed', 'Materials needed. ${lab.materials.join(' ')}',
                  boardText: lab.materials.join('\n• '), boardTheme: 'white'));
              contentCount++;
            }
            for (var i = 0; i < lab.procedure.length; i++) {
              scenes.add(LessonScene('lab', 'Step ${i + 1} of ${lab.procedure.length}', 'Step ${i + 1}. ${lab.procedure[i]}',
                  boardTheme: i.isEven ? 'ruled' : 'graph', formula: sub == 'chemistry'));
              contentCount++;
            }
            if (lab.observation.isNotEmpty) {
              scenes.add(LessonScene('lab', 'Observation', 'Observation. ${lab.observation.join(' ')}', boardTheme: 'graph'));
              contentCount++;
            }
            if (lab.result.isNotEmpty) {
              scenes.add(LessonScene('lab', 'Result', 'Result. ${lab.result.join(' ')}', boardTheme: 'green'));
              contentCount++;
            }
            for (final sf in lab.safety) {
              scenes.add(LessonScene('safety', 'Safety first', 'Safety first. $sf', boardTheme: 'black'));
              contentCount++;
            }
          } else if (point != null) {
            final detail = sentences(index.pageText(pg)).where((x) => x.length > 35).take(2).join(' ');
            if (detail.isNotEmpty) {
              scenes.add(LessonScene('board', 'Let us understand', 'Let us understand this properly. $detail',
                  boardTheme: styleFor(detail, styleIdx, themeSetting).theme));
              contentCount++;
            }
            final ex = SubjectEngine.dailyLifeFor('science', point);
            scenes.add(LessonScene('daily', 'Daily-life connect', '$ex From your textbook: $point',
                explain: ex, source: point, boardTheme: 'white'));
            contentCount++;
          }
        case 'social':
          final years = SubjectEngine.yearsIn(index.pageText(pg));
          if (years.isNotEmpty) {
            scenes.add(LessonScene('timeline', 'Timeline', 'Timeline check. The key years on this page are ${years.join(', ')}. Place them in order and remember what changed.',
                boardText: years.join('  →  '), boardTheme: 'black'));
            contentCount++;
          } else if (point != null) {
            final ex = SubjectEngine.dailyLifeFor('social', point);
            scenes.add(LessonScene('daily', 'Daily-life connect', '$ex From your textbook: $point',
                explain: ex, source: point, boardTheme: 'white'));
            contentCount++;
          }
        case 'language':
          if (ruleIdx < rules.length) {
            final r = rules[ruleIdx++];
            scenes.add(LessonScene('board', 'Grammar rule', 'Grammar rule from your book. $r', boardText: r, boardTheme: 'green'));
            contentCount++;
          } else if (vocabIdx < vocab.length) {
            final v = vocab[vocabIdx++];
            final use = v.usage.isNotEmpty ? ' From your book: ${v.usage}' : '';
            scenes.add(LessonScene('vocab', 'New word', 'New word. ${v.word}. It means ${v.meaning}. Say it aloud: ${v.word}.$use',
                boardText: '${v.word}\n= ${v.meaning}${v.usage.isNotEmpty ? '\n\n"${v.usage}"' : ''}', boardTheme: 'white'));
            contentCount++;
            if (v.usage.length > 25) {
              final words = v.usage.split(RegExp(r'\s+')).where((w) => w.replaceAll(RegExp(r'[^A-Za-z]'), '').length >= 5).toList();
              if (words.isNotEmpty) {
                final ans = words.reduce((a, b) => a.length >= b.length ? a : b).replaceAll(RegExp(r'[^A-Za-z\-]'), '');
                if (ans.length >= 4) {
                  scenes.add(LessonScene('practice', 'Your turn',
                      'Your turn. Complete the sentence from your book. ${v.usage.replaceAll(ans, 'dash')}. The answer is $ans.',
                      boardText: v.usage, extra: ans, boardTheme: 'ruled'));
                  contentCount++;
                }
              }
            }
          }
        default:
          if (point != null && subject == 'general') {
            final ex = SubjectEngine.dailyLifeFor('general', point);
            scenes.add(LessonScene('daily', 'Daily-life connect', '$ex From your textbook: $point',
                explain: ex, source: point, boardTheme: 'white'));
            contentCount++;
          }
      }
      // One animated diagram per part (on the second page, or later if needed).
      if (!diagramAdded && (pg == pages.last || pages.indexOf(pg) >= 1)) {
        final d = diagramFor(subject: subject, pageText: index.pageText(pg), keyPoints: keyPoints, pageNo: pg);
        if (d != null) {
          scenes.add(d);
          diagramAdded = true;
          contentCount++;
        }
      }
      // Interactive quick check roughly every 4 content scenes.
      if (contentCount > 0 && contentCount % 4 == 0) {
        final q = _quickCheck(allSents, scenes.length);
        if (q != null) scenes.add(q);
      }
    }
    scenes.add(const LessonScene('end', 'Part complete',
        'You finished this part. Take the test for this part — score forty percent or more to unlock the next part.',
        explain: 'You finished this part. Take the test for this part — score forty percent or more to unlock the next part. '
            'Your mind map, key points and quiz are ready too.'));
    return scenes;
  }
}
