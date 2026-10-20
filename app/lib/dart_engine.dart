import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'subject_engine.dart';

/// The whole classroom engine, in Dart — no Python anywhere in the app.
///
/// PDF text/structure comes from Syncfusion's Dart PDF parser, page
/// pictures from Android PdfRenderer (one tiny platform method), page
/// numbers are found by searching the extracted text (never invented),
/// and lessons are played by the interactive Flutter lesson player.
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

class DartPage {
  final int page;
  final String text;
  final List<DartBlock> blocks;
  const DartPage(this.page, this.text, this.blocks);
  Map<String, dynamic> toJson() => {
        'page': page,
        'text': text,
        'blocks': blocks.map((b) => b.toJson()).toList()
      };
  factory DartPage.fromJson(Map<String, dynamic> j) => DartPage(
        (j['page'] as num?)?.toInt() ?? 0,
        (j['text'] ?? '').toString(),
        ((j['blocks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) =>
                DartBlock.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
            .toList(),
      );
}

class DartPdfIndex {
  final String title;
  final int pageCount;
  final List<DartPage> pages;
  const DartPdfIndex(this.title, this.pageCount, this.pages);

  String pageText(int page) =>
      (page >= 1 && page <= pageCount) ? pages[page - 1].text : '';

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
  static bool _syncfusionReady = false;

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

  /// Creates a session: copies the PDF into the app, extracts its text
  /// with the Dart parser and asks Android to render page pictures.
  static Future<Map<String, dynamic>> createSession({
    required String pdfPath,
    required String language,
    int? grade,
    String brain = 'offline',
    String brainServerUrl = '',
  }) async {
    final src = File(pdfPath);
    if (!await src.exists()) {
      throw StateError('PDF file not found. Please pick it again.');
    }
    final bytes = await src.readAsBytes();
    DartPdfIndex index;
    try {
      index = _extract(bytes, src.uri.pathSegments.last);
    } catch (e) {
      throw StateError('Could not read this PDF: $e');
    }
    if (index.pageCount == 0) {
      throw StateError('This PDF has no readable pages.');
    }
    final id =
        'session_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final dir = await _sessionDir(id);
    final bookFile = File('${dir.path}/book.pdf');
    await bookFile.writeAsBytes(bytes);
    await File('${dir.path}/index.json').writeAsString(jsonEncode({
      'title': index.title,
      'page_count': index.pageCount,
      'pages': index.pages.map((p) => p.toJson()).toList(),
    }));

    String pageDir = '';
    try {
      pageDir = await _ch.invokeMethod<String>(
              'renderPages', {'pdfPath': bookFile.path}) ??
          '';
    } catch (_) {
      pageDir = ''; // lesson player shows text scenes if pictures are missing
    }

    final subj = SubjectEngine.detect(
        index.title, index.pages.map((p) => p.text).toList());
    final meta = <String, dynamic>{
      'session_id': id,
      'title': index.title,
      'page_count': index.pageCount,
      'subject': subj.id,
      'subject_label': subj.label,
      'brain': brain,
      'language': language,
      'grade': grade,
      'state': 'active',
      'page_dir': pageDir,
      'lessons': <dynamic>[],
      'completed_parts': <dynamic>[],
    };
    await _putMeta(meta);
    return {
      'session_id': id,
      'title': index.title,
      'page_count': index.pageCount,
      'brain': brain,
      'state': 'active'
    };
  }

  static DartPdfIndex _extract(List<int> bytes, String fileName) {
    if (!_syncfusionReady) {
      _syncfusionReady = true;
    }
    final doc = PdfDocument(inputBytes: bytes);
    try {
      if (doc.pages.count == 0) return const DartPdfIndex('', 0, []);
      final extractor = PdfTextExtractor(doc);
      final title = (doc.documentInformation.title ?? '').trim().isNotEmpty
          ? doc.documentInformation.title.trim()
          : fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final pages = <DartPage>[];
      for (var i = 0; i < doc.pages.count; i++) {
        final pageSize = doc.pages[i].size;
        final text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        final blocks = <DartBlock>[];
        try {
          for (final line in extractor.extractTextLines(
              startPageIndex: i, endPageIndex: i)) {
            final t = line.text.trim();
            if (t.length < 2) continue;
            final b = line.bounds;
            blocks.add(DartBlock(t, [
              (b.left / pageSize.width).clamp(0.0, 1.0).toDouble(),
              (b.top / pageSize.height).clamp(0.0, 1.0).toDouble(),
              (b.right / pageSize.width).clamp(0.0, 1.0).toDouble(),
              (b.bottom / pageSize.height).clamp(0.0, 1.0).toDouble(),
            ]));
          }
        } catch (_) {
          // text-only page: blocks fall back to paragraph bands below
        }
        if (blocks.isEmpty && text.trim().isNotEmpty) {
          final paras = text
              .split(RegExp(r'\n\s*\n|\n'))
              .map((s) => s.trim())
              .where((s) => s.length >= 2)
              .toList();
          final total = paras.fold<int>(0, (a, p) => a + p.length);
          var y = 0.04;
          for (final p in paras) {
            final frac =
                total == 0 ? 0.05 : math.max(0.03, p.length / total * 0.9);
            final y2 = math.min(0.96, y + frac);
            blocks.add(DartBlock(p, [
              0.05,
              double.parse(y.toStringAsFixed(3)),
              0.95,
              double.parse(y2.toStringAsFixed(3))
            ]));
            y = y2 + 0.012;
          }
        }
        pages.add(DartPage(i + 1, text, blocks));
      }
      return DartPdfIndex(title, doc.pages.count, pages);
    } finally {
      doc.dispose();
    }
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
  }) async {
    final meta = await _meta(sessionId);
    if (meta == null) throw StateError('Textbook session not found.');
    final partNo =
        RegExp(r'Part\s+(\d+)').firstMatch(partLabel)?.group(1) ?? '0';
    final url = 'lesson://$sessionId/$partNo';
    final lessons = ((meta['lessons'] as List?) ?? const []).toList();
    lessons.removeWhere((l) => l is Map && l['output'] == url);
    lessons.add({
      'video_id': 'lesson_${partNo}_${DateTime.now().millisecondsSinceEpoch}',
      'question': question,
      'status': 'ready',
      'file': null,
      'output': url,
      'pages': pageRange ?? const [],
    });
    meta['lessons'] = lessons;
    await _putMeta(meta);
    return {'output': url, 'file': null, 'captions': null};
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
