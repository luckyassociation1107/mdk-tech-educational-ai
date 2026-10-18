import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class PlayerScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  final String sessionId;
  final String videoPath;
  final String captionsPath;
  final String title;
  final int? part;

  const PlayerScreen({
    super.key,
    required this.gateway,
    required this.settings,
    required this.sessionId,
    required this.videoPath,
    required this.captionsPath,
    required this.title,
    this.part,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _ctrl;
  List<CaptionLine> _caps = [];
  bool _ready = false;
  bool _markedDone = false;
  String? _error;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final f = File(widget.captionsPath);
      if (await f.exists()) {
        _caps = CaptionLine.parseSrt(await f.readAsString());
      }
      final c = VideoPlayerController.file(File(widget.videoPath));
      await c.initialize();
      final resume = await ProgressStore.watchPosition(widget.videoPath);
      if (resume > Duration.zero && resume < c.value.duration - const Duration(seconds: 5)) {
        await c.seekTo(resume);
      }
      c.addListener(_onTick);
      _ctrl = c;
      if (!mounted) return;
      setState(() => _ready = true);
      c.play();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  void _onTick() {
    final c = _ctrl;
    if (c == null || !mounted) return;
    if (c.value.position.inSeconds % 5 == 0) {
      ProgressStore.saveWatchPosition(widget.videoPath, c.value.position);
    }
    if (c.value.position >= c.value.duration - const Duration(seconds: 2) && c.value.duration > Duration.zero) {
      _markedDone = true;
    }
    setState(() {});
  }

  String? get _currentCaption {
    final c = _ctrl;
    if (c == null || _caps.isEmpty) return null;
    final pos = c.value.position;
    for (final line in _caps) {
      if (pos >= line.start && pos <= line.end) return line.text;
    }
    return null;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onTick);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_markedDone);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop(_markedDone)),
        ),
        body: _error != null
            ? EmptyState(icon: Icons.error_outline_rounded, title: 'Video could not play', message: _error!)
            : !_ready || c == null
                ? const Center(child: CircularProgressIndicator())
                : Column(children: [
                    AspectRatio(
                      aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                      child: Stack(alignment: Alignment.center, children: [
                        VideoPlayer(c),
                        if (!c.value.isPlaying)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle, border: Border.all(color: Colors.white54)),
                            child: const Icon(Icons.play_arrow_rounded, size: 44, color: Colors.white),
                          ),
                        Positioned.fill(
                          child: GestureDetector(onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play())),
                        ),
                        if (_currentCaption != null)
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.78), borderRadius: BorderRadius.circular(10)),
                              child: Text(_currentCaption!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35, fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                      child: Row(children: [
                        Text(_fmt(c.value.position), style: const TextStyle(color: AppColors.muted)),
                        Expanded(
                          child: Slider(
                            value: c.value.duration == Duration.zero
                                ? 0
                                : (c.value.position.inMilliseconds / c.value.duration.inMilliseconds).clamp(0, 1),
                            onChanged: (v) => c.seekTo(Duration(milliseconds: (v * c.value.duration.inMilliseconds).round())),
                          ),
                        ),
                        Text(_fmt(c.value.duration), style: const TextStyle(color: AppColors.muted)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        IconButton(
                          icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 30),
                          onPressed: () => c.seekTo(c.value.position - const Duration(seconds: 10)),
                        ),
                        IconButton(
                          icon: Icon(c.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                              color: Colors.white, size: 54),
                          onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 30),
                          onPressed: () => c.seekTo(c.value.position + const Duration(seconds: 10)),
                        ),
                        PopupMenuButton<double>(
                          initialValue: _speed,
                          tooltip: 'Playback speed',
                          onSelected: (v) {
                            setState(() => _speed = v);
                            c.setPlaybackSpeed(v);
                          },
                          itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5]
                              .map((v) => PopupMenuItem(value: v, child: Text('${v}x${v == 1.0 ? ' (teacher pace)' : ''}')))
                              .toList(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(border: Border.all(color: AppColors.stroke), borderRadius: BorderRadius.circular(99)),
                            child: Text('${_speed}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ]),
                    ),
                    if (widget.part != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () {
                              ProgressStore.saveWatchPosition(widget.videoPath, Duration.zero);
                              Navigator.of(context).pop(true);
                            },
                            icon: const Icon(Icons.lock_open_rounded),
                            label: Text(_markedDone ? 'Complete Part ${widget.part} & unlock next' : 'Mark Part ${widget.part} complete & unlock next'),
                          ),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Tip: 1.0x is the teacher pace the class was recorded at. Use 0.75x for revision and pause to copy the notes.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, height: 1.45)),
                    ),
                  ]),
      ),
    );
  }
}
