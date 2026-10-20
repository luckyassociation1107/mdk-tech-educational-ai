import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dart_engine.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import '../speech/speech_channel.dart';

/// Page-by-page textbook reader with pinch zoom, full-book search and
/// "read this page to me". Works fully offline from the pages already
/// rendered on the phone.
class ReaderScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final int startPage;
  final List<int>? highlightPages;
  const ReaderScreen(
      {super.key,
      required this.settings,
      required this.book,
      this.startPage = 1,
      this.highlightPages});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  static const SpeechChannel _ttsCh = SpeechChannel();
  DartPdfIndex? _index;
  String _dir = '';
  PageController? _pc;
  int _page = 1;
  final Set<int> _triedRender = {};
  bool _loading = true;
  bool _speaking = false;
  bool _chrome = true;
  Set<int> _bookmarks = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _bmKey => 'bookmarks_${widget.book.sessionId}';

  Future<void> _loadBookmarks() async {
    final p = await SharedPreferences.getInstance();
    final list = (p.getStringList(_bmKey) ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    if (mounted) setState(() => _bookmarks = list);
  }

  Future<void> _toggleBookmark() async {
    final p = await SharedPreferences.getInstance();
    final set = {..._bookmarks};
    if (!set.add(_page)) set.remove(_page);
    await p.setStringList(_bmKey, set.map((e) => '$e').toList());
    if (!mounted) return;
    setState(() => _bookmarks = set);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          set.contains(_page) ? 'Page $_page bookmarked' : 'Bookmark removed'),
      duration: const Duration(milliseconds: 1200),
    ));
  }

  Future<void> _openBookmarks() async {
    if (_bookmarks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('No bookmarks yet — tap the bookmark icon on any page.')));
      return;
    }
    final pages = _bookmarks.toList()..sort();
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99))),
          Padding(
            padding: EdgeInsets.all(14),
            child: Text('Bookmarks',
                style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
          ),
          ...pages.map((pg) => ListTile(
                leading: Icon(Icons.bookmark_rounded, color: AppColors.amber),
                title: Text('Page $pg',
                    style: TextStyle(
                        color: AppColors.text, fontWeight: FontWeight.w700)),
                trailing: IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 18, color: AppColors.muted),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final p = await SharedPreferences.getInstance();
                    final set = {..._bookmarks}..remove(pg);
                    await p.setStringList(
                        _bmKey, set.map((e) => '$e').toList());
                    if (mounted) setState(() => _bookmarks = set);
                  },
                ),
                onTap: () => Navigator.of(ctx).pop(pg),
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (chosen != null) _goTo(chosen);
  }

  Future<void> _load() async {
    await _loadBookmarks();
    final index = await DartEngine.loadIndex(widget.book.sessionId);
    final dir = await DartEngine.pageDirOf(widget.book.sessionId);
    if (!mounted) return;
    final total = index?.pageCount ?? widget.book.pageCount;
    final start = widget.startPage.clamp(1, total == 0 ? 1 : total).toInt();
    setState(() {
      _index = index;
      _dir = dir;
      _page = start;
      _pc = PageController(initialPage: start - 1);
      _loading = false;
    });
  }

  Future<void> _search() async {
    final index = _index;
    if (index == null) return;
    final ctrl = TextEditingController();
    final page = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _SearchSheet(index: index, controller: ctrl),
    );
    if (page != null && mounted) {
      _goTo(page);
    }
  }

  void _goTo(int page) {
    final total = _index?.pageCount ?? widget.book.pageCount;
    if (total == 0) return;
    final target = page.clamp(1, total).toInt();
    _pc?.jumpToPage(target - 1);
    setState(() => _page = target);
  }

  Future<void> _readPage({bool stop = false}) async {
    if (stop || _speaking) {
      await _ttsCh.invokeMethod('stopTts').catchError((_) => null);
      if (mounted) setState(() => _speaking = false);
      if (stop) return;
    }
    final text = _index?.pageText(_page) ?? '';
    if (text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'This page has no readable text — it may be a picture page.')));
      return;
    }
    final clipped = text.length > 1400 ? text.substring(0, 1400) : text;
    setState(() => _speaking = true);
    await _ttsCh.invokeMethod('speak', {
      'text': clipped,
      'language': widget.settings.language,
      'rate': widget.settings.speechRate,
      'pitch': widget.settings.speechPitch,
    }).catchError((_) => null);
  }

  @override
  void dispose() {
    _pc?.dispose();
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  /// Pages are rendered locally with PDFium (Android + Windows); the first
  /// session may still be filling its cache, so ask again when one is missing.
  Future<void> _ensurePage(int page) async {
    if (_triedRender.contains(page)) return;
    _triedRender.add(page);
    final path = await DartEngine.ensurePageImage(widget.book.sessionId, page);
    if (!mounted || path == null) return;
    setState(() => _dir = File(path).parent.path);
  }

  @override
  Widget build(BuildContext context) {
    final total = _index?.pageCount ?? widget.book.pageCount;
    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070B14),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.book.shortTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                  fontSize: 15)),
          Text('Page $_page of $total',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
        ]),
        actions: [
          IconButton(
              tooltip: 'Search this book',
              onPressed: _loading ? null : _search,
              icon: Icon(Icons.search_rounded, color: AppColors.teal)),
          IconButton(
            tooltip: _speaking ? 'Stop reading' : 'Read this page to me',
            onPressed: _loading ? null : () => _readPage(stop: _speaking),
            icon: Icon(
                _speaking
                    ? Icons.stop_circle_rounded
                    : Icons.record_voice_over_rounded,
                color: AppColors.teal),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _chrome = !_chrome),
                  child: PageView.builder(
                    controller: _pc,
                    itemCount: total == 0 ? 1 : total,
                    onPageChanged: (i) {
                      _ttsCh.invokeMethod('stopTts').catchError((_) => null);
                      setState(() {
                        _page = i + 1;
                        _speaking = false;
                      });
                    },
                    itemBuilder: (ctx, i) {
                      final file = File('$_dir/page_${i + 1}.png');
                      if (!file.existsSync()) {
                        _ensurePage(i + 1);
                        return const Center(
                          child: EmptyState(
                            icon: Icons.image_not_supported_rounded,
                            title: 'Page not rendered',
                            message:
                                'Open a class for this part once — the pages render on the phone and stay available here.',
                          ),
                        );
                      }
                      final marked =
                          widget.highlightPages?.contains(i + 1) ?? false;
                      return Stack(children: [
                        Positioned.fill(
                          child: InteractiveViewer(
                            minScale: 1,
                            maxScale: 6,
                            child: InteractiveViewer(
                              panEnabled: true,
                              boundaryMargin: const EdgeInsets.all(20),
                              child: Image.file(file, fit: BoxFit.contain),
                            ),
                          ),
                        ),
                        if (_bookmarks.contains(i + 1))
                          Positioned(
                            left: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: AppColors.amber.withOpacity(0.95),
                                  borderRadius: BorderRadius.circular(99)),
                              child: const Icon(Icons.bookmark_rounded,
                                  size: 13, color: Colors.black),
                            ),
                          ),
                        if (marked)
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                  color: AppColors.amber.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(99)),
                              child: const Text('PART PAGE',
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.7)),
                            ),
                          ),
                      ]);
                    },
                  ),
                ),
              ),
              if (_chrome)
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  decoration: const BoxDecoration(
                      color: Color(0xFF0B1020),
                      border:
                          Border(top: BorderSide(color: Color(0xFF1E293B)))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Text('$_page',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      Expanded(
                        child: Slider(
                          value: total == 0
                              ? 1.0
                              : _page
                                  .toDouble()
                                  .clamp(1.0, total.toDouble())
                                  .toDouble(),
                          min: 1,
                          max: total == 0 ? 1 : total.toDouble(),
                          onChanged:
                              total <= 1 ? null : (v) => _goTo(v.round()),
                          activeColor: AppColors.teal,
                        ),
                      ),
                      Text('$total',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ]),
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _pill(Icons.first_page_rounded, 'Start',
                              () => _goTo(1)),
                          _pill(Icons.chevron_left_rounded, 'Back',
                              () => _goTo(_page - 1)),
                          _pill(Icons.chevron_right_rounded, 'Next',
                              () => _goTo(_page + 1)),
                          _pill(Icons.last_page_rounded, 'End',
                              () => _goTo(total)),
                        ]),
                  ]),
                ),
            ]),
    );
  }

  Widget _pill(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppColors.teal, size: 20),
          Text(label,
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  final DartPdfIndex index;
  final TextEditingController controller;
  const _SearchSheet({required this.index, required this.controller});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  String _q = '';
  List<({int page, String snippet})> _results = const [];

  void _run(String q) {
    final query = q.trim().toLowerCase();
    final out = <({int page, String snippet})>[];
    if (query.length < 2) {
      setState(() {
        _q = q;
        _results = const [];
      });
      return;
    }
    for (var p = 1; p <= widget.index.pageCount; p++) {
      final text = widget.index.pageText(p).replaceAll(RegExp(r'\s+'), ' ');
      final idx = text.toLowerCase().indexOf(query);
      if (idx >= 0) {
        final start = (idx - 45).clamp(0, text.length).toInt();
        final end = (idx + query.length + 70).clamp(0, text.length).toInt();
        out.add((page: p, snippet: '…${text.substring(start, end)}…'));
        if (out.length >= 40) break;
      }
    }
    setState(() {
      _q = q;
      _results = out;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        const SizedBox(height: 12),
        Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: widget.controller,
            autofocus: true,
            style: TextStyle(color: AppColors.text),
            decoration: InputDecoration(
              hintText: 'Search the whole book…',
              hintStyle: TextStyle(color: AppColors.muted),
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.muted),
              filled: true,
              fillColor: AppColors.cardLight,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.stroke)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.stroke)),
            ),
            onChanged: _run,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Text(
              _q.trim().length < 2
                  ? 'Type at least 2 letters.'
                  : '${_results.length}${_results.length >= 40 ? '+' : ''} pages found',
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            itemCount: _results.length,
            itemBuilder: (ctx, i) {
              final r = _results[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GradientCard(
                  onTap: () => Navigator.of(ctx).pop(r.page),
                  padding: const EdgeInsets.all(13),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: AppColors.teal.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('${r.page}',
                              style: TextStyle(
                                  color: AppColors.teal,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13)),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(r.snippet,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.text,
                                  fontSize: 12.5,
                                  height: 1.4)),
                        ),
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
