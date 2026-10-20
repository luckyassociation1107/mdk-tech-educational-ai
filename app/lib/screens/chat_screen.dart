import 'package:flutter/material.dart';

import '../ai/ai_brain.dart';
import '../dart_engine.dart';
import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'brain_webview_screen.dart';

class ChatScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  final TextbookItem book;
  const ChatScreen(
      {super.key,
      required this.gateway,
      required this.settings,
      required this.book});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMsg> _msgs = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _msgs.add(ChatMsg('assistant',
        'Ask me anything from “${widget.book.shortTitle}”. I will answer from your textbook only — try “Explain the main idea in simple words” or “Give an example”.'));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _busy) return;
    setState(() {
      _msgs.add(ChatMsg('user', q));
      _input.clear();
      _busy = true;
    });
    _jump();
    try {
      // 1) Online AI brain (same free service the PDF website uses).
      final index = await DartEngine.loadIndex(widget.book.sessionId);
      final bookText = index == null
          ? ''
          : List.generate(index.pages.length, (i) => index.pageText(i + 1))
              .join('\n\n');
      String? aiAnswer;
      if (bookText.trim().length > 40) {
        final brainData = await DartEngine.loadBrainData(widget.book.sessionId);
        try {
          aiAnswer = await AiBrain.ask(
            pdfText: bookText,
            question: q,
            summary: (brainData['summary'] ?? '').toString(),
          );
        } on BrainException {
          aiAnswer = null; // offline → fall through to the book search
        }
      }
      // 2) Offline fallback: the textbook's own sentences with page numbers.
      final out = aiAnswer == null
          ? await widget.gateway.askChat(
              sessionId: widget.book.sessionId,
              question: q,
              brain: widget.settings.brain,
              brainServerUrl: widget.settings.brainServerUrl,
            )
          : {'answer': aiAnswer};
      if (!mounted) return;
      setState(() {
        _msgs.add(ChatMsg('assistant', (out['answer'] ?? '').toString()));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgs
            .add(ChatMsg('assistant', 'I could not answer that right now: $e'));
        _busy = false;
      });
    }
    _jump();
  }

  void _jump() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients)
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        actions: [
          if (widget.settings.brain == 'website')
            IconButton(
              tooltip: 'AI Brain (website)',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BrainWebViewScreen(
                    gateway: widget.gateway,
                    settings: widget.settings,
                    sessionId: widget.book.sessionId,
                    bookTitle: widget.book.shortTitle),
              )),
              icon: const Icon(Icons.psychology_rounded),
            ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ask PDF', style: TextStyle(fontWeight: FontWeight.w900)),
          Text(widget.book.shortTitle,
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            itemCount: _msgs.length + (_busy ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= _msgs.length) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Reading your textbook…',
                          style: TextStyle(color: AppColors.muted)),
                    ]),
                  ),
                );
              }
              final m = _msgs[i];
              return Align(
                alignment:
                    m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82),
                  decoration: BoxDecoration(
                    gradient: m.isUser ? AppColors.accentGradient : null,
                    color: m.isUser ? null : AppColors.card,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(m.isUser ? 18 : 6),
                      bottomRight: Radius.circular(m.isUser ? 6 : 18),
                    ),
                    border:
                        m.isUser ? null : Border.all(color: AppColors.stroke),
                  ),
                  child: SelectableText(m.content,
                      style: TextStyle(color: AppColors.text, height: 1.45)),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
          decoration: BoxDecoration(
              color: AppColors.bg2,
              border: Border(top: BorderSide(color: AppColors.stroke))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(color: AppColors.text),
                decoration: const InputDecoration(
                    hintText: 'Ask PDF…', border: OutlineInputBorder()),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _busy ? null : _send,
              style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14)),
              child: const Icon(Icons.arrow_upward_rounded),
            ),
          ]),
        ),
      ]),
    );
  }
}
