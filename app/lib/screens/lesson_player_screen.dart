import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dart_engine.dart';
import '../store.dart';
import '../widgets.dart';

class _Scene {
  final String kind; // title | board | reading | zoom | end
  final String heading;
  final String narration;
  final int? page;
  final Rect? zone; // normalized focus region for zoom scenes
  final String boardTheme;
  final bool formula;
  const _Scene(this.kind, this.heading, this.narration, {this.page, this.zone, this.boardTheme = 'green', this.formula = false});
}

const _boards = <String, ({Color bg, Color fg, Color accent})>{
  'green': (bg: Color(0xFF17573A), fg: Color(0xFFF4FFF8), accent: Color(0xFFFDE68A)),
  'black': (bg: Color(0xFF14181F), fg: Color(0xFFF9FAFB), accent: Color(0xFF7DD3FC)),
  'white': (bg: Color(0xFFF8FAFC), fg: Color(0xFF0F172A), accent: Color(0xFF2563EB)),
  'ruled': (bg: Color(0xFFEFF4FF), fg: Color(0xFF1E3A8A), accent: Color(0xFFDC2626)),
  'graph': (bg: Color(0xFFFFFDF5), fg: Color(0xFF1F2937), accent: Color(0xFF059669)),
};

/// The classroom itself — a Zoom-style class drawn & spoken in Flutter.
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

class _LessonPlayerScreenState extends State<LessonPlayerScreen> {
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  DartPdfIndex? _index;
  String _pageDir = '';
  List<_Scene> _scenes = [];
  List<String> _brainPoints = const [];
  int _scene = 0;
  bool _playing = false;
  bool _loading = true;

  // --- sync state for the current scene ---
  Timer? _timer;
  int _spoken = 0; // chars the voice has actually reached
  bool _rangeSeen = false;
  bool _ttsDone = false;
  bool _advancing = false;
  DateTime _sceneStart = DateTime.now();
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final index = await DartEngine.loadIndex(widget.sessionId);
    final dir = await DartEngine.pageDirOf(widget.sessionId);
    _brainPoints = await DartEngine.brainKeyPoints(widget.sessionId);
    _ttsCh.setMethodCallHandler((call) async {
      if (call.method == 'ttsRange') {
        final end = (call.arguments is Map) ? (call.arguments['end'] as num?)?.toInt() ?? 0 : 0;
        if (end > _spoken) {
          _spoken = end;
          _rangeSeen = true;
        }
      } else if (call.method == 'ttsDone' || call.method == 'ttsError') {
        _ttsDone = true;
      }
    });
    if (!mounted) return;
    setState(() {
      _index = index;
      _pageDir = dir;
      _scenes = _buildScenes(index);
      _loading = false;
    });
    if (_scenes.isNotEmpty) _playScene(0);
  }

  // ---------- scene construction ----------

  static List<String> _sentences(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Board + font follow the matter: formulas get the graph board and a
  /// mono font, definitions the green board, examples the white board,
  /// long explanations the ruled notebook.
  ({String theme, bool formula}) _styleFor(String text, int i) {
    final forced = widget.settings.theme;
    if (forced.contains('green')) return (theme: 'green', formula: false);
    if (forced.contains('black')) return (theme: 'black', formula: false);
    if (forced.contains('white')) return (theme: 'white', formula: false);
    if (forced.contains('ruled')) return (theme: 'ruled', formula: false);
    if (forced.contains('graph')) return (theme: 'graph', formula: true);
    final t = text.toLowerCase();
    final mathHits = RegExp(r'[=+×÷√π%^<>]').allMatches(text).length + RegExp(r'\d').allMatches(text).length;
    if (mathHits >= 4) return (theme: 'graph', formula: true);
    if (t.contains('example') || t.contains('for instance')) return (theme: 'white', formula: false);
    if (t.contains('is called') || t.contains(' is defined ') || t.contains('means ') || t.contains('definition')) {
      return (theme: 'green', formula: false);
    }
    if (text.length > 240) return (theme: 'ruled', formula: false);
    const cycle = ['green', 'black', 'white', 'ruled', 'graph'];
    return (theme: cycle[i % cycle.length], formula: false);
  }

  /// Figure/diagram zones: big text-free gaps between text bands.
  List<Rect> _imageZones(DartPage page) {
    final bands = page.blocks.where((b) => b.bbox.length == 4).toList()..sort((a, b) => a.bbox[1].compareTo(b.bbox[1]));
    if (bands.isEmpty) return const [];
    final zones = <Rect>[];
    var prevBottom = bands.first.bbox[3];
    for (var i = 1; i < bands.length; i++) {
      final top = bands[i].bbox[1];
      if (top - prevBottom > 0.13) {
        zones.add(Rect.fromLTRB(0.05, prevBottom + 0.015, 0.95, top - 0.015));
      }
      prevBottom = math.max(prevBottom, bands[i].bbox[3]);
    }
    if (prevBottom < 0.84) zones.add(Rect.fromLTRB(0.05, prevBottom + 0.015, 0.95, 0.97));
    zones.sort((a, b) => b.height.compareTo(a.height));
    return zones.take(1).toList();
  }

  String _captionNear(DartPage page, Rect zone) {
    DartBlock? caption;
    DartBlock? after;
    for (final b in page.blocks) {
      if (b.bbox.length != 4) continue;
      final t = b.text.toLowerCase();
      if (t.contains('fig') || t.contains('diagram') || t.contains('table') || t.contains('picture')) {
        caption ??= b;
      }
      if (b.bbox[1] >= zone.bottom - 0.02) after ??= b;
    }
    final c = (caption ?? after)?.text.trim() ?? '';
    return c.length > 200 ? c.substring(0, 200) : c;
  }

  List<_Scene> _buildScenes(DartPdfIndex? index) {
    if (index == null) return const [];
    final scenes = <_Scene>[
      _Scene('title', widget.title,
          'Part ${widget.partNumber}. Pages ${widget.pages.isEmpty ? '' : '${widget.pages.first} to ${widget.pages.last}'}. Let us learn this part step by step, page by page.'),
    ];
    final keyPoints = <String>[..._brainPoints];
    for (final pg in widget.pages) {
      for (final s in _sentences(index.pageText(pg))) {
        if (s.length > 40 && !s.toLowerCase().contains('click here') && keyPoints.length < 10) keyPoints.add(s);
      }
    }
    var kp = 0;
    var styleIdx = 0;
    for (final pg in widget.pages) {
      final page = index.pages[pg - 1];
      final sents = _sentences(index.pageText(pg)).where((s) => s.length > 30).take(2).toList();
      final narration = sents.isEmpty ? 'Read this page carefully and notice the highlighted lines.' : sents.join(' ');
      scenes.add(_Scene('reading', 'Page $pg', narration.length > 460 ? narration.substring(0, 460) : narration, page: pg));
      // Zoom into the page's figure/diagram and explain it.
      for (final zone in _imageZones(page)) {
        final cap = _captionNear(page, zone);
        final explain = cap.isNotEmpty
            ? 'Look carefully at this figure. $cap'
            : 'Look carefully at this picture on page $pg. Notice every label and part — your test may ask about it.';
        scenes.add(_Scene('zoom', 'Figure • Page $pg', explain, page: pg, zone: zone));
      }
      if (kp < keyPoints.length) {
        final point = keyPoints[kp];
        final st = _styleFor(point, styleIdx++);
        scenes.add(_Scene('board', kp < _brainPoints.length ? 'Brain key point' : 'Key point',
            point.length > 320 ? point.substring(0, 320) : point,
            boardTheme: st.theme, formula: st.formula));
        kp++;
      }
    }
    scenes.add(const _Scene('end', 'Part complete', 'You finished this part. Take the test for this part — score forty percent or more to unlock the next part.'));
    return scenes;
  }

  // ---------- playback engine (voice-driven) ----------

  double _estSeconds(String text) => (text.length / 13.5).clamp(2.5, 50.0).toDouble();

  int get _revealed {
    final s = _scenes.isEmpty ? null : _scenes[_scene];
    if (s == null) return 0;
    if (_rangeSeen) return math.min(s.narration.length, _spoken);
    final elapsed = DateTime.now().difference(_sceneStart).inMilliseconds / 1000.0;
    if (elapsed < 0.8) return 0;
    final frac = (elapsed / _estSeconds(s.narration)).clamp(0.0, 1.0);
    return (s.narration.length * frac).floor();
  }

  double get _progress {
    final s = _scenes.isEmpty ? null : _scenes[_scene];
    if (s == null) return 0;
    return (_revealed / math.max(1, s.narration.length)).clamp(0.0, 1.0).toDouble();
  }

  void _playScene(int i) {
    _timer?.cancel();
    final s = _scenes[i];
    setState(() {
      _scene = i;
      _playing = true;
      _spoken = 0;
      _rangeSeen = false;
      _ttsDone = false;
      _advancing = false;
      _sceneStart = DateTime.now();
      _tick = 0;
    });
    _ttsCh.invokeMethod('speak', {
      'text': s.narration,
      'language': widget.settings.language == 'te-IN' ? 'te-IN' : 'en-IN',
      'rate': 0.92,
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
      final finishedVoice = _ttsDone && _revealed >= s.narration.length - 2;
      final hardCap = elapsed > _estSeconds(s.narration) + 14;
      if (!_advancing && elapsed >= 1 && (finishedVoice || hardCap)) {
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

  void _finish() {
    _timer?.cancel();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  // ---------- views ----------

  String _currentSentence(_Scene s) {
    final end = math.min(s.narration.length, _revealed + 1);
    final upto = s.narration.substring(0, end);
    final parts = _sentences(s.narration);
    var acc = 0;
    for (final p in parts) {
      acc += p.length + 1;
      if (end <= acc) return p;
    }
    return upto;
  }

  Widget _revealedText(String text, {required Color main, required Color dim, required double size, bool mono = false, double height = 1.6}) {
    final r = math.min(text.length, _revealed);
    return RichText(
      text: TextSpan(children: [
        TextSpan(
            text: text.substring(0, r),
            style: TextStyle(color: main, fontSize: size, height: height, fontWeight: FontWeight.w700, fontFamily: mono ? 'monospace' : null)),
        TextSpan(
            text: text.substring(r),
            style: TextStyle(color: dim, fontSize: size, height: height, fontWeight: FontWeight.w500, fontFamily: mono ? 'monospace' : null)),
      ]),
    );
  }

  Widget _boardView(_Scene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final len = s.narration.length;
    final size = s.formula ? (len > 160 ? 19.0 : 23.0) : (len > 260 ? 16.5 : len > 140 ? 19.0 : 22.0);
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
      ),
      child: Stack(children: [
        if (s.boardTheme == 'ruled' || s.boardTheme == 'graph')
          Positioned.fill(child: CustomPaint(painter: _BoardLinesPainter(theme: s.boardTheme, color: c.accent))),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(s.heading.toUpperCase(),
                  style: TextStyle(color: c.accent, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 13)),
              const Spacer(),
              Text(s.formula ? 'FORMULA' : s.boardTheme.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(color: c.accent.withOpacity(0.75), fontWeight: FontWeight.w800, letterSpacing: 1.1, fontSize: 10.5)),
            ]),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: _revealedText(s.narration, main: c.fg, dim: c.fg.withOpacity(0.35), size: size, mono: s.formula),
              ),
            ),
            Row(children: [
              Icon(Icons.draw_rounded, size: 16, color: c.accent),
              const SizedBox(width: 6),
              Text(_ttsDone ? 'done — next…' : 'writing with the voice…', style: TextStyle(color: c.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pageImage(_Scene s, {Rect? zone, double zoomT = 0}) {
    final img = File('$_pageDir/page_${s.page}.png');
    if (!img.existsSync()) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: _revealedText(s.narration, main: const Color(0xFF334155), dim: const Color(0xFF94A3B8), size: 16),
        ),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      Widget image = Image.file(img, fit: BoxFit.fill, width: w, height: h);
      if (zone != null) {
        final target = math.min(4.2, 0.92 / math.max(0.15, zone.width)).toDouble();
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

  Widget _readingView(_Scene s) {
    final blocks = (_index != null && s.page != null) ? _index!.pages[s.page! - 1].blocks : const <DartBlock>[];
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFF6F1E7), borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        Rect? rect;
        if (blocks.isNotEmpty) {
          final idx = math.min(blocks.length - 1, (_progress * blocks.length).floor());
          final b = blocks[idx].bbox;
          if (b.length == 4) rect = Rect.fromLTRB(b[0] * w, b[1] * h, b[2] * w, b[3] * h);
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

  Widget _zoomView(_Scene s) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF0B1220), borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(10),
      child: Stack(children: [
        Positioned.fill(child: _pageImage(s, zone: s.zone, zoomT: Curves.easeInOut.transform(_progress.clamp(0.0, 1.0)))),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(99)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.zoom_in_rounded, size: 14, color: Colors.white),
              SizedBox(width: 5),
              Text('FIGURE FOCUS', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1)),
            ]),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.72), borderRadius: BorderRadius.circular(12)),
            child: Text(s.narration, maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.45)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _scenes.isEmpty ? null : _scenes[_scene];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
        actions: [
          TextButton(onPressed: _finish, child: const Text('Finish', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : s == null
              ? const EmptyState(icon: Icons.error_outline_rounded, title: 'Lesson not available', message: 'This textbook could not be prepared on this device.')
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.red.withOpacity(0.15), borderRadius: BorderRadius.circular(99)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.circle, size: 8, color: AppColors.red),
                          SizedBox(width: 5),
                          Text('LIVE CLASS', style: TextStyle(color: AppColors.red, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                        ]),
                      ),
                      const SizedBox(width: 10),
                      Text('Part ${widget.partNumber} • ${_scene + 1}/${_scenes.length}',
                          style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      const Spacer(),
                      Text(
                          s.kind == 'reading'
                              ? 'Reading the textbook'
                              : s.kind == 'zoom'
                                  ? 'Looking at the figure'
                                  : s.kind == 'board'
                                      ? 'On the board'
                                      : '',
                          style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: _scenes.isEmpty ? 0 : (_scene + _progress) / _scenes.length,
                        minHeight: 6,
                        backgroundColor: AppColors.stroke,
                        valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                        child: s.kind == 'reading'
                            ? _readingView(s)
                            : s.kind == 'zoom'
                                ? _zoomView(s)
                                : _boardView(s)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
                      child: Row(children: [
                        const Icon(Icons.subtitles_rounded, size: 16, color: AppColors.teal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_currentSentence(s), maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.text, height: 1.45, fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      IconButton.filledTonal(onPressed: _scene > 0 ? _prev : null, icon: const Icon(Icons.skip_previous_rounded)),
                      IconButton.filled(
                        onPressed: _toggle,
                        icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
                        style: IconButton.styleFrom(backgroundColor: AppColors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)),
                      ),
                      IconButton.filledTonal(
                        onPressed: _scene < _scenes.length - 1 ? () => _next() : _finish,
                        icon: Icon(_scene < _scenes.length - 1 ? Icons.skip_next_rounded : Icons.check_rounded),
                      ),
                    ]),
                  ]),
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
