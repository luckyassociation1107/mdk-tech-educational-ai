import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/ai_config.dart';
import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../study_stats.dart';
import '../ui/premium_ui.dart';
import '../updater.dart';
import '../vault/emoji_vault.dart';
import '../widgets.dart';
import 'exams_hub_screen.dart';
import 'report_screen.dart';
import 'child_gate_screen.dart';
import 'daily_challenge_screen.dart';
import 'revision_screen.dart';
import 'brain_screen.dart';
import 'profile_screen.dart';
import 'ai_settings_screen.dart';
import 'settings_screen.dart';
import 'textbook_screen.dart';

class HomeScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  const HomeScreen({super.key, required this.gateway, required this.settings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TextbookItem> _books = [];
  Map<String, double> _progress = {};
  bool _loading = true;
  bool _adding = false;
  String? _error;
  int _streak = 0;
  int _xp = 0;
  int _scenesToday = 0;
  int _minutesToday = 0;
  List<bool> _week = List<bool>.filled(7, false);
  List<BadgeInfo> _badges = const [];

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
      final raw = await widget.gateway.listSessions(
          brain: widget.settings.brain,
          brainServerUrl: widget.settings.brainServerUrl);
      final books = raw
          .whereType<Map>()
          .map(TextbookItem.fromMap)
          .where((b) => b.sessionId.isNotEmpty)
          .toList();
      final prog = <String, double>{};
      for (final b in books) {
        try {
          final s = await widget.gateway.chapterSeries(b.sessionId,
              pagesPerPart: widget.settings.pagesPerPart,
              brain: widget.settings.brain,
              brainServerUrl: widget.settings.brainServerUrl);
          final parts = ((s['parts'] as List?) ?? const [])
              .whereType<Map>()
              .map(SeriesPart.fromMap)
              .toList();
          final localDone = await ProgressStore.completedParts(b.sessionId);
          final done = parts
              .where((p) => p.completed || localDone.contains(p.part))
              .length;
          prog[b.sessionId] = parts.isEmpty ? 0 : done / parts.length;
        } catch (_) {
          prog[b.sessionId] = 0;
        }
      }
      final streak = await StudyStats.streak();
      final xp = await StudyStats.totalXp();
      final scenes = await StudyStats.scenesToday();
      final mins = await StudyStats.minutesToday();
      final week = await StudyStats.last7();
      final badges = await StudyStats.badges();
      if (!mounted) return;
      setState(() {
        _books = books;
        _progress = prog;
        _streak = streak;
        _xp = xp;
        _scenesToday = scenes;
        _minutesToday = mins;
        _week = week;
        _badges = badges;
        _loading = false;
      });
      _celebrateNewBadges();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _addTextbook() async {
    final picked = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked?.files.single.path;
    if (path == null) return;

    // The PDF is read by the teacher's own AI now — without a key there is
    // nothing to read it with, so say that plainly instead of failing later.
    final cfg = AiConfig.current;
    if (!cfg.ready) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Add your AI key first'),
          content: Text(
            'This app no longer reads PDFs on the device. The book is uploaded to '
            'your own AI account, which extracts the text, finds the figures and '
            'designs the lesson. Paste a key once in AI & Prompts — it is kept in '
            'the device keystore.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Open AI settings')),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const AiSettingsScreen()));
      }
      return;
    }

    setState(() => _adding = true);
    _stage = ValueNotifier('Uploading the PDF to ${cfg.provider.label}…');
    _showStageDialog();
    try {
      final s = await widget.gateway.createSession(
        pdfPath: path,
        language: widget.settings.language,
        brain: widget.settings.brain,
        brainServerUrl: widget.settings.brainServerUrl,
        onProgress: (done, total, stage) {
          _stage?.value = total > 1 ? '$stage  ($done/$total)' : stage;
        },
      );
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      final book = TextbookItem(
        sessionId: (s['session_id'] ?? '').toString(),
        title: (s['title'] ?? 'Textbook').toString(),
        pageCount: (s['page_count'] as num?)?.toInt() ?? 0,
        state: 'active',
        brain: (s['brain'] ?? '').toString(),
      );
      if (!mounted) return;
      setState(() => _adding = false);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TextbookScreen(
            gateway: widget.gateway, settings: widget.settings, book: book),
      ));
      _load();
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() => _adding = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not add textbook: $e')));
      }
    } finally {
      _stage = null;
    }
  }

  ValueNotifier<String>? _stage;

  /// A blocking "the AI is reading your book" card — the upload can take a
  /// few seconds per batch, so the teacher can see exactly what is happening.
  void _showStageDialog() {
    final stage = _stage;
    if (stage == null) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        content: ValueListenableBuilder<String>(
          valueListenable: stage,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 16),
              Text(value,
                  style: TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'The PDF is uploaded once. Pages and figures are cut and the video is built on this device.',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 11, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _celebrating = false;

  /// Shows a one-time celebration the first time a badge unlocks.
  Future<void> _celebrateNewBadges() async {
    if (_celebrating) return;
    final unlocked = _badges.where((b) => b.unlocked).map((b) => b.id).toSet();
    if (unlocked.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final seen = (p.getStringList('seen_badges') ?? const <String>[]).toSet();
    final fresh = unlocked.difference(seen);
    if (fresh.isEmpty) return;
    await p.setStringList('seen_badges', seen.union(unlocked).toList());
    if (!mounted) return;
    final badge = _badges.firstWhere((b) => b.id == fresh.first);
    _celebrating = true;
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await showCelebration(context,
        title: 'Badge unlocked!',
        subtitle: '${badge.title} — ${badge.description}');
    _celebrating = false;
  }

  String _greeting() {
    final h = DateTime.now().hour;
    final name = VaultStore.current?.name;
    final who = (name == null || name.isEmpty) ? '' : ' $name';
    if (h < 12) return 'Good morning$who — ready to learn?';
    if (h < 17) return 'Good afternoon$who — keep the streak alive';
    return 'Good evening$who — one class a day wins';
  }

  /// "Continue learning" — the single most useful action on Home.
  Widget _continueCard() {
    final next =
        _books.where((b) => (_progress[b.sessionId] ?? 0) < 1.0).toList();
    final book = next.isEmpty ? _books.first : next.first;
    final pct = ((_progress[book.sessionId] ?? 0) * 100).round();
    return GlassCard(
      padding: const EdgeInsets.all(18),
      tint: const Color(0xFF6366F1),
      alpha: 0.18,
      onTap: () async {
        await Navigator.of(context).push(PageTransition.route(
          TextbookScreen(
              gateway: widget.gateway, settings: widget.settings, book: book),
        ));
        _load();
      },
      child: Row(children: [
        Container(
          width: 54,
          height: 66,
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: AppColors.indigo.withOpacity(0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 6))
            ],
          ),
          child: const Icon(Icons.menu_book_rounded,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CONTINUE LEARNING',
                style: TextStyle(
                    color: AppColors.teal,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1)),
            const SizedBox(height: 3),
            Text(book.shortTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                    begin: 0,
                    end: (_progress[book.sessionId] ?? 0)
                        .clamp(0.0, 1.0)
                        .toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(AppColors.teal),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text('$pct% completed',
                style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 10),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
              shape: BoxShape.circle, gradient: AppColors.heroGradient),
          child: const Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: 26),
        ),
      ]),
    );
  }

  Widget _statsCard() {
    final goal = widget.settings.dailyGoal < 1 ? 12 : widget.settings.dailyGoal;
    final frac = (_scenesToday / goal).clamp(0.0, 1.0).toDouble();
    final level = StudyStats.levelForXp(_xp);
    final intoLevel = _xp % 250;
    return GradientCard(
      gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF1E1B4B)]),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: Color(0xFFFBBF24), size: 16),
              const SizedBox(width: 4),
              Text('$_streak day streak',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12)),
            ]),
          ),
          const Spacer(),
          Text('Level $level • ${StudyStats.levelName(level)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          SizedBox(
            width: 62,
            height: 62,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 62,
                height: 62,
                child: CircularProgressIndicator(
                  value: frac,
                  strokeWidth: 6,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF5EEAD4)),
                ),
              ),
              Text('${(frac * 100).round()}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_scenesToday / $goal scenes today',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
              const SizedBox(height: 2),
              Text('$_minutesToday min studied • $_xp XP total',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11.5)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (intoLevel / 250).clamp(0.0, 1.0).toDouble(),
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFA7F3D0)),
                ),
              ),
              const SizedBox(height: 4),
              Text('${250 - intoLevel} XP to level ${level + 1}',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 10.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < 7; i++) ...[
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  height: 26,
                  decoration: BoxDecoration(
                    color: _week[i]
                        ? const Color(0xFF5EEAD4)
                        : Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: _week[i]
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: Color(0xFF0F172A))
                      : null,
                ),
                const SizedBox(height: 3),
                Text(
                  i == 6
                      ? 'Today'
                      : [
                          'M',
                          'T',
                          'W',
                          'T',
                          'F',
                          'S',
                          'S'
                        ][(DateTime.now().weekday - 6 + i) % 7],
                  style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 9,
                      fontWeight: FontWeight.w700),
                ),
              ]),
            ),
            if (i < 6) const SizedBox(width: 4),
          ],
        ]),
      ]),
    );
  }

  Widget _badgesStrip() {
    final unlocked = _badges.where((b) => b.unlocked).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Achievements',
            style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
                fontSize: 14.5)),
        const SizedBox(width: 8),
        Text('$unlocked/${_badges.length}',
            style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _badges.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final b = _badges[i];
            final color = b.unlocked ? AppColors.amber : AppColors.muted;
            return Container(
              width: 74,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: b.unlocked ? color.withOpacity(0.12) : AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color:
                        b.unlocked ? color.withOpacity(0.5) : AppColors.stroke),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_badgeIcon(b.icon),
                    color:
                        b.unlocked ? color : AppColors.muted.withOpacity(0.55),
                    size: 22),
                const SizedBox(height: 4),
                Text(b.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: b.unlocked ? AppColors.text : AppColors.muted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800)),
              ]),
            );
          },
        ),
      ),
    ]);
  }

  IconData _badgeIcon(String id) => switch (id) {
        Icons2.school => Icons.school_rounded,
        Icons2.fire => Icons.local_fire_department_rounded,
        Icons2.explore => Icons.explore_rounded,
        Icons2.calendar => Icons.calendar_month_rounded,
        Icons2.bolt => Icons.bolt_rounded,
        Icons2.trophy => Icons.emoji_events_rounded,
        Icons2.cards => Icons.style_rounded,
        Icons2.brain => Icons.psychology_rounded,
        Icons2.star => Icons.star_rounded,
        _ => Icons.check_circle_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _adding ? null : _addTextbook,
        icon: _adding
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file_rounded),
        label: const Text('Add textbook'),
      ),
      body: AuroraBackground(
        dense: true,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 96),
              children: [
                Row(children: [
                  const GlowIcon(Icons.auto_stories_rounded,
                      color: Color(0xFF6366F1), size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GradientText('Textbook Classroom', size: 20),
                          Text(_greeting(),
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 12.5)),
                        ]),
                  ),
                  GlassCard(
                    padding: const EdgeInsets.all(4),
                    radius: 14,
                    onTap: () async {
                      await Navigator.of(context).push(PageTransition.route(
                        ProfileScreen(
                          settings: widget.settings,
                          onSignedOut: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => ChildGateScreen(
                                  settings: widget.settings,
                                  onLoggedIn: () {
                                    Navigator.of(context).pushAndRemoveUntil(
                                      MaterialPageRoute(
                                          builder: (_) => HomeScreen(
                                              gateway: widget.gateway,
                                              settings: widget.settings)),
                                      (_) => false,
                                    );
                                  },
                                ),
                              ),
                              (_) => false,
                            );
                          },
                        ),
                      ));
                      if (mounted) setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(VaultStore.current?.avatar ?? '🙂',
                          style: const TextStyle(fontSize: 17)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GlassCard(
                    padding: const EdgeInsets.all(4),
                    radius: 14,
                    onTap: () async {
                      await Navigator.of(context).push(PageTransition.route(
                          SettingsScreen(settings: widget.settings)));
                      _load();
                    },
                    child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.settings_rounded,
                            color: AppColors.muted, size: 20)),
                  ),
                ]),
                const SizedBox(height: 16),
                const UpdateBanner(),
                if (_books.isNotEmpty) _continueCard(),
                if (_books.isNotEmpty) const SizedBox(height: 12),
                _statsCard(),
                const SizedBox(height: 14),
                _badgesStrip(),
                const SizedBox(height: 16),
                GradientCard(
                  gradient: AppColors.heroGradient,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your teacher is ready.',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Colors.white)),
                        const SizedBox(height: 6),
                        const Text(
                            'Upload a textbook PDF. The chapter is split into parts — watch, answer, and unlock the next class.',
                            style:
                                TextStyle(color: Colors.white70, height: 1.45)),
                        const SizedBox(height: 16),
                        Wrap(spacing: 8, runSpacing: 8, children: const [
                          _HeroChip(
                              icon: Icons.highlight_rounded,
                              label: 'Live page highlights'),
                          _HeroChip(
                              icon: Icons.draw_rounded,
                              label: 'Voice-synced writing'),
                          _HeroChip(
                              icon: Icons.lock_open_rounded,
                              label: 'Part unlocking'),
                          _HeroChip(
                              icon: Icons.chat_rounded, label: 'Ask PDF chat'),
                        ]),
                      ]),
                ),
                const SizedBox(height: 16),
                GradientCard(
                  onTap: () {
                    if (_books.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Add a textbook first — the brain reads that book.')));
                      return;
                    }
                    final b = _books.first;
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BrainScreen(
                        settings: widget.settings,
                        sessionId: b.sessionId,
                        bookTitle: b.shortTitle,
                      ),
                    ));
                  },
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: AppColors.violet.withOpacity(0.18),
                      ),
                      child: const Text('🧠', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text('AI Brain',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: AppColors.text)),
                            const SizedBox(width: 7),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.green.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('online',
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.green)),
                            ),
                          ]),
                          const SizedBox(height: 3),
                          Text(
                            _books.isEmpty
                                ? 'Add a book, then get a real AI summary + answers'
                                : 'Real AI summary & answers → used in your lessons',
                            style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11.5,
                                height: 1.45),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                ),
                const SectionTitle('Academics'),
                Row(children: [
                  Expanded(
                    child: GradientCard(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ExamsHubScreen(
                            gateway: widget.gateway, settings: widget.settings),
                      )),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.quiz_rounded,
                                color: AppColors.teal, size: 26),
                            SizedBox(height: 10),
                            Text('Exams & Tests',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                    fontSize: 15)),
                            SizedBox(height: 3),
                            Text(
                                'MCQ • Fill • Short\nTimed exams, doubt clearing',
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11.5,
                                    height: 1.45)),
                          ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GradientCard(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ReportScreen(
                            gateway: widget.gateway, settings: widget.settings),
                      )),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.emoji_events_rounded,
                                color: AppColors.amber, size: 26),
                            SizedBox(height: 10),
                            Text('Report Card',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                    fontSize: 15)),
                            SizedBox(height: 3),
                            Text(
                                'Marks • Grades • Rank & level\nWeak-part revision plan',
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11.5,
                                    height: 1.45)),
                          ]),
                    ),
                  ),
                ]),
                const SectionTitle('Today'),
                GradientCard(
                  onTap: () async {
                    await Navigator.of(context).push(PageTransition.route(
                      DailyChallengeScreen(
                          gateway: widget.gateway,
                          settings: widget.settings,
                          books: _books),
                    ));
                    _load();
                  },
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: AppColors.amber.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.bolt_rounded,
                          color: AppColors.amber, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Daily challenge',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                    fontSize: 14.5)),
                            const SizedBox(height: 3),
                            Text(
                                '5 mixed questions from your books • up to +60 XP',
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11.5,
                                    height: 1.4)),
                          ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                ),
                const SectionTitle('Smart revision'),
                GradientCard(
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RevisionScreen(
                          gateway: widget.gateway, settings: widget.settings),
                    ));
                    _load();
                  },
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: AppColors.red.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.auto_fix_high_rounded,
                          color: AppColors.red, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Revise weak topics',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.text,
                                    fontSize: 14.5)),
                            SizedBox(height: 3),
                            Text(
                                'Parts under 60% get a re-watch + flashcard plan from your own marks',
                                style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11.5,
                                    height: 1.4)),
                          ]),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                  ]),
                ),
                const SectionTitle('My textbooks'),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: CircularProgressIndicator()))
                else if (_error != null)
                  EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Engine not reachable',
                      message: _error!,
                      buttonLabel: 'Retry',
                      onButton: _load)
                else if (_books.isEmpty)
                  const EmptyState(
                    icon: Icons.menu_book_rounded,
                    title: 'No textbooks yet',
                    message:
                        'Tap “Add textbook”, choose a chapter PDF, and your first class series will be created.',
                  )
                else
                  ..._books.map((b) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GradientCard(
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => TextbookScreen(
                                  gateway: widget.gateway,
                                  settings: widget.settings,
                                  book: b),
                            ));
                            _load();
                          },
                          child: Row(children: [
                            Container(
                              width: 52,
                              height: 64,
                              decoration: BoxDecoration(
                                  gradient: AppColors.accentGradient,
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.menu_book_rounded,
                                  color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.shortTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.text,
                                            fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text('${b.pageCount} pages • ${b.state}',
                                        style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 12.5)),
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(99),
                                      child: LinearProgressIndicator(
                                        value: _progress[b.sessionId] ?? 0,
                                        minHeight: 6,
                                        backgroundColor: AppColors.stroke,
                                        valueColor: AlwaysStoppedAnimation(
                                            AppColors.teal),
                                      ),
                                    ),
                                  ]),
                            ),
                            const SizedBox(width: 12),
                            ProgressRing(
                                value: _progress[b.sessionId] ?? 0, size: 52),
                          ]),
                        ),
                      )),
                const SizedBox(height: 10),
                GradientCard(
                  child: Row(children: [
                    Icon(Icons.phone_android_rounded, color: AppColors.teal),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          'Videos are rendered on this phone. Only the AI brain may use the internet, depending on your Settings.',
                          style: TextStyle(
                              color: AppColors.muted,
                              height: 1.45,
                              fontSize: 13)),
                    ),
                  ]),
                ),
              ],
            ),
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
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}
