import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../store.dart';
import '../study_stats.dart';
import '../subject_engine.dart';
import '../dart_engine.dart';
import '../widgets.dart';

/// Spaced-repetition flashcards (Leitner boxes 0–4).
/// Cards are made ONLY from the textbook's own key points and glossary
/// words; nothing is invented. Cards you get wrong come back today,
/// cards you know move further into the future.
class FlashcardsScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final List<SeriesPart> parts;
  const FlashcardsScreen({super.key, required this.settings, required this.book, required this.parts});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> with SingleTickerProviderStateMixin {
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  static const _intervals = [0, 1, 2, 4, 8, 16]; // days per box
  static const _boxColors = [Color(0xFFF87171), Color(0xFFFB923C), Color(0xFFFBBF24), Color(0xFF34D399), Color(0xFF2DD4BF), Color(0xFF6366F1)];

  List<_Card> _cards = const [];
  List<_Card> _due = const [];
  int _i = 0;
  bool _flipped = false;
  bool _loading = true;
  int _reviewed = 0;

  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _storeKey => 'flash_${widget.book.sessionId}';

  Future<void> _load() async {
    final texts = <String>[];
    final vocab = <String>[];
    for (final p in widget.parts) {
      for (final k in p.keyPoints) {
        if (k.trim().length > 25) texts.add(k.trim());
      }
    }
    if (texts.length < 6) {
      final brain = await DartEngine.brainKeyPoints(widget.book.sessionId);
      texts.addAll(brain.where((b) => b.trim().length > 25));
    }
    final subject = await DartEngine.subjectOf(widget.book.sessionId);
    if (subject == 'language') {
      final index = await DartEngine.loadIndex(widget.book.sessionId);
      if (index != null) {
        final pageTexts = widget.parts.expand((p) => p.pages).map((n) => index.pageText(n)).toList();
        for (final v in SubjectEngine.vocabWords(pageTexts, max: 12)) {
          vocab.add('${v.word}\u0001${v.meaning}\u0001${v.usage}');
        }
      }
    }
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> saved = {};
    try {
      final raw = prefs.getString(_storeKey);
      if (raw != null) saved = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {}

    final now = DateTime.now().millisecondsSinceEpoch;
    final cards = <_Card>[];
    final seen = <String>{};
    for (final t in texts) {
      final id = 'kp_${t.hashCode}';
      if (!seen.add(id)) continue;
      final words = t.split(RegExp(r'\s+')).map((w) => w.replaceAll(RegExp(r'[^A-Za-z\-]'), '')).where((w) => w.length >= 6).toList();
      final blank = words.isEmpty ? null : words.reduce((a, b) => a.length >= b.length ? a : b);
      final front = blank == null ? t : t.replaceAll(blank!, '________');
      final st = saved[id];
      final box = (st is List && st.length >= 2) ? (st[0] as num).toInt().clamp(0, 5).toInt() : 0;
      final due = (st is List && st.length >= 2) ? (st[1] as num).toInt() : now;
      cards.add(_Card(id: id, front: front, back: t, hint: blank == null ? 'Key point' : 'Missing word: $blank', box: box, due: due, kind: 'kp'));
    }
    for (final v in vocab) {
      final parts = v.split('\u0001');
      if (parts.length < 2) continue;
      final id = 'vo_${parts[0].hashCode}';
      if (!seen.add(id)) continue;
      final st = saved[id];
      final box = (st is List && st.length >= 2) ? (st[0] as num).toInt().clamp(0, 5).toInt() : 0;
      final due = (st is List && st.length >= 2) ? (st[1] as num).toInt() : now;
      cards.add(_Card(
        id: id,
        front: '${parts[0]}\n\nWhat does it mean?',
        back: '${parts[0]} = ${parts[1]}${parts.length > 2 && parts[2].isNotEmpty ? '\n\n"${parts[2]}"' : ''}',
        hint: 'New word',
        box: box,
        due: due,
        kind: 'vocab',
      ));
    }
    cards.shuffle(math.Random(7));
    final due = cards.where((c) => c.due <= now).toList();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _due = due;
      _i = 0;
      _flipped = false;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, dynamic>{};
    for (final c in _cards) {
      out[c.id] = [c.box, c.due];
    }
    await prefs.setString(_storeKey, jsonEncode(out));
  }

  Future<void> _answer(int quality) async {
    if (_due.isEmpty || _i >= _due.length) return;
    final c = _due[_i];
    final idx = _cards.indexWhere((x) => x.id == c.id);
    final now = DateTime.now();
    int box;
    int dueMs;
    if (quality == 0) {
      box = 0;
      dueMs = now.millisecondsSinceEpoch; // again today
    } else if (quality == 2) {
      box = math.min(5, c.box + 2);
      dueMs = now.add(Duration(days: _intervals[box])).millisecondsSinceEpoch;
    } else {
      box = math.min(5, c.box + 1);
      dueMs = now.add(Duration(days: _intervals[box])).millisecondsSinceEpoch;
    }
    if (idx >= 0) {
      _cards[idx] = _cards[idx].copyWith(box: box, due: dueMs);
    }
    setState(() {
      _reviewed++;
      _flipped = false;
      _i++;
    });
    _flip.value = 0;
    ProgressStore.addXp(widget.book.sessionId, quality == 0 ? 1 : 3);
    StudyStats.bumpFlashcards();
    StudyStats.recordActivity(scenes: 1);
    await _save();
    if (_i >= _due.length) {
      setState(() {});
    }
  }

  void _speak(String text) {
    _ttsCh.invokeMethod('speak', {'text': text, 'language': "en-IN", 'rate': widget.settings.speechRate}).catchError((_) => null);
  }

  @override
  void dispose() {
    _flip.dispose();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _due.isNotEmpty && _i >= _due.length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Flashcards', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text('${_cards.length} cards', style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? const EmptyState(
                  icon: Icons.style_rounded,
                  title: 'No cards yet',
                  message: 'Watch a class first — its key points become your flashcards automatically.',
                )
              : done
                  ? _doneView()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                      children: [
                        Row(children: [
                          Text('Due today', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 15)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.teal.withOpacity(0.16), borderRadius: BorderRadius.circular(99)),
                            child: Text('${math.max(0, _due.length - _i)}', style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.w900, fontSize: 12)),
                          ),
                          const Spacer(),
                          Text('reviewed $_reviewed', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: _due.isEmpty ? 0.0 : (_i / _due.length).clamp(0.0, 1.0).toDouble(),
                            minHeight: 5,
                            backgroundColor: AppColors.stroke,
                            valueColor: const AlwaysStoppedAnimation(AppColors.teal),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_due.isEmpty)
                          GradientCard(
                            child: Column(children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 42),
                              const SizedBox(height: 8),
                              const Text('All caught up!', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 17)),
                              const SizedBox(height: 4),
                              Text('${_cards.length} cards are scheduled for later. Come back tomorrow — or watch a class to add more cards.',
                                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
                            ]),
                          )
                        else ...[
                          _cardView(_due[_i]),
                          const SizedBox(height: 16),
                          if (!_flipped)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () {
                                  setState(() => _flipped = true);
                                  _flip.forward();
                                  _speak(_due[_i].back);
                                },
                                icon: const Icon(Icons.flip_rounded),
                                label: const Text('Show answer'),
                                style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 15)),
                              ),
                            )
                          else
                            Row(children: [
                              Expanded(child: _gradeButton('Again', 'Today', AppColors.red, 0)),
                              const SizedBox(width: 8),
                              Expanded(child: _gradeButton('Good', '+1 box', AppColors.amber, 1)),
                              const SizedBox(width: 8),
                              Expanded(child: _gradeButton('Easy', '+2 boxes', AppColors.green, 2)),
                            ]),
                        ],
                        const SizedBox(height: 18),
                        _boxLegend(),
                      ],
                    ),
    );
  }

  Widget _gradeButton(String title, String sub, Color color, int quality) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _answer(quality),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.55)),
        ),
        child: Column(children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13.5)),
          Text(sub, style: TextStyle(color: color.withOpacity(0.85), fontSize: 10.5)),
        ]),
      ),
    );
  }

  Widget _cardView(_Card c) {
    final color = _boxColors[c.box.clamp(0, 5).toInt()];
    return GestureDetector(
      onTap: () {
        setState(() => _flipped = !_flipped);
        if (_flipped) {
          _flip.forward();
          _speak(c.back);
        } else {
          _flip.reverse();
        }
      },
      child: AnimatedBuilder(
        animation: _flip,
        builder: (context, _) {
          final t = _flip.value;
          final showBack = t > 0.5;
          final angle = t * math.pi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..setEntry(3, 2, 0.0012)..rotateY(angle),
            child: Container(
              height: 290,
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: showBack
                      ? [const Color(0xFF134E4A), const Color(0xFF0F172A)]
                      : [const Color(0xFF312E81), const Color(0xFF0F172A)],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withOpacity(0.55), width: 1.3),
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(math.pi),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.22), borderRadius: BorderRadius.circular(99)),
                      child: Text(showBack ? 'ANSWER' : c.hint.toUpperCase(),
                          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                    ),
                    const Spacer(),
                    Text('BOX ${c.box + 1}', style: const TextStyle(color: Colors.white38, fontSize: 9.5, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 14),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        showBack ? c.back : c.front,
                        style: TextStyle(color: Colors.white, fontSize: showBack ? 16 : 18, height: 1.5, fontWeight: showBack ? FontWeight.w600 : FontWeight.w800),
                      ),
                    ),
                  ),
                  Text(showBack ? 'Tap to hide' : 'Tap to reveal • ${c.kind == 'vocab' ? 'word' : 'key point'}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _boxLegend() {
    return GradientCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('How it works', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 13)),
        const SizedBox(height: 6),
        const Text(
          'Right answers move the card further into the future (1 → 2 → 4 → 8 → 16 days). '
          'A wrong card comes back today, so the same weak point repeats until it is truly remembered.',
          style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (var b = 0; b < 6; b++) ...[
            Container(
              width: 26,
              height: 8,
              decoration: BoxDecoration(color: _boxColors[b], borderRadius: BorderRadius.circular(99)),
            ),
            const SizedBox(width: 4),
          ],
          const Spacer(),
          const Text('new → known', style: TextStyle(color: AppColors.muted, fontSize: 10)),
        ]),
      ]),
    );
  }

  Widget _doneView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 46),
            const SizedBox(height: 8),
            Text('$_reviewed cards reviewed', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Your future reviews are scheduled. Small daily reviews are how a chapter really sticks.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _i = 0;
              _reviewed = 0;
              _flipped = false;
            });
            _load();
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Back to deck'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ],
    );
  }
}

class _Card {
  final String id;
  final String front;
  final String back;
  final String hint;
  final int box;
  final int due;
  final String kind;
  const _Card({required this.id, required this.front, required this.back, required this.hint, required this.box, required this.due, required this.kind});
  _Card copyWith({int? box, int? due}) => _Card(id: id, front: front, back: back, hint: hint, box: box ?? this.box, due: due ?? this.due, kind: kind);
}
