import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dart_engine.dart';
import '../diagrams.dart';
import '../lesson_content.dart';
import '../store.dart';
import '../study_stats.dart';
import '../translate_service.dart';
import '../vault/emoji_vault.dart';
import '../word_bank.dart';
import '../widgets.dart';
import 'voice_studio_screen.dart';
import '../speech/speech_channel.dart';

const _boards = <String, ({Color bg, Color fg, Color accent})>{
  'green': (
    bg: Color(0xFF17573A),
    fg: Color(0xFFF4FFF8),
    accent: Color(0xFFFDE68A)
  ),
  'black': (
    bg: Color(0xFF14181F),
    fg: Color(0xFFF9FAFB),
    accent: Color(0xFF7DD3FC)
  ),
  'white': (
    bg: Color(0xFFF8FAFC),
    fg: Color(0xFF0F172A),
    accent: Color(0xFF2563EB)
  ),
  'ruled': (
    bg: Color(0xFFEFF4FF),
    fg: Color(0xFF1E3A8A),
    accent: Color(0xFFDC2626)
  ),
  'graph': (
    bg: Color(0xFFFFFDF5),
    fg: Color(0xFF1F2937),
    accent: Color(0xFF059669)
  ),
};

/// The classroom itself — a live Zoom-style class drawn & spoken in Flutter.
///
/// SYNC: the Android voice reports the exact character range it is
/// speaking (ttsRange). Board writing, captions and the textbook page
/// highlighter all move from those ranges, so text can never run ahead
/// of or behind the voice. If a voice engine gives no ranges, a timed
/// fallback takes over for that scene.
class LessonPlayerScreen extends StatefulWidget {
  final AppSettings settings;
  final String sessionId;
  final String title;
  final int partNumber;
  final List<int> pages;

  const LessonPlayerScreen({
    super.key,
    required this.settings,
    required this.sessionId,
    required this.title,
    required this.partNumber,
    required this.pages,
  });

  @override
  State<LessonPlayerScreen> createState() => _LessonPlayerScreenState();
}

class _LessonPlayerScreenState extends State<LessonPlayerScreen>
    with SingleTickerProviderStateMixin {
  static const SpeechChannel _ttsCh = SpeechChannel();
  DartPdfIndex? _index;
  String _pageDir = '';
  List<LessonScene> _scenes = [];
  List<String> _brainPoints = const [];
  int _scene = 0;
  bool _playing = false;
  bool _loading = true;

  // --- explanation translation ---
  String _lang = 'en';
  final Map<int, String> _tr = {};
  List<String?> _voice = [];
  bool _translating = false;
  int _translateFailed = 0;

  // --- sync state for the current scene ---
  Timer? _timer;
  int _spoken = 0;
  bool _rangeSeen = false;
  bool _ttsDone = false;
  bool _advancing = false;
  DateTime _sceneStart = DateTime.now();
  int _tick = 0;

  // --- interactive quick checks / xp ---
  String? _picked;
  bool? _pickedRight;
  int _xp = 0;
  int _xpGained = 0;
  Timer? _xpTimer;
  bool _theatre = false;

  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  final int _viewers = 24 + math.Random().nextInt(70);

  @override
  void initState() {
    super.initState();
    _lang = widget.settings.explainLanguage;
    _init();
  }

  Future<void> _init() async {
    final index = await DartEngine.loadIndex(widget.sessionId);
    final dir = await DartEngine.pageDirOf(widget.sessionId);
    _brainPoints = await DartEngine.brainKeyPoints(widget.sessionId);
    final subject = await DartEngine.subjectOf(widget.sessionId);
    _ttsCh.setMethodCallHandler((call) async {
      if (call.method == 'ttsRange') {
        final end = (call.arguments is Map)
            ? (call.arguments['end'] as num?)?.toInt() ?? 0
            : 0;
        if (end > _spoken) {
          _spoken = end;
          _rangeSeen = true;
        }
      } else if (call.method == 'ttsDone' || call.method == 'ttsError') {
        _ttsDone = true;
      }
    });
    // The AI designs the lesson script (custom prompt); when it is not
    // available the on-device builder still produces a lesson from the AI's
    // own extracted text.
    final aiScenes = await DartEngine.loadScenes(widget.sessionId, widget.partNumber);
    if (!mounted) return;
    final scenes = aiScenes.isNotEmpty
        ? aiScenes
        : index == null
            ? <LessonScene>[]
            : LessonContent.build(
            index: index,
            pages: widget.pages,
            partNumber: widget.partNumber,
            title: widget.title,
            subject: subject,
            brainPoints: _brainPoints,
            themeSetting: widget.settings.theme,
          );
    final xp = await ProgressStore.xpOf(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _index = index;
      _pageDir = dir;
      _scenes = scenes;
      _voice = List<String?>.filled(scenes.length, null);
      _loading = false;
      _xp = xp;
    });
    await _prepareTranslation();
    if (!mounted) return;
    if (_scenes.isNotEmpty) _playScene(0);
  }

  /// Translates only our own explanation lines (never the textbook text).
  Future<void> _prepareTranslation() async {
    if (_lang == 'en' || _scenes.isEmpty) return;
    setState(() {
      _translating = true;
      _translateFailed = 0;
    });
    final idx = <int>[];
    final texts = <String>[];
    for (var i = 0; i < _scenes.length; i++) {
      final e = _scenes[i].explain;
      if (e != null && e.trim().isNotEmpty) {
        idx.add(i);
        texts.add(e);
      }
    }
    final known = _brainPoints
        .expand((k) => RegExp(r'\b[A-Z][a-zA-Z]{2,}\b')
            .allMatches(k)
            .map((m) => m.group(0)!))
        .where((w) => w.length > 3)
        .toSet()
        .take(40)
        .toList();
    final out =
        await TranslateService.translateAll(texts, _lang, knownTerms: known);
    if (!mounted) return;
    setState(() {
      for (final k in out.keys) {
        _tr[idx[k]] = out[k]!;
        _voice[idx[k]] = out[k];
      }
      _translateFailed = texts.length - out.length;
      _translating = false;
    });
    if (_translateFailed > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_translateFailed == texts.length
            ? 'Translation needs internet the first time. Playing in English — the translation will be saved once online.'
            : 'Most explanation is in ${xLang(_lang).english}; $_translateFailed line(s) stayed in English.'),
      ));
    }
  }

  String _voiceOf(int i) =>
      _voice.length > i ? (_voice[i] ?? _scenes[i].narration) : '';
  String? _trOf(int i) => _tr[i];

  Future<void> _changeLanguage() async {
    final picked = await pickExplainLanguage(context, _lang);
    if (picked == null || !mounted) return;
    _lang = picked.code;
    widget.settings.explainLanguage = picked.code;
    await widget.settings.save();
    _tr.clear();
    _voice = List<String?>.filled(_scenes.length, null);
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    _timer?.cancel();
    await _prepareTranslation();
    if (!mounted) return;
    _playScene(_scene);
  }

  // ---------- playback engine (voice-driven) ----------

  double _estSeconds(String text) =>
      (text.length / 13.5).clamp(2.5, 60.0).toDouble();

  String get _voiceText {
    if (_scenes.isEmpty) return '';
    return _voiceOf(_scene);
  }

  int get _revealed {
    if (_scenes.isEmpty) return 0;
    final text = _voiceText;
    if (_rangeSeen) return math.min(text.length, _spoken);
    final elapsed =
        DateTime.now().difference(_sceneStart).inMilliseconds / 1000.0;
    if (elapsed < 0.8) return 0;
    final frac = (elapsed / _estSeconds(text)).clamp(0.0, 1.0);
    return (text.length * frac).floor();
  }

  double get _progress {
    final text = _voiceText;
    if (text.isEmpty) return 0;
    return (_revealed / math.max(1, text.length)).clamp(0.0, 1.0).toDouble();
  }

  void _playScene(int i, {bool slow = false}) {
    _timer?.cancel();
    final s = _scenes[i];
    final text = _voiceOf(i);
    StudyStats.recordActivity(seconds: _estSeconds(text).round());
    setState(() {
      _scene = i;
      _playing = true;
      _spoken = 0;
      _rangeSeen = false;
      _ttsDone = false;
      _advancing = false;
      _sceneStart = DateTime.now();
      _tick = 0;
      if (s.kind != 'quick') {
        _picked = null;
        _pickedRight = null;
      }
    });
    final locale =
        _tr.containsKey(i) ? xLang(_lang).tts : bookVoiceLocale(text);
    _ttsCh.invokeMethod('speak', {
      'text': text,
      'language': locale,
      'rate': slow ? 0.62 : widget.settings.speechRate,
      'pitch': widget.settings.speechPitch,
      'voice': widget.settings.voiceName,
    }).catchError((_) {
      _ttsDone = true;
      return null;
    });
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _tick++);
      final elapsed = DateTime.now().difference(_sceneStart).inSeconds;
      final finishedVoice = _ttsDone && _revealed >= text.length - 2;
      final hardCap = elapsed > _estSeconds(text) + 16;
      // Quick checks wait for the student's answer instead of racing on.
      final waitForAnswer = s.kind == 'quick' && _picked == null;
      if (!_advancing &&
          elapsed >= 1 &&
          !waitForAnswer &&
          (finishedVoice || hardCap)) {
        _advancing = true;
        Future<void>.delayed(const Duration(milliseconds: 350), () {
          if (mounted && _playing) _next(auto: true);
        });
      }
    });
  }

  void _next({bool auto = false}) {
    if (_scene >= _scenes.length - 1) {
      _finish();
      return;
    }
    _playScene(_scene + 1);
  }

  void _prev() {
    if (_scene > 0) _playScene(_scene - 1);
  }

  Future<void> _toggle() async {
    if (_playing) {
      _timer?.cancel();
      try {
        await _ttsCh.invokeMethod('stopTts');
      } catch (_) {}
      setState(() => _playing = false);
    } else {
      _playScene(_scene);
    }
  }

  void _answerQuick(String option) {
    final s = _scenes[_scene];
    final right = option == s.answer;
    setState(() {
      _picked = option;
      _pickedRight = right;
    });
    if (right) {
      _xpGained = 10;
      ProgressStore.addXp(widget.sessionId, 10).then((v) {
        if (mounted) setState(() => _xp = v);
      });
      _xpTimer?.cancel();
      _xpTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _xpGained = 0);
      });
      _advancing = true;
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _playing) _next();
      });
    } else {
      _xpGained = 0;
    }
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    await ProgressStore.addXp(widget.sessionId, 20);
    await StudyStats.recordClassFinished();
    await VaultStore.log('class', 'Finished part ${widget.partNumber} — ${widget.title}');
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _xpTimer?.cancel();
    _pulse.dispose();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  // ---------- views ----------

  /// Numbered (T26-T32) and bulleted (T33-T38) cards: the model sends plain
  /// lines, the player draws the markers so the board looks like a slide.
  String _listify(LessonScene s, String text) {
    final style = SceneTemplate.list(s.template);
    if (style.isEmpty) return text;
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return text;
    if (style == 'numbered') {
      return [
        for (var i = 0; i < lines.length; i++)
          '${i + 1}.  ${lines[i].replaceFirst(RegExp(r'^[·•\-–]\s*'), '')}'
      ].join('\n');
    }
    return [
      for (final l in lines) '•  ${l.replaceFirst(RegExp(r'^[·•\-–]\s*'), '')}'
    ].join('\n');
  }

  String _boardDisplay(LessonScene s) {
    var t = s.boardFor(_trOf(_scenes.indexOf(s)));
    if (s.kind == 'practice' && s.extra != null && _progress < 0.55) {
      t = t.replaceAll(s.extra!, '——————');
    } else if (s.kind == 'practice' && s.extra != null) {
      t = t.replaceAll(s.extra!, '[ ${s.extra} ]');
    }
    return _listify(s, t);
  }

  String _currentSentence() {
    final text = _voiceText;
    final end = math.min(text.length, _revealed + 1);
    final parts = LessonContent.sentences(text);
    var acc = 0;
    for (final p in parts) {
      acc += p.length + 1;
      if (end <= acc) return p;
    }
    return text;
  }

  Widget _revealedText(String text,
      {required Color main,
      required Color dim,
      required double size,
      bool mono = false,
      double height = 1.6}) {
    final r = (text.length * _progress).floor().clamp(0, text.length);
    return RichText(
      text: TextSpan(children: [
        TextSpan(
            text: text.substring(0, r),
            style: TextStyle(
                color: main,
                fontSize: size,
                height: height,
                fontWeight: FontWeight.w700,
                fontFamily: mono ? 'monospace' : null)),
        TextSpan(
            text: text.substring(r),
            style: TextStyle(
                color: dim,
                fontSize: size,
                height: height,
                fontWeight: FontWeight.w500,
                fontFamily: mono ? 'monospace' : null)),
      ]),
    );
  }

  /// T01-T06 — a title card, not a paragraph on a board. The voice speaks the
  /// narration; the screen shows the class name and one subtitle line.
  Widget _titleView(LessonScene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final cinematic = s.template.isEmpty || SceneTemplate.cinematic(s.template);
    final sub = (s.boardText ?? '').trim();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cinematic
              ? [c.bg, Color.lerp(c.bg, c.accent, 0.32)!]
              : [c.bg, c.bg],
        ),
      ),
      padding: const EdgeInsets.all(22),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cinematic)
                Icon(Icons.auto_awesome_rounded,
                    color: c.accent, size: 26),
              const SizedBox(height: 10),
              Text(
                s.heading,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.fg,
                  fontWeight: FontWeight.w900,
                  height: 1.15,
                  fontSize: s.heading.length > 42
                      ? 24
                      : s.heading.length > 24
                          ? 30
                          : 36,
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(width: 54, height: 3, color: c.accent),
                const SizedBox(height: 12),
                Text(sub,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.fg.withOpacity(0.86),
                        fontSize: 14,
                        height: 1.4,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// T51-T54 — two columns. The model sends "Left | Right" lines; the first
  /// line that has a "|" is the pair of column titles.
  Widget _compareView(LessonScene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final rows = <(String, String)>[];
    for (final line in _boardDisplay(s).split('\n')) {
      if (!line.contains('|')) continue;
      final parts = line.split('|');
      rows.add((parts.first.trim(), parts.skip(1).join('|').trim()));
    }
    if (rows.length < 2) return _boardView(s);
    final head = rows.first;
    final body = rows.skip(1).toList();
    Widget col(String title, List<String> items, Color tint) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
                color: tint.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tint.withOpacity(0.5))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.fg,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      letterSpacing: 0.8)),
              const SizedBox(height: 8),
              for (final it in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('•  $it',
                      style: TextStyle(
                          color: c.fg.withOpacity(0.94),
                          fontSize: 13,
                          height: 1.35)),
                ),
            ]),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.heading.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
                fontSize: 12.5)),
        const SizedBox(height: 12),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            col(head.$1, [for (final r in body) r.$1], c.accent),
            const SizedBox(width: 10),
            col(head.$2, [for (final r in body) r.$2], c.fg),
          ]),
        ),
      ]),
    );
  }

  /// T26-T32 / T30-T31 — numbered steps joined by a line.
  Widget _stepsView(LessonScene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final lines = _boardDisplay(s)
        .split('\n')
        .map((l) => l.trim().replaceFirst(RegExp(r'^\d+[.)]\s*'), ''))
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return _boardView(s);
    final timeline = s.kind == 'timeline' ||
        SceneTemplate.list(s.template) == 'numbered' && s.kind == 'timeline';
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.heading.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.accent,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
                fontSize: 12.5)),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: timeline
                                    ? c.accent.withOpacity(0.2)
                                    : c.accent,
                                shape: BoxShape.circle,
                                border: timeline
                                    ? Border.all(color: c.accent, width: 2)
                                    : null),
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    color: timeline ? c.accent : c.bg,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12)),
                          ),
                          if (i != lines.length - 1)
                            Container(
                                width: 2,
                                height: 22,
                                color: c.accent.withOpacity(0.35)),
                        ]),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(lines[i],
                                style: TextStyle(
                                    color: c.fg,
                                    fontSize: 14,
                                    height: 1.38,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  /// T58 — a quote card. `extra` carries the author.
  Widget _quoteView(LessonScene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final body = _boardDisplay(s);
    final author = (s.extra ?? '').trim();
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(width: 5, color: c.accent),
        const SizedBox(width: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.format_quote_rounded,
                      color: c.accent.withOpacity(0.8), size: 30),
                  const SizedBox(height: 4),
                  Text(body,
                      style: TextStyle(
                          color: c.fg,
                          fontStyle: FontStyle.italic,
                          fontSize: 18,
                          height: 1.45,
                          fontWeight: FontWeight.w700)),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('— $author',
                        style: TextStyle(
                            color: c.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ],
                ]),
          ),
        ),
      ]),
    );
  }

  /// T57 / T15 — a term and its meaning, like a dictionary card.
  Widget _vocabView(LessonScene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final meaning = _boardDisplay(s);
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
      ),
      padding: const EdgeInsets.all(18),
      child: Center(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(99)),
              child: Text('KEY WORD',
                  style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.2)),
            ),
            const SizedBox(height: 10),
            Text(s.heading,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.fg,
                    fontWeight: FontWeight.w900,
                    fontSize: s.heading.length > 26 ? 24 : 30)),
            const SizedBox(height: 12),
            Text(meaning,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.fg.withOpacity(0.9),
                    fontSize: 15,
                    height: 1.5,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _boardView(LessonScene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final len = _voiceText.length;
    final size = s.formula
        ? (len > 160 ? 19.0 : 23.0)
        : (len > 260
            ? 16.0
            : len > 140
                ? 18.5
                : 21.5);
    final translated = _tr.containsKey(_scenes.indexOf(s));
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
      ),
      child: Stack(children: [
        if (s.boardTheme == 'ruled' || s.boardTheme == 'graph')
          Positioned.fill(
              child: CustomPaint(
                  painter: _BoardLinesPainter(
                      theme: s.boardTheme, color: c.accent))),
        Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (SceneTemplate.heading(s.template) == 'marker')
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: c.accent.withOpacity(0.28),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text(s.heading.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.fg,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            fontSize: 12.5)),
                  ),
                )
              else
              Text(s.heading.toUpperCase(),
                  style: TextStyle(
                      color: c.accent,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      fontSize: 12.5)),
              const Spacer(),
              if (SceneTemplate.heading(s.template) == 'underline')
                Container(
                  width: 44,
                  height: 3,
                  margin: const EdgeInsets.only(right: 10),
                  color: c.accent,
                ),
              if (s.explain != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: c.accent.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(99)),
                  child: Text(
                      translated
                          ? 'EXPLANATION • ${xLang(_lang).code.toUpperCase()}'
                          : 'EXPLANATION',
                      style: TextStyle(
                          color: c.accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 9.5,
                          letterSpacing: 0.8)),
                )
              else
                Text(s.formula ? 'FORMULA' : s.boardTheme.toUpperCase(),
                    style: TextStyle(
                        color: c.accent.withOpacity(0.75),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        fontSize: 10)),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: _revealedText(_boardDisplay(s),
                    main: c.fg,
                    dim: c.fg.withOpacity(0.35),
                    size: size,
                    mono: s.formula),
              ),
            ),
            if (s.kind == 'quick' && s.options.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in s.options)
                  _QuickChip(
                    label: o,
                    state: _picked == null
                        ? 0
                        : (o == s.answer ? 1 : (o == _picked ? 2 : 0)),
                    onTap: _picked == null ? () => _answerQuick(o) : null,
                  ),
              ]),
              if (_picked != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(
                        _pickedRight == true
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        size: 18,
                        color: _pickedRight == true
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626)),
                    const SizedBox(width: 6),
                    Text(
                      _pickedRight == true
                          ? 'Correct! +10 XP'
                          : 'Not quite — the right word is ${s.answer}. Listen once more and continue.',
                      style: TextStyle(
                          color: _pickedRight == true
                              ? const Color(0xFF065F46)
                              : const Color(0xFF991B1B),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        _advancing = true;
                        _next();
                      },
                      child: const Text('Continue',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.draw_rounded, size: 15, color: c.accent),
              const SizedBox(width: 6),
              Text(
                s.kind == 'quick' && _picked == null
                    ? 'your turn — tap the right word'
                    : (_ttsDone ? 'done — next…' : 'writing with the voice…'),
                style: TextStyle(
                    color: c.accent, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pageImage(LessonScene s, {Rect? zone, double zoomT = 0}) {
    final img = File('$_pageDir/page_${s.page}.png');
    if (!img.existsSync()) {
      _ensurePage(s.page);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _revealedText(_voiceText,
              main: const Color(0xFF334155),
              dim: const Color(0xFF94A3B8),
              size: 16),
        ),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      Widget image = Image.file(img, fit: BoxFit.fill, width: w, height: h);
      if (zone != null) {
        final target =
            math.min(4.2, 0.92 / math.max(0.15, zone.width)).toDouble();
        final scale = 1 + (target - 1) * zoomT;
        final cx = zone.left + zone.width / 2;
        final cy = zone.top + zone.height / 2;
        var tx = (0.5 - cx) * w * scale;
        var ty = (0.5 - cy) * h * scale;
        tx = tx.clamp(-(scale - 1) * w / 2, (scale - 1) * w / 2).toDouble();
        ty = ty.clamp(-(scale - 1) * h / 2, (scale - 1) * h / 2).toDouble();
        image = Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(tx, ty, 0)..scale(scale),
          child: image,
        );
      }
      return ClipRect(child: image);
    });
  }

  /// A figure that the AI located on the page and the app cut out of the
  /// PDF with those coordinates — used only when a scene needs a picture.
  Widget _figureView(LessonScene s) {
    final path = s.imagePath;
    final file = path == null ? null : File(path);
    if (file == null || !file.existsSync()) {
      return _pageImage(s, zone: s.zone);
    }
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF0B1220),
          borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(10),
      child: Stack(children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.66),
                borderRadius: BorderRadius.circular(99)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.crop_free_rounded, size: 14, color: Colors.white),
              SizedBox(width: 5),
              Text('FIGURE • FROM YOUR BOOK',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
            ]),
          ),
        ),
      ]),
    );
  }

  final Set<int> _pageTried = {};

  /// Ask the engine to render this page (PDFium works on Android & Windows).
  Future<void> _ensurePage(int? page) async {
    if (page == null || _pageTried.contains(page)) return;
    _pageTried.add(page);
    final path =
        await DartEngine.ensurePageImage(widget.sessionId, page);
    if (!mounted || path == null) return;
    setState(() => _pageDir = File(path).parent.path);
  }

  Widget _diagramView(LessonScene s) {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke)),
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Expanded(
          child: DiagramView(
            type: s.extra ?? 'cycle',
            labels: s.labels,
            progress: _progress,
            accent: AppColors.teal,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          s.boardFor(_trOf(_scenes.indexOf(s))),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
      ]),
    );
  }

  Widget _readingView(LessonScene s) {
    final blocks = (_index != null && s.page != null)
        ? (_index!.pageOf(s.page!)?.blocks ?? const <DartBlock>[])
        : const <DartBlock>[];
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFFF6F1E7),
          borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        Rect? rect;
        if (blocks.isNotEmpty) {
          final idx =
              math.min(blocks.length - 1, (_progress * blocks.length).floor());
          final b = blocks[idx].bbox;
          if (b.length == 4)
            rect = Rect.fromLTRB(b[0] * w, b[1] * h, b[2] * w, b[3] * h);
        }
        return Stack(children: [
          Positioned.fill(child: _pageImage(s)),
          if (rect != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.amber.withOpacity(0.38),
                  border: Border.all(color: AppColors.amber, width: 1.6),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _zoomView(LessonScene s) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFF0B1220),
          borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(10),
      child: Stack(children: [
        Positioned.fill(
            child: _pageImage(s,
                zone: s.zone,
                zoomT: Curves.easeInOut.transform(_progress.clamp(0.0, 1.0)))),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(99)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
              SizedBox(width: 5),
              Text('FIGURE FOCUS',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
            ]),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.78),
                borderRadius: BorderRadius.circular(12)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.labels.isNotEmpty && s.labels.first.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text('📖 ${s.labels.first.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.amber,
                              fontSize: 12,
                              fontWeight: FontWeight.w900)),
                    ),
                  Text(_trOf(_scenes.indexOf(s)) ?? s.narration,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12.5, height: 1.45)),
                  if (s.labels.length > 1) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final l in s.labels.skip(1))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(99)),
                          child: Text(l,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ],
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _liveHeader() {
    return Row(children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.red.withOpacity(0.15 + 0.12 * _pulse.value),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color: AppColors.red.withOpacity(0.4 + 0.4 * _pulse.value)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: AppColors.red),
            SizedBox(width: 5),
            Text('LIVE',
                style: TextStyle(
                    color: AppColors.red,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8)),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      CircleAvatar(
          radius: 11,
          backgroundColor: AppColors.indigo,
          child: Icon(Icons.school_rounded, size: 13, color: Colors.white)),
      const SizedBox(width: 6),
      Text('Teacher',
          style: TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
      const Spacer(),
      Icon(Icons.visibility_rounded,
          size: 13, color: AppColors.muted.withOpacity(0.9)),
      const SizedBox(width: 4),
      Text('$_viewers',
          style: TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12)),
      const SizedBox(width: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: AppColors.teal.withOpacity(0.14),
            borderRadius: BorderRadius.circular(99)),
        child: Text('$_xp XP',
            style: TextStyle(
                color: AppColors.teal,
                fontWeight: FontWeight.w900,
                fontSize: 11.5)),
      ),
      if (_xpGained > 0)
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 500),
          builder: (context, t, child) => Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child:
                Transform.translate(offset: Offset(0, -18 * t), child: child),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: 6),
            child: Text('+10',
                style: TextStyle(
                    color: AppColors.teal,
                    fontWeight: FontWeight.w900,
                    fontSize: 13)),
          ),
        ),
    ]);
  }

  String _kindLabel(LessonScene s) => switch (s.kind) {
        'reading' => 'Reading the textbook',
        'zoom' => 'Looking at the figure',
        'figure' => 'Figure from your book',
        'summary' => 'What we learnt',
        'vocab' => 'New word',
        'practice' => 'Your turn',
        'steps' => 'Step by step',
        'daily' => 'Daily-life example',
        'timeline' => 'Timeline',
        'lab' => 'Lab • Experiment',
        'safety' => 'Safety first',
        'diagram' => 'Drawing the diagram',
        'quick' => 'Quick check — tap to answer',
        'end' => 'Class complete',
        'title' => 'Class starting',
        _ => 'On the board',
      };

  Widget _miniAction(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 19, color: AppColors.muted),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Future<void> _openVoiceStudio() async {
    _timer?.cancel();
    await _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    if (!mounted) return;
    setState(() => _playing = false);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VoiceStudioScreen(settings: widget.settings),
    ));
    if (mounted) _playScene(_scene);
  }

  Future<void> _wordHelp() async {
    final text = _voiceText;
    final words = RegExp(r'[A-Za-z][A-Za-z\-]{4,}')
        .allMatches(text)
        .map((m) => m.group(0)!)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pageText =
        (_index != null && _scenes.isNotEmpty && _scenes[_scene].page != null)
            ? _index!.pageText(_scenes[_scene].page!)
            : text;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => WordHelpSheet(
        words: words.take(24).toList(),
        pageText: pageText,
        lang: _lang,
        tts: _ttsCh,
        sessionId: widget.sessionId,
        page: _scenes[_scene].page?.toString() ?? '',
        onExit: () => _ttsCh.invokeMethod('stopTts').catchError((_) => null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _scenes.isEmpty ? null : _scenes[_scene];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _theatre
          ? null
          : AppBar(
              backgroundColor: AppColors.bg,
              title: Text(widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.text,
                      fontSize: 15.5)),
              actions: [
                IconButton(
                  tooltip: 'Theatre mode',
                  onPressed: () => setState(() => _theatre = true),
                  icon: Icon(Icons.fullscreen_rounded, color: AppColors.muted),
                ),
                IconButton(
                  tooltip: 'Explanation language',
                  onPressed: _changeLanguage,
                  icon: Stack(clipBehavior: Clip.none, children: [
                    Icon(Icons.translate_rounded, color: AppColors.teal),
                    if (_lang != 'en')
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: AppColors.indigo,
                              borderRadius: BorderRadius.circular(99)),
                          child: Text(_lang.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w900)),
                        ),
                      ),
                  ]),
                ),
                TextButton(
                    onPressed: _finish,
                    child: Text('Finish',
                        style: TextStyle(
                            color: AppColors.teal,
                            fontWeight: FontWeight.w800))),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : s == null
              ? const EmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Lesson not available',
                  message:
                      'This textbook could not be prepared on this device.')
              : Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  child: Column(children: [
                    if (_theatre)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.red.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(99)),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.circle, size: 7, color: AppColors.red),
                              SizedBox(width: 4),
                              Text('LIVE',
                                  style: TextStyle(
                                      color: AppColors.red,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.7)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Text('${_scene + 1}/${_scenes.length}',
                              style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700)),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(() => _theatre = false),
                            icon: const Icon(Icons.fullscreen_exit_rounded,
                                size: 17),
                            label: const Text('Exit'),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.muted,
                                visualDensity: VisualDensity.compact),
                          ),
                        ]),
                      )
                    else ...[
                      _liveHeader(),
                      const SizedBox(height: 6),
                      Row(children: [
                        Text(
                            'Part ${widget.partNumber} • ${_scene + 1}/${_scenes.length}',
                            style: TextStyle(
                                color: AppColors.muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                        const Spacer(),
                        Text(_kindLabel(s),
                            style: TextStyle(
                                color: AppColors.teal,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ]),
                      const SizedBox(height: 6),
                    ],
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _scenes.isEmpty
                            ? 0
                            : (_scene + _progress) / _scenes.length,
                        minHeight: _theatre ? 3 : 5,
                        backgroundColor: AppColors.stroke,
                        valueColor: AlwaysStoppedAnimation(AppColors.teal),
                      ),
                    ),
                    if (_translating && !_theatre)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Text('Preparing ${xLang(_lang).english} explanation…',
                              style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 420),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) {
                          final slide = Tween<Offset>(
                                  begin: const Offset(0.06, 0.03),
                                  end: Offset.zero)
                              .animate(anim);
                          return FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                  position: slide, child: child));
                        },
                        child: KeyedSubtree(
                          key: ValueKey('$_scene-${s.kind}-${s.template}'),
                          child: s.kind == 'reading'
                              ? _readingView(s)
                              : s.kind == 'zoom'
                                  ? _zoomView(s)
                                  : s.kind == 'figure'
                                      ? _figureView(s)
                                      : s.kind == 'diagram'
                                          ? _diagramView(s)
                                          : s.kind == 'title'
                                              ? _titleView(s)
                                              : s.kind == 'compare'
                                                  ? _compareView(s)
                                                  : (s.kind == 'steps' ||
                                                          s.kind == 'timeline')
                                                      ? _stepsView(s)
                                                      : s.kind == 'quote'
                                                          ? _quoteView(s)
                                                          : s.kind == 'vocab'
                                                              ? _vocabView(s)
                                                              : _boardView(s),
                        ),
                      ),
                    ),
                    if (!_theatre) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 9),
                        decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.stroke)),
                        child: Row(children: [
                          Icon(Icons.subtitles_rounded,
                              size: 15, color: AppColors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_currentSentence(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppColors.text,
                                    height: 1.4,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _miniAction(Icons.replay_rounded, 'Repeat',
                                () => _playScene(_scene)),
                            _miniAction(Icons.slow_motion_video_rounded, 'Slow',
                                () => _playScene(_scene, slow: true)),
                            _miniAction(
                                Icons.spellcheck_rounded, 'Words', _wordHelp),
                            _miniAction(
                                Icons.speed_rounded, 'Voice', _openVoiceStudio),
                          ]),
                      const SizedBox(height: 10),
                    ],
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton.filledTonal(
                              onPressed: _scene > 0 ? _prev : null,
                              icon: const Icon(Icons.skip_previous_rounded)),
                          IconButton.filled(
                            onPressed: _toggle,
                            icon: Icon(
                                _playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 28),
                            style: IconButton.styleFrom(
                                backgroundColor: AppColors.indigo,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(14)),
                          ),
                          IconButton.filledTonal(
                            onPressed: _scene < _scenes.length - 1
                                ? () => _next()
                                : _finish,
                            icon: Icon(_scene < _scenes.length - 1
                                ? Icons.skip_next_rounded
                                : Icons.check_rounded),
                          ),
                        ]),
                  ]),
                ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final int state; // 0 idle, 1 correct, 2 wrong
  final VoidCallback? onTap;
  const _QuickChip({required this.label, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = switch (state) {
      1 => const Color(0xFFD1FAE5),
      2 => const Color(0xFFFEE2E2),
      _ => Colors.white,
    };
    final fg = switch (state) {
      1 => const Color(0xFF065F46),
      2 => const Color(0xFF991B1B),
      _ => const Color(0xFF1E293B),
    };
    final border = switch (state) {
      1 => const Color(0xFF059669),
      2 => const Color(0xFFDC2626),
      _ => const Color(0xFF94A3B8),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: border, width: 1.4)),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Text(label,
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w800, fontSize: 14)),
        ),
      ),
    );
  }
}

class _BoardLinesPainter extends CustomPainter {
  final String theme;
  final Color color;
  const _BoardLinesPainter({required this.theme, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.18)
      ..strokeWidth = 1;
    if (theme == 'ruled') {
      for (var y = 36.0; y < size.height; y += 30) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else {
      for (var x = 0.0; x < size.width; x += 26) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = 0.0; y < size.height; y += 26) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tap any hard word from the board: the voice says it slowly, the app
/// shows the textbook sentence where it appears, and (when an explanation
/// language is chosen) its translation — perfect for making notes.
class WordHelpSheet extends StatefulWidget {
  final List<String> words;
  final String pageText;
  final String lang;
  final SpeechChannel tts;
  final String sessionId;
  final String page;
  final VoidCallback onExit;
  const WordHelpSheet({
    super.key,
    required this.words,
    required this.pageText,
    required this.lang,
    required this.tts,
    required this.sessionId,
    this.page = '',
    required this.onExit,
  });

  @override
  State<WordHelpSheet> createState() => _WordHelpSheetState();
}

class _WordHelpSheetState extends State<WordHelpSheet> {
  String? _word;
  String? _translation;
  bool _loading = false;

  String _context(String word) {
    final flat = widget.pageText.replaceAll(RegExp(r'\s+'), ' ');
    final idx = flat.toLowerCase().indexOf(word.toLowerCase());
    if (idx < 0) return '';
    final start = (idx - 60).clamp(0, flat.length);
    final end = (idx + word.length + 90).clamp(0, flat.length);
    return '…${flat.substring(start, end)}…';
  }

  Future<void> _pick(String w) async {
    setState(() {
      _word = w;
      _translation = null;
      _loading = widget.lang != 'en';
    });
    widget.tts.invokeMethod('speak',
        {'text': w, 'language': 'en-IN', 'rate': 0.62}).catchError((_) => null);
    String? t;
    if (widget.lang != 'en') {
      t = await TranslateService.translate(w, widget.lang);
      if (mounted) {
        setState(() {
          _translation = t;
          _loading = false;
        });
      }
    }
    await WordBank.add(
        widget.sessionId,
        WordEntry(
          word: w,
          context: _context(w),
          translation: t ?? '',
          page: widget.page,
          when: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Column(children: [
          const SizedBox(height: 12),
          Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99))),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Word help',
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w900)),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
                'Tap a word — the voice says it slowly, and you see it inside your own textbook line.',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 12, height: 1.35)),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 7, runSpacing: 7, children: [
              for (final w in widget.words)
                GestureDetector(
                  onTap: () => _pick(w),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: _word == w
                          ? AppColors.teal.withOpacity(0.22)
                          : AppColors.cardLight,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color:
                              _word == w ? AppColors.teal : AppColors.stroke),
                    ),
                    child: Text(w,
                        style: TextStyle(
                            color: _word == w ? AppColors.teal : AppColors.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
          if (_word != null) ...[
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    GradientCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(_word!,
                                  style: TextStyle(
                                      color: AppColors.teal,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17)),
                              const SizedBox(width: 8),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => widget.tts.invokeMethod(
                                    'speak', {
                                  'text': _word!,
                                  'language': 'en-IN',
                                  'rate': 0.55
                                }).catchError((_) => null),
                                icon: Icon(Icons.volume_up_rounded,
                                    size: 18, color: AppColors.teal),
                              ),
                              const Spacer(),
                              if (_loading)
                                const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                            ]),
                            if (_translation != null) ...[
                              const SizedBox(height: 4),
                              Text(_translation!,
                                  style: TextStyle(
                                      color: AppColors.amber,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                            ],
                            const SizedBox(height: 10),
                            Text('In your textbook',
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8)),
                            const SizedBox(height: 4),
                            Text(_context(_word!),
                                style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 13,
                                    height: 1.5)),
                          ]),
                    ),
                  ]),
            ),
          ] else
            Expanded(
                child: ListView(
                    controller: scroll,
                    children: const [SizedBox(height: 20)])),
        ]),
      ),
    );
  }
}
