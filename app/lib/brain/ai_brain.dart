import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// ─────────────────────────────────────────────────────────────────────
///  AiBrain — the online AI brain, called straight from the app.
///
///  The textbook brain used to be driven only by automating a website in
///  an in-app WebView. That website itself does something much simpler:
///  it extracts the PDF text in the browser, then POSTs plain JSON to a
///  free chat endpoint and reads the answer back as a stream.
///
///  This class does exactly the same thing natively, so the brain works
///  on Android AND Windows, with no WebView, no file-chooser and no
///  scraping of a page that can change its buttons.
///
///  Contract (captured from the live site):
///    POST https://productivity-tools-server-qgvsu.ondigitalocean.app/
///    {"messages":[...], "model":"gpt-4o-mini", "stream":true, ...}
///    → text/event-stream of OpenAI-compatible chunks
///      data: {"choices":[{"delta":{"content":"..."}}]}
///      data: [DONE]
/// ─────────────────────────────────────────────────────────────────────
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

class AiBrain {
  static const String endpoint =
      'https://productivity-tools-server-qgvsu.ondigitalocean.app/';
  static const String model = 'gpt-4o-mini';
  static const String origin =
      'https://pdf-summarizer-app-2e8ds.ondigitalocean.app';
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Mobile Safari/537.36';

  /// The textbook text is trimmed to this many characters per request so a
  /// very large book never exceeds the server's request size.
  static const int maxTextChars = 45000;

  static const String summarizePrompt =
      'As a professional summarizer, write detailed summary of the provided pdf file content. '
      'Please ensure that the summary is well-organized and easy to read, with clear headings and '
      'subheadings to guide the reader through each section. Rely strictly on the provided text, '
      'without including external information.';

  static const String askPrompt =
      'You are a helpful assistant that can answer questions based on the provided PDF content. '
      'Return formatted result.';

  /// Extra instruction so the answer is useful inside a classroom app.
  static const String classroomHint =
      'You are helping a school student. Keep the language simple, give everyday examples, '
      'and keep technical words in English.';

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

  /// Trim big books to a sane request size, on a sentence boundary if we can.
  static String clip(String text) {
    final clean = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (clean.length <= maxTextChars) return clean;
    final cut = clean.substring(0, maxTextChars);
    final lastStop = cut.lastIndexOf('. ');
    return lastStop > maxTextChars * 0.7 ? cut.substring(0, lastStop + 1) : cut;
  }

  static Map<String, dynamic> summarizeBody(String pdfText, int level) => {
        'messages': [
          {'role': 'system', 'content': summarizePrompt},
          {'role': 'system', 'content': classroomHint},
          {'role': 'user', 'content': levelInstruction(level)},
          {'role': 'user', 'content': clip(pdfText)},
        ],
        'model': model,
        'response_format': {'type': 'text'},
        'stream': true,
        'top_p': 1,
        'temperature': 0.4,
        'presence_penalty': 0,
        'frequency_penalty': 0,
        'max_completion_tokens': 4096,
      };

  static Map<String, dynamic> askBody({
    required String pdfText,
    required String question,
    String? previousSummary,
  }) =>
      {
        'messages': [
          {'role': 'system', 'content': askPrompt},
          {'role': 'system', 'content': classroomHint},
          {'role': 'system', 'content': 'PDF Content: ${clip(pdfText)}'},
          if (previousSummary != null && previousSummary.trim().isNotEmpty)
            {'role': 'assistant', 'content': previousSummary},
          {'role': 'user', 'content': question},
        ],
        'model': model,
        'response_format': {'type': 'text'},
        'stream': true,
        'top_p': 1,
        'temperature': 0.4,
        'presence_penalty': 0,
        'frequency_penalty': 0,
        'max_completion_tokens': 4096,
      };

  /// Pull the text out of one SSE line. Returns null for keep-alive/padding.
  static String? parseSseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('data:')) return null;
    final payload = trimmed.substring(5).trim();
    if (payload.isEmpty) return null;
    if (payload == '[DONE]') return null;
    try {
      final obj = jsonDecode(payload);
      if (obj is! Map) return null;
      final choices = obj['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final delta = first['delta'];
      if (delta is Map) {
        final c = delta['content'];
        if (c is String && c.isNotEmpty) return c;
      }
      // Some servers send the whole message instead of a delta.
      final message = first['message'];
      if (message is Map) {
        final c = message['content'];
        if (c is String && c.isNotEmpty) return c;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Streams a completion. [onChunk] is called with each piece of text.
  static Future<String> _stream(Map<String, dynamic> body,
      {void Function(String chunk)? onChunk,
      BrainCancel? cancel,
      Duration timeout = const Duration(seconds: 180)}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final buffer = StringBuffer();
    IOSink? sink;
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      // The service only answers requests that look like they come from the
      // website it serves, so send the same origin/referer/UA.
      request.headers.set('origin', origin);
      request.headers.set('referer', '$origin/');
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      request.add(utf8.encode(jsonEncode(body)));
      final response =
          await request.close().timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        final err = await response.transform(utf8.decoder).join();
        throw BrainException(
            'Brain server said ${response.statusCode}. ${err.isEmpty ? '' : err.substring(0, err.length > 160 ? 160 : err.length)}');
      }

      final done = Completer<void>();
      var lineBuffer = '';
      final sub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (cancel?.cancelled == true) return;
        // Some proxies fold SSE into one line; keep a buffer for safety.
        lineBuffer = line;
        final chunk = parseSseLine(lineBuffer);
        if (chunk != null) {
          buffer.write(chunk);
          onChunk?.call(chunk);
        }
      }, onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      }, cancelOnError: true);

      try {
        await done.future.timeout(timeout,
            onTimeout: () => throw BrainException(
                'The brain took too long to answer. Check your internet and try again.'));
      } finally {
        await sub.cancel();
      }

      final text = buffer.toString().trim();
      if (text.isEmpty) {
        throw BrainException('The brain sent an empty answer. Try again.');
      }
      return text;
    } on SocketException catch (e) {
      throw BrainException('No internet connection (${e.message}).');
    } finally {
      sink?.close();
      client.close(force: true);
    }
  }

  static Future<String> summarize(
    String pdfText, {
    int level = 1,
    void Function(String chunk)? onChunk,
    BrainCancel? cancel,
  }) {
    if (pdfText.trim().length < 40) {
      throw BrainException(
          'This textbook has too little readable text for the brain.');
    }
    return _stream(summarizeBody(pdfText, level),
        onChunk: onChunk, cancel: cancel);
  }

  static Future<String> ask({
    required String pdfText,
    required String question,
    String? summary,
    void Function(String chunk)? onChunk,
    BrainCancel? cancel,
  }) {
    if (question.trim().isEmpty) {
      throw BrainException('Type a question first.');
    }
    return _stream(
        askBody(pdfText: pdfText, question: question, previousSummary: summary),
        onChunk: onChunk,
        cancel: cancel);
  }

  /// Quick connectivity check used by the UI before showing "online".
  static Future<bool> reachable(
      {Duration timeout = const Duration(seconds: 8)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.headUrl(Uri.parse(endpoint)).timeout(timeout);
      final res = await req.close().timeout(timeout);
      await res.drain<void>();
      return res.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
