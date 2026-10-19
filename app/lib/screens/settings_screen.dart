import 'package:flutter/material.dart';

import '../catalog_service.dart';
import '../nostr_crypto.dart';
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
  late final TextEditingController _catalogForm;
  late final TextEditingController _catalogEntry;
  late final TextEditingController _catalogSheet;
  late final TextEditingController _nostrNsec;
  late final TextEditingController _nostrNpub;
  late final TextEditingController _catalogSecret;
  String? _ttsInfo;
  String? _catalogInfo;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.settings.brainServerUrl);
    _catalogForm = TextEditingController(text: widget.settings.catalogFormUrl);
    _catalogEntry = TextEditingController(text: widget.settings.catalogEntryId);
    _catalogSheet = TextEditingController(text: widget.settings.catalogSheetUrl);
    _nostrNsec = TextEditingController(text: widget.settings.catalogNsec);
    _nostrNpub = TextEditingController(text: widget.settings.catalogNpub);
    _catalogSecret = TextEditingController(text: widget.settings.catalogSecret);
  }

  @override
  void dispose() {
    _url.dispose();
    _catalogForm.dispose();
    _catalogEntry.dispose();
    _catalogSheet.dispose();
    _nostrNsec.dispose();
    _nostrNpub.dispose();
    _catalogSecret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    widget.settings.brainServerUrl = _url.text.trim();
    widget.settings.catalogFormUrl = _catalogForm.text.trim();
    widget.settings.catalogEntryId = _catalogEntry.text.trim();
    widget.settings.catalogSheetUrl = _catalogSheet.text.trim();
    widget.settings.catalogNsec = _nostrNsec.text.trim();
    widget.settings.catalogNpub = _nostrNpub.text.trim();
    widget.settings.catalogSecret = _catalogSecret.text.trim();
    await widget.settings.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  void _deriveNpub() {
    final nsec = _nostrNsec.text.trim();
    if (NostrCrypto.isHexKey(nsec)) {
      try {
        setState(() => _nostrNpub.text = NostrCrypto.pubkeyHex(nsec));
      } catch (_) {}
    }
  }

  void _generateKey() {
    final sk = NostrCrypto.generateSecretHex();
    setState(() {
      _nostrNsec.text = sk;
      _nostrNpub.text = NostrCrypto.pubkeyHex(sk);
      _catalogInfo = 'New catalog key created. Save, then share ONLY the public key (npub) with student devices; keep the private key (nsec) on teacher/principal devices.';
    });
  }

  Future<void> _testCatalog() async {
    await _save();
    setState(() => _catalogInfo = 'Checking cloud catalog…');
    final entries = await CatalogService.fetch(widget.settings);
    if (!mounted) return;
    setState(() => _catalogInfo = entries.isEmpty
        ? 'No entries read yet. Check the Sheet link is shared as “Anyone with the link can view”, then try again after a teacher shares a PDF.'
        : 'Cloud catalog OK — ${entries.length} link(s) found. Latest: ${entries.first.t}');
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
          const SectionTitle('Cloud link catalog'),
          GradientCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'When a teacher adds a textbook PDF it is automatically uploaded to Gofile, and its link is stored in one shared catalog (a Google Form feeding a Google Sheet). Student devices read the catalog, so every shared link appears everywhere. Entries are stored encoded — nothing readable shows on any public page. Full setup: CATALOG-SETUP.md in the project.',
                  style: TextStyle(color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 12),
              const Text('Nostr catalog (recommended — free, unlimited, no account):',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _nostrNsec,
                onChanged: (_) => _deriveNpub(),
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Catalog private key — nsec (teacher/principal devices only)', hintText: '64-char hex', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nostrNpub,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Catalog public key — npub (share with every device)', hintText: 'auto-filled from the private key', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _catalogSecret,
                obscureText: true,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Catalog secret (every device — students too)', hintText: 'school-only secret phrase; entries are encrypted with this', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _generateKey, icon: const Icon(Icons.key_rounded), label: const Text('Create new catalog key (founder, once)')),
              const SizedBox(height: 6),
              const Text('With a catalog secret set, every entry is AES-256 encrypted on this phone before publishing — outside the app the catalog is unreadable ciphertext; only devices with this secret see the real titles and links. Share the public key (npub) + secret with all school devices; the private key (nsec) only with staff.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
              const SizedBox(height: 14),
              const Text('Legacy option — Google Form/Sheet (optional):',
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _catalogForm,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Catalog Form link (viewform URL)', hintText: 'https://docs.google.com/forms/d/e/…/viewform', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _catalogEntry,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Form entry id', hintText: 'entry.123456789', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _catalogSheet,
                style: const TextStyle(color: AppColors.text),
                decoration: const InputDecoration(labelText: 'Catalog Sheet link', hintText: 'https://docs.google.com/spreadsheets/d/…', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _testCatalog, icon: const Icon(Icons.cloud_done_rounded), label: const Text('Test catalog read')),
              if (_catalogInfo != null) ...[
                const SizedBox(height: 10),
                Text(_catalogInfo!, style: const TextStyle(color: AppColors.teal, height: 1.45)),
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
