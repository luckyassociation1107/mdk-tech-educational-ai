import 'package:flutter/material.dart';

import '../ai/ai_config.dart';
import '../ai/ai_prompts.dart';
import '../ai/ai_service.dart';
import '../ai/web_ai_engine.dart';
import '../widgets.dart';

/// The only AI settings there are: the three prompts.
///
/// There is no key, no provider and no model to choose, because the app does
/// not call a paid API — it drives the free PDF-teacher website inside its own
/// WebView. Nothing here costs money.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late AiConfig _cfg;
  final _extract = TextEditingController();
  final _script = TextEditingController();
  final _ask = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await AiConfig.load();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _extract.text = cfg.extractPrompt;
      _script.text = cfg.scriptPrompt;
      _ask.text = cfg.askPrompt;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _extract.dispose();
    _script.dispose();
    _ask.dispose();
    super.dispose();
  }

  AiConfig get _edited => _cfg.copyWith(
        extractPrompt:
            _extract.text.trim().isEmpty ? AiPrompts.extract : _extract.text,
        scriptPrompt:
            _script.text.trim().isEmpty ? AiPrompts.script : _script.text,
        askPrompt: _ask.text.trim().isEmpty ? AiPrompts.ask : _ask.text,
      );

  Future<void> _save() async {
    final cfg = _edited;
    setState(() => _busy = true);
    await cfg.save();
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _busy = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Prompts saved')));
  }

  Future<void> _test() async {
    if (!WebAiEngine.instance.supported) {
      setState(() {
        _testOk = false;
        _testResult = 'The free AI needs Android — this device has no WebView.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _testResult = 'Opening the free website…';
      _testOk = false;
    });
    try {
      final out = await AiService.test();
      if (!mounted) return;
      setState(() {
        _testOk = out.toUpperCase().contains('READY');
        _testResult = _testOk
            ? 'The free website is up and waiting for a PDF. Nothing to pay.'
            : 'Unexpected answer: "${out.length > 80 ? out.substring(0, 80) : out}"';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testResult = '$e';
        _busy = false;
      });
    }
  }

  void _resetPrompts() {
    setState(() {
      _extract.text = AiPrompts.extract;
      _script.text = AiPrompts.script;
      _ask.text = AiPrompts.ask;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppColors.palette;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('AI & Prompts'),
        actions: [
          IconButton(
            tooltip: 'Reset prompts to the defaults',
            onPressed: _resetPrompts,
            icon: Icon(Icons.restart_alt_rounded, color: AppColors.muted),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              _card(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.auto_awesome_rounded, color: p.accent, size: 18),
                        const SizedBox(width: 8),
                        Text('The free AI reads your PDF',
                            style: TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 14.5)),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'The app opens the public PDF-teacher website inside its own '
                        'WebView, uploads the book there and types the prompts below. '
                        'No API key, no account, no cost — and nothing is parsed on the '
                        'device. The answers come back as page text, figure captions and '
                        'the lesson script; the app then finds each figure box in the page '
                        'pixels, cuts it out with PDFium and paints the lesson locally.',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: 12.3, height: 1.5),
                      ),
                    ]),
              ),
              const SizedBox(height: 12),
              _card(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                            WebAiEngine.instance.supported
                                ? Icons.verified_rounded
                                : Icons.error_outline_rounded,
                            color: WebAiEngine.instance.supported
                                ? AppColors.green
                                : AppColors.amber,
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            WebAiEngine.instance.supported
                                ? 'Free AI ready · Android WebView'
                                : 'Free AI needs Android',
                            style: TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 13),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(
                        WebAiEngine.instance.supported
                            ? 'Everything below is free. The same prompts are used for '
                                'the PDF, the video script and Ask PDF.'
                            : 'This device has no WebView, so the free AI cannot run here. '
                                'Read the textbook on the Android app.',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: 11.5, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _test,
                            icon: _busy
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.wifi_tethering_rounded, size: 17),
                            label: const Text('Test the free AI'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save_rounded, size: 17),
                            label: const Text('Save'),
                          ),
                        ),
                      ]),
                      if (_testResult != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (_testOk ? Colors.green : AppColors.red)
                                .withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: (_testOk ? Colors.green : AppColors.red)
                                    .withOpacity(0.4)),
                          ),
                          child: Text(_testResult!,
                              style: TextStyle(
                                  color: _testOk
                                      ? Colors.greenAccent
                                      : AppColors.red,
                                  fontSize: 12)),
                        ),
                      ],
                    ]),
              ),
              const SizedBox(height: 12),
              _promptCard(
                'PDF EXTRACTION PROMPT',
                'Sent with the PDF. Must return the JSON the app expects '
                    '(title, subject, pages[{page, text, figures[{caption, where}]}]). '
                    'Keep {start}, {end} and {total} so big books are read in batches.',
                _extract,
              ),
              const SizedBox(height: 12),
              _promptCard(
                'VIDEO SCRIPT PROMPT',
                'This is what makes the lesson. Placeholders: {title} {subject} '
                    '{language} {grade} {part} {pages} {teacher_note} {content} {figures}.',
                _script,
              ),
              const SizedBox(height: 12),
              _promptCard(
                'DOUBT-ANSWERING PROMPT',
                'Used by Ask PDF and the AI Brain. Placeholders: {title} {pages} '
                    '{content} {question} {language}.',
                _ask,
              ),
              const SizedBox(height: 16),
              Text(
                'Tip: the free AI reads text, not pictures. A scanned book (photos of '
                'pages) cannot be read, and figure boxes are measured on the device, so '
                'charts, photos and boxed diagrams come out best.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
              ),
            ]),
    );
  }

  TextStyle _label() => TextStyle(
      color: AppColors.muted,
      fontSize: 10.5,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.1);

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.stroke),
        ),
        child: child,
      );

  Widget _promptCard(String title, String help, TextEditingController c) => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: _label()),
          const SizedBox(height: 6),
          Text(help,
              style:
                  TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45)),
          const SizedBox(height: 10),
          TextField(
            controller: c,
            minLines: 6,
            maxLines: 14,
            style: const TextStyle(
                fontSize: 12, height: 1.45, fontFamily: 'monospace'),
            decoration: const InputDecoration(contentPadding: EdgeInsets.all(10)),
          ),
        ]),
      );
}
