import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dart_engine.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

/// Mind map for a part: the part is the centre, each key point a branch.
/// Tap any node to read/hear the full textbook line. Built only from the
/// book's own key points — nothing invented.
class MindMapScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final List<SeriesPart> parts;
  const MindMapScreen({super.key, required this.settings, required this.book, required this.parts});

  @override
  State<MindMapScreen> createState() => _MindMapScreenState();
}

class _MindMapScreenState extends State<MindMapScreen> {
  static const MethodChannel _ttsCh = MethodChannel('com.mdk.textbook_video/engine');
  int _partIdx = 0;
  List<String> _points = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int idx) async {
    setState(() => _loading = true);
    final brain = await DartEngine.brainKeyPoints(widget.book.sessionId);
    final part = widget.parts.isEmpty ? null : widget.parts[idx];
    final pts = [...?part?.keyPoints, ...brain];
    final seen = <String>{};
    final clean = <String>[];
    for (final p in pts) {
      final t = p.trim();
      final k = t.toLowerCase();
      if (t.length > 12 && !seen.contains(k)) {
        seen.add(k);
        clean.add(t);
      }
    }
    if (!mounted) return;
    setState(() {
      _partIdx = idx;
      _points = clean.take(8).toList();
      _loading = false;
    });
  }

  String _short(String s, {int words = 4}) {
    final w = s.replaceAll(RegExp(r'\s+'), ' ').trim().split(' ');
    var out = w.take(words).join(' ');
    out = out.replaceAll(RegExp(r'[.,;:]+$'), '');
    if (out.length > 34) out = '${out.substring(0, 31)}…';
    return out;
  }

  Future<void> _open(String title, String body, Color color) async {
    _ttsCh.invokeMethod('speak', {'text': body, 'language': 'en-IN', 'rate': 0.9}).catchError((_) => null);
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 26),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.bubble_chart_rounded, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15))),
            IconButton(
              onPressed: () => _ttsCh.invokeMethod('speak', {'text': body, 'language': 'en-IN', 'rate': 0.9}).catchError((_) => null),
              icon: const Icon(Icons.volume_up_rounded, color: AppColors.teal),
            ),
          ]),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(color: AppColors.text, fontSize: 14, height: 1.5)),
          const SizedBox(height: 10),
          const Text('Textbook line — read it in your book for the full context.',
              style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
        ]),
      ),
    );
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
  }

  @override
  void dispose() {
    _ttsCh.invokeMethod('stopTts').catchError((_) => null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final part = widget.parts.isEmpty ? null : widget.parts[_partIdx];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Mind map', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 16)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : part == null
              ? const EmptyState(icon: Icons.hub_rounded, title: 'No parts yet', message: 'Open a textbook first.')
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: DropdownButton<int>(
                      value: _partIdx.clamp(0, math.max(0, widget.parts.length - 1)),
                      isExpanded: true,
                      dropdownColor: AppColors.card,
                      underline: Container(height: 1, color: AppColors.stroke),
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
                      items: [
                        for (var i = 0; i < widget.parts.length; i++)
                          DropdownMenuItem(value: i, child: Text('Part ${widget.parts[i].part} — ${widget.parts[i].pageLabel}')),
                      ],
                      onChanged: (v) {
                        if (v != null) _load(v);
                      },
                    ),
                  ),
                  Expanded(
                    child: _points.isEmpty
                        ? const EmptyState(
                            icon: Icons.hub_rounded,
                            title: 'No map yet',
                            message: 'Watch this class once — its key points become your mind map.',
                          )
                        : InteractiveViewer(
                            minScale: 0.6,
                            maxScale: 2.6,
                            boundaryMargin: const EdgeInsets.all(160),
                            child: SizedBox(
                              width: 760,
                              height: 760,
                              child: Stack(children: [
                                Positioned.fill(
                                  child: CustomPaint(painter: _MapPainter(count: _points.length)),
                                ),
                                _node(
                                  center: true,
                                  left: 760 / 2 - 96,
                                  top: 760 / 2 - 42,
                                  label: 'Part ${part.part}\n${part.pageLabel}',
                                  color: AppColors.indigo,
                                  onTap: () => _open('Part ${part.part}', _points.join('\n\n'), AppColors.indigo),
                                ),
                                for (var i = 0; i < _points.length; i++)
                                  _branchNode(i, _points.length, _points[i]),
                              ]),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                    child: Text(
                      '${_points.length} key-point branches • tap a node to hear it • pinch to zoom',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ),
                ]),
    );
  }

  Widget _branchNode(int i, int total, String text) {
    const cx = 380.0, cy = 380.0, r = 268.0;
    final angle = (2 * math.pi * i / math.max(1, total)) - math.pi / 2;
    final x = cx + r * math.cos(angle) - 88;
    final y = cy + r * math.sin(angle) - 32;
    const colors = [AppColors.teal, AppColors.violet, AppColors.amber, AppColors.green, Color(0xFF60A5FA), Color(0xFFF472B6), Color(0xFFA3E635), Color(0xFFFB923C)];
    final c = colors[i % colors.length];
    return _node(
      center: false,
      left: x,
      top: y,
      label: _short(text),
      color: c,
      onTap: () => _open('Key point ${i + 1}', text, c),
    );
  }

  Widget _node({required bool center, required double left, required double top, required String label, required Color color, required VoidCallback onTap}) {
    return Positioned(
      left: left,
      top: top,
      width: center ? 192 : 176,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: center ? 14 : 11, vertical: center ? 12 : 9),
          decoration: BoxDecoration(
            color: color.withOpacity(center ? 0.28 : 0.14),
            borderRadius: BorderRadius.circular(center ? 16 : 12),
            border: Border.all(color: color.withOpacity(0.7), width: center ? 1.6 : 1.1),
            boxShadow: [BoxShadow(color: color.withOpacity(0.16), blurRadius: 12, spreadRadius: 1)],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.text,
              fontWeight: center ? FontWeight.w900 : FontWeight.w700,
              fontSize: center ? 14 : 11.5,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final int count;
  const _MapPainter({required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, r = 268.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    const colors = [AppColors.teal, AppColors.violet, AppColors.amber, AppColors.green, Color(0xFF60A5FA), Color(0xFFF472B6), Color(0xFFA3E635), Color(0xFFFB923C)];
    for (var i = 0; i < count; i++) {
      final angle = (2 * math.pi * i / math.max(1, count)) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      paint.color = colors[i % colors.length].withOpacity(0.45);
      final path = Path()
        ..moveTo(cx, cy)
        ..cubicTo(cx + (x - cx) * 0.35, cy + (y - cy) * 0.15, cx + (x - cx) * 0.65, cy + (y - cy) * 0.85, x, y);
      canvas.drawPath(path, paint);
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = colors[i % colors.length]);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.count != count;
}
