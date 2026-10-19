import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../auth_models.dart';
import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'exams_hub_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'share_pdf_screen.dart';
import 'textbook_screen.dart';

class HomeScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  final AppUser? user;
  final VoidCallback? onSignOut;
  const HomeScreen({super.key, required this.gateway, required this.settings, this.user, this.onSignOut});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TextbookItem> _books = [];
  Map<String, double> _progress = {};
  bool _loading = true;
  bool _adding = false;
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
      final prog = <String, double>{};
      for (final b in books) {
        try {
          final s = await widget.gateway.chapterSeries(b.sessionId,
              pagesPerPart: widget.settings.pagesPerPart, brain: widget.settings.brain, brainServerUrl: widget.settings.brainServerUrl);
          final parts = ((s['parts'] as List?) ?? const []).whereType<Map>().map(SeriesPart.fromMap).toList();
          final localDone = await ProgressStore.completedParts(b.sessionId);
          final done = parts.where((p) => p.completed || localDone.contains(p.part)).length;
          prog[b.sessionId] = parts.isEmpty ? 0 : done / parts.length;
        } catch (_) {
          prog[b.sessionId] = 0;
        }
      }
      if (!mounted) return;
      setState(() {
        _books = books;
        _progress = prog;
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

  Future<void> _addTextbook() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => _adding = true);
    try {
      final s = await widget.gateway.createSession(
        pdfPath: path,
        language: widget.settings.language,
        brain: widget.settings.brain,
        brainServerUrl: widget.settings.brainServerUrl,
      );
      final book = TextbookItem(
        sessionId: (s['session_id'] ?? '').toString(),
        title: (s['title'] ?? 'Textbook').toString(),
        pageCount: (s['page_count'] as num?)?.toInt() ?? 0,
        state: 'active',
        brain: (s['brain'] ?? '').toString(),
      );
      // Teachers/principals: the new textbook is automatically shared -
      // uploaded to Gofile and registered in the cloud link catalog.
      final u = widget.user;
      if (u != null && u.role.canUpload) {
        _autoShare(path, book.title);
      }
      if (!mounted) return;
      setState(() => _adding = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TextbookScreen(gateway: widget.gateway, settings: widget.settings, book: book),
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add textbook: $e')));
    }
  }

  /// Fire-and-forget: upload the just-added textbook to Gofile, record it
  /// for the school, and register the link in the cloud catalog. Sharing
  /// must never block or break studying, so failures stay quiet.
  Future<void> _autoShare(String pdfPath, String title) async {
    final u = widget.user;
    if (u == null) return;
    try {
      final up = await GofileService.uploadPdf(file: File(pdfPath), userId: u.id);
      final now = DateTime.now().millisecondsSinceEpoch;
      await AuthStore.addSharedPdf(SharedPdf(
        id: 'pdf_$now',
        title: title.isEmpty ? up.name : title,
        fileName: up.name,
        downloadPage: up.downloadPage,
        uploadedById: u.id,
        uploadedByName: u.name,
        schoolId: u.schoolId,
        className: '',
        localPath: pdfPath,
        createdAt: now,
      ));
      final posted = await CatalogService.post(
        widget.settings,
        CatalogEntry(t: title.isEmpty ? up.name : title, u: up.downloadPage, by: u.name, cls: '', ts: now),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(posted ? 'Textbook shared to Gofile + cloud catalog' : 'Textbook shared to Gofile')));
    } catch (_) {
      // Offline or Gofile hiccup: the textbook still works on this device.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adding ? null : _addTextbook,
        icon: _adding
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file_rounded),
        label: const Text('Add textbook'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 96),
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.school_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('AI Textbook Classroom', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.text)),
                    Text('Learn any chapter, page by page', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ]),
                ),
                IconButton(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SettingsScreen(settings: widget.settings)));
                    _load();
                  },
                  icon: const Icon(Icons.settings_rounded, color: AppColors.muted),
                ),
                if (widget.onSignOut != null)
                  IconButton(
                    tooltip: 'Sign out (${widget.user?.name ?? ''})',
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout_rounded, color: AppColors.muted),
                  ),
              ]),
              const SizedBox(height: 20),
              GradientCard(
                gradient: AppColors.heroGradient,
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your teacher is ready.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                  const SizedBox(height: 6),
                  const Text('Upload a textbook PDF. The chapter is split into parts — watch, answer, and unlock the next class.',
                      style: TextStyle(color: Colors.white70, height: 1.45)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: const [
                    _HeroChip(icon: Icons.highlight_rounded, label: 'Live page highlights'),
                    _HeroChip(icon: Icons.draw_rounded, label: 'Voice-synced writing'),
                    _HeroChip(icon: Icons.lock_open_rounded, label: 'Part unlocking'),
                    _HeroChip(icon: Icons.chat_rounded, label: 'Ask PDF chat'),
                  ]),
                ]),
              ),
              const SectionTitle('Academics'),
              Row(children: [
                Expanded(
                  child: GradientCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ExamsHubScreen(gateway: widget.gateway, settings: widget.settings),
                    )),
                    padding: const EdgeInsets.all(16),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.quiz_rounded, color: AppColors.teal, size: 26),
                      SizedBox(height: 10),
                      Text('Exams & Tests', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 15)),
                      SizedBox(height: 3),
                      Text('MCQ • Fill • Short\nTimed exams, doubt clearing', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45)),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GradientCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ReportScreen(gateway: widget.gateway, settings: widget.settings),
                    )),
                    padding: const EdgeInsets.all(16),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.emoji_events_rounded, color: AppColors.amber, size: 26),
                      SizedBox(height: 10),
                      Text('Report Card', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 15)),
                      SizedBox(height: 3),
                      Text('Marks • Grades • Rank & level\nWeak-part revision plan', style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45)),
                    ]),
                  ),
                ),
              ]),
              if (widget.user != null && widget.user!.role.canUpload) ...[
                const SizedBox(height: 12),
                GradientCard(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SharePdfScreen(user: widget.user!, settings: widget.settings),
                  )),
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: AppColors.red.withOpacity(0.14), borderRadius: BorderRadius.circular(13)),
                      child: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.red),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Share PDFs with students', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 15)),
                        SizedBox(height: 3),
                        Text('Free Gofile shelf — students download & keep PDFs. Videos come from the engine, never uploads.',
                            style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.45)),
                      ]),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: AppColors.muted),
                  ]),
                ),
              ],
              const SectionTitle('My textbooks'),
              if (_loading)
                const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                EmptyState(icon: Icons.cloud_off_rounded, title: 'Engine not reachable', message: _error!, buttonLabel: 'Retry', onButton: _load)
              else if (_books.isEmpty)
                const EmptyState(
                  icon: Icons.menu_book_rounded,
                  title: 'No textbooks yet',
                  message: 'Tap “Add textbook”, choose a chapter PDF, and your first class series will be created.',
                )
              else
                ..._books.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GradientCard(
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => TextbookScreen(gateway: widget.gateway, settings: widget.settings, book: b, viewer: widget.user),
                          ));
                          _load();
                        },
                        child: Row(children: [
                          Container(
                            width: 52,
                            height: 64,
                            decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 26),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b.shortTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text('${b.pageCount} pages • ${b.state}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: _progress[b.sessionId] ?? 0,
                                  minHeight: 6,
                                  backgroundColor: AppColors.stroke,
                                  valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          ProgressRing(value: _progress[b.sessionId] ?? 0, size: 52),
                        ]),
                      ),
                    )),
              const SizedBox(height: 10),
              const GradientCard(
                child: Row(children: [
                  Icon(Icons.phone_android_rounded, color: AppColors.teal),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Videos are rendered on this phone. Only the AI brain may use the internet, depending on your Settings.',
                        style: TextStyle(color: AppColors.muted, height: 1.45, fontSize: 13)),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeroChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}
