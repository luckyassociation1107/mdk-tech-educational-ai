import 'ai_client.dart';
import 'ai_config.dart';
import 'ai_prompts.dart';

/// Raised for anything the teacher can fix (key, quota, internet).
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

/// Summary and doubt-clearing on top of [AiClient].
///
/// v0.23 called a free endpoint that belonged to somebody else's website.
/// Since v0.24 every call goes to the teacher's own account — the same key,
/// provider and prompts that read the PDF — so there is nothing borrowed,
/// nothing spoofed and nothing that can disappear overnight.
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

  /// True when a key is configured — the UI says "online" only then.
  static Future<bool> reachable() async {
    final cfg = AiConfig.current.ready ? AiConfig.current : await AiConfig.load();
    return cfg.ready;
  }

  static Future<String> summarize(
    String pdfText, {
    int level = 1,
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
          'No AI key yet. Open Settings → AI & Prompts and paste your key.');
    }
    final prompt = '${levelInstruction(level)}\n\n$classroomHint\n\n'
        'Summarise ONLY the textbook text below. Do not add outside facts.\n\n'
        '---8<---\n${clip(pdfText)}\n---8<---';
    try {
      final out = await AiClient().generate(
        cfg,
        parts: [AiPart.text(prompt)],
        maxTokens: 3000,
      );
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
    void Function(String chunk)? onChunk,
    BrainCancel? cancel,
  }) async {
    if (question.trim().isEmpty) {
      throw BrainException('Type a question first.');
    }
    final cfg = AiConfig.current.ready ? AiConfig.current : await AiConfig.load();
    if (!cfg.ready) {
      throw BrainException(
          'No AI key yet. Open Settings → AI & Prompts and paste your key.');
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
      final out = await AiClient().generate(
        cfg,
        parts: [AiPart.text(prompt)],
        maxTokens: 2000,
      );
      if (cancel?.cancelled == true) return '';
      onChunk?.call(out);
      return out.trim();
    } on AiException catch (e) {
      throw BrainException(e.message);
    }
  }
}
