import 'dart:typed_data';

import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_service.dart';
import 'ai_prompts.dart';
import 'json_utils.dart';

class ExtractedFigure {
  final int page;
  final String caption;

  /// Where on the page the figure sits: top / middle / bottom. The free
  /// website mode can only give this; the exact box is found locally.
  final String where;

  /// Only present when the model could actually see the page layout.
  final List<double>? bbox;

  const ExtractedFigure(this.page, this.caption,
      {this.where = '', this.bbox});

  Map<String, dynamic> toJson() => {
        'page': page,
        'caption': caption,
        if (where.isNotEmpty) 'where': where,
        if (bbox != null) 'bbox': bbox,
      };
}

class ExtractedPage {
  final int page;
  final String text;
  final List<ExtractedFigure> figures;
  const ExtractedPage(this.page, this.text, this.figures);
}

class ExtractionResult {
  final String title;
  final String subject;
  final List<ExtractedPage> pages;
  final String provider;
  final String model;
  const ExtractionResult({
    required this.title,
    required this.subject,
    required this.pages,
    required this.provider,
    required this.model,
  });

  List<ExtractedFigure> get allFigures =>
      pages.expand((p) => p.figures).toList();
}

/// Reads a textbook by **uploading the PDF to the teacher's own AI** and
/// asking the questions in [AiConfig.extractPrompt] — there is no PDF text
/// parser on the device any more.
///
/// Big books are read in page batches, because one answer can only hold so
/// much text; each batch is merged into a single index that is cached in the
/// session folder.
class TextbookExtractor {
  static const int batchSize = 12;
  static const int bigBookSize = 40;

  static List<List<int>> batchesFor(int pageCount) {
    if (pageCount <= 0) return const [];
    final size = pageCount > 90 ? bigBookSize : batchSize;
    final out = <List<int>>[];
    for (var start = 1; start <= pageCount; start += size) {
      final end = (start + size - 1).clamp(1, pageCount);
      out.add([start, end]);
    }
    return out;
  }

  static Future<ExtractionResult> extract({
    required Uint8List pdfBytes,
    required String filename,
    required int pageCount,
    required AiConfig cfg,
    AiClient? client,
    void Function(int done, int total, String stage)? onProgress,
  }) async {
    if (!cfg.ready) {
      throw AiException(
          'Add your AI key first (Settings → AI & Prompts). The PDF is read by the AI, so the key is required.');
    }
    final ai = client ?? AiClient();
    final batches = batchesFor(pageCount);
    final effective = batches.isEmpty
        ? [
            [1, 0]
          ] // unknown page count: ask for the whole file
        : batches;

    final pages = <int, ExtractedPage>{};
    String title = '';
    String subject = 'general';

    for (var i = 0; i < effective.length; i++) {
      final start = effective[i][0];
      final end = effective[i][1];
      final label = end == 0 ? 'the whole book' : 'pages $start–$end';
      onProgress?.call(i, effective.length, 'AI is reading $label');
      final prompt = AiPrompts.fill(cfg.extractPrompt, {
        'start': '$start',
        'end': end == 0 ? 'the last page' : '$end',
        'total': pageCount > 0 ? '$pageCount' : 'unknown',
      });
      String raw;
      try {
        raw = await AiService.generate(
          cfg,
          prompt: prompt,
          pdf: pdfBytes,
          pdfName: filename,
          json: true,
          maxTokens: 8192,
          client: client,
        );
      } on AiException catch (e) {
        throw AiException('Reading $label failed: ${e.message}');
      }
      final obj = JsonUtils.object(raw);
      if (obj == null) {
        throw AiException(
            'The AI answered $label with something that is not JSON. Open the prompt in Settings and try again.');
      }
      if (title.isEmpty) {
        title = JsonUtils.str(obj['title']);
      }
      final s = JsonUtils.str(obj['subject']).toLowerCase();
      if (subject == 'general' && s.isNotEmpty) subject = s;

      final rawPages = obj['pages'];
      if (rawPages is List) {
        var fallbackNo = start;
        for (final item in rawPages) {
          if (item is! Map) continue;
          final no = JsonUtils.integer(item['page'], fallback: fallbackNo);
          final text = JsonUtils.str(item['text']);
          final figures = <ExtractedFigure>[];
          final rf = item['figures'];
          if (rf is List) {
            for (final f in rf) {
              if (f is! Map) continue;
              final box = JsonUtils.bbox(f['bbox']);
              final where = JsonUtils.str(f['where']).toLowerCase();
              final caption = JsonUtils.str(f['caption']);
              if (box == null && where.isEmpty && caption.isEmpty) continue;
              figures.add(ExtractedFigure(
                no,
                caption.isEmpty ? 'figure' : caption,
                where: where,
                bbox: box,
              ));
            }
          }
          if (text.isEmpty && figures.isEmpty) {
            fallbackNo++;
            continue;
          }
          final pageNo = no > 0 ? no : fallbackNo;
          pages[pageNo] = ExtractedPage(pageNo, text, figures);
          fallbackNo = pageNo + 1;
        }
      }
      onProgress?.call(i + 1, effective.length, 'Read $label');
    }

    if (pages.isEmpty) {
      throw AiException(
          'The AI could not read any page. Check that this PDF has text (a scanned book may need a vision model such as Gemini or GPT-4.1).');
    }

    final ordered = pages.values.toList()..sort((a, b) => a.page.compareTo(b.page));
    return ExtractionResult(
      title: title.isEmpty ? _titleFromFile(filename) : title,
      subject: subject,
      pages: ordered,
      provider: cfg.provider.name,
      model: cfg.model,
    );
  }

  static String _titleFromFile(String filename) {
    final base = filename.split(RegExp(r'[/\\]')).last;
    final noExt = base.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final clean = noExt.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return clean.isEmpty ? 'Textbook' : clean;
  }
}
