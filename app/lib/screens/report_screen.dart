import 'package:flutter/material.dart';

import '../academic_models.dart';
import '../engine_gateway.dart';
import '../exam_store.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'textbook_screen.dart';

/// Report card: rank band, level/XP, per-textbook marks table, recent
/// attempts and weak parts to revise. All from tests taken on this phone.
class ReportScreen extends StatefulWidget {
  final EngineGateway gateway;
  final AppSettings settings;
  const ReportScreen(
      {super.key, required this.gateway, required this.settings});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  ReportData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await ExamStore.loadAll();
    if (!mounted) return;
    setState(() {
      _data = ReportData(results);
      _loading = false;
    });
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day} ${months[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  String _grade(double pct) {
    if (pct >= 90) return 'A+';
    if (pct >= 80) return 'A';
    if (pct >= 70) return 'B+';
    if (pct >= 60) return 'B';
    if (pct >= 50) return 'C';
    if (pct >= 40) return 'D';
    return 'F';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Report Card',
            style:
                TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
        actions: [
          if (d != null && d.tests > 0)
            IconButton(
              tooltip: 'Clear test history',
              icon: Icon(Icons.delete_sweep_rounded, color: AppColors.muted),
              onPressed: () async {
                final go = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: AppColors.card,
                    title: Text('Clear all test history?',
                        style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w800)),
                    content: Text(
                        'Marks, ranks and levels will reset. This cannot be undone.',
                        style: TextStyle(color: AppColors.muted)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Keep')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Clear')),
                    ],
                  ),
                );
                if (go == true) {
                  await ExamStore.clearAll();
                  _load();
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : d == null || d.tests == 0
              ? const EmptyState(
                  icon: Icons.emoji_events_rounded,
                  title: 'No tests yet',
                  message:
                      'Your ranks, marks and level will appear here. Open Exams & Tests and take your first textbook test.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                  children: [
                      GradientCard(
                        gradient: AppColors.heroGradient,
                        padding: const EdgeInsets.all(22),
                        child: Column(children: [
                          const Icon(Icons.emoji_events_rounded,
                              size: 40, color: Colors.white),
                          const SizedBox(height: 8),
                          Text(d.rank.rank,
                              style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white)),
                          Text(d.rank.title,
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 14),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _Stat('${d.tests}', 'Tests'),
                                _Stat('${_fmt(d.avgPct)}%', 'Average'),
                                _Stat('${_fmt(d.bestPct)}%', 'Best'),
                                _Stat(_grade(d.avgPct), 'Grade'),
                              ]),
                          const SizedBox(height: 14),
                          if (d.rank.nextAt != null) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                  'Score ${_fmt(d.rank.nextAt!)}% average to reach the next rank',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: (d.avgPct / d.rank.nextAt!).clamp(0, 1),
                                minHeight: 8,
                                backgroundColor: Colors.white24,
                                valueColor:
                                    const AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                          ] else
                            const Text('Top rank — keep it up!',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      Builder(builder: (_) {
                        final lv = levelFor(d.xp);
                        return Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: GradientCard(
                            child: Row(children: [
                              Container(
                                width: 52,
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    gradient: AppColors.accentGradient,
                                    borderRadius: BorderRadius.circular(16)),
                                child: Text('${lv.level}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 20)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'Level ${lv.level} • ${_fmt(d.xp)} XP',
                                          style: TextStyle(
                                              color: AppColors.text,
                                              fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 5),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(99),
                                        child: LinearProgressIndicator(
                                          value: lv.progress,
                                          minHeight: 7,
                                          backgroundColor: AppColors.stroke,
                                          valueColor: AlwaysStoppedAnimation(
                                              AppColors.amber),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                          'Next level at ${lv.nextAt} XP — every mark you earn counts.',
                                          style: TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 11.5)),
                                    ]),
                              ),
                            ]),
                          ),
                        );
                      }),
                      const SectionTitle('Marks by textbook'),
                      ...d.books.map((b) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GradientCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(b.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: AppColors.text,
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 3),
                                        Text(
                                            '${b.tests} test(s) • best ${_fmt(b.best)}%',
                                            style: TextStyle(
                                                color: AppColors.muted,
                                                fontSize: 12)),
                                      ]),
                                ),
                                ProgressRing(value: b.avg / 100, size: 46),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: AppColors.teal.withOpacity(0.14),
                                      borderRadius: BorderRadius.circular(99)),
                                  child: Text(_grade(b.avg),
                                      style: TextStyle(
                                          color: AppColors.teal,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 12)),
                                ),
                              ]),
                            ),
                          )),
                      if (d.weakParts.isNotEmpty) ...[
                        const SectionTitle('Revise these parts'),
                        ...d.weakParts.map((w) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: GradientCard(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                child: Row(children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: AppColors.amber),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${w.title} • Part ${w.part}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: AppColors.text,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13.5)),
                                          Text(
                                              'Average ${_fmt(w.avg)}% across ${w.tests} test(s) — rewatch this class, then retake.',
                                              style: TextStyle(
                                                  color: AppColors.muted,
                                                  fontSize: 12)),
                                        ]),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(context)
                                        .push(MaterialPageRoute(
                                      builder: (_) => TextbookScreen(
                                        gateway: widget.gateway,
                                        settings: widget.settings,
                                        book: TextbookItem(
                                            sessionId: w.sessionId,
                                            title: w.title,
                                            pageCount: 0,
                                            state: 'active',
                                            brain: ''),
                                      ),
                                    )),
                                    child: Text('Revise',
                                        style: TextStyle(
                                            color: AppColors.teal,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                ]),
                              ),
                            )),
                      ],
                      const SectionTitle('Recent tests'),
                      ...d.results.take(10).map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: GradientCard(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(children: [
                                Icon(
                                    r.passed
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    color: r.passed
                                        ? AppColors.green
                                        : AppColors.red,
                                    size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${r.bookTitle} • ${r.partLabel}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: AppColors.text,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13.5)),
                                        Text(
                                            '${_date(r.when)} • ${_fmt(r.earned)}/${r.total} marks',
                                            style: TextStyle(
                                                color: AppColors.muted,
                                                fontSize: 12)),
                                      ]),
                                ),
                                Text('${_fmt(r.percentage)}%',
                                    style: TextStyle(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(width: 8),
                                Text(r.grade,
                                    style: TextStyle(
                                        color: r.passed
                                            ? AppColors.teal
                                            : AppColors.red,
                                        fontWeight: FontWeight.w900)),
                              ]),
                            ),
                          )),
                      const SizedBox(height: 8),
                      Text(
                          'Ranks and levels are calculated from tests taken on this phone only — your own progress, honestly measured.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                              height: 1.5)),
                    ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      ]);
}
