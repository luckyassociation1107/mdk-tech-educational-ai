import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../engine_gateway.dart';
import '../store.dart';
import '../widgets.dart';

/// The online AI brain, automated inside the app.
///
/// The PDF-teacher website (and browser extensions like it) cannot run
/// inside a phone app directly, so this screen drives the real website
/// in an in-app WebView: it uploads THIS student's textbook from THIS
/// device, picks the detail level, taps Summarize, sends chat questions
/// and reads the answers back out of the page.
///
/// Everything the brain produces — the summary and every Q&A — is saved
/// locally in the student's own session (DartEngine brain.json) and from
/// then on is used by the local lesson player and tests. Lessons,
/// videos and chats stay on the individual device; each student runs
/// their own brain session with their own PDF and their own questions.
class BrainWebViewScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  final String sessionId;
  final String bookTitle;
  const BrainWebViewScreen(
      {super.key,
      required this.gateway,
      required this.settings,
      required this.sessionId,
      required this.bookTitle});

  static const brainUrl =
      'https://pdf-summarizer-app-2e8ds.ondigitalocean.app/';

  @override
  State<BrainWebViewScreen> createState() => _BrainWebViewScreenState();
}

class _BrainWebViewScreenState extends State<BrainWebViewScreen> {
  InAppWebViewController? _web;
  final _log = <String>[];
  final _questionCtrl = TextEditingController();
  String _pdfPath = '';
  bool _pdfReady = false;
  bool _pageReady = false;
  bool _summarizing = false;
  bool _asking = false;
  int _level = 1; // 0 brief, 1 medium, 2 detailed (website slider)
  String _summary = '';
  List<Map<String, dynamic>> _qa = [];
  String _lastQuestion = '';

  bool get _supported => Platform.isAndroid || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  void _say(String m) {
    if (!mounted) return;
    setState(() => _log.insert(0, m));
  }

  Future<void> _prepare() async {
    final data = await widget.gateway.loadBrainData(widget.sessionId);
    final p = await widget.gateway.sessionPdfPath(widget.sessionId);
    final exists = await File(p).exists();
    if (!mounted) return;
    setState(() {
      _summary = (data['summary'] ?? '').toString();
      _level = (data['level'] as num?)?.toInt() ?? 1;
      _qa = ((data['qa'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      _pdfPath = p;
      _pdfReady = exists;
    });
    if (_supported && exists) _initWeb();
  }

  // The WebView widget itself creates the controller (onWebViewCreated) and
  // loads the site; nothing to build here any more.
  void _initWeb() {
    if (mounted) setState(() {});
  }

  // ---------- JS helpers ----------

  Future<String> _js(String code) async {
    final c = _web;
    if (c == null) return '';
    final r = await c.evaluateJavascript(source: code);
    if (r == null) return '';
    var s = r.toString();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      try {
        s = jsonDecode(s).toString();
      } catch (_) {}
    }
    return s;
  }

  /// Hands the site this student's textbook without opening the native file
  /// picker: the PDF bytes go into a `File` in the page, exactly as the free
  /// AI engine does it. Works on the phone and on Windows the same way.
  Future<void> _uploadPdf() async {
    final bytes = await File(_pdfPath).readAsBytes();
    final b64 = base64Encode(bytes);
    const chunk = 900000;
    await _js('window.__mdkPdf = []; "reset"');
    for (var i = 0; i < b64.length; i += chunk) {
      final part = b64.substring(i, (i + chunk).clamp(0, b64.length));
      await _js('window.__mdkPdf.push("$part"); ${i ~/ chunk}');
    }
    final res = await _js("""(() => {
      const input = document.querySelector('input[type=file]');
      if (!input) return 'no-input';
      const b64 = (window.__mdkPdf || []).join('');
      const bin = atob(b64);
      const arr = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
      const f = new File([arr], 'textbook.pdf', {type: 'application/pdf'});
      const dt = new DataTransfer();
      dt.items.add(f);
      input.files = dt.files;
      input.dispatchEvent(new Event('change', {bubbles: true}));
      window.__mdkPdf = [];
      return 'ok';
    })()""");
    if (res != 'ok') {
      throw StateError('Upload box not found on the page yet ($res). '
          'Wait for it to load, then try again.');
    }
  }

  Future<String> _pageText() async {
    try {
      return await _js('document.body ? document.body.innerText : ""');
    } catch (_) {
      return '';
    }
  }

  Future<bool> _waitFor(Future<bool> Function() probe,
      {int seconds = 90}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(end)) {
      if (await probe()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    return false;
  }

  Future<String> _waitStable(Future<String> Function() extract,
      {int seconds = 120, int minLen = 20}) async {
    final end = DateTime.now().add(Duration(seconds: seconds));
    var last = '';
    var stable = 0;
    while (DateTime.now().isBefore(end)) {
      final cur = await extract();
      if (cur.length >= minLen && cur == last) {
        if (++stable >= 3) return cur;
      } else {
        stable = 0;
        last = cur;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    return last.length >= minLen ? last : '';
  }

  // ---------- extraction (matches the live website's DOM behaviour) ----------

  static String extractSummary(String pageText) {
    var t = pageText;
    final end = t.indexOf('Rate us');
    if (end > 0) t = t.substring(0, end);
    int start = -1;
    for (final p in [
      RegExp(r'Summary[^\n]*\n'),
      RegExp(r'Summarize (brief|medium|detailed)[^\n]*\n', caseSensitive: false)
    ]) {
      final ms = p.allMatches(t).toList();
      if (ms.isNotEmpty) start = ms.last.end;
    }
    if (start < 0 || start >= t.length) return '';
    var out = t.substring(start).trim();
    for (final cut in ['\nAsk PDF', '\nSend message']) {
      final i = out.indexOf(cut);
      if (i > 0) out = out.substring(0, i).trim();
    }
    return out.length >= 40 ? out : '';
  }

  static String extractAnswer(String pageText, String question) {
    var t = pageText;
    final end = t.indexOf('Rate us');
    if (end > 0) t = t.substring(0, end);
    final idx = t.lastIndexOf(question);
    if (idx < 0) return '';
    var out = t.substring(idx + question.length).trim();
    out = out.replaceAll('Send message', '').trim();
    return out;
  }

  // ---------- automation ----------

  Future<void> _summarize({int? level}) async {
    if (_web == null || _summarizing) return;
    final lvl = level ?? _level;
    setState(() => _summarizing = true);
    try {
      _say('Opening the website brain…');
      if (!_pageReady) {
        await _waitFor(() async => _pageReady, seconds: 60);
      }
      _say('Uploading your textbook PDF (stays your copy, on your device)…');
      await _uploadPdf();
      final hasSlider = await _waitFor(() async {
        final r = await _js(
            "document.querySelector('input[type=range]') ? 'yes' : 'no'");
        return r == 'yes';
      }, seconds: 90);
      if (!hasSlider)
        throw StateError(
            'The website did not accept the PDF in time. Check internet and try again — or use “Capture visible summary” after doing it by hand below.');
      await _js(
          "(() => { const r = document.querySelector('input[type=range]'); const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set; set.call(r, '$lvl'); r.dispatchEvent(new Event('input', {bubbles: true})); r.dispatchEvent(new Event('change', {bubbles: true})); return 'ok'; })()");
      _say('Asking the brain to summarize (${[
        'Brief',
        'Medium',
        'Detailed'
      ][lvl]})…');
      await _js(
          "(() => { const b = document.querySelector('#summarize') || [...document.querySelectorAll('button')].find(x => /summarize/i.test(x.textContent || '')); if (b) b.click(); return 'ok'; })()");
      final summary = await _waitStable(
          () async => extractSummary(await _pageText()),
          seconds: 180,
          minLen: 60);
      if (summary.isEmpty)
        throw StateError(
            'Summary not readable yet. If it is visible below, tap “Capture visible summary”.');
      await widget.gateway.saveBrainSummary(widget.sessionId, summary, lvl);
      if (!mounted) return;
      setState(() => _summary = summary);
      _say('Summary saved on this device ✔ — lessons and tests will use it.');
    } catch (e) {
      _say('⚠ $e');
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _ask() async {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty || _web == null || _asking) return;
    setState(() {
      _asking = true;
      _lastQuestion = q;
    });
    try {
      if (_summary.isEmpty) {
        _say('First the brain needs the summary — doing that now…');
        await _summarize(level: 1);
        if (_summary.isEmpty)
          throw StateError(
              'Could not summarize first. Try “Upload & Summarize”, then ask again.');
      }
      _say('Asking the brain: “$q”');
      final jsQ = jsonEncode(q);
      await _js(
          "(() => { const t = document.querySelector('textarea'); if (!t) return 'no-ta'; const set = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set; set.call(t, $jsQ); t.dispatchEvent(new Event('input', {bubbles: true})); return 'ok'; })()");
      await _js(
          "(() => { const b = document.querySelector('#send-message'); if (b) { b.click(); return 'ok'; } return 'no-send'; })()");
      final before = await _pageText();
      final answer = await _waitStable(() async {
        final t = await _pageText();
        return t == before ? '' : extractAnswer(t, q);
      }, seconds: 150, minLen: 15);
      if (answer.isEmpty)
        throw StateError(
            'Answer not readable yet. If it is visible below, tap “Capture answer”.');
      await widget.gateway.addBrainQa(widget.sessionId, q, answer);
      if (!mounted) return;
      setState(() {
        _qa = [
          ..._qa,
          {'q': q, 'a': answer, 'ts': DateTime.now().millisecondsSinceEpoch}
        ];
        _questionCtrl.clear();
      });
      _say('Answer saved on this device ✔');
    } catch (e) {
      _say('⚠ $e');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _captureSummary() async {
    final s = extractSummary(await _pageText());
    if (s.isEmpty) {
      _say('⚠ No summary visible on the page yet.');
      return;
    }
    await widget.gateway.saveBrainSummary(widget.sessionId, s, _level);
    if (!mounted) return;
    setState(() => _summary = s);
    _say('Captured & saved on this device ✔');
  }

  Future<void> _captureAnswer() async {
    if (_lastQuestion.isEmpty) {
      _say('⚠ Ask a question first (type it above), then capture.');
      return;
    }
    final a = extractAnswer(await _pageText(), _lastQuestion);
    if (a.length < 10) {
      _say('⚠ No answer visible for the last question yet.');
      return;
    }
    await widget.gateway.addBrainQa(widget.sessionId, _lastQuestion, a);
    if (!mounted) return;
    setState(() => _qa = [
          ..._qa,
          {
            'q': _lastQuestion,
            'a': a,
            'ts': DateTime.now().millisecondsSinceEpoch
          }
        ]);
    _say('Captured & saved on this device ✔');
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('AI Brain (website)')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          GradientCard(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.bookTitle,
                  style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5)),
              const SizedBox(height: 6),
              Text(
                  'Your textbook is uploaded to the PDF-teacher website by automation inside this app, but the summary, answers, lessons and tests are stored and used only on THIS device — your own private brain session.',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 12.5, height: 1.45)),
              if (!_supported) ...[
                const SizedBox(height: 10),
                Text(
                    'The website brain needs an in-app browser (Android WebView / Edge WebView2). This device has none — use the on-device brain.',
                    style: TextStyle(
                        color: AppColors.amber, fontSize: 12.5, height: 1.45)),
              ],
              if (!_pdfReady) ...[
                const SizedBox(height: 10),
                Text(
                    'This textbook PDF is not on this device, so there is nothing to upload. Add/download the textbook here first.',
                    style: TextStyle(
                        color: AppColors.amber, fontSize: 12.5, height: 1.45)),
              ],
            ]),
          ),
          if (_supported) ...[
            const SectionTitle('Website (automated)'),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 380,
                color: Colors.white,
                child: InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(BrainWebViewScreen.brainUrl)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    useShouldOverrideUrlLoading: false,
                  ),
                  onWebViewCreated: (c) {
                    _web = c;
                    if (mounted) setState(() {});
                  },
                  onLoadStop: (c, url) {
                    if (!_pageReady) {
                      setState(() => _pageReady = true);
                      _say('Website brain loaded. Tap “Upload & Summarize”.');
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
                'You can watch the automation work. If it stalls, tap through manually — then use the Capture buttons.',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 12, height: 1.45)),
          ],
          const SectionTitle('Summarize'),
          GradientCard(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<int>(
                value: _level,
                dropdownColor: AppColors.card,
                style: TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                    labelText: 'Summary detail', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Brief')),
                  DropdownMenuItem(value: 1, child: Text('Medium')),
                  DropdownMenuItem(value: 2, child: Text('Detailed')),
                ],
                onChanged: (v) => setState(() => _level = v ?? 1),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: (_supported && _pdfReady && !_summarizing)
                        ? () => _summarize()
                        : null,
                    icon: _summarizing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label:
                        Text(_summarizing ? 'Working…' : 'Upload & Summarize'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                    onPressed: _web == null ? null : _captureSummary,
                    child: const Text('Capture visible summary')),
              ]),
            ]),
          ),
          if (_summary.isNotEmpty) ...[
            const SectionTitle('Summary (saved on this device)'),
            GradientCard(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                    child: Text(_summary,
                        style: TextStyle(
                            color: AppColors.text,
                            height: 1.55,
                            fontSize: 13.5))),
              ),
            ),
          ],
          const SectionTitle('Ask the brain'),
          GradientCard(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: _questionCtrl,
                style: TextStyle(color: AppColors.text),
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Your question about this PDF',
                    hintText:
                        'e.g. Explain quadratic equations with an example',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        (_supported && _pdfReady && !_asking) ? _ask : null,
                    icon: _asking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(_asking ? 'Asking…' : 'Ask'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                    onPressed: _web == null ? null : _captureAnswer,
                    child: const Text('Capture answer')),
              ]),
              if (_qa.isNotEmpty) ...[
                const SizedBox(height: 14),
                ..._qa.reversed.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Q: ${(e['q'] ?? '').toString()}',
                                style: TextStyle(
                                    color: AppColors.teal,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13)),
                            const SizedBox(height: 4),
                            Text((e['a'] ?? '').toString(),
                                style: TextStyle(
                                    color: AppColors.text,
                                    height: 1.5,
                                    fontSize: 13)),
                          ]),
                    )),
              ],
            ]),
          ),
          const SectionTitle('Automation log'),
          GradientCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _log.isEmpty
                  ? [
                      Text('Ready.',
                          style:
                              TextStyle(color: AppColors.muted, fontSize: 12.5))
                    ]
                  : _log
                      .take(8)
                      .map((l) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(l,
                              style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12.5,
                                  height: 1.4))))
                      .toList(),
            ),
          ),
        ],
      ),
    );
  }
}
