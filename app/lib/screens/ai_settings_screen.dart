import 'package:flutter/material.dart';

import '../ai/ai_client.dart';
import '../ai/ai_config.dart';
import '../ai/ai_prompts.dart';
import '../ai/ai_service.dart';
import '../ai/web_ai_engine.dart';
import '../widgets.dart';

/// Where the teacher plugs in the AI that reads the textbook.
///
/// The app no longer parses the PDF on the device: the PDF is uploaded to
/// this account, with the prompts below, and the model answers with the
/// page text, the figure boxes and the lesson script.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late AiConfig _cfg;
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _base = TextEditingController();
  final _extract = TextEditingController();
  final _script = TextEditingController();
  final _ask = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _reveal = false;
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
      _key.text = cfg.apiKey;
      _model.text = cfg.model;
      _base.text = cfg.baseUrl;
      _extract.text = cfg.extractPrompt;
      _script.text = cfg.scriptPrompt;
      _ask.text = cfg.askPrompt;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _base.dispose();
    _extract.dispose();
    _script.dispose();
    _ask.dispose();
    super.dispose();
  }

  AiConfig get _edited => _cfg.copyWith(
        provider: _cfg.provider,
        apiKey: _key.text.trim(),
        model: _model.text.trim(),
        baseUrl: _base.text.trim(),
        extractPrompt: _extract.text.trim().isEmpty ? AiPrompts.extract : _extract.text,
        scriptPrompt: _script.text.trim().isEmpty ? AiPrompts.script : _script.text,
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
        .showSnackBar(const SnackBar(content: Text('AI settings saved')));
  }

  Future<void> _test() async {
    final cfg = _edited;
    if (!cfg.ready) {
      setState(() {
        _testOk = false;
        _testResult = cfg.mode == AiMode.webview
            ? 'Free mode runs on Android only — on Windows add your own key.'
            : 'Paste an API key first.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _testResult = 'Calling ${cfg.provider.label}…';
      _testOk = false;
    });
    try {
      final out = await AiService.test(cfg);
      if (!mounted) return;
      setState(() {
        _testOk = out.toUpperCase().contains('READY');
        _testResult = _testOk
            ? (cfg.mode == AiMode.webview
                ? 'The free website answered "READY". Nothing to pay.'
                : 'Connected to ${cfg.provider.label} — the model replied "READY".')
            : 'The AI answered something unexpected: "${out.length > 80 ? out.substring(0, 80) : out}"';
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

  void _applyProvider(AiProvider p) {
    setState(() {
      _cfg = _cfg.copyWith(provider: p);
      _model.text = p.defaultModel;
      _base.text = p.defaultBaseUrl;
      _testResult = null;
    });
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.auto_awesome_rounded, color: p.accent, size: 18),
                    const SizedBox(width: 8),
                    Text('The AI reads your PDF',
                        style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Nothing is parsed on the device. The PDF goes to the AI with the '
                    'extraction prompt below; it answers with the page text and where each '
                    'figure sits. The app then finds the figure box from the page pixels, '
                    'cuts it out with PDFium and paints the lesson locally.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.3, height: 1.5),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              _card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('HOW TO REACH THE AI', style: _label()),
                  const SizedBox(height: 8),
                  _modeTile(
                    AiMode.webview,
                    'Free — automate the website',
                    'No key, no account, no cost. Drives the public PDF-teacher '
                        'website inside the app (Android).',
                    Icons.credit_card_off_rounded,
                  ),
                  const SizedBox(height: 8),
                  _modeTile(
                    AiMode.api,
                    'My own API key',
                    'OpenAI / Gemini / Claude. Works on Windows too and can see '
                        'the page images. Costs per book on your account.',
                    Icons.key_rounded,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _cfg.mode == AiMode.webview
                        ? 'Free mode uses the same prompts below and the same lesson '
                            'pipeline — only the AI behind them changes.'
                        : 'Your key is stored in the device keystore.',
                    style: TextStyle(
                        color: AppColors.muted, fontSize: 11, height: 1.4),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              if (_cfg.mode == AiMode.api)
              _card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PROVIDER', style: _label()),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<AiProvider>(
                    value: _cfg.provider,
                    dropdownColor: AppColors.card,
                    items: [
                      for (final pr in AiProvider.values)
                        DropdownMenuItem(value: pr, child: Text(pr.label)),
                    ],
                    onChanged: (v) {
                      if (v != null) _applyProvider(v);
                    },
                  ),
                  const SizedBox(height: 14),
                  Text('API KEY (stored in the device keystore)', style: _label()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _key,
                    obscureText: !_reveal,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: _cfg.provider.keyHint,
                      suffixIcon: IconButton(
                        icon: Icon(
                            _reveal
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: AppColors.muted),
                        onPressed: () => setState(() => _reveal = !_reveal),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('MODEL', style: _label()),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _model,
                    decoration: InputDecoration(
                        hintText: _cfg.provider.defaultModel),
                  ),
                  if (_cfg.provider == AiProvider.custom) ...[
                    const SizedBox(height: 14),
                    Text('BASE URL', style: _label()),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _base,
                      decoration:
                          const InputDecoration(hintText: 'https://api.example.com'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _test,
                        icon: _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering_rounded, size: 17),
                        label: const Text('Test connection'),
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
                              color: _testOk ? Colors.greenAccent : AppColors.red,
                              fontSize: 12)),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              _promptCard(
                'PDF EXTRACTION PROMPT',
                'Sent with the PDF. Must return the JSON the app expects '
                    '(title, subject, pages[{page, text, figures[{caption, bbox}]}]). '
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
                'Tip: if a book shows "the AI could not read any page", the PDF may be a '
                'scan. Use a vision-capable model (Gemini, GPT-4.1, Claude) — the PDF is '
                'uploaded as a file, so the model can see the pages itself.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
              ),
            ]),
    );
  }

  Widget _modeTile(AiMode mode, String title, String help, IconData icon) {
    final on = _cfg.mode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        _cfg = _cfg.copyWith(mode: mode);
        _testResult = null;
      }),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? AppColors.palette.primary.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: on ? AppColors.palette.primary : AppColors.stroke,
              width: on ? 1.6 : 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 18,
              color: on ? AppColors.palette.primary : AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(help,
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 11, height: 1.4)),
            ]),
          ),
          if (on)
            Icon(Icons.check_circle_rounded,
                size: 17, color: AppColors.palette.primary),
        ]),
      ),
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

  Widget _promptCard(String title, String help, TextEditingController c) =>
      _card(
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
            style: const TextStyle(fontSize: 12, height: 1.45, fontFamily: 'monospace'),
            decoration: const InputDecoration(contentPadding: EdgeInsets.all(10)),
          ),
        ]),
      );
}
