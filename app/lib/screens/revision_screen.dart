import 'package:flutter/material.dart';

import '../dart_engine.dart';
import '../engine_gateway.dart';
import '../exam_store.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'flashcards_screen.dart';
import 'lesson_player_screen.dart';

/// "Revise what is weak" — reads the student's own test history on this
/// phone and turns every part below 60% into a one-tap revision plan:
/// re-watch the class, run its flashcards, then retry the test.
class RevisionScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  const RevisionScreen({super.key, required this.gateway, required this.settings});

  @override
  State<RevisionScreen> createState() => _RevisionScreenState();
}

class _RevisionScreenState extends State<RevisionScreen> {
  ReportData? _report;
  final Map<String, List<SeriesPart>> _partsBySession = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await ExamStore.loadAll();
    final report = ReportData(results);
    for (final p in report.weakParts.take(12)) {
      if (_partsBySession.containsKey(p.sessionId)) continue;
      try {
        final s = await widget.gateway.chapterSeries(
          p.sessionId,
          pagesPerPart: widget.settings.pagesPerPart,
          brain: widget.settings.brain,
          brainServerUrl: widget.settings.brainServerUrl,
        );
        _partsBySession[p.sessionId] =
            ((s['parts'] as List?) ?? const []).whereType<Map>().map(SeriesPart.fromMap).toList();
      } catch (_) {
        _partsBySession[p.sessionId] = const [];
      }
    }
    if (!mounted) return;
    setState(() {
      _report = report;
      _loading = false;
    });
  }

  Future<void> _rewatch(PartStats p) async {
    final parts = _partsBySession[p.sessionId] ?? const <SeriesPart>[];
    final part = parts.where((x) => x.part == p.part).firstOrNull;
    final pages = part?.pages ?? const <int>[];
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LessonPlayerScreen(
        settings: widget.settings,
        sessionId: p.sessionId,
        title: '${p.title} • Part ${p.part}',
        partNumber: p.part,
        pages: pages,
      ),
    ));
    _load();
  }

  Future<void> _flashcards(PartStats p) async {
    final parts = _partsBySession[p.sessionId] ?? const <SeriesPart>[];
    int count = 0;
    try {
      final index = await DartEngine.loadIndex(p.sessionId);
      count = index?.pageCount ?? 0;
    } catch (_) {}
    if (!mounted) return;
    final book = TextbookItem(
      sessionId: p.sessionId,
      title: p.title,
      pageCount: count,
      state: 'active',
      brain: '',
    );
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlashcardsScreen(
        settings: widget.settings,
        book: book,
        parts: parts.where((x) => x.part == p.part).toList(),
      ),
    ));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final weak = _report?.weakParts ?? const <PartStats>[];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title:  Text('Revise weak topics', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 26),
                children: [
                  GradientCard(
                    gradient: const LinearGradient(colors: [Color(0xFF7C2D12), Color(0xFF4338CA)]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Built from your own marks', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Text(
                        weak.isEmpty
                            ? 'No weak part right now. Take a part test — anything below 60% will appear here with a revision plan.'
                            : '${weak.length} part${weak.length == 1 ? '' : 's'} scored below 60%. Re-watch the class, run the flashcards, then retry the test.',
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.45),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  ...weak.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GradientCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: (p.avg < 40 ? AppColors.red : AppColors.amber).withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text('${p.avg.round()}%',
                                    style: TextStyle(
                                        color: p.avg < 40 ? AppColors.red : AppColors.amber,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13)),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style:  TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 13.5)),
                                  Text('Part ${p.part} • ${p.partLabel} • ${p.tests} test${p.tests == 1 ? '' : 's'}',
                                      style:  TextStyle(color: AppColors.muted, fontSize: 11.5)),
                                ]),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _rewatch(p),
                                  icon: const Icon(Icons.play_circle_rounded, size: 17),
                                  label: const Text('Re-watch'),
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 11)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _flashcards(p),
                                  icon: const Icon(Icons.style_rounded, size: 17),
                                  label: const Text('Flashcards'),
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.teal, side:  BorderSide(color: AppColors.teal)),
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      )),
                  if (weak.isEmpty)
                    const EmptyState(
                      icon: Icons.emoji_events_rounded,
                      title: 'Nothing weak yet',
                      message: 'Your report card builds this plan automatically after each part test.',
                    ),
                ],
              ),
            ),
    );
  }
}
