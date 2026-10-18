import 'package:flutter/material.dart';

import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'chat_screen.dart';
import 'exam_setup_screen.dart';
import 'report_screen.dart';

/// Academics hub: pick a textbook + part and start a test, jump into
/// doubt clearing, or open the report card.
class ExamsHubScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  const ExamsHubScreen({super.key, required this.gateway, required this.settings});

  @override
  State<ExamsHubScreen> createState() => _ExamsHubScreenState();
}

class _ExamsHubScreenState extends State<ExamsHubScreen> {
  List<TextbookItem> _books = [];
  final Map<String, List<SeriesPart>> _parts = {};
  bool _loading = true;
  String? _error;

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
      final raw = await widget.gateway.listSessions(brain: widget.settings.brain, brainServerUrl: widget.settings.brainServerUrl);
      final books = raw.whereType<Map>().map(TextbookItem.fromMap).where((b) => b.sessionId.isNotEmpty).toList();
      for (final b in books) {
        try {
          final s = await widget.gateway.chapterSeries(b.sessionId,
              pagesPerPart: widget.settings.pagesPerPart, brain: widget.settings.brain, brainServerUrl: widget.settings.brainServerUrl);
          _parts[b.sessionId] = ((s['parts'] as List?) ?? const []).whereType<Map>().map(SeriesPart.fromMap).toList();
        } catch (_) {
          _parts[b.sessionId] = [];
        }
      }
      if (!mounted) return;
      setState(() {
        _books = books;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Exams & Academics', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 30), children: [
          GradientCard(
            gradient: AppColors.heroGradient,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Test yourself. Level up.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Auto-graded tests from your own textbook, marks, report card and ranks — all on this phone, no internet needed.',
                  style: TextStyle(color: Colors.white70, height: 1.5)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReportScreen(gateway: widget.gateway, settings: widget.settings),
                )),
                icon: const Icon(Icons.emoji_events_rounded, size: 18),
                label: const Text('Open report card'),
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.indigo),
              ),
            ]),
          ),
          const SectionTitle('Choose a textbook & part'),
          if (_loading)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            EmptyState(icon: Icons.cloud_off_rounded, title: 'Engine not reachable', message: _error!, buttonLabel: 'Retry', onButton: _load)
          else if (_books.isEmpty)
            const EmptyState(
              icon: Icons.menu_book_rounded,
              title: 'Add a textbook first',
              message: 'Tests are generated from your textbook’s key points. Go back and tap “Add textbook” to upload a chapter PDF.',
            )
          else
            ..._books.map((b) {
              final parts = _parts[b.sessionId] ?? const [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: GradientCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(13)),
                        child: const Icon(Icons.menu_book_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(b.shortTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text, fontSize: 15)),
                      ),
                    ]),
                    const SizedBox(height: 13),
                    if (parts.isEmpty)
                      const Text('Parts are still being prepared for this book.', style: TextStyle(color: AppColors.muted, fontSize: 12.5))
                    else
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ...parts.map((p) => ActionChip(
                              avatar: Icon(p.completed ? Icons.check_circle_rounded : Icons.quiz_rounded,
                                  size: 16, color: p.completed ? AppColors.green : AppColors.teal),
                              label: Text('Part ${p.part} test'),
                              backgroundColor: AppColors.cardLight,
                              side: const BorderSide(color: AppColors.stroke),
                              labelStyle: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12.5),
                              onPressed: () async {
                                await Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => ExamSetupScreen(gateway: widget.gateway, settings: widget.settings, book: b, part: p),
                                ));
                                _load();
                              },
                            )),
                      ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ChatScreen(gateway: widget.gateway, settings: widget.settings, book: b),
                          )),
                          icon: const Icon(Icons.chat_rounded, size: 17),
                          label: const Text('Clear doubts'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => ReportScreen(gateway: widget.gateway, settings: widget.settings),
                          )),
                          icon: const Icon(Icons.workspace_premium_rounded, size: 17),
                          label: const Text('My marks'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              );
            }),
        ]),
      ),
    );
  }
}
