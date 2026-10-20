import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store.dart';
import '../translate_service.dart';
import '../widgets.dart';

/// Voice Studio — picks the exact device voice, tunes speed and pitch and
/// previews it, so the teacher's voice sounds right for the student.
class VoiceStudioScreen extends StatefulWidget {
  final AppSettings settings;
  const VoiceStudioScreen({super.key, required this.settings});

  @override
  State<VoiceStudioScreen> createState() => _VoiceStudioScreenState();
}

class _VoiceStudioScreenState extends State<VoiceStudioScreen> {
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  List<Map<String, dynamic>> _voices = const [];
  bool _loading = true;
  bool _noVoices = false;

  @override
  void initState() {
    super.initState();
    _list();
  }

  Future<void> _list() async {
    setState(() {
      _loading = true;
      _noVoices = false;
    });
    try {
      final raw = await _ttsCh.invokeMethod<List<dynamic>>('listVoices', {'language': widget.settings.language});
      final out = <Map<String, dynamic>>[];
      for (final v in raw ?? const []) {
        if (v is Map) out.add(v.map((k, val) => MapEntry(k.toString(), val)));
      }
      if (!mounted) return;
      setState(() {
        _voices = out;
        _loading = false;
        _noVoices = out.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _noVoices = true;
      });
    }
  }

  Future<void> _preview({String? voice}) async {
    final sample = widget.settings.explainLanguage == 'en'
        ? 'Hello! This is your teacher voice. Every word on the board is spoken exactly as it is written.'
        : 'Hello! This is your teacher voice. ${xLang(widget.settings.explainLanguage).english} explanation will be read in this voice.';
    await _ttsCh.invokeMethod('speak', {
      'text': sample,
      'language': widget.settings.language,
      'rate': widget.settings.speechRate,
      'pitch': widget.settings.speechPitch,
      'voice': voice ?? widget.settings.voiceName,
    }).catchError((_) => null);
  }

  String _title(Map<String, dynamic> v) {
    final name = (v['name'] ?? '').toString();
    final parts = name.split('#');
    final short = parts.length > 1 ? parts[1] : name;
    final loc = (v['locale'] ?? '').toString();
    return '$short • $loc';
  }

  String _sub(Map<String, dynamic> v) {
    final bits = <String>[];
    final q = (v['quality'] as num?)?.toInt() ?? 0;
    bits.add(q >= 400 ? 'high quality' : q >= 300 ? 'normal' : 'basic');
    if (v['network'] == true) bits.add('needs internet');
    if (v['notInstalled'] == true) bits.add('not installed');
    return bits.join(' • ');
  }

  @override
  void dispose() {
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title:  Text('Voice Studio', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
        actions: [
          IconButton(onPressed: () => _preview(), icon:  Icon(Icons.play_circle_rounded, color: AppColors.teal, size: 28)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          GradientCard(
            gradient: AppColors.heroGradient,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your teacher’s voice', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Speed and pitch change how the voice feels — a slower voice is easier for hard chapters, a fuller pitch sounds warmer.',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.45)),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.speed_rounded, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text('${(s.speechRate * 100).round()}% speed',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
              Slider(
                value: s.speechRate.clamp(0.5, 1.5).toDouble(),
                min: 0.5,
                max: 1.5,
                divisions: 20,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (v) => setState(() => s.speechRate = v),
                onChangeEnd: (_) {
                  s.save();
                  _preview();
                },
              ),
              Row(children: [
                const Icon(Icons.graphic_eq_rounded, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text('Pitch ${s.speechPitch.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
              ]),
              Slider(
                value: s.speechPitch.clamp(0.7, 1.3).toDouble(),
                min: 0.7,
                max: 1.3,
                divisions: 12,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (v) => setState(() => s.speechPitch = v),
                onChangeEnd: (_) {
                  s.save();
                  _preview();
                },
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      s.speechRate = 0.92;
                      s.speechPitch = 1.0;
                      s.save();
                      setState(() {});
                      _preview();
                    },
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Reset'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _preview(),
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: const Text('Test'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.indigo),
                  ),
                ),
              ]),
            ]),
          ),
          const SectionTitle('Installed voices'),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_noVoices)
             GradientCard(
              child: Text(
                'No voices reported by this device. Android → Settings → Language & input → Text-to-speech → install a voice for this language.',
                style: TextStyle(color: AppColors.muted, height: 1.45, fontSize: 12.5),
              ),
            )
          else ...[
            GradientCard(
              onTap: () {
                setState(() => s.voiceName = '');
                s.save();
                _preview(voice: '');
              },
              child: Row(children: [
                Icon(s.voiceName.isEmpty ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    color: AppColors.teal, size: 20),
                const SizedBox(width: 10),
                 Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('System default', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13.5)),
                    Text('Let Android choose the best voice', style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            ..._voices.map((v) {
              final name = (v['name'] ?? '').toString();
              final sel = name == s.voiceName;
              final bad = v['notInstalled'] == true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Opacity(
                  opacity: bad ? 0.5 : 1,
                  child: GradientCard(
                    onTap: bad
                        ? null
                        : () {
                            setState(() => s.voiceName = name);
                            s.save();
                            _preview(voice: name);
                          },
                    child: Row(children: [
                      Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                          color: sel ? AppColors.teal : AppColors.muted, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_title(v),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 13)),
                          Text(_sub(v), style:  TextStyle(color: AppColors.muted, fontSize: 11)),
                        ]),
                      ),
                       Icon(Icons.play_arrow_rounded, color: AppColors.muted, size: 18),
                    ]),
                  ),
                ),
              );
            }),
             GradientCard(
              child: Text(
                'Tip: a voice marked “needs internet” sounds better but stops working offline. '
                'For an offline class, choose a voice without that label.',
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
