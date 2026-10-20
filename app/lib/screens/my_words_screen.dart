import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../store.dart';
import '../word_bank.dart';
import '../widgets.dart';

/// My Words — every word tapped in Word help, with its textbook sentence
/// and translation, searchable and usable as a personal dictionary.
class MyWordsScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  const MyWordsScreen({super.key, required this.settings, required this.book});

  @override
  State<MyWordsScreen> createState() => _MyWordsScreenState();
}

class _MyWordsScreenState extends State<MyWordsScreen> {
  static const MethodChannel _ttsCh =
      MethodChannel('com.mdk.textbook_video/engine');
  List<WordEntry> _all = const [];
  String _q = '';
  bool _loading = true;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await WordBank.load(widget.book.sessionId);
    if (!mounted) return;
    setState(() {
      _all = all;
      _loading = false;
    });
  }

  List<WordEntry> get _filtered {
    if (_q.isEmpty) return _all;
    final q = _q.toLowerCase();
    return _all
        .where((e) =>
            e.word.toLowerCase().contains(q) ||
            e.context.toLowerCase().contains(q) ||
            e.translation.toLowerCase().contains(q))
        .toList();
  }

  void _speak(String text) {
    _ttsCh.invokeMethod('speak', {
      'text': text,
      'language': 'en-IN',
      'rate': widget.settings.speechRate,
      'pitch': widget.settings.speechPitch
    }).catchError((_) => null);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('My Words',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          if (_all.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.card,
                    title: const Text('Clear word bank?'),
                    content: const Text(
                        'This removes every saved word for this textbook.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel')),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.red),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await WordBank.clear(widget.book.sessionId);
                  _load();
                }
              },
              icon: Icon(Icons.delete_sweep_rounded, color: AppColors.red),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'Search your words…',
                    hintStyle: TextStyle(color: AppColors.muted),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: AppColors.muted),
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  Text('${rows.length} words',
                      style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('tap a word to hear it',
                      style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: rows.isEmpty
                    ? EmptyState(
                        icon: Icons.spellcheck_rounded,
                        title: _all.isEmpty ? 'No words yet' : 'No match',
                        message: _all.isEmpty
                            ? 'Inside a class tap “Words”, then tap any hard word. It is saved here with its textbook sentence and translation.'
                            : 'Try a different spelling.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final e = rows[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: GradientCard(
                              padding: const EdgeInsets.all(14),
                              onTap: () => _speak(e.word),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Expanded(
                                        child: Text(e.word,
                                            style: TextStyle(
                                                color: AppColors.text,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 15)),
                                      ),
                                      if (e.page.isNotEmpty)
                                        Text('page ${e.page}',
                                            style: TextStyle(
                                                color: AppColors.muted,
                                                fontSize: 10.5)),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _speak(e.word),
                                        icon: Icon(Icons.volume_up_rounded,
                                            size: 18, color: AppColors.teal),
                                      ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () async {
                                          await WordBank.remove(
                                              widget.book.sessionId, e.word);
                                          _load();
                                        },
                                        icon: Icon(Icons.close_rounded,
                                            size: 17, color: AppColors.muted),
                                      ),
                                    ]),
                                    if (e.translation.isNotEmpty)
                                      Text(e.translation,
                                          style: TextStyle(
                                              color: AppColors.amber,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13)),
                                    if (e.context.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(e.context,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 12,
                                              height: 1.45)),
                                    ],
                                  ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}
