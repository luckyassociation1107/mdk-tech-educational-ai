import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../widgets.dart';

/// Notes = the key points of every part + the real caption notes of
/// generated videos, saveable as a text file on the device.
class NotesScreen extends StatefulWidget {
  final TextbookItem book;
  final List<SeriesPart> parts;
  final List<VideoItem> videos;
  const NotesScreen({super.key, required this.book, required this.parts, required this.videos});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  Map<String, List<CaptionLine>> _videoNotes = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final out = <String, List<CaptionLine>>{};
    for (final v in widget.videos) {
      final path = v.playablePath;
      if (path == null) continue;
      final srt = File(path.replaceAll(RegExp(r'\.mp4$', caseSensitive: false), '.srt'));
      if (await srt.exists()) {
        out[v.videoId] = CaptionLine.parseSrt(await srt.readAsString());
      }
    }
    if (!mounted) return;
    setState(() {
      _videoNotes = out;
      _loading = false;
    });
  }

  String _allNotesText() {
    final b = StringBuffer()..writeln('${widget.book.title} — My Notes\n');
    for (final p in widget.parts) {
      b.writeln('Part ${p.part} (${p.pageLabel})');
      for (final k in p.keyPoints) {
        b.writeln('• $k');
      }
      b.writeln();
    }
    _videoNotes.forEach((id, lines) {
      b.writeln('Class notes ($id)');
      for (final l in lines.take(120)) {
        b.writeln('• ${l.text}');
      }
      b.writeln();
    });
    return b.toString();
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/${widget.book.sessionId}_notes.txt');
      await f.writeAsString(_allNotesText());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notes saved: ${f.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('My notes'),
        actions: [IconButton(onPressed: _save, icon: const Icon(Icons.download_rounded), tooltip: 'Save notes')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
              children: [
                ...widget.parts.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GradientCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Part ${p.part} • ${p.pageLabel}',
                              style:  TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 15)),
                          const SizedBox(height: 10),
                          if (p.keyPoints.isEmpty)
                             Text('Key points will appear after the series is loaded.', style: TextStyle(color: AppColors.muted))
                          else
                            ...p.keyPoints.map((k) => Padding(
                                  padding: const EdgeInsets.only(bottom: 7),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                     Text('•  ', style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w900)),
                                    Expanded(child: Text(k, style:  TextStyle(color: AppColors.text, height: 1.45))),
                                  ]),
                                )),
                        ]),
                      ),
                    )),
                if (_videoNotes.isNotEmpty) const SectionTitle('From your classes'),
                ..._videoNotes.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GradientCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                           Text('Teacher said…', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text)),
                          const SizedBox(height: 10),
                          ...e.value.take(30).map((l) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('• ${l.text}', style:  TextStyle(color: AppColors.muted, height: 1.45)),
                              )),
                        ]),
                      ),
                    )),
                FilledButton.icon(onPressed: _save, icon: const Icon(Icons.download_rounded), label: const Text('Download all notes (.txt)')),
              ],
            ),
    );
  }
}
