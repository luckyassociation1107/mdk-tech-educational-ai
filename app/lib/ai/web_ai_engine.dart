import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'ai_client.dart';

/// Free mode: drives the public PDF-teacher website inside the app's own
/// WebView — no account, no API key, no cost.
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

  /// True while a request is running — the host widget shows the mini panel.
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  WebViewController? _controller;
  bool _loaded = false;
  bool _pdfSent = false;
  String _pdfFingerprint = '';

  Future<void> _queue = Future<void>.value();

  bool get supported => !kIsWeb && Platform.isAndroid;

  WebViewController get controller {
    final c = _controller;
    if (c == null) {
      throw AiException(
          'The free website mode needs the WebView panel. Open Settings → AI & Prompts and try again.');
    }
    return c;
  }

  /// Called by the host widget once, when it can host a WebView.
  void attach(WebViewController c) {
    if (_controller != null) return;
    _controller = c;
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000));
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
    if (!supported) {
      throw AiException(
          'The free website mode runs on Android. On Windows, add your own API key instead.');
    }
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
    stage.value = 'Opening the classroom AI…';
    await controller.loadRequest(Uri.parse(siteUrl));
    _loaded = true;
    // Wait for the page to be usable (file input or ask box present).
    final ok = await _waitFor(
      const Duration(seconds: 40),
      () async => (await _state()).hasAsk || (await _state()).hasFile,
    );
    if (!ok) {
      _loaded = false;
      throw AiException(
          'The free website did not load. Check your internet (or use your own API key in Settings).');
    }
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
      await _openSite();
    }

    stage.value = 'Uploading the PDF to the free AI…';
    await _dismissDialogs();

    // Base64 in chunks: a 20 MB string in one evaluateJavascript call can
    // kill the Android WebView.
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
          'The free website did not accept the PDF (${res.toString()}). Try again, or use your own API key.');
    }

    // The site extracts the text in the browser itself; the "Ask PDF" box
    // only exists once that is done, so it is the ready signal.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _dismissDialogs();
    final ready = await _waitFor(const Duration(seconds: 120), () async {
      final s = await _state();
      return s.hasAsk;
    });
    if (!ready) {
      throw AiException(
          'The free website is still reading this PDF. If it is a scan, it may not be able to. Try a text PDF or your own API key.');
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
      throw AiException('The free website changed its layout. Use your own API key instead.');
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
      })()""")).toString();
      if (sent == 'sent') break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (sent != 'sent') {
      throw AiException(
          'The free website did not enable its send button. Try again, or use your own API key.');
    }

    // Wait for a new answer, then for it to stop growing.
    final deadline = DateTime.now().add(timeout);
    var last = '';
    var stable = 0;
    var sawNew = false;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final s = await _state();
      if (s.answers > before.answers || s.last != before.last) sawNew = true;
      final text = s.last.replaceAll('\r', '').trim();
      if (sawNew && text.isNotEmpty) {
        if (text == last) {
          stable++;
          if (stable >= 2) return text;
        } else {
          stable = 0;
          last = text;
        }
        stage.value = 'The free AI is answering… ${text.length} chars';
      }
    }
    if (sawNew && last.isNotEmpty) return last;
    throw AiException(
        'The free AI did not answer in time. Try again, or add your own API key in Settings.');
  }

  // ----------------------------------------------------------------- utils

  Future<_PageState> _state() async {
    final raw = await _js("""(() => {
      const ta = document.querySelector('textarea[placeholder="Ask PDF"]');
      const file = document.querySelector('input[type=file]');
      const bubbles = document.querySelectorAll('.prose-sm, .prose-neutral');
      const last = bubbles.length ? bubbles[bubbles.length - 1].innerText : '';
      return JSON.stringify({
        hasAsk: !!ta,
        hasFile: !!file,
        answers: bubbles.length,
        last: last,
      });
    })()""");
    try {
      var text = raw.toString();
      if (text.startsWith('"') && text.endsWith('"')) {
        text = jsonDecode(text) as String;
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      return _PageState(
        hasAsk: j['hasAsk'] == true,
        hasFile: j['hasFile'] == true,
        answers: (j['answers'] as num?)?.toInt() ?? 0,
        last: (j['last'] ?? '').toString(),
      );
    } catch (_) {
      return const _PageState(hasAsk: false, hasFile: false, answers: 0, last: '');
    }
  }

  Future<dynamic> _js(String script) async {
    try {
      final r = await controller.runJavaScriptReturningResult(script);
      if (r is String && r.length >= 2 && r.startsWith('"') && r.endsWith('"')) {
        try {
          return jsonDecode(r);
        } catch (_) {
          return r;
        }
      }
      return r;
    } catch (e) {
      throw AiException('The free website could not be driven ($e). Use your own API key instead.');
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

  /// Start a fresh conversation (used when the teacher changes the book).
  Future<void> reset() async {
    _loaded = false;
    _pdfSent = false;
    _pdfFingerprint = '';
  }
}

class _PageState {
  final bool hasAsk;
  final bool hasFile;
  final int answers;
  final String last;
  const _PageState({
    required this.hasAsk,
    required this.hasFile,
    required this.answers,
    required this.last,
  });
}
