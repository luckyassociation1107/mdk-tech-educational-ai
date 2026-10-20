import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../store.dart';
import '../study_stats.dart';
import '../ui/premium_ui.dart';
import '../widgets.dart';

/// Completion certificate — a shareable PNG for finishing a textbook.
class CertificateScreen extends StatefulWidget {
  final AppSettings settings;
  final TextbookItem book;
  final int partsDone;
  final int partsTotal;
  final double averagePct;
  const CertificateScreen({
    super.key,
    required this.settings,
    required this.book,
    required this.partsDone,
    required this.partsTotal,
    required this.averagePct,
  });

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  final GlobalKey _key = GlobalKey();
  String? _savedPath;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('certificate not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/classroom/certificates');
      if (!await folder.exists()) await folder.create(recursive: true);
      final safe = widget.book.shortTitle.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final f = File('${folder.path}/certificate_$safe.jpg'.replaceAll('.jpg', '.png'));
      await f.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() {
        _savedPath = f.path;
        _busy = false;
      });
      await showCelebration(context, title: 'Certificate saved!', subtitle: 'Find it in classroom/certificates on your phone.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.partsTotal == 0 ? 0.0 : widget.partsDone / widget.partsTotal;
    final level = StudyStats.levelForXp((widget.averagePct * 20).round());
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Certificate', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          IconButton(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded, color: AppColors.teal),
          ),
        ],
      ),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            RepaintBoundary(
              key: _key,
              child: AspectRatio(
                aspectRatio: 1.414, // A4 landscape
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF134E4A)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(painter: const _CertificateOrnament()),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF2DD4BF)]),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            const Text('TEXTBOOK CLASSROOM',
                                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 2.4)),
                          ]),
                          const SizedBox(height: 14),
                          const Text('CERTIFICATE',
                              style: TextStyle(color: Color(0xFFFDE68A), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4)),
                          const Text('of completion',
                              style: TextStyle(color: Colors.white54, fontSize: 10.5, letterSpacing: 1.6)),
                          const Spacer(),
                          const Text('This certifies that the learner has completed',
                              style: TextStyle(color: Colors.white70, fontSize: 11)),
                          const SizedBox(height: 10),
                          Text(
                            widget.book.shortTitle,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, height: 1.2),
                          ),
                          const SizedBox(height: 12),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _stat('${widget.partsDone}/${widget.partsTotal}', 'parts'),
                            _divider(),
                            _stat('${widget.averagePct.toStringAsFixed(0)}%', 'average'),
                            _divider(),
                            _stat('Lv $level', 'level'),
                          ]),
                          const Spacer(),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('DATE',
                                  style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                              Text(DateTime.now().toString().split(' ').first,
                                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
                            ]),
                            Column(children: [
                              const Icon(Icons.verified_rounded, color: Color(0xFF2DD4BF), size: 22),
                              const Text('verified on device',
                                  style: TextStyle(color: Colors.white38, fontSize: 7.5)),
                            ]),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              const Text('PROGRESS',
                                  style: TextStyle(color: Colors.white38, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                              Text('${(streak * 100).round()}% of the book',
                                  style: const TextStyle(color: Colors.white70, fontSize: 10)),
                            ]),
                          ]),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_savedPath != null)
              GradientCard(
                child: Row(children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.green),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Saved as PNG', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 13.5)),
                      Text(_savedPath!, style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Save certificate image'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 10),
            GradientCard(
              child: Text(
                'The certificate is generated on this phone from your own progress — no account, no server. '
                'Share the PNG in your class group or keep it in your portfolio.',
                style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(children: [
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
      Text(label.toUpperCase(),
          style: const TextStyle(color: Colors.white38, fontSize: 7.5, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
    ]);
  }

  Widget _divider() => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.white24,
      );
}

class _CertificateOrnament extends CustomPainter {
  const _CertificateOrnament();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF2DD4BF).withOpacity(0.55);
    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(10)), paint);
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFFFDE68A).withOpacity(0.35);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(18, 18, size.width - 36, size.height - 36), const Radius.circular(8)), gold);
    // corner accents
    final accent = Paint()..color = const Color(0xFFFDE68A).withOpacity(0.5);
    for (final c in [
      Offset(12, 12),
      Offset(size.width - 12, 12),
      Offset(12, size.height - 12),
      Offset(size.width - 12, size.height - 12),
    ]) {
      canvas.drawCircle(c, 2.6, accent);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
