import 'dart:ui' show Rect;

import '../lesson_content.dart';
import 'ai_config.dart';
import 'ai_exception.dart';
import 'ai_service.dart';
import 'ai_prompts.dart';
import 'json_utils.dart';
import 'textbook_extractor.dart';

/// Turns textbook pages into the scene list the on-device player renders.
///
/// The *design* of the video — how many scenes, what the teacher says, which
/// figure to show and where it is on the page — comes from the AI, driven by
/// the editable script prompt. The *video itself* is still produced on the
/// device: Flutter paints the board, the voice comes from the system TTS and
/// the figures are cropped out of the PDF locally.
class ScriptDesigner {
  static const int _maxContentChars = 14000;

  static Future<List<LessonScene>?> design({
    required AiConfig cfg,
    required String title,
    required String subject,
    required String language,
    int? grade,
    required int partNumber,
    required List<int> pages,
    required List<ExtractedPage> indexPages,
    required String teacherNote,
    Future<String?> Function(int page, List<double>? bbox, String where)? crop,
  }) async {
    final wanted = pages.isEmpty
        ? indexPages.take(12).map((p) => p.page).toSet()
        : pages.toSet();

    final buf = StringBuffer();
    final figures = <(int, ExtractedFigure)>[];
    for (final p in indexPages.where((p) => wanted.contains(p.page))) {
      if (buf.length < _maxContentChars) {
        buf.writeln('Page ${p.page}:');
        buf.writeln(p.text.trim().isEmpty ? '(no text)' : p.text.trim());
        buf.writeln();
      }
      for (final f in p.figures) {
        figures.add((p.page, f));
      }
    }
    if (buf.isEmpty) {
      buf.write(indexPages
          .take(12)
          .map((p) => 'Page ${p.page}: ${p.text}')
          .join('\n'));
    }

    final figCatalog = figures.isEmpty
        ? 'No figures were detected on these pages — do not use any figure scene.'
        : figures
            .map((f) =>
                '- page ${f.$1}, caption "${f.$2.caption}", '
                'sits at the ${f.$2.where.isEmpty ? 'middle' : f.$2.where} of the page')
            .join('\n');

    final prompt = AiPrompts.fill(cfg.scriptPrompt, {
      'title': title,
      'subject': subject,
      'language': language,
      'grade': grade == null ? 'not set' : 'class $grade',
      'part': '$partNumber',
      'pages': pages.isEmpty ? 'the first pages' : '${pages.first}–${pages.last}',
      'teacher_note': teacherNote.trim().isEmpty
          ? 'Teach this part clearly, in the simplest words, with daily-life examples.'
          : teacherNote.trim(),
      'content': buf.toString().trim(),
      'figures': figCatalog,
    });

    final String raw;
    try {
      raw = await AiService.generate(prompt: prompt);
    } on AiException catch (e) {
      throw AiException('Designing the lesson failed: ${e.message}');
    }
    final obj = JsonUtils.object(raw);
    if (obj == null) return null;
    final list = obj['scenes'];
    if (list is! List) return null;

    final scenes = <LessonScene>[];
    for (final item in list) {
      if (item is! Map) continue;
      final scene = await _scene(item, crop);
      if (scene != null) scenes.add(scene);
    }
    if (scenes.length < 4) return null;

    if (scenes.first.kind != 'title') {
      scenes.insert(
        0,
        LessonScene('title', title,
            'Part $partNumber. Let us learn this part step by step.'),
      );
    }
    if (scenes.last.kind != 'summary') {
      scenes.add(LessonScene('summary', 'What we learnt',
          'We finished this part. Revise the board once before the quick test.',
          boardText: scenes
              .map((s) => s.heading)
              .where((h) => h.trim().isNotEmpty)
              .take(4)
              .join('\n')));
    }
    return scenes;
  }

  /// Quick-check options come back in several shapes from real models:
  /// plain `["Sunlight", …]` with `answer: "Sunlight"`, or lettered
  /// `["a) Sunlight", "b) Moonlight"]` with `answer: "a"`. Neither should
  /// show the letter twice or mark the wrong chip right.
  static ({List<String> options, String answer}) _answerFor(
      String answer, List<String> options) {
    final prefix = RegExp(r'^\(?([a-dA-D1-4])\s*[.):\-]\s+');
    var opts = options;
    var key = answer.trim();

    if (opts.every((o) => prefix.hasMatch(o))) {
      final keys = opts
          .map((o) => prefix.firstMatch(o)!.group(1)!.toLowerCase())
          .toList();
      final wanted = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final at = keys.indexOf(wanted);
      opts = opts.map((o) => o.replaceFirst(prefix, '').trim()).toList();
      if (at >= 0) return (options: opts, answer: opts[at]);
    }

    if (opts.contains(key)) return (options: opts, answer: key);

    final lower = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (lower.isNotEmpty) {
      for (final o in opts) {
        final ol = o.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (ol == lower || ol.contains(lower)) {
          return (options: opts, answer: o);
        }
      }
    }
    return (options: opts, answer: opts.first);
  }

  static Future<LessonScene?> _scene(
    Map raw,
    Future<String?> Function(int page, List<double>? bbox, String where)? crop,
  ) async {
    var kind = JsonUtils.str(raw['kind']).toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (kind.isEmpty) {
      // Some models mangle the key; infer the type from what came back.
      if (JsonUtils.str(raw['caption']).isNotEmpty &&
          (raw['page'] != null || raw['bbox'] != null)) {
        kind = 'figure';
      } else if ((raw['options'] as List?)?.isNotEmpty == true) {
        kind = 'quick';
      } else if (JsonUtils.str(raw['boardText']).isNotEmpty) {
        kind = 'board';
      } else {
        kind = 'board';
      }
    }
    if (kind == 'figure' || kind == 'fig') {
      kind = 'figure';
    }
    final heading = JsonUtils.str(raw['heading']);
    final narration = JsonUtils.speech(JsonUtils.str(raw['narration']));
    if (narration.length < 20 || narration.length > 1200) return null;
    // Optional VISTA hint ("T23"). Unknown or absent ids stay empty.
    final tpl = SceneTemplate.clean(JsonUtils.str(raw['template']));

    switch (kind) {
      case 'title':
        return LessonScene('title', heading.isEmpty ? 'Lesson' : heading,
            narration,
            boardText: JsonUtils.str(raw['boardText']),
            explain: narration,
            template: tpl);

      case 'quick':
        var options = ((raw['options'] as List?) ?? const [])
            .map((o) => JsonUtils.str(o))
            .where((o) => o.isNotEmpty)
            .take(4)
            .toList();
        if (options.length < 2) return null;
        var answer = JsonUtils.str(raw['answer']);
        final fixed = _answerFor(answer, options);
        options = fixed.options;
        answer = fixed.answer;
        return LessonScene('quick', heading.isEmpty ? 'Quick check' : heading,
            narration,
            boardText: JsonUtils.str(raw['boardText']),
            options: options,
            answer: answer,
            explain: narration,
            template: tpl);

      case 'figure':
        final page = JsonUtils.integer(raw['page']);
        if (page <= 0) return null;
        final box = JsonUtils.bbox(raw['bbox']);
        final where = JsonUtils.str(raw['where']).toLowerCase();
        String? imagePath;
        if (crop != null) {
          imagePath = await crop(page, box, where);
        }
        if (imagePath == null) return null; // no picture → the board teaches it
        return LessonScene(
            'figure', heading.isEmpty ? 'Look at this figure' : heading, narration,
            labels: [
              JsonUtils.str(raw['caption']),
              if (where.isNotEmpty) 'from the ${where} of the page',
            ].where((s) => s.isNotEmpty).toList(),
            page: page,
            zone: box == null
                ? null
                : Rect.fromLTRB(box[0], box[1], box[2], box[3]),
            imagePath: imagePath,
            explain: narration,
            template: tpl);

      case 'daily':
        return LessonScene('daily', heading.isEmpty ? 'In daily life' : heading,
            narration,
            boardText: JsonUtils.str(raw['boardText']),
            explain: narration,
            template: tpl);

      case 'summary':
        final board = JsonUtils.str(raw['boardText']);
        return LessonScene('summary', heading.isEmpty ? 'What we learnt' : heading,
            narration,
            boardText: board.isEmpty ? null : board,
            explain: narration,
            template: tpl);

      // ---- VISTA-style kinds the player already knows how to paint ----
      case 'steps':
      case 'timeline':
      case 'compare':
      case 'vocab':
      case 'quote':
      case 'formula':
      case 'practice':
        final board = JsonUtils.str(raw['boardText']);
        if (board.trim().isEmpty && kind != 'practice') return null;
        return LessonScene(kind, heading.isEmpty ? kind : heading, narration,
            boardText: board.trim().isEmpty ? null : board,
            boardTheme: 'green',
            formula: kind == 'formula',
            extra: JsonUtils.str(raw['extra']),
            explain: narration,
            template: tpl);

      case 'board':
      default:
        final board = JsonUtils.str(raw['boardText']);
        return LessonScene('board', heading.isEmpty ? 'Lesson' : heading, narration,
            boardText: board.isEmpty ? null : board,
            boardTheme: 'green',
            explain: narration,
            template: tpl);
    }
  }
}
