import 'dart:typed_data';

import 'ai_exception.dart';
import 'web_ai_engine.dart';

/// One door for every AI call in the app.
///
/// The only engine is the **free** one: the public PDF-teacher website is
/// driven inside the app's own WebView — no account, no key, no cost. Callers
/// (extractor, script designer, brain) never care how it happens.
class AiService {
  /// Test seam: when set, every call is answered locally instead of driving
  /// the website, so the whole pipeline can be tested without a network.
  static Future<String> Function(String prompt, Uint8List? pdf, String pdfName)?
      debugTransport;

  static bool get isStubbed => debugTransport != null;

  static Future<String> generate({
    required String prompt,
    Uint8List? pdf,
    String pdfName = 'textbook.pdf',
  }) {
    final stub = debugTransport;
    if (stub != null) return stub(prompt, pdf, pdfName);
    return WebAiEngine.instance.generate(
      prompt: prompt,
      pdfBytes: pdf,
      pdfName: pdfName,
    );
  }

  /// Quick round trip used by Settings → "Test connection".
  static Future<String> test() async {
    final stub = debugTransport;
    if (stub != null) return (await stub('READY', null, '')).trim();
    return WebAiEngine.instance.selfTest();
  }
}
