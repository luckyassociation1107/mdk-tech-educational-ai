import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai/ai_brain.dart';
import '../dart_engine.dart';
import '../engine_gateway.dart';
import '../store.dart';
import '../vault/emoji_vault.dart';
import '../ui/premium_ui.dart';
import '../widgets.dart';
import 'brain_webview_screen.dart';

/// The AI brain, in the app.
///
/// Reads this textbook's text, sends it to the free chat service the
/// PDF-teacher website uses, and streams the answer back. The summary and
/// every question/answer are saved in the student's own session folder, and
/// from then on the lesson player uses them as its key points and
/// explanations.
///
/// Works on Android and Windows. Needs internet for the AI part; the rest of
/// the app stays offline.
class BrainScreen extends StatefulWidget {
  final AppSettings settings;
  final String sessionId;
  final String bookTitle;

  /// Used by the tests: skips the network reachability probe.
  final bool? onlineOverride;
  const BrainScreen({
    super.key,
    required this.settings,
    required this.sessionId,
    required this.bookTitle,
    this.onlineOverride,
  });

  @override
  State<BrainScreen> createState() => _BrainScreenState();
}

class _BrainScreenState extends State<BrainScreen> {
  final _questionCtrl = TextEditingController();
  final _scroll = ScrollController();

  String _bookText = '';
  bool _loading = true;
  bool _online = false;
  int _level = 1;
  bool _busy = false;
  String _streaming = '';
  String _summary = '';
  List<Map<String, dynamic>> _qa = [];
  String _status = '';
  String? _error;
  BrainCancel? _cancel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _questionCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // A broken/missing session must still open the screen (and explain
    // itself) instead of leaving the user on a spinner.
    String text = '';
    Map<String, dynamic> data = {'summary': '', 'level': 1, 'qa': <dynamic>[]};
    try {
      if (widget.sessionId.isEmpty) throw StateError('no session');
      final index = await DartEngine.loadIndex(widget.sessionId);
      if (index != null) {
        text = List.generate(index.pages.length, (i) => index.pageText(i + 1))
            .join('\n\n');
      }
    } catch (_) {}
    try {
      if (widget.sessionId.isEmpty) throw StateError('no session');
      data = await DartEngine.loadBrainData(widget.sessionId);
    } catch (_) {}
    final online = widget.onlineOverride ?? await AiBrain.reachable();
    if (!mounted) return;
    setState(() {
      _bookText = text.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
      _summary = (data['summary'] ?? '').toString();
      _level = (data['level'] as num?)?.toInt() ?? 1;
      _qa = ((data['qa'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      _online = online;
      _loading = false;
      _status = online
          ? 'Brain ready · ${_chars()} of textbook text'
          : 'No AI key yet — add one in Settings → AI & Prompts. Lessons still work offline.';
    });
  }

  String _chars() {
    final n = _bookText.length;
    return n > 1000
        ? '${(n / 1000).toStringAsFixed(1)}k characters'
        : '$n characters';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _runSummary() async {
    if (_busy) return;
    if (_bookText.length < 40) {
      setState(() => _error = 'This textbook has no readable text to send.');
      return;
    }
    final cancel = BrainCancel();
    setState(() {
      _busy = true;
      _error = null;
      _streaming = '';
      _cancel = cancel;
      _status = 'Asking the brain for a summary…';
    });
    try {
      final result = await AiBrain.summarize(
        _bookText,
        level: _level,
        cancel: cancel,
        onChunk: (c) {
          if (!mounted) return;
          setState(() => _streaming += c);
          _scrollToEnd();
        },
      );
      await DartEngine.saveBrainSummary(widget.sessionId, result, _level);
      await VaultStore.log(
          'brain', 'AI summary saved (${result.length} chars)');
      if (!mounted) return;
      setState(() {
        _summary = result;
        _streaming = '';
        _busy = false;
        _status =
            'Saved on this device ✔ — lessons now start from this summary.';
      });
    } on BrainException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _streaming = '';
        _error = '$e';
        _status = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _streaming = '';
        _error = 'Unexpected error: $e';
      });
    } finally {
      _cancel = null;
    }
  }

  Future<void> _ask() async {
    final q = _questionCtrl.text.trim();
    if (_busy || q.isEmpty) return;
    final cancel = BrainCancel();
    setState(() {
      _busy = true;
      _error = null;
      _streaming = '';
      _cancel = cancel;
      _status = 'Asking: “$q”';
    });
    try {
      final answer = await AiBrain.ask(
        pdfText: _bookText,
        question: q,
        summary: _summary.isEmpty ? null : _summary,
        cancel: cancel,
        onChunk: (c) {
          if (!mounted) return;
          setState(() => _streaming += c);
          _scrollToEnd();
        },
      );
      await DartEngine.addBrainQa(widget.sessionId, q, answer);
      await VaultStore.log('brain',
          'AI answer saved for: ${q.length > 40 ? q.substring(0, 40) : q}');
      if (!mounted) return;
      setState(() {
        _qa = [
          ..._qa,
          {'q': q, 'a': answer, 'ts': DateTime.now().millisecondsSinceEpoch}
        ];
        _questionCtrl.clear();
        _streaming = '';
        _busy = false;
        _status = 'Answer saved ✔ — it is now part of this chapter.';
      });
      _scrollToEnd();
    } on BrainException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _streaming = '';
        _error = '$e';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _streaming = '';
        _error = 'Unexpected error: $e';
      });
    } finally {
      _cancel = null;
    }
  }

  void _stop() {
    _cancel?.cancel();
    setState(() {
      _busy = false;
      _streaming = '';
      _status = 'Stopped.';
    });
  }

  Future<void> _clear() async {
    await DartEngine.clearBrainData(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _summary = '';
      _qa = [];
      _status = 'Brain data cleared. Lessons fall back to the textbook text.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('🧠 AI Brain',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Website mode (Android)',
            onPressed: _loading
                ? null
                : () async {
                    await Navigator.of(context).push(PageTransition.route(
                      BrainWebViewScreen(
                        gateway: EngineGateway(),
                        settings: widget.settings,
                        sessionId: widget.sessionId,
                        bookTitle: widget.bookTitle,
                      ),
                    ));
                    if (mounted) _load();
                  },
            icon: Icon(Icons.public_rounded, size: 19, color: AppColors.muted),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : AuroraBackground(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
                children: [
                  GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color:
                                  _online ? AppColors.green : AppColors.amber,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.bookTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 7),
                        Text(
                          'Reads this book on your phone, sends only the text to the free AI service, '
                          'and saves the reply here. Works on Android and Windows.',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                              height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.notes_rounded,
                              size: 13, color: AppColors.muted),
                          const SizedBox(width: 5),
                          Text(_chars(),
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 11)),
                          const Spacer(),
                          if (_summary.isNotEmpty)
                            Text('summary saved',
                                style: TextStyle(
                                    color: AppColors.teal,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                        ]),
                      ],
                    ),
                  ),
                  const SectionTitle('1 · Summary'),
                  Row(
                    children: [
                      for (final l in const [
                        [0, 'Brief'],
                        [1, 'Medium'],
                        [2, 'Detailed']
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GlassCard(
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _level = l[0] as int),
                              tint: _level == l[0] ? AppColors.teal : null,
                              alpha: _level == l[0] ? 0.18 : 0.06,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              child: Center(
                                child: Text(
                                  l[1] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: _level == l[0]
                                        ? AppColors.teal
                                        : AppColors.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy || !_online ? null : _runSummary,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                      label: Text(_summary.isEmpty
                          ? 'Summarize this book with AI'
                          : 'Summarize again'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionTitle('2 · Ask the book'),
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                    child: Column(children: [
                      TextField(
                        controller: _questionCtrl,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(fontSize: 13),
                        decoration: const InputDecoration(
                          hintText:
                              'e.g. Explain photosynthesis with an example',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _ask(),
                      ),
                      Row(children: [
                        Expanded(
                          child: Text('Answers are saved and used in lessons',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 10.5)),
                        ),
                        FilledButton(
                          onPressed: _busy || !_online ? null : _ask,
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.teal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 10)),
                          child: const Text('Ask',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                      ]),
                    ]),
                  ),
                  if (_status.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(children: [
                        if (_busy)
                          const SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        if (_busy) const SizedBox(width: 8),
                        Expanded(
                          child: Text(_status,
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 11.5)),
                        ),
                        if (_busy)
                          TextButton(
                              onPressed: _stop, child: const Text('stop')),
                      ]),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    GlassCard(
                      tint: AppColors.red,
                      alpha: 0.12,
                      padding: const EdgeInsets.all(13),
                      child: Row(children: [
                        Icon(Icons.error_outline_rounded,
                            size: 17, color: AppColors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(
                                  color: AppColors.red,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                  ],
                  if (_streaming.isNotEmpty) ...[
                    const SectionTitle('Writing…'),
                    GlassCard(
                      child: SelectableText(
                        _streaming,
                        style: const TextStyle(fontSize: 12.5, height: 1.55),
                      ),
                    ),
                  ],
                  if (_summary.isNotEmpty) ...[
                    const SectionTitle('Saved summary'),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(_summary,
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.55)),
                          const SizedBox(height: 10),
                          Row(children: [
                            Icon(Icons.school_rounded,
                                size: 14, color: AppColors.teal),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Lessons, podcasts and tests now use these points.',
                                style: TextStyle(
                                    color: AppColors.muted, fontSize: 10.5),
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await Clipboard.setData(
                                    ClipboardData(text: _summary));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Summary copied')));
                              },
                              icon: Icon(Icons.copy_rounded,
                                  size: 16, color: AppColors.muted),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ],
                  if (_qa.isNotEmpty) ...[
                    SectionTitle('Q&A (${_qa.length})',
                        action: 'clear', onAction: _clear),
                    ..._qa.reversed.take(12).map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: GlassCard(
                            padding: const EdgeInsets.all(13),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Q. ${p['q']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5)),
                                const SizedBox(height: 6),
                                SelectableText('${p['a']}',
                                    style: const TextStyle(
                                        fontSize: 12, height: 1.5)),
                              ],
                            ),
                          ),
                        )),
                  ],
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(13),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The AI runs on a free public service — no account, no key, no payment. '
                          'It needs internet and can be busy sometimes; the book, lessons and tests '
                          'keep working without it.',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 10.8,
                              height: 1.5),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }
}
