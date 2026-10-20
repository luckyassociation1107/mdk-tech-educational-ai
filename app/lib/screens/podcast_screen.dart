import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dart_engine.dart';
import '../lesson_content.dart';
import '../models.dart';
import '../store.dart';
import '../study_stats.dart';
import '../translate_service.dart';
import '../widgets.dart';

/// Audio class ("podcast") for a textbook part — the same teaching as the
/// live class, but ears-only: perfect for revision while walking or
/// travelling. Uses the device voice offline; explanation can be
/// translated just like in the video class.
class PodcastScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final List<SeriesPart> parts;
  const PodcastScreen({super.key, required this.settings, required this.book, required this.parts});

  @override
  State<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends State<PodcastScreen> {
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  int _partIdx = 0;
  List<LessonScene> _scenes = const [];
  final Map<int, String> _tr = {};
  int _scene = 0;
  bool _playing = false;
  bool _loading = true;
  bool _translating = false;
  double _rate = 0.92;
  String _lang = 'en';

  @override
  void initState() {
    super.initState();
    _lang = widget.settings.explainLanguage;
    _ttsCh.setMethodCallHandler((call) async {
      if (call.method == 'ttsDone' || call.method == 'ttsError') {
        if (mounted && _playing) {
          Future<void>.delayed(const Duration(milliseconds: 420), () {
            if (mounted && _playing) _next();
          });
        }
      }
    });
    _load(0);
  }

  Future<void> _load(int idx) async {
    if (widget.parts.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    _stopVoice();
    setState(() {
      _loading = true;
      _scenes = const [];
      _scene = 0;
      _playing = false;
      _tr.clear();
    });
    final part = widget.parts[idx];
    final index = await DartEngine.loadIndex(widget.book.sessionId);
    final brain = await DartEngine.brainKeyPoints(widget.book.sessionId);
    final subject = await DartEngine.subjectOf(widget.book.sessionId);
    if (!mounted) return;
    final scenes = index == null
        ? <LessonScene>[]
        : LessonContent.build(
            index: index,
            pages: part.pages,
            partNumber: part.part,
            title: 'Part ${part.part} • ${part.pageLabel}',
            subject: subject,
            brainPoints: brain,
            themeSetting: widget.settings.theme,
          );
    setState(() {
      _partIdx = idx;
      _scenes = scenes;
      _loading = false;
    });
    await _translate();
  }

  Future<void> _translate() async {
    if (_lang == 'en' || _scenes.isEmpty) return;
    setState(() => _translating = true);
    final idx = <int>[];
    final texts = <String>[];
    for (var i = 0; i < _scenes.length; i++) {
      final e = _scenes[i].explain;
      if (e != null && e.trim().isNotEmpty) {
        idx.add(i);
        texts.add(e);
      }
    }
    final out = await TranslateService.translateAll(texts, _lang);
    if (!mounted) return;
    setState(() {
      for (final k in out.keys) {
        _tr[idx[k]] = out[k]!;
      }
      _translating = false;
    });
  }

  String _textAt(int i) {
    if (i < 0 || i >= _scenes.length) return '';
    final s = _scenes[i];
    return _tr[i] ?? s.narration;
  }

  void _speak(String text, int i) {
    final locale = _tr.containsKey(i) ? xLang(_lang).tts : bookVoiceLocale(text);
    _ttsCh.invokeMethod('speak', {'text': text, 'language': locale, 'rate': _rate}).catchError((_) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted && _playing) _next();
      });
      return null;
    });
  }

  void _playFrom(int i) {
    if (_scenes.isEmpty) return;
    setState(() {
      _scene = i;
      _playing = true;
    });
    _speak(_textAt(i), i);
  }

  void _next() {
    if (_scene >= _scenes.length - 1) {
      _stopVoice();
      setState(() => _playing = false);
      ProgressStore.addXp(widget.book.sessionId, 15);
      StudyStats.recordClassFinished();
      return;
    }
    _playFrom(_scene + 1);
  }

  void _prev() {
    if (_scene > 0) _playFrom(_scene - 1);
  }

  void _toggle() {
    if (_playing) {
      _stopVoice();
      setState(() => _playing = false);
    } else {
      _playFrom(_scene);
    }
  }

  void _stopVoice() {
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
  }

  Future<void> _language() async {
    final picked = await pickExplainLanguage(context, _lang);
    if (picked == null || !mounted) return;
    setState(() {
      _lang = picked.code;
      _tr.clear();
    });
    widget.settings.explainLanguage = picked.code;
    await widget.settings.save();
    await _translate();
    if (mounted && _playing) _playFrom(_scene);
  }

  @override
  void dispose() {
    _stopVoice();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.parts.isEmpty ? null : widget.parts[_partIdx];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title:  Text('Podcast class', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
        actions: [
          IconButton(onPressed: _language, icon:  Icon(Icons.translate_rounded, color: AppColors.teal)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : part == null
              ? const EmptyState(icon: Icons.podcasts_rounded, title: 'No parts yet', message: 'Open a textbook first.')
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _Artwork(book: widget.book, playing: _playing, subjectLabel: widget.book.subjectLabel),
                    const SizedBox(height: 14),
                    Text('${widget.book.shortTitle} • Part ${part.part}',
                        style:  TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 17)),
                    Text('${part.pageLabel} • ${_scenes.length} scenes • offline voice',
                        style:  TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    if (_translating)
                       Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text('Translating explanation…', style: TextStyle(color: AppColors.teal, fontSize: 12)),
                      ),
                    const SizedBox(height: 12),
                    Row(children: [
                       Text('Part', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButton<int>(
                          value: _partIdx.clamp(0, math.max(0, widget.parts.length - 1)),
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          underline: Container(height: 1, color: AppColors.stroke),
                          style:  TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13.5),
                          items: [
                            for (var i = 0; i < widget.parts.length; i++)
                              DropdownMenuItem(value: i, child: Text('Part ${widget.parts[i].part} — ${widget.parts[i].pageLabel}')),
                          ],
                          onChanged: (v) {
                            if (v != null) _load(v);
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Slider(
                      value: (_scene + 1).toDouble().clamp(1.0, math.max(1, _scenes.length).toDouble()),
                      min: 1,
                      max: math.max(1, _scenes.length).toDouble(),
                      onChanged: _scenes.isEmpty
                          ? null
                          : (v) {
                              _playFrom(v.round() - 1);
                            },
                    ),
                    Row(children: [
                      Text('Scene ${_scene + 1}/${_scenes.length}', style:  TextStyle(color: AppColors.muted, fontSize: 12)),
                      const Spacer(),
                      Text(_kindName(_scenes.isEmpty ? '' : _scenes[_scene].kind),
                          style:  TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800, fontSize: 12)),
                    ]),
                    const SizedBox(height: 6),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton.filledTonal(onPressed: _prev, icon: const Icon(Icons.replay_10_rounded)),
                      const SizedBox(width: 10),
                      IconButton.filled(
                        onPressed: _scenes.isEmpty ? null : _toggle,
                        icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34),
                        style: IconButton.styleFrom(backgroundColor: AppColors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.all(18)),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(onPressed: _next, icon: const Icon(Icons.forward_10_rounded)),
                    ]),
                    const SizedBox(height: 4),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (final r in [0.75, 0.92, 1.1])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text('${(r * 100).round()}%', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                            selected: _rate == r,
                            onSelected: (_) => setState(() => _rate = r),
                            selectedColor: AppColors.teal.withOpacity(0.22),
                            backgroundColor: AppColors.card,
                            labelStyle: TextStyle(color: _rate == r ? AppColors.teal : AppColors.muted),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 14),
                    const SectionTitle('Episode transcript'),
                    ...List.generate(_scenes.length, (i) {
                      final s = _scenes[i];
                      final sel = i == _scene;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GradientCard(
                          onTap: () => _playFrom(i),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(
                              sel && _playing ? Icons.graphic_eq_rounded : Icons.play_circle_outline_rounded,
                              color: sel ? AppColors.teal : AppColors.muted,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s.heading, style: TextStyle(color: sel ? AppColors.teal : AppColors.text, fontWeight: FontWeight.w800, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(_tr[i] ?? s.narration, maxLines: 3, overflow: TextOverflow.ellipsis,
                                    style:  TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
                                if (_tr.containsKey(i))
                                   Padding(
                                    padding: EdgeInsets.only(top: 3),
                                    child: Text('Explanation translated • textbook line kept in the book\'s language',
                                        style: TextStyle(color: AppColors.teal, fontSize: 10.5, fontWeight: FontWeight.w700)),
                                  ),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }

  String _kindName(String kind) => switch (kind) {
        'reading' => 'Reading the book',
        'zoom' => 'Figure focus',
        'daily' => 'Daily-life example',
        'lab' => 'Lab',
        'quick' => 'Quick check',
        'title' => 'Intro',
        'end' => 'Wrap-up',
        _ => 'Teaching',
      };
}

class _Artwork extends StatefulWidget {
  final TextbookItem book;
  final bool playing;
  final String subjectLabel;
  const _Artwork({required this.book, required this.playing, required this.subjectLabel});

  @override
  State<_Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<_Artwork> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(children: [
        Positioned(
          right: -30,
          top: -30,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.10)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Container(
              width: 92,
              height: 118,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white38),
              ),
              child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 42),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('PODCAST CLASS', style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                const SizedBox(height: 4),
                Text(widget.book.shortTitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.2)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
                  child: Text(widget.subjectLabel, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Row(
                    children: List.generate(14, (i) {
                      final base = 6 + (i * 7) % 22;
                      final h = widget.playing ? base + (10 * math.sin((_c.value * math.pi) + i / 2)).abs() : base * 0.55;
                      return Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: Container(
                          width: 3.2,
                          height: h.toDouble(),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(99)),
                        ),
                      );
                    }),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
