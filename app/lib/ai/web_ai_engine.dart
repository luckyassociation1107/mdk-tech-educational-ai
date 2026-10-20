import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'ai_exception.dart';

/// Free mode: drives the public PDF-teacher website inside the app's own
/// WebView — no account, no API key, no cost.
///
/// One plugin for every platform: `flutter_inappwebview` uses the system
/// Chromium WebView on Android and Microsoft Edge WebView2 on Windows, so
/// the same automation code reads a book on a phone and on a laptop.
///
/// The page runs in a headless WebView (no screen space taken): the app only
/// needs the DOM, not a picture of it. What is happening is shown in the
/// status panel instead.
///
/// Verified against the live site:
///  * the file input accepts a programmatically built `File` (DataTransfer),
///    so the PDF upload needs no native file picker;
///  * the "Ask PDF" textarea accepts any prompt (set through the native
///    value setter so React notices) and the send button submits it;
///  * the answer streams into a `.prose-sm` / `.prose-neutral` block, which
///    is read back as plain text.
///
/// Everything is one long-lived session: after the PDF is uploaded once, the
/// same conversation is used for the extraction and for every lesson script.
class WebAiEngine {
  WebAiEngine._();

  static final WebAiEngine instance = WebAiEngine._();

  static const String siteUrl =
      'https://pdf-summarizer-app-2e8ds.ondigitalocean.app/';

  /// Shown in the UI while the site works, so nothing happens invisibly.
  final ValueNotifier<String> stage = ValueNotifier<String>('');

  /// True while a request is running — the host widget shows the status panel.
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  HeadlessInAppWebView? _web;
  InAppWebViewController? _controller;
  /// Set when a page must be reopened because the book changed.
  bool _needsReload = false;
  bool _loaded = false;
  bool _pdfSent = false;
  String _pdfFingerprint = '';

  Future<void> _queue = Future<void>.value();

  /// Android has the system WebView; Windows has Edge WebView2 (the same
  /// Chromium, driven through the same plugin).
  bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isWindows);

  /// Human name of the engine on this device — used in Settings.
  String get engineName => Platform.isWindows
      ? 'Microsoft Edge WebView2'
      : 'Android WebView';

  /// Throws a teacher-readable error on a platform that cannot host the
  /// free mode (web, tests, Linux).
  void assertSupported() {
    if (supported) return;
    throw AiException(
        'The free AI needs a WebView — the Android app or the Windows app. '
        'This device has neither.');
  }

  // ------------------------------------------------------------- webview

  /// Starts the headless page once. Later calls reuse the same webview and
  /// therefore the same conversation with the site.
  Future<void> _startWebView() async {
    if (_controller != null) return;
    stage.value = 'Opening the classroom AI…';
    final headless = HeadlessInAppWebView(
      // A laptop-sized page: the site keeps the same layout it has in a
      // browser, which is what the automation was verified against.
      initialSize: const Size(1080, 1600),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        supportZoom: false,
        mediaPlaybackRequiresUserGesture: false,
        transparentBackground: false,
        useHybridComposition: true,
      ),
      initialUrlRequest: URLRequest(url: WebUri(siteUrl)),
      onWebViewCreated: (c) => _controller = c,
    );
    try {
      await headless.run();
    } catch (e) {
      try {
        await headless.dispose();
      } catch (_) {}
      throw AiException(_startFailure(e));
    }
    _web = headless;
    _controller = headless.webViewController ?? _controller;
    if (_controller == null) {
      throw AiException(_startFailure('no controller'));
    }
  }

  static String _startFailure(Object e) {
    final low = e.toString().toLowerCase();
    if (low.contains('webview2') || low.contains('edge runtime')) {
      return 'This PC is missing the Microsoft Edge WebView2 runtime, so the '
          'free AI cannot open. Install “WebView2 Runtime” from Microsoft, '
          'then try again.';
    }
    return 'The free website could not open ($e). Check your internet and '
        'try again.';
  }

  /// Closes the page and forgets the session (used when the teacher changes
  /// the book or wants a clean start).
  Future<void> reset() async {
    try {
      await _web?.dispose();
    } catch (_) {}
    _web = null;
    _controller = null;
    _needsReload = false;
    _loaded = false;
    _pdfSent = false;
    _pdfFingerprint = '';
  }

  /// Serialised entry point: one prompt at a time, on one session.
  Future<String> generate({
    required String prompt,
    List<int>? pdfBytes,
    String pdfName = 'textbook.pdf',
    Duration timeout = const Duration(minutes: 4),
  }) {
    final run = _queue.then((_) => _run(
          prompt: prompt,
          pdfBytes: pdfBytes,
          pdfName: pdfName,
          timeout: timeout,
        ));
    // Keep the chain alive even when a request fails.
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<String> _run({
    required String prompt,
    List<int>? pdfBytes,
    required String pdfName,
    required Duration timeout,
  }) async {
    assertSupported();
    busy.value = true;
    try {
      await _openSite();
      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        await _upload(pdfBytes, pdfName);
      }
      stage.value = 'Asking the free AI…';
      return await _ask(prompt, timeout: timeout);
    } finally {
      stage.value = '';
      busy.value = false;
    }
  }

  // ------------------------------------------------------------------ open

  Future<void> _openSite() async {
    if (_loaded) return;
    await _startWebView();
    stage.value = 'Opening the classroom AI…';
    if (_needsReload) {
      // A previous book is still in the conversation — start on a clean page.
      _needsReload = false;
      await _js('location.replace(${jsonEncode(siteUrl)}); "nav"');
    }
    final ok = await _waitFor(
      const Duration(seconds: 60),
      () async {
        final s = await _state();
        return s.hasAsk || s.hasFile;
      },
    );
    if (!ok) {
      _loaded = false;
      throw AiException(
          'The free website did not load. Check your internet and try again.');
    }
    _loaded = true;
  }

  /// The site keeps an "Errors" modal in the DOM as a `<dialog class="modal">`
  /// and opens it when something goes wrong; while it is open it covers the
  /// page and swallows clicks, so every step starts by closing it.
  Future<void> _dismissDialogs() async {
    await _js(r"""(() => {
      let closed = 0;
      for (const d of document.querySelectorAll('dialog')) {
        const shown = d.open || getComputedStyle(d).opacity !== '0';
        if (!shown) continue;
        const btn = [...d.querySelectorAll('button')]
          .find(b => /^(ok|close|got it|dismiss)$/i.test((b.innerText || '').trim()));
        if (btn) btn.click();
        try { d.close(); } catch (e) {}
        closed++;
      }
      return closed;
    })()""");
  }

  // ---------------------------------------------------------------- upload

  Future<void> _upload(List<int> bytes, String name) async {
    final fingerprint = '${bytes.length}:${_hash(bytes)}:$name';
    if (_pdfSent && _pdfFingerprint == fingerprint) return;
    if (_pdfSent) {
      // A different book: the old conversation must not leak into it.
      _loaded = false;
      _pdfSent = false;
      _pdfFingerprint = '';
      _needsReload = true;
      await _openSite();
    }

    stage.value = 'Uploading the PDF to the free AI…';
    await _dismissDialogs();

    // Base64 in chunks: a 20 MB string in one evaluateJavascript call can
    // choke the WebView (and the method channel on Windows).
    final b64 = base64Encode(bytes);
    const chunk = 900000;
    await _js('window.__mdkPdf = []; "reset"');
    for (var i = 0; i < b64.length; i += chunk) {
      final part = b64.substring(i, (i + chunk).clamp(0, b64.length));
      await _js('window.__mdkPdf.push("$part"); ${i ~/ chunk}');
      stage.value =
          'Uploading the PDF… ${((i + part.length) / b64.length * 100).round()}%';
    }

    final res = await _js("""(() => {
      const input = document.querySelector('input[type=file]');
      if (!input) return 'no-input';
      const b64 = (window.__mdkPdf || []).join('');
      const bin = atob(b64);
      const arr = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
      const file = new File([arr], ${jsonEncode(name)}, {type: 'application/pdf'});
      const dt = new DataTransfer();
      dt.items.add(file);
      input.files = dt.files;
      input.dispatchEvent(new Event('change', {bubbles: true}));
      window.__mdkPdf = [];
      return 'ok';
    })()""");

    if (res.toString() != 'ok') {
      throw AiException(
          'The free website did not accept the PDF (${res.toString()}). Try again.');
    }

    // The site extracts the text in the browser itself; the "Ask PDF" box
    // only exists once that is done, so it is the ready signal. A scan (photos
    // of pages) makes it give up and open its "Errors" popup within a second —
    // say that plainly instead of waiting two minutes for an ask box.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    String? siteError;
    var ready = false;
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(deadline)) {
      final s = await _state();
      if (s.hasAsk) {
        ready = true;
        break;
      }
      if (s.error.isNotEmpty) {
        siteError = s.error;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (siteError != null) {
      await _dismissDialogs();
      throw AiException(friendlySiteError(siteError));
    }
    if (!ready) {
      throw AiException(
          'The free website did not finish reading this PDF. If it is very '
          'large, try a smaller file.');
    }
    _pdfSent = true;
    _pdfFingerprint = fingerprint;
    stage.value = 'The free AI has the book. Asking…';
  }

  // ------------------------------------------------------------------- ask

  Future<String> _ask(String prompt, {required Duration timeout}) async {
    await _dismissDialogs();
    final before = await _state();
    if (!before.hasAsk) {
      throw AiException(
          'The free website is not ready for questions yet. Upload the PDF first, then ask.');
    }

    // Long prompts go in chunks for the same memory reason as the PDF.
    const chunk = 120000;
    if (prompt.length <= chunk) {
      await _js("""(() => {
        const ta = document.querySelector('textarea[placeholder="Ask PDF"]');
        const set = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
        set.call(ta, ${jsonEncode(prompt)});
        ta.dispatchEvent(new Event('input', {bubbles: true}));
        return 'typed';
      })()""");
    } else {
      await _js('window.__mdkPrompt = ""; "reset"');
      for (var i = 0; i < prompt.length; i += chunk) {
        final part = prompt.substring(i, (i + chunk).clamp(0, prompt.length));
        await _js('window.__mdkPrompt += ${jsonEncode(part)}; ${i ~/ chunk}');
      }
      await _js("""(() => {
        const ta = document.querySelector('textarea[placeholder="Ask PDF"]');
        const set = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set;
        set.call(ta, window.__mdkPrompt);
        ta.dispatchEvent(new Event('input', {bubbles: true}));
        window.__mdkPrompt = "";
        return 'typed';
      })()""");
    }

    // React flips the send button from disabled to enabled one frame after the
    // input event, so give it a few tries instead of racing it.
    var sent = 'no-send';
    for (var i = 0; i < 12; i++) {
      sent = (await _js("""(() => {
        const ta = document.querySelector('textarea[placeholder="Ask PDF"]');
        if (!ta) return 'no-send';
        const box = ta.closest('div');
        let btns = [...box.querySelectorAll('button.btn-square')].filter(b => !b.disabled);
        if (!btns.length) btns = [...document.querySelectorAll('button.btn-square')].filter(b => !b.disabled);
        if (!btns.length) return 'no-send';
        btns[btns.length - 1].click();
        return 'sent';
      })()"""))
          .toString();
      if (sent == 'sent') break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (sent != 'sent') {
      throw AiException(
          'The free website did not enable its send button. Try again.');
    }

    // Wait for a new answer, then for it to stop growing. Chunks arrive about
    // every 300 ms while the model writes, so a full second of silence is a
    // finished answer; three ticks leaves room for a mid-sentence pause.
    final deadline = DateTime.now().add(timeout);
    var last = '';
    var stable = 0;
    var sawNew = false;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final s = await _state();
      if (s.error.isNotEmpty) {
        await _dismissDialogs();
        throw AiException(friendlySiteError(s.error));
      }
      if (s.answers > before.answers || s.last != before.last) sawNew = true;
      final text = s.last.replaceAll('\r', '').trim();
      if (sawNew && text.isNotEmpty) {
        if (text == last) {
          stable++;
          if (stable >= 3) return text;
        } else {
          stable = 0;
          last = text;
        }
        stage.value = 'The free AI is answering… ${text.length} chars';
      }
    }
    if (sawNew && last.isNotEmpty) return last;
    throw AiException('The free AI did not answer in time. Try again.');
  }

  // ----------------------------------------------------------------- utils

  Future<_PageState> _state() async {
    final raw = await _js("""(() => {
      const ta = document.querySelector('textarea[placeholder="Ask PDF"]');
      const file = document.querySelector('input[type=file]');
      const bubbles = document.querySelectorAll('.prose-sm, .prose-neutral');
      const last = bubbles.length ? bubbles[bubbles.length - 1].innerText : '';
      // The "Errors" popup is always in the DOM; it is only on screen when
      // DaisyUI gives it opacity 1 (hidden => opacity 0, pointer-events none).
      let error = '';
      for (const d of document.querySelectorAll('dialog')) {
        if (getComputedStyle(d).opacity === '0') continue;
        const t = (d.innerText || '').replace(/\s+/g, ' ').trim();
        if (t) { error = t; break; }
      }
      return JSON.stringify({
        hasAsk: !!ta,
        hasFile: !!file,
        answers: bubbles.length,
        last: last,
        error: error,
      });
    })()""");
    try {
      final j = _asMap(raw);
      if (j == null) {
        return const _PageState(
            hasAsk: false, hasFile: false, answers: 0, last: '');
      }
      return _PageState(
        hasAsk: j['hasAsk'] == true,
        hasFile: j['hasFile'] == true,
        answers: (j['answers'] as num?)?.toInt() ?? 0,
        last: (j['last'] ?? '').toString(),
        error: (j['error'] ?? '').toString(),
      );
    } catch (_) {
      return const _PageState(
          hasAsk: false, hasFile: false, answers: 0, last: '');
    }
  }

  /// JavaScript answers arrive differently on each platform: a Map on
  /// Android (already decoded), a JSON string on Windows, and sometimes a
  /// string that still needs one more decode. Accept all three.
  static Map<String, dynamic>? _asMap(dynamic raw) {
    dynamic v = raw;
    for (var i = 0; i < 3; i++) {
      if (v is Map) {
        return v.map((k, x) => MapEntry(k.toString(), x));
      }
      if (v is! String) return null;
      try {
        v = jsonDecode(v);
      } catch (_) {
        return null;
      }
    }
    return v is Map ? v.map((k, x) => MapEntry(k.toString(), x)) : null;
  }

  Future<dynamic> _js(String script) async {
    final c = _controller;
    if (c == null) {
      throw AiException('The free website is not open yet. Try again.');
    }
    try {
      final r = await c.evaluateJavascript(source: script);
      if (r is String && r.length >= 2 && r.startsWith('"') && r.endsWith('"')) {
        try {
          return jsonDecode(r);
        } catch (_) {
          return r;
        }
      }
      return r;
    } catch (e) {
      throw AiException('The free website could not be driven ($e). Try again.');
    }
  }

  static int _hash(List<int> bytes) {
    var h = 0x811c9dc5;
    void mix(int b) {
      h ^= b;
      h = (h * 0x01000193) & 0xffffffff;
    }

    mix(bytes.length & 0xff);
    mix((bytes.length >> 8) & 0xff);
    mix((bytes.length >> 16) & 0xff);
    final step = bytes.length <= 4096 ? 1 : bytes.length ~/ 4096;
    for (var i = 0; i < bytes.length; i += step) {
      mix(bytes[i]);
    }
    return h;
  }

  Future<bool> _waitFor(Duration limit, Future<bool> Function() check) async {
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      if (await check()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }

  /// The site speaks in its own words; a teacher reading this on a phone
  /// should get one plain sentence back.
  @visibleForTesting
  static String friendlySiteError(String raw) {
    final low = raw.toLowerCase();
    final detail = raw.replaceFirst(RegExp(r'^Errors\s*'), '').trim();
    if (low.contains('scan') ||
        low.contains('image-based') ||
        low.contains('no text')) {
      return 'This book looks like photos of pages (a scan), so there is no '
          'text for the free AI to read. Use a PDF that has real text.';
    }
    if (low.contains('too large') || low.contains('size limit')) {
      return 'This PDF is too large for the free website. Split it into '
          'smaller chapters and try again.';
    }
    if (detail.isEmpty) return 'The free website reported an error. Try again.';
    return 'The free website could not read this PDF: $detail';
  }

  /// Settings → "Test connection" for the free mode.
  ///
  /// There is nothing to ask before a PDF is uploaded (the site only shows
  /// its Ask box once a book is in), so the check is "the site is up and
  /// waiting for a PDF".
  Future<String> selfTest() async {
    assertSupported();
    busy.value = true;
    stage.value = 'Checking the free website…';
    try {
      await _openSite();
      final s = await _state();
      if (!s.hasFile && !s.hasAsk) {
        throw AiException(
            'The free website opened but its upload box is missing. It may have '
            'changed; try again later.');
      }
      return 'READY';
    } finally {
      stage.value = '';
      busy.value = false;
    }
  }
}

class _PageState {
  final bool hasAsk;
  final bool hasFile;
  final int answers;
  final String last;

  /// Text of the site's "Errors" popup while it is on screen, else ''.
  final String error;

  const _PageState({
    required this.hasAsk,
    required this.hasFile,
    required this.answers,
    required this.last,
    this.error = '',
  });
}
