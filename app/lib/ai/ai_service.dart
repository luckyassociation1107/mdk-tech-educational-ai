import 'dart:typed_data';

import 'ai_client.dart';
import 'ai_config.dart';
import 'web_ai_engine.dart';

/// One door for every AI call in the app.
///
/// * [AiMode.webview] — **free**: the public PDF-teacher website is driven in
///   the app's own WebView (no account, no key, no cost).
/// * [AiMode.api] — the teacher's own key, called directly (works on Windows
///   too, and can see the page images).
///
/// Callers (extractor, script designer, brain) never care which one is on.
class AiService {
  static Future<String> generate(
    AiConfig cfg, {
    required String prompt,
    Uint8List? pdf,
    String pdfName = 'textbook.pdf',
    bool json = false,
    int maxTokens = 4096,
    AiClient? client,
  }) {
    if (cfg.mode == AiMode.webview) {
      return WebAiEngine.instance.generate(
        prompt: prompt,
        pdfBytes: pdf,
        pdfName: pdfName,
      );
    }
    return (client ?? AiClient()).generate(
      cfg,
      parts: [
        AiPart.text(prompt),
        if (pdf != null) AiPart.pdf(pdf, pdfName),
      ],
      json: json,
      maxTokens: maxTokens,
    );
  }

  /// Quick round trip used by Settings → "Test connection".
  static Future<String> test(AiConfig cfg) async {
    if (cfg.mode == AiMode.webview) {
      if (!WebAiEngine.instance.supported) {
        throw AiException(
            'Free website mode runs on Android only. On Windows, switch to your own API key.');
      }
      return WebAiEngine.instance.selfTest();
    }
    final out = await (AiClient()).generate(
      cfg,
      parts: [AiPart.text('Reply with exactly this word and nothing else: READY')],
      maxTokens: 16,
    );
    return out.trim();
  }
}
