import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dart_engine.dart';
import '../store.dart';
import '../widgets.dart';

class _Scene {
  final String kind; // title | reading | board | end
  final String heading;
  final String narration;
  final int? page;
  final String boardTheme;
  const _Scene(this.kind, this.heading, this.narration, {this.page, this.boardTheme = 'green'});
}

const _boards = <String, ({Color bg, Color fg, Color accent})>{
  'green': (bg: Color(0xFF17573A), fg: Color(0xFFF4FFF8), accent: Color(0xFFFDE68A)),
  'black': (bg: Color(0xFF14181F), fg: Color(0xFFF9FAFB), accent: Color(0xFF7DD3FC)),
  'white': (bg: Color(0xFFF8FAFC), fg: Color(0xFF0F172A), accent: Color(0xFF2563EB)),
  'ruled': (bg: Color(0xFFEFF4FF), fg: Color(0xFF1E3A8A), accent: Color(0xFFDC2626)),
  'graph': (bg: Color(0xFFFFFDF5), fg: Color(0xFF1F2937), accent: Color(0xFF059669)),
};

/// The classroom itself, drawn & spoken entirely in Flutter: board
/// writing synced to the device voice, real textbook pages with the
/// current passage highlighted, and captions. Returns true when the
/// student finished the part (so the caller unlocks the next one).
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
  // Device voice via MainActivity's Android TextToSpeech (no plugin needed).
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  DartPdfIndex? _index;
  String _pageDir = '';
  List<_Scene> _scenes = [];
  int _scene = 0;
  double _progress = 0; // 0..1 in current scene
  bool _playing = false;
  bool _ttsDone = false;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final index = await DartEngine.loadIndex(widget.sessionId);
    final dir = await DartEngine.pageDirOf(widget.sessionId);
    _ttsCh.setMethodCallHandler((call) async {
      if (call.method == 'ttsDone' || call.method == 'ttsError') _ttsDone = true;
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

  List<_Scene> _buildScenes(DartPdfIndex? index) {
    if (index == null) return const [];
    const cycle = ['green', 'white', 'black', 'ruled', 'graph'];
    final requested = widget.settings.theme;
    String boardFor(int i) {
      if (requested.contains('green')) return 'green';
      if (requested.contains('black')) return 'black';
      if (requested.contains('white')) return 'white';
      if (requested.contains('ruled')) return 'ruled';
      if (requested.contains('graph')) return 'graph';
      return cycle[i % cycle.length];
    }

    final keyPoints = <String>[];
    for (final pg in widget.pages) {
      final joined = index.pageText(pg).replaceAll(RegExp(r'\s+'), ' ').trim();
      for (final s in joined.split(RegExp(r'(?<=[.!?])\s+'))) {
        final t = s.trim();
        if (t.length > 40 && !t.toLowerCase().contains('click here')) keyPoints.add(t);
        if (keyPoints.length >= 8) break;
      }
      if (keyPoints.length >= 8) break;
    }

    final scenes = <_Scene>[
      _Scene('title', widget.title,
          'Part ${widget.partNumber}. Pages ${widget.pages.isEmpty ? '' : '${widget.pages.first} to ${widget.pages.last}'}. Let us learn this part step by step, page by page.'),
    ];
    var kp = 0;
    for (final pg in widget.pages) {
      final joined = index.pageText(pg).replaceAll(RegExp(r'\s+'), ' ').trim();
      final sents = joined.split(RegExp(r'(?<=[.!?])\s+')).map((s) => s.trim()).where((s) => s.length > 30).take(2).toList();
      final narration = sents.isEmpty ? 'Read this page carefully and notice the highlighted lines.' : sents.join(' ');
      scenes.add(_Scene('reading', 'Page $pg', narration.length > 460 ? narration.substring(0, 460) : narration, page: pg));
      if (kp < keyPoints.length) {
        scenes.add(_Scene('board', 'Key point', keyPoints[kp], boardTheme: boardFor(kp)));
        kp++;
      }
    }
    scenes.add(const _Scene('end', 'Part complete', 'You finished this part. Take the test for this part — score forty percent or more to unlock the next part.'));
    return scenes;
  }

  double _estSeconds(String text) => (text.length / 13.5).clamp(2.5, 45.0).toDouble();

  void _playScene(int i) {
    _timer?.cancel();
    setState(() {
      _scene = i;
      _progress = 0;
      _playing = true;
      _ttsDone = false;
    });
    final scene = _scenes[i];
    _ttsCh.invokeMethod('speak', {
      'text': scene.narration,
      'language': widget.settings.language == 'te-IN' ? 'te-IN' : 'en-IN',
      'rate': 0.9,
    }).catchError((_) {
      _ttsDone = true;
    });
    final est = _estSeconds(scene.narration);
    var elapsed = 0.0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      elapsed += 0.1;
      final p = (elapsed / est).clamp(0, 1).toDouble();
      setState(() => _progress = p);
      if (p >= 1 && _ttsDone) {
        t.cancel();
        _next(auto: true);
      }
      if (elapsed > est + 8) {
        // Never trap the student on a silent TTS engine.
        t.cancel();
        _next(auto: true);
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
    _ttsCh.invokeMethod('stopTts').catchError((_) {});
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ttsCh.invokeMethod('stopTts').catchError((_) {});
    super.dispose();
  }

  Widget _boardView(_Scene s) {
    final c = _boards[s.boardTheme] ?? _boards['green']!;
    final chars = math.min(s.narration.length, (s.narration.length * _progress).floor());
    final shown = s.narration.substring(0, chars);
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.35), width: 6),
      ),
      child: Stack(children: [
        if (s.boardTheme == 'ruled' || s.boardTheme == 'graph')
          Positioned.fill(
            child: CustomPaint(painter: _BoardLinesPainter(theme: s.boardTheme, color: c.accent)),
          ),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.heading.toUpperCase(),
                style: TextStyle(color: c.accent, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontSize: 13)),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Text(shown,
                    style: TextStyle(color: c.fg, fontSize: 21, height: 1.65, fontWeight: FontWeight.w600)),
              ),
            ),
            Row(children: [
              Icon(Icons.draw_rounded, size: 16, color: c.accent),
              const SizedBox(width: 6),
              Text('writing with the voice…', style: TextStyle(color: c.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _readingView(_Scene s) {
    final img = File('$_pageDir/page_${s.page}.png');
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
          Positioned.fill(
            child: img.existsSync()
                ? Image.file(img, fit: BoxFit.contain)
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(s.narration, style: const TextStyle(color: Color(0xFF334155), fontSize: 16, height: 1.6)),
                    ),
                  ),
          ),
          if (rect != null && img.existsSync())
            Positioned.fromRect(
              rect: rect,
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

  @override
  Widget build(BuildContext context) {
    final s = _scenes.isEmpty ? null : _scenes[_scene];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('Finish', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800)),
          ),
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
                      Text('Scene ${_scene + 1} of ${_scenes.length}', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      const Spacer(),
                      Text(s.kind == 'reading' ? 'Reading the textbook' : s.kind == 'board' ? 'On the board' : '',
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
                    Expanded(child: s.kind == 'reading' ? _readingView(s) : _boardView(s)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
                      child: Text(s.narration, maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.text, height: 1.45, fontSize: 13.5)),
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
    final paint = Paint()..color = color.withOpacity(0.18)..strokeWidth = 1;
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
