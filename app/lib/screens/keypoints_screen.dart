import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../dart_engine.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import '../speech/speech_channel.dart';

/// The Key Points Book: every part's own key points (plus the website
/// brain's points when they exist) collected into one study booklet that
/// can be searched, read aloud and saved as a text file on the phone.
class KeyPointsScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final List<SeriesPart> parts;
  const KeyPointsScreen(
      {super.key,
      required this.settings,
      required this.book,
      required this.parts});

  @override
  State<KeyPointsScreen> createState() => _KeyPointsScreenState();
}

class _KeyPointsScreenState extends State<KeyPointsScreen> {
  static const SpeechChannel _ttsCh = SpeechChannel();
  List<String> _brain = const [];
  final _search = TextEditingController();
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final brain = await DartEngine.brainKeyPoints(widget.book.sessionId);
    if (!mounted) return;
    setState(() {
      _brain = brain;
      _loading = false;
    });
  }

  List<({int part, String label, String point})> get _rows {
    final out = <({int part, String label, String point})>[];
    final seen = <String>{};
    void add(int part, String label, String point) {
      final t = point.trim();
      final k = t.toLowerCase();
      if (t.length < 10 || seen.contains(k)) return;
      if (_q.isNotEmpty && !t.toLowerCase().contains(_q)) return;
      seen.add(k);
      out.add((part: part, label: label, point: t));
    }

    for (final p in widget.parts) {
      final label = 'Part ${p.part} • ${p.pageLabel}';
      for (final k in p.keyPoints) {
        add(p.part, label, k);
      }
    }
    for (final b in _brain) {
      add(0, 'Website brain summary', b);
    }
    return out;
  }

  Future<void> _export() async {
    final rows = _rows;
    if (rows.isEmpty) return;
    final sb = StringBuffer()
      ..writeln('KEY POINTS BOOK')
      ..writeln(widget.book.shortTitle)
      ..writeln(widget.book.subjectLabel)
      ..writeln('Saved ${DateTime.now()}')
      ..writeln('=' * 46);
    var cur = -1;
    for (final r in rows) {
      if (r.part != cur) {
        cur = r.part;
        sb
          ..writeln()
          ..writeln('— ${r.label} —');
      }
      sb.writeln('• ${r.point}');
    }
    sb
      ..writeln()
      ..writeln(
          'Note: every line above is from the textbook itself (or the brain summary of it). '
          'Explanations given during the class are labelled as examples and are not printed here as textbook facts.');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final d = Directory('${dir.path}/classroom/notes');
      if (!await d.exists()) await d.create(recursive: true);
      final safe =
          widget.book.shortTitle.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final f = File('${d.path}/${safe}_key_points.txt');
      await f.writeAsString(sb.toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to ${f.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  void _speak(String text) {
    _ttsCh.invokeMethod('speak', {
      'text': text,
      'language': 'en-IN',
      'rate': 0.9
    }).catchError((_) => null);
  }

  @override
  void dispose() {
    _search.dispose();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows =
        _loading ? const <({int part, String label, String point})>[] : _rows;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Key Points Book',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.text,
                fontSize: 16)),
        actions: [
          IconButton(
              tooltip: 'Save as text file',
              onPressed: rows.isEmpty ? null : _export,
              icon: Icon(Icons.save_alt_rounded, color: AppColors.teal)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                child: TextField(
                  controller: _search,
                  style: TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'Search key points…',
                    hintStyle: TextStyle(color: AppColors.muted),
                    prefixIcon:
                        Icon(Icons.search_rounded, color: AppColors.muted),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.stroke)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.stroke)),
                  ),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(children: [
                  Text('${rows.length} points • ${widget.parts.length} parts',
                      style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (_brain.isNotEmpty)
                    Text('brain summary included',
                        style: TextStyle(
                            color: AppColors.teal,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.menu_book_rounded,
                        title: 'No key points yet',
                        message:
                            'Watch a class for a part first — its textbook key points land here automatically.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final newPart = i == 0 || rows[i - 1].part != r.part;
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (newPart)
                                  Padding(
                                    padding: EdgeInsets.only(
                                        top: i == 0 ? 2 : 16, bottom: 8),
                                    child: Row(children: [
                                      Container(
                                          width: 4,
                                          height: 16,
                                          decoration: BoxDecoration(
                                              color: AppColors.teal,
                                              borderRadius:
                                                  BorderRadius.circular(99))),
                                      const SizedBox(width: 8),
                                      Text(r.label,
                                          style: TextStyle(
                                              color: AppColors.text,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13.5)),
                                    ]),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: GradientCard(
                                    onTap: () => _speak(r.point),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.only(top: 1),
                                            child: Icon(Icons.circle,
                                                size: 7, color: AppColors.teal),
                                          ),
                                          const SizedBox(width: 9),
                                          Expanded(
                                              child: Text(r.point,
                                                  style: TextStyle(
                                                      color: AppColors.text,
                                                      fontSize: 13,
                                                      height: 1.45,
                                                      fontWeight:
                                                          FontWeight.w600))),
                                          const SizedBox(width: 6),
                                          Icon(Icons.volume_up_rounded,
                                              size: 17, color: AppColors.muted),
                                        ]),
                                  ),
                                ),
                              ]);
                        },
                      ),
              ),
            ]),
    );
  }
}
