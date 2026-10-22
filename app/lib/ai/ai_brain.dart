import 'dart:typed_data';

import 'ai_config.dart';
import 'ai_exception.dart';
import 'ai_prompts.dart';
import 'ai_service.dart';

/// Raised for anything the teacher can fix (internet, the website, the PDF).
class BrainException implements Exception {
  final String message;
  BrainException(this.message);
  @override
  String toString() => message;
}

/// Lets the UI stop a running request.
class BrainCancel {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// Summary and doubt-clearing on top of the free website AI.
///
/// Every call goes through [AiService], which drives the public PDF-teacher
/// website inside the app's WebView — the same session, the same prompts and
/// the same book that read the PDF. No key, no cost.
class AiBrain {
  /// Trim huge books so a summary request stays inside the context window.
  static const int maxTextChars = 45000;

  static const String classroomHint =
      'You are helping a school student. Keep the language simple, give everyday '
      'examples, and keep technical words in English.';

  static String levelInstruction(int level) {
    switch (level) {
      case 0:
        return 'Write a brief summary in under 150 words.';
      case 2:
        return 'Write a detailed summary with every definition, process, formula and example.';
      default:
        return 'Write a medium-length summary with the main headings and key points.';
    }
  }

  /// Trim big books on a sentence boundary.
  static String clip(String text) {
    final clean = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (clean.length <= maxTextChars) return clean;
    final cut = clean.substring(0, maxTextChars);
    final lastStop = cut.lastIndexOf('. ');
    return lastStop > maxTextChars * 0.7 ? cut.substring(0, lastStop + 1) : cut;
  }

  /// True when this device can host the free mode — the UI says "online"
  /// only then.
  static Future<bool> reachable() async {
    final cfg = AiConfig.current.ready ? AiConfig.current : await AiConfig.load();
    return cfg.ready;
  }

  static Future<String> summarize(
    String pdfText, {
    int level = 1,
    Uint8List? pdf,
    String pdfName = 'textbook.pdf',
    void Function(String chunk)? onChunk,
    BrainCancel? cancel,
  }) async {
    if (pdfText.trim().length < 40) {
      throw BrainException(
          'This textbook has too little readable text for the brain.');
    }
    final cfg = AiConfig.current.ready ? AiConfig.current : await AiConfig.load();
    if (!cfg.ready) {
      throw BrainException(
          'The free AI needs an in-app browser (Android WebView / Edge '
          'WebView2). This device has none.');
    }
    final prompt = '${levelInstruction(level)}\n\n$classroomHint\n\n'
        'Summarise ONLY the textbook text below. Do not add outside facts.\n'
        'Reply with the summary only.\n\n'
        '---8<---\n${clip(pdfText)}\n---8<---';
    try {
      final out = await AiService.generate(prompt: prompt, pdf: pdf, pdfName: pdfName);
      if (cancel?.cancelled == true) return '';
      onChunk?.call(out);
      return out.trim();
    } on AiException catch (e) {
      throw BrainException(e.message);
    }
  }

  static Future<String> ask({
    required String pdfText,
    required String question,
    String? summary,
    Uint8List? pdf,
    String pdfName = 'textbook.pdf',
    void Function(String chunk)? onChunk,
    BrainCancel? cancel,
  }) async {
    if (question.trim().isEmpty) {
      throw BrainException('Type a question first.');
    }
    final cfg = AiConfig.current.ready ? AiConfig.current : await AiConfig.load();
    if (!cfg.ready) {
      throw BrainException(
          'The free AI needs an in-app browser (Android WebView / Edge '
          'WebView2). This device has none.');
    }
    final prompt = AiPrompts.fill(cfg.askPrompt, {
      'title': 'this textbook',
      'pages': 'the attached extract',
      'language': 'the student\'s language',
      'question': question.trim(),
      'content': clip(
          '${summary == null || summary.trim().isEmpty ? '' : 'Earlier summary:\n$summary\n\n'}'
          'Textbook text:\n$pdfText'),
    });
    try {
      final out = await AiService.generate(prompt: prompt, pdf: pdf, pdfName: pdfName);
      if (cancel?.cancelled == true) return '';
      onChunk?.call(out);
      return out.trim();
    } on AiException catch (e) {
      throw BrainException(e.message);
    }
  }
}
