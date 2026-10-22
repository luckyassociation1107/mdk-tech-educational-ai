import 'package:flutter/material.dart';

import '../store.dart';
import '../speech/neural_tts.dart';
import '../speech/online_voice.dart';
import '../translate_service.dart';
import '../widgets.dart';
import '../speech/speech_channel.dart';

/// Voice Studio — picks the exact device voice, tunes speed and pitch and
/// previews it, so the teacher's voice sounds right for the student.
class VoiceStudioScreen extends StatefulWidget {
  final AppSettings settings;
  const VoiceStudioScreen({super.key, required this.settings});

  @override
  State<VoiceStudioScreen> createState() => _VoiceStudioScreenState();
}

class _VoiceStudioScreenState extends State<VoiceStudioScreen> {
  static const SpeechChannel _ttsCh = SpeechChannel();
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
      final raw = await _ttsCh.invokeMethod<List<dynamic>>(
          'listVoices', {'language': widget.settings.language});
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

  String _engineResult = '';
  bool _engineBusy = false;

  /// Speaks a short sample with the chosen engine, so the teacher hears the
  /// difference before starting a class.
  Future<void> _testEngine(String engine) async {
    final lang = widget.settings.explainLanguage;
    setState(() {
      _engineBusy = true;
      _engineResult = '';
    });
    try {
      if (engine == 'device') {
        final r = await _ttsCh.invokeMethod('checkTts', {'language': lang});
        final ok = r is Map && r['available'] == true;
        if (mounted) {
          setState(() {
            _engineResult = ok
                ? 'The device has a voice for this language.'
                : 'This device has no voice for it yet — install it in the '
                    'system Text-to-speech settings, or switch to the online voice.';
          });
        }
      } else {
        final r = await OnlineVoice.instance.selfTest(_ttsCodeFor(lang),
            neuralVoice: widget.settings.neuralVoice.isEmpty
                ? null
                : widget.settings.neuralVoice);
        if (mounted) {
          setState(() {
            _engineResult = r.startsWith('OK')
                ? 'Online voice works for this language (${r.substring(3)}).'
                : 'Online voice could not be reached right now. The class will '
                    'fall back to the device voice.';
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _engineResult = '$e');
    } finally {
      if (mounted) setState(() => _engineBusy = false);
    }
  }

  String _ttsCodeFor(String code) => code;

  Future<void> _stopAll() async {
    await _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    await OnlineVoice.instance.stop().catchError((_) {});
  }

  Future<void> _preview({String? voice}) async {
    await _stopAll();
    final sample = widget.settings.explainLanguage == 'en'
        ? 'Hello! This is your teacher voice. Every word on the board is spoken exactly as it is written.'
        : 'Hello! This is your teacher voice. ${xLang(widget.settings.explainLanguage).english} explanation will be read in this voice.';
    final rate = widget.settings.speechRate;
    if (widget.settings.voiceEngine == 'online') {
      try {
        await OnlineVoice.instance.speak(
            text: sample,
            lang: widget.settings.explainLanguage,
            rate: rate,
            pitch: widget.settings.speechPitch,
            neuralVoice: widget.settings.neuralVoice.isEmpty
                ? null
                : widget.settings.neuralVoice);
      } catch (_) {
        await _ttsCh.invokeMethod('speak', {
          'text': sample,
          'language': widget.settings.language,
          'rate': rate,
          'pitch': widget.settings.speechPitch,
          'voice': voice ?? widget.settings.voiceName,
        }).catchError((_) => null);
      }
      return;
    }
    await _ttsCh.invokeMethod('speak', {
      'text': sample,
      'language': widget.settings.language,
      'rate': rate,
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
    bits.add(q >= 400
        ? 'high quality'
        : q >= 300
            ? 'normal'
            : 'basic');
    if (v['network'] == true) bits.add('needs internet');
    if (v['notInstalled'] == true) bits.add('not installed');
    return bits.join(' • ');
  }

  @override
  void dispose() {
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    OnlineVoice.instance.stop().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Voice Studio',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                fontSize: 16)),
        actions: [
          IconButton(
              onPressed: () => _preview(),
              icon: Icon(Icons.play_circle_rounded,
                  color: AppColors.teal, size: 28)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
        children: [
          const SectionTitle('Voice engine'),
          GradientCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'The same words, two very different teachers.',
                  style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 14)),
              const SizedBox(height: 6),
              Text(
                  'Device voice works offline and needs no internet, but a phone '
                  'only has the voices that were installed with it. The online '
                  'voice reads every language the app offers and sounds human — '
                  'it needs internet while the class runs.',
                  style: TextStyle(
                      color: AppColors.muted, fontSize: 12, height: 1.45)),
              const SizedBox(height: 12),
              for (final opt in const [
                ('device', 'Device voice', 'offline · installed voices only'),
                ('online', 'Online neural voice', 'human · male or female · prefers internet'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      setState(() => s.voiceEngine = opt.$1);
                      await s.save();
                      await _testEngine(opt.$1);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: s.voiceEngine == opt.$1
                            ? AppColors.teal.withOpacity(0.14)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: s.voiceEngine == opt.$1
                                ? AppColors.teal
                                : AppColors.stroke),
                      ),
                      child: Row(children: [
                        Icon(
                            s.voiceEngine == opt.$1
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: s.voiceEngine == opt.$1
                                ? AppColors.teal
                                : AppColors.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(opt.$2,
                                    style: TextStyle(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13)),
                                Text(opt.$3,
                                    style: TextStyle(
                                        color: AppColors.muted, fontSize: 11)),
                              ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              if (s.voiceEngine == 'online') ...[
                const SizedBox(height: 4),
                const Divider(height: 18),
                Text('Pick a voice',
                    style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    'Voices for ${xLang(s.explainLanguage).english}. '
                    'Change the explanation language above to hear the other voices.',
                    style: TextStyle(
                        color: AppColors.muted, fontSize: 11, height: 1.4)),
                const SizedBox(height: 8),
                if (neuralVoicesFor(s.explainLanguage).isEmpty)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                        'There is no online voice for '
                        '${xLang(s.explainLanguage).english} yet — this language '
                        'is read by the device voice. Everything else stays the same.',
                        style: TextStyle(
                            color: AppColors.amber, fontSize: 11, height: 1.4)),
                  )
                else
                  for (final v in neuralVoicesFor(s.explainLanguage))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          setState(() => s.neuralVoice = v.name);
                          await s.save();
                          await _preview();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: s.neuralVoice == v.name
                                ? AppColors.teal.withOpacity(0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: s.neuralVoice == v.name
                                    ? AppColors.teal
                                    : AppColors.stroke),
                          ),
                          child: Row(children: [
                            Icon(
                                v.gender == 'F'
                                    ? Icons.face_3_rounded
                                    : Icons.face_6_rounded,
                                size: 18,
                                color: s.neuralVoice == v.name
                                    ? AppColors.teal
                                    : AppColors.muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(v.label,
                                  style: TextStyle(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5)),
                            ),
                            if (s.neuralVoice == v.name)
                              Icon(Icons.check_rounded,
                                  size: 16, color: AppColors.teal),
                          ]),
                        ),
                      ),
                    ),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _engineBusy
                        ? null
                        : () async {
                            await _testEngine(s.voiceEngine);
                            await _preview();
                          },
                    icon: _engineBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.hearing_rounded, size: 18),
                    label: const Text('Hear this voice'),
                  ),
                ),
              ]),
              if (_engineResult.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_engineResult,
                      style: TextStyle(
                          color: _engineResult.toLowerCase().contains('not') ||
                                  _engineResult.toLowerCase().contains('no voice') ||
                                  _engineResult.toLowerCase().contains('could not')
                              ? AppColors.amber
                              : AppColors.green,
                          fontSize: 11.5,
                          height: 1.4)),
                ),
            ]),
          ),
          GradientCard(
            gradient: AppColors.heroGradient,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your teacher’s voice',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                  'Speed and pitch change how the voice feels — a slower voice is easier for hard chapters, a fuller pitch sounds warmer.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12.5, height: 1.45)),
              const SizedBox(height: 14),
              Row(children: [
                const Icon(Icons.speed_rounded,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text('${(s.speechRate * 100).round()}% speed',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5)),
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
                const Icon(Icons.graphic_eq_rounded,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text('Pitch ${s.speechPitch.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5)),
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
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _preview(),
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: const Text('Test'),
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.indigo),
                  ),
                ),
              ]),
            ]),
          ),
          const SectionTitle('Installed voices'),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()))
          else if (_noVoices)
            GradientCard(
              child: Text(
                'No voices reported by this device. Android → Settings → Language & input → Text-to-speech → install a voice for this language.',
                style: TextStyle(
                    color: AppColors.muted, height: 1.45, fontSize: 12.5),
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
                Icon(
                    s.voiceName.isEmpty
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: AppColors.teal,
                    size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('System default',
                            style: TextStyle(
                                color: AppColors.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5)),
                        Text('Let Android choose the best voice',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 11.5)),
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
                      Icon(
                          sel
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: sel ? AppColors.teal : AppColors.muted,
                          size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_title(v),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13)),
                              Text(_sub(v),
                                  style: TextStyle(
                                      color: AppColors.muted, fontSize: 11)),
                            ]),
                      ),
                      Icon(Icons.play_arrow_rounded,
                          color: AppColors.muted, size: 18),
                    ]),
                  ),
                ),
              );
            }),
            GradientCard(
              child: Text(
                'Tip: a voice marked “needs internet” sounds better but stops working offline. '
                'For an offline class, choose a voice without that label.',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 12, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
