import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'ai/ai_client.dart';
import 'ai/ai_config.dart';
import 'ai/script_designer.dart';
import 'ai/textbook_extractor.dart';
import 'lesson_content.dart';
import 'pdf/pdf_raster.dart';
import 'subject_engine.dart';

/// The whole classroom engine, in Dart — no Python anywhere in the app.
///
/// Since v0.24.0 the textbook is read by the teacher's own AI: the PDF is
/// uploaded with a custom prompt and the model returns the page text plus
/// the bounding box of every figure. Nothing parses the PDF on the device
/// any more. Page pictures and figure crops are rendered locally with
/// PDFium (`pdfx`), which works on Android and Windows alike, and the
/// lesson video is still painted, spoken and animated entirely on-device.
class DartBlock {
  final String text;
  final List<double> bbox; // normalised [x0, y0, x1, y1]
  const DartBlock(this.text, this.bbox);
  Map<String, dynamic> toJson() => {'text': text, 'bbox': bbox};
  factory DartBlock.fromJson(Map<String, dynamic> j) => DartBlock(
        (j['text'] ?? '').toString(),
        ((j['bbox'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class DartFigure {
  final String caption;
  final List<double> bbox; // normalised [x0, y0, x1, y1], top-left origin
  const DartFigure(this.caption, this.bbox);
  Map<String, dynamic> toJson() => {'caption': caption, 'bbox': bbox};
  factory DartFigure.fromJson(Map<String, dynamic> j) => DartFigure(
        (j['caption'] ?? '').toString(),
        ((j['bbox'] as List?) ?? const [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class DartPage {
  final int page;
  final String text;
  final List<DartBlock> blocks;

  /// Figures the AI found on this page, with the box to crop them out.
  final List<DartFigure> figures;
  const DartPage(this.page, this.text, this.blocks, {this.figures = const []});
  Map<String, dynamic> toJson() => {
        'page': page,
        'text': text,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'figures': figures.map((f) => f.toJson()).toList(),
      };
  factory DartPage.fromJson(Map<String, dynamic> j) => DartPage(
        (j['page'] as num?)?.toInt() ?? 0,
        (j['text'] ?? '').toString(),
        ((j['blocks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) =>
                DartBlock.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
            .toList(),
        figures: ((j['figures'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) =>
                DartFigure.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
            .toList(),
      );
}

class DartPdfIndex {
  final String title;
  final int pageCount;
  final List<DartPage> pages;
  const DartPdfIndex(this.title, this.pageCount, this.pages);

  /// The AI may skip pages that carry no text at all, so look the page up by
  /// its real number instead of trusting the list index.
  DartPage? pageOf(int page) {
    for (final p in pages) {
      if (p.page == page) return p;
    }
    return null;
  }

  String pageText(int page) => pageOf(page)?.text ?? '';

  static const _stop = {
    'the',
    'and',
    'what',
    'explain',
    'with',
    'this',
    'that',
    'from',
    'give',
    'does',
    'how',
    'why',
    'please',
    'video',
    'examples',
    'example',
    'topic',
    'concept',
    'student',
    'question',
  };

  /// Deterministic keyword search — real pages only, exactly like the
  /// engine spec demands.
  List<int> findRelevantPages(String query, {int top = 2}) {
    final terms = RegExp(r'[a-zA-Z]{3,}')
        .allMatches(query.toLowerCase())
        .map((m) => m.group(0)!)
        .where((t) => !_stop.contains(t))
        .toList();
    if (terms.isEmpty) return pageCount == 0 ? [] : [1];
    final scored = <(double, int)>[];
    for (final p in pages) {
      final text = p.text.toLowerCase();
      var score = 0.0;
      for (final t in terms) {
        score += t.allMatches(text).length * (1 + t.length / 12.0);
      }
      scored.add((score, p.page));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    final out =
        scored.where((s) => s.$1 > 0).take(top).map((s) => s.$2).toList();
    return out.isEmpty ? [1] : out;
  }
}

class DartEngine {
  static const _ch = MethodChannel('com.mdk.textbook_video/engine');

  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/classroom');
    await root.create(recursive: true);
    return root;
  }

  static Future<File> _indexFile() async =>
      File('${(await _root()).path}/sessions.json');

  static Future<List<Map<String, dynamic>>> _metas() async {
    final f = await _indexFile();
    if (!await f.exists()) return [];
    try {
      return ((jsonDecode(await f.readAsString()) as List)
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveMetas(List<Map<String, dynamic>> metas) async {
    final f = await _indexFile();
    await f.writeAsString(jsonEncode(metas));
  }

  static Future<Map<String, dynamic>?> _meta(String sessionId) async {
    for (final m in await _metas()) {
      if (m['session_id'] == sessionId) return m;
    }
    return null;
  }

  static Future<void> _putMeta(Map<String, dynamic> meta) async {
    final metas = await _metas();
    final i = metas.indexWhere((m) => m['session_id'] == meta['session_id']);
    if (i >= 0) {
      metas[i] = meta;
    } else {
      metas.add(meta);
    }
    await _saveMetas(metas);
  }

  static Future<Directory> _sessionDir(String sessionId) async {
    final dir = Directory('${(await _root()).path}/$sessionId');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<String> sessionPdfPath(String sessionId) async =>
      '${(await _sessionDir(sessionId)).path}/book.pdf';

  static Future<String> subjectOf(String sessionId) async {
    final meta = await _meta(sessionId);
    return (meta?['subject'] ?? 'general').toString();
  }

  // ---------- website-brain results (kept 100% on this device) ----------
  // The in-app WebView automation (brain_webview_screen) talks to the
  // PDF-teacher website, but everything it produces — summary, Q&A — is
  // stored here, per session, per student. Nothing is shared or synced.

  static Future<File> _brainFile(String sessionId) async =>
      File('${(await _sessionDir(sessionId)).path}/brain.json');

  static Future<Map<String, dynamic>> loadBrainData(String sessionId) async {
    try {
      final f = await _brainFile(sessionId);
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return {'summary': '', 'level': 1, 'qa': <dynamic>[]};
  }

  static Future<void> _saveBrainData(
      String sessionId, Map<String, dynamic> data) async {
    final f = await _brainFile(sessionId);
    await f.writeAsString(jsonEncode(data));
    final meta = await _meta(sessionId);
    if (meta != null) {
      meta['brain_summary'] = (data['summary'] ?? '').toString();
      await _putMeta(meta);
    }
  }

  static Future<void> saveBrainSummary(
      String sessionId, String summary, int level) async {
    final data = await loadBrainData(sessionId);
    data['summary'] = summary;
    data['level'] = level;
    await _saveBrainData(sessionId, data);
  }

  static Future<void> addBrainQa(
      String sessionId, String question, String answer) async {
    final data = await loadBrainData(sessionId);
    final qa = ((data['qa'] as List?) ?? const []).toList();
    qa.add({
      'q': question,
      'a': answer,
      'ts': DateTime.now().millisecondsSinceEpoch
    });
    data['qa'] = qa;
    await _saveBrainData(sessionId, data);
  }

  static Future<void> clearBrainData(String sessionId) async {
    final f = await _brainFile(sessionId);
    if (await f.exists()) await f.delete();
    final meta = await _meta(sessionId);
    if (meta != null) {
      meta.remove('brain_summary');
      await _putMeta(meta);
    }
  }

  /// Brain summary sentences (if the student ran the website brain) —
  /// lesson scenes prefer these individualized key points, then fall
  /// back to raw textbook sentences.
  static Future<List<String>> brainKeyPoints(String sessionId) async {
    final meta = await _meta(sessionId);
    final summary = (meta?['brain_summary'] ?? '').toString();
    if (summary.isEmpty) return const [];
    return summary
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.length > 30)
        .take(8)
        .toList();
  }

  static Future<DartPdfIndex?> loadIndex(String sessionId) async {
    final dir = await _sessionDir(sessionId);
    final f = File('${dir.path}/index.json');
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    return DartPdfIndex(
      (j['title'] ?? 'Textbook').toString(),
      (j['page_count'] as num?)?.toInt() ?? 0,
      ((j['pages'] as List?) ?? const []).whereType<Map>().map((e) {
        final m = e.map((k, v) => MapEntry(k.toString(), v));
        return DartPage.fromJson(m);
      }).toList(),
    );
  }

  /// Creates a session by **uploading the PDF to the teacher's own AI**.
  ///
  /// The model returns the page text and every figure box (see
  /// [TextbookExtractor]); pages are then rendered locally with PDFium so
  /// the reader and the figure zooms have pictures on Android and Windows.
  static Future<Map<String, dynamic>> createSession({
    required String pdfPath,
    required String language,
    int? grade,
    String brain = 'offline',
    String brainServerUrl = '',
    void Function(int done, int total, String stage)? onProgress,
  }) async {
    final src = File(pdfPath);
    if (!await src.exists()) {
      throw StateError('PDF file not found. Please pick it again.');
    }
    final bytes = await src.readAsBytes();
    final fileName = src.uri.pathSegments.last;

    final cfg = AiConfig.current.ready ? AiConfig.current : await AiConfig.load();
    if (!cfg.ready) {
      throw StateError(
          'Add your AI key first — Settings → AI & Prompts. This app reads the PDF with your AI now, not on the device.');
    }

    final devicePageCount = await PdfRaster.pageCount(src.path);

    onProgress?.call(0, 1, 'Uploading the PDF to ${cfg.provider.label}');
    final ExtractionResult extraction;
    try {
      extraction = await TextbookExtractor.extract(
        pdfBytes: bytes,
        filename: fileName,
        pageCount: devicePageCount,
        cfg: cfg,
        onProgress: onProgress,
      );
    } on AiException catch (e) {
      throw StateError(e.message);
    }

    final id =
        'session_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final dir = await _sessionDir(id);
    final bookFile = File('${dir.path}/book.pdf');
    await bookFile.writeAsBytes(bytes);

    final pages = extraction.pages
        .map((p) => DartPage(
              p.page,
              p.text,
              const [],
              figures: p.figures
                  .map((f) => DartFigure(f.caption, f.bbox))
                  .toList(),
            ))
        .toList();
    final pageCount = pages.isEmpty ? 0 : pages.last.page;

    await File('${dir.path}/index.json').writeAsString(jsonEncode({
      'title': extraction.title,
      'page_count': pageCount,
      'source': 'ai',
      'provider': extraction.provider,
      'model': extraction.model,
      'pages': pages.map((p) => p.toJson()).toList(),
    }));

    final subj = SubjectEngine.detect(
        extraction.title, pages.map((p) => p.text).toList());

    final pagesDir = Directory('${dir.path}/pages');
    await pagesDir.create(recursive: true);

    final meta = <String, dynamic>{
      'session_id': id,
      'title': extraction.title,
      'page_count': pageCount,
      'subject': subj.id,
      'subject_label': subj.label,
      'brain': brain,
      'language': language,
      'grade': grade,
      'state': 'active',
      'page_dir': pagesDir.path,
      'ai_provider': extraction.provider,
      'ai_model': extraction.model,
      'figures': extraction.allFigures.length,
      'lessons': <dynamic>[],
      'completed_parts': <dynamic>[],
    };
    await _putMeta(meta);

    // Page pictures are only needed when the reader opens: do it quietly.
    unawaited(_renderAllPages(id, bookFile.path, pageCount));

    return {
      'session_id': id,
      'title': extraction.title,
      'page_count': pageCount,
      'brain': brain,
      'state': 'active',
      'ai': extraction.provider,
      'ai_model': extraction.model,
      'figures': extraction.allFigures.length,
    };
  }

  /// Renders every page once, in the background, so the reader is instant
  /// afterwards. Safe to call twice; already-rendered pages are skipped.
  static Future<void> _renderAllPages(
      String sessionId, String pdfPath, int pageCount) async {
    if (PdfRaster.unavailable || pageCount <= 0) return;
    final dir = await _sessionDir(sessionId);
    for (var p = 1; p <= pageCount; p++) {
      final out = File('${dir.path}/pages/page_$p.png');
      if (await out.exists()) continue;
      final ok = await PdfRaster.renderPage(
          pdfPath: pdfPath, page: p, outPath: out.path, targetWidth: 1240);
      if (ok == null) return; // rendering not available here; stop quietly
    }
  }

  /// Render one page on demand (reader, zoom scenes).
  static Future<String?> ensurePageImage(String sessionId, int page) async {
    final dir = await _sessionDir(sessionId);
    final out = File('${dir.path}/pages/page_$page.png');
    if (await out.exists()) return out.path;
    final pdf = File('${dir.path}/book.pdf');
    if (!await pdf.exists()) return null;
    final ok = await PdfRaster.renderPage(
        pdfPath: pdf.path, page: page, outPath: out.path, targetWidth: 1240);
    return ok;
  }

  /// Cut one figure out of the PDF using the AI's coordinates.
  ///
  /// The same page+box always maps to the same file, so a script can be
  /// replayed without ever touching the PDF again.
  static Future<String?> figurePath(
      String sessionId, int page, List<double> bbox) async {
    if (bbox.length != 4) return null;
    final dir = await _sessionDir(sessionId);
    final key = [page, ...bbox.map((n) => (n * 1000).round())].join('_');
    final out = File('${dir.path}/figures/f_$key.png');
    if (await out.exists()) return out.path;
    final pdf = File('${dir.path}/book.pdf');
    if (!await pdf.exists()) return null;
    return PdfRaster.cropFigure(
        pdfPath: pdf.path, page: page, bbox: bbox, outPath: out.path);
  }

  /// The AI-designed script for one part, if one was generated.
  static Future<List<LessonScene>> loadScenes(
      String sessionId, int part) async {
    final meta = await _meta(sessionId);
    final all = meta?['scenes'];
    if (all is! Map) return const [];
    final list = all['$part'];
    if (list is! List) return const [];
    final out = <LessonScene>[];
    for (final item in list) {
      if (item is Map) {
        final s = LessonScene.fromJson(item.map((k, v) => MapEntry(k.toString(), v)));
        if (s != null) out.add(s);
      }
    }
    return out;
  }

  static Future<void> saveScenes(
      String sessionId, int part, List<LessonScene>? scenes) async {
    final meta = await _meta(sessionId);
    if (meta == null) return;
    final all = <String, dynamic>{};
    final current = meta['scenes'];
    if (current is Map) {
      current.forEach((k, v) => all['$k'] = v);
    }
    if (scenes == null) {
      all.remove('$part');
    } else {
      all['$part'] = scenes.map((s) => s.toJson()).toList();
    }
    meta['scenes'] = all;
    await _putMeta(meta);
  }

  static List<String> _keyPointsFor(DartPdfIndex index, List<int> range) {
    final key = <String>[];
    for (final pg in range) {
      final joined =
          (index.pageText(pg)).replaceAll(RegExp(r'\s+'), ' ').trim();
      final sents = joined
          .split(RegExp(r'(?<=[.!?])\s+'))
          .map((s) => s.trim())
          .where(
              (s) => s.length > 40 && !s.toLowerCase().contains('click here'))
          .take(2);
      key.addAll(sents);
    }
    return key
        .map((s) => s.length > 220 ? s.substring(0, 220) : s)
        .take(6)
        .toList();
  }

  static Future<Map<String, dynamic>> chapterSeries(String sessionId,
      {int pagesPerPart = 6}) async {
    final meta = await _meta(sessionId);
    final index = await loadIndex(sessionId);
    if (meta == null || index == null) return {'parts': []};
    final done = ((meta['completed_parts'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toSet();
    final parts = <Map<String, dynamic>>[];
    var start = 1;
    while (start <= index.pageCount) {
      final end = math.min(index.pageCount, start + pagesPerPart - 1);
      final range = [for (var p = start; p <= end; p++) p];
      final partNo = parts.length + 1;
      parts.add({
        'part': partNo,
        'pages': range,
        'key_points': _keyPointsFor(index, range),
        'unlocked': partNo == 1 || done.contains(partNo - 1),
        'completed': done.contains(partNo),
      });
      start += pagesPerPart;
    }
    return {
      'session_id': sessionId,
      'total_pages': index.pageCount,
      'parts': parts
    };
  }

  static Future<Map<String, dynamic>> completePart(
      String sessionId, int part) async {
    final meta = await _meta(sessionId);
    if (meta != null) {
      final done = ((meta['completed_parts'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toSet()
        ..add(part);
      meta['completed_parts'] = done.toList()..sort();
      await _putMeta(meta);
    }
    return chapterSeries(sessionId);
  }

  /// Extractive doubt clearing: finds the real pages for the question and
  /// answers with the textbook's own sentences (quoted, page-referenced).
  static Future<Map<String, dynamic>> askChat(
      String sessionId, String question) async {
    final index = await loadIndex(sessionId);
    if (index == null) throw StateError('Textbook session not found.');
    final pages = index.findRelevantPages(question, top: 2);
    final lines = <String>[];
    for (final pg in pages) {
      final sents = index
          .pageText(pg)
          .replaceAll(RegExp(r'\s+'), ' ')
          .split(RegExp(r'(?<=[.!?])\s+'))
          .map((s) => s.trim())
          .where((s) => s.length > 40)
          .take(3);
      for (final s in sents) {
        lines.add('• (Page $pg) $s');
      }
    }
    final answer = lines.isEmpty
        ? 'I could not find that in this textbook yet. Try asking with the exact words used in the chapter.'
        : 'From your textbook:\n${lines.join('\n')}';
    return {'answer': answer, 'chat': <dynamic>[]};
  }

  static Future<Map<String, dynamic>> generateLesson({
    required String sessionId,
    required String question,
    required List<int>? pageRange,
    required String partLabel,
    String language = 'en',
    int? grade,
  }) async {
    final meta = await _meta(sessionId);
    if (meta == null) throw StateError('Textbook session not found.');
    final index = await loadIndex(sessionId);
    final partNo =
        int.tryParse(RegExp(r'Part\s+(\d+)').firstMatch(partLabel)?.group(1) ?? '') ??
            0;
    final pages = pageRange ??
        (index == null
            ? const <int>[]
            : [for (var p = 1; p <= math.min(12, index.pageCount); p++) p]);

    // Ask the AI to design the lesson script (scenes, narration, figures).
    List<LessonScene>? scenes;
    if (index != null) {
      final cfg =
          AiConfig.current.ready ? AiConfig.current : await AiConfig.load();
      if (cfg.ready) {
        try {
          scenes = await ScriptDesigner.design(
            cfg: cfg,
            title: (meta['title'] ?? 'Textbook').toString(),
            subject: (meta['subject'] ?? 'general').toString(),
            language: language,
            grade: grade ?? (meta['grade'] as num?)?.toInt(),
            partNumber: partNo,
            pages: pages,
            indexPages: index.pages
                .map((p) => ExtractedPage(
                      p.page,
                      p.text,
                      p.figures
                          .map((f) => ExtractedFigure(p.page, f.caption, f.bbox))
                          .toList(),
                    ))
                .toList(),
            teacherNote: question,
            crop: (page, bbox) => figurePath(sessionId, page, bbox),
          );
        } catch (_) {
          scenes = null; // offline / quota → the on-device builder takes over
        }
      }
    }
    await saveScenes(sessionId, partNo, scenes);

    final url = 'lesson://$sessionId/$partNo';
    final lessons = ((meta['lessons'] as List?) ?? const []).toList();
    lessons.removeWhere((l) => l is Map && l['output'] == url);
    lessons.add({
      'video_id': 'lesson_${partNo}_${DateTime.now().millisecondsSinceEpoch}',
      'question': question,
      'status': 'ready',
      'file': null,
      'output': url,
      'pages': pages,
      'script': scenes == null ? 'on-device' : 'ai',
      'scenes': scenes?.length ?? 0,
    });
    meta['lessons'] = lessons;
    await _putMeta(meta);
    return {
      'output': url,
      'file': null,
      'captions': null,
      'script': scenes == null ? 'on-device' : 'ai',
    };
  }

  static Future<List<dynamic>> sessionLessons(String sessionId) async {
    final meta = await _meta(sessionId);
    return ((meta?['lessons'] as List?) ?? const []).toList();
  }

  static Future<List<dynamic>> listSessions() async {
    final metas = await _metas();
    return metas
        .where((m) => m['state'] == 'active')
        .map((m) => {
              'session_id': m['session_id'],
              'title': m['title'],
              'page_count': m['page_count'],
              'brain': m['brain'],
              'state': m['state'],
            })
        .toList();
  }

  static Future<Map<String, dynamic>> disconnect(String sessionId) async {
    final meta = await _meta(sessionId);
    if (meta != null) {
      meta['state'] = 'closed';
      await _putMeta(meta);
    }
    return {'cleanup': 'done'};
  }

  static Future<String> pageDirOf(String sessionId) async {
    final meta = await _meta(sessionId);
    return (meta?['page_dir'] ?? '').toString();
  }

  static Future<Map<String, dynamic>> checkTts(String language) async {
    try {
      final r = await _ch
          .invokeMapMethod<String, dynamic>('checkTts', {'language': language});
      return r ??
          {'available': false, 'reason': 'no response from Android TTS'};
    } catch (e) {
      return {'available': false, 'reason': '$e'};
    }
  }
}
