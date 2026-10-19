import 'package:flutter/material.dart';

import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'brain_webview_screen.dart';
import 'chat_screen.dart';
import 'exam_setup_screen.dart';
import 'generate_sheet.dart';
import 'lesson_player_screen.dart';
import 'notes_screen.dart';
import 'player_screen.dart';

class TextbookScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  final TextbookItem book;

  const TextbookScreen({super.key, required this.gateway, required this.settings, required this.book});

  @override
  State<TextbookScreen> createState() => _TextbookScreenState();
}

class _TextbookScreenState extends State<TextbookScreen> {
  List<SeriesPart> _parts = [];
  List<VideoItem> _videos = [];
  Set<int> _localDone = {};
  bool _loading = true;
  String? _error;
  bool _generating = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.gateway.chapterSeries(widget.book.sessionId,
          pagesPerPart: widget.settings.pagesPerPart, brain: widget.settings.brain, brainServerUrl: widget.settings.brainServerUrl);
      final parts = ((s['parts'] as List?) ?? const []).whereType<Map>().map(SeriesPart.fromMap).toList()
        ..sort((a, b) => a.part.compareTo(b.part));
      final vids = await widget.gateway.sessionVideos(widget.book.sessionId,
          brain: widget.settings.brain, brainServerUrl: widget.settings.brainServerUrl);
      final done = await ProgressStore.completedParts(widget.book.sessionId);
      if (!mounted) return;
      setState(() {
        _parts = parts;
        _videos = vids.whereType<Map>().map(VideoItem.fromMap).toList();
        _localDone = done;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool _isDone(SeriesPart p) => p.completed || _localDone.contains(p.part);

  bool _isUnlocked(SeriesPart p) {
    if (p.unlocked || p.part == 1) return true;
    final prev = _parts.where((x) => x.part == p.part - 1);
    return prev.isNotEmpty && _isDone(prev.first);
  }

  double get _progress {
    if (_parts.isEmpty) return 0;
    return _parts.where(_isDone).length / _parts.length;
  }

  Future<void> _generate(SeriesPart part) async {
    final next = _parts.where((x) => x.part == part.part + 1).firstOrNull;
    final cfg = await showGenerateSheet(
      context,
      bookTitle: widget.book.shortTitle,
      part: part,
      nextPart: next,
      settings: widget.settings,
    );
    if (cfg == null || !mounted) return;
    setState(() => _generating = true);
    try {
      final out = await widget.gateway.generateVideo(
        sessionId: widget.book.sessionId,
        question: cfg.question,
        mode: cfg.mode,
        resolution: widget.settings.resolution,
        theme: widget.settings.theme,
        pageReading: cfg.pageReading,
        pageRange: part.pages,
        partLabel: 'Part ${part.part}: ${part.pageLabel}',
        nextPartLabel: next == null ? '' : 'Part ${next.part}: ${next.pageLabel}',
        brain: widget.settings.brain,
        brainServerUrl: widget.settings.brainServerUrl,
      );
      if (!mounted) return;
      setState(() => _generating = false);
      await _load();
      final path = out['output']?.toString();
      if (path != null && path.isNotEmpty) {
        _openPlayer(path: path, title: 'Part ${part.part} — ${part.pageLabel}', part: part, captionsPath: out['captions']?.toString());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generation failed: $e')));
    }
  }

  Future<void> _openPlayer({required String path, required String title, SeriesPart? part, String? captionsPath}) async {
    final bool? completed;
    if (path.startsWith('lesson://')) {
      // Interactive Flutter lesson (board + voice + highlighted pages).
      completed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => LessonPlayerScreen(
          settings: widget.settings,
          sessionId: widget.book.sessionId,
          title: title,
          partNumber: part?.part ?? 0,
          pages: part?.pages ?? const [],
        ),
      ));
    } else {
      completed = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => PlayerScreen(
          gateway: widget.gateway,
          settings: widget.settings,
          sessionId: widget.book.sessionId,
          videoPath: path,
          captionsPath: captionsPath ?? path.replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '.srt'),
          title: title,
          part: part?.part,
        ),
      ));
    }
    if (completed == true && part != null) {
      await ProgressStore.setPartCompleted(widget.book.sessionId, part.part, true);
      try {
        await widget.gateway.completePart(widget.book.sessionId, part.part,
            brain: widget.settings.brain, brainServerUrl: widget.settings.brainServerUrl);
      } catch (_) {/* engine unlock mirrors on next load anyway */}
    }
    _load();
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close this textbook session?'),
        content: const Text('Temporary files will be cleaned up on the device. Your exported videos stay saved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close session')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.gateway.disconnect(widget.book.sessionId);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Close failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.book.shortTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.settings.brain == 'website')
            IconButton(
              tooltip: 'AI Brain (website)',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BrainWebViewScreen(
                    gateway: widget.gateway, settings: widget.settings, sessionId: widget.book.sessionId, bookTitle: widget.book.shortTitle),
              )),
              icon: const Icon(Icons.psychology_rounded),
            ),
          IconButton(
            tooltip: 'Ask PDF',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChatScreen(gateway: widget.gateway, settings: widget.settings, book: widget.book),
            )),
            icon: const Icon(Icons.chat_rounded),
          ),
          IconButton(tooltip: 'Close session', onPressed: _disconnect, icon: const Icon(Icons.logout_rounded)),
        ],
      ),
      body: Stack(children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
            children: [
              GradientCard(
                gradient: AppColors.heroGradient,
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.book.shortTitle, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text('${widget.book.pageCount} pages • ${_parts.length} parts • ${(_progress * 100).round()}% completed',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 8,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 14),
                  ProgressRing(value: _progress, size: 64),
                ]),
              ),
              const SectionTitle('Chapter series'),
              if (_loading)
                const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                EmptyState(icon: Icons.error_outline_rounded, title: 'Could not load the series', message: _error!, buttonLabel: 'Retry', onButton: _load)
              else if (_parts.isEmpty)
                const EmptyState(icon: Icons.layers_rounded, title: 'No parts yet', message: 'The chapter series will appear here once the textbook is analyzed.')
              else
                ..._parts.map((p) {
                  final done = _isDone(p);
                  final unlocked = _isUnlocked(p);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Opacity(
                      opacity: unlocked ? 1 : 0.62,
                      child: GradientCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: done ? const LinearGradient(colors: [AppColors.green, AppColors.teal]) : AppColors.accentGradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(done ? Icons.check_rounded : Icons.play_lesson_rounded, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Part ${p.part}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.text)),
                                Text(p.pageLabel, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                              ]),
                            ),
                            LockBadge(unlocked: unlocked, completed: done),
                          ]),
                          if (p.keyPoints.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ...p.keyPoints.take(2).map((k) => Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Text('•  ', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w900)),
                                    Expanded(child: Text(k, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, height: 1.4, fontSize: 13))),
                                  ]),
                                )),
                          ],
                          const SizedBox(height: 12),
                          Row(children: [
                            ...[
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: unlocked && !_generating ? () => _generate(p) : null,
                                  icon: const Icon(Icons.movie_creation_rounded, size: 18),
                                  label: Text(done ? 'Generate again' : 'Generate class'),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: unlocked
                                    ? () {
                                        final v = _videos.where((x) => x.playablePath != null).lastOrNull;
                                        if (v?.playablePath != null) {
                                          _openPlayer(path: v!.playablePath!, title: 'Part ${p.part} — ${p.pageLabel}', part: p);
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Generate this part first — then it will play here.')));
                                        }
                                      }
                                    : null,
                                icon: const Icon(Icons.play_circle_rounded, size: 18),
                                label: const Text('Watch'),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: unlocked
                                  ? () async {
                                      await Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => ExamSetupScreen(
                                            gateway: widget.gateway, settings: widget.settings, book: widget.book, part: p),
                                      ));
                                      _load();
                                    }
                                  : null,
                              icon: const Icon(Icons.quiz_rounded, size: 18),
                              label: const Text('Take test — 40% unlocks the next part'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.teal,
                                side: const BorderSide(color: AppColors.teal),
                              ),
                            ),
                          ),
                          if (!unlocked)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text('Finish the previous part and mark it complete to unlock this class.',
                                  style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                            ),
                        ]),
                      ),
                    ),
                  );
                }),
              const SectionTitle('Your videos'),
              if (_videos.isEmpty)
                const GradientCard(
                  child: Text('Generated classes for this textbook will appear here.', style: TextStyle(color: AppColors.muted)),
                )
              else
                ..._videos.map((v) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GradientCard(
                        onTap: v.playablePath == null
                            ? null
                            : () => _openPlayer(path: v.playablePath!, title: v.question),
                        child: Row(children: [
                          const Icon(Icons.smart_display_rounded, color: AppColors.teal, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(v.question, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                              Text(v.status, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                            ]),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                        ]),
                      ),
                    )),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChatScreen(gateway: widget.gateway, settings: widget.settings, book: widget.book),
                    )),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Ask PDF'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => NotesScreen(book: widget.book, parts: _parts, videos: _videos),
                    )),
                    icon: const Icon(Icons.note_alt_rounded),
                    label: const Text('Notes'),
                  ),
                ),
              ]),
            ],
          ),
        ),
        if (_generating) const Positioned.fill(child: GenerationProgress()),
      ]),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
  E? get lastOrNull => isEmpty ? null : last;
}
