import 'package:flutter/material.dart';

import '../engine_gateway.dart';
import '../store.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;
  String? _ttsInfo;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.settings.brainServerUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    widget.settings.brainServerUrl = _url.text.trim();
    await widget.settings.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _checkVoice() async {
    final gw = EngineGateway();
    final r = await gw.checkTts(widget.settings.language);
    if (!mounted) return;
    setState(() => _ttsInfo = r['available'] == true
        ? 'A device voice is available for ${widget.settings.language}.'
        : 'No device voice found for ${widget.settings.language}. Install it in Android Settings → Languages → Text-to-speech, or keep captions on.');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          const SectionTitle('Learning'),
          GradientCard(
            child: Column(children: [
              _dropdown('Narration language', s.language, const {'en-IN': 'English (India)', 'te-IN': 'Telugu (India)'},
                  (v) => setState(() => s.language = v)),
              _dropdown('Pages per part', '${s.pagesPerPart}', const {'4': '4 pages', '6': '6 pages', '8': '8 pages'},
                  (v) => setState(() => s.pagesPerPart = int.parse(v))),
              _dropdown('Video quality', s.resolution, const {'854x480': '480p — faster on phone', '1280x720': '720p HD — slower, sharper'},
                  (v) => setState(() => s.resolution = v)),
              _dropdown(
                  'Board style',
                  s.theme,
                  const {
                    'auto': 'Auto — teacher changes boards',
                    'green_board': 'Green board',
                    'black_board': 'Black board',
                    'white_board': 'White board',
                    'ruled_board': 'Ruled notebook',
                    'graph_board': 'Graph board',
                  },
                  (v) => setState(() => s.theme = v)),
            ]),
          ),
          const SectionTitle('AI brain'),
          GradientCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _dropdown(
                  'Brain mode',
                  s.brain,
                  const {
                    'offline': 'On-device (works without a server)',
                    'playwright': 'Online AI brain (needs brain server)',
                  },
                  (v) => setState(() => s.brain = v)),
              if (s.brain == 'playwright') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _url,
                  style: const TextStyle(color: AppColors.text),
                  decoration: const InputDecoration(
                    labelText: 'Brain server URL',
                    hintText: 'http://192.168.1.5:3000',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('The online brain is the PDF-teacher website service. Your PDF is sent there for teaching content; videos are still rendered on this phone.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.45)),
              ],
            ]),
          ),
          const SectionTitle('Voice'),
          GradientCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Teacher voice uses this phone’s Text-to-Speech for on-device narration. Check that a voice exists for your language:',
                  style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _checkVoice, icon: const Icon(Icons.record_voice_over_rounded), label: const Text('Check device voice')),
              if (_ttsInfo != null) ...[
                const SizedBox(height: 10),
                Text(_ttsInfo!, style: const TextStyle(color: AppColors.teal, height: 1.45)),
              ],
            ]),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_rounded), label: const Text('Save settings')),
        ],
      ),
    );
  }

  Widget _dropdown(String label, String value, Map<String, String> options, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700))),
        DropdownButton<String>(
          value: options.containsKey(value) ? value : options.keys.first,
          dropdownColor: AppColors.cardLight,
          style: const TextStyle(color: AppColors.text),
          underline: const SizedBox.shrink(),
          items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ]),
    );
  }
}
