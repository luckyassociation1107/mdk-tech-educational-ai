import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:textbook_video_classroom/pdf/figure_finder.dart';

/// Builds a synthetic page: white paper, a few hard text lines at the top,
/// and one solid rectangle where a figure would be.
Uint8List page({
  int w = 300,
  int h = 420,
  int figX0 = 60,
  int figY0 = 126,
  int figX1 = 240,
  int figY1 = 294,
  bool coloured = true,
  bool textLines = true,
}) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = 255;
    px[i * 4 + 1] = 255;
    px[i * 4 + 2] = 255;
    px[i * 4 + 3] = 255;
  }
  void dot(int x, int y, int r, int g, int b) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = (y * w + x) * 4;
    px[i] = r;
    px[i + 1] = g;
    px[i + 2] = b;
  }

  if (textLines) {
    for (var line = 0; line < 5; line++) {
      final y = 24 + line * 14;
      for (var x = 20; x < w - 20; x++) {
        if ((x ~/ 3) % 2 == 0) dot(x, y, 30, 30, 30); // broken strokes
      }
    }
  }
  for (var y = figY0; y < figY1; y++) {
    for (var x = figX0; x < figX1; x++) {
      if (coloured) {
        dot(x, y, 40, 150, 70);
      } else {
        // a line drawing: dark strokes on paper, dense enough to be a figure
        if ((x * 7 + y * 3) % 5 < 2) dot(x, y, 30, 30, 30);
      }
    }
  }
  return px;
}

void main() {
  group('figure finder', () {
    test('finds a coloured figure and ignores the text lines', () {
      final boxes = FigureFinder.detect(page(), 300, 420);
      expect(boxes, isNotEmpty);
      final b = boxes.first;
      // 60..240 of 300 → 0.20..0.80 ; 126..294 of 420 → 0.30..0.70
      expect(b.left, closeTo(0.20, 0.06));
      expect(b.right, closeTo(0.80, 0.06));
      expect(b.top, closeTo(0.30, 0.06));
      expect(b.bottom, closeTo(0.70, 0.06));
    });

    test('finds a dense line drawing too', () {
      final boxes =
          FigureFinder.detect(page(coloured: false, figY0: 60, figY1: 200), 300, 420);
      expect(boxes, isNotEmpty);
      expect(boxes.first.centerY, lessThan(0.6));
    });

    test('a page of only text has no figure', () {
      final boxes = FigureFinder.detect(
          page(figX0: 0, figY0: 0, figX1: 0, figY1: 0), 300, 420);
      expect(boxes, isEmpty);
    });

    test('returns an empty list for a broken buffer', () {
      expect(FigureFinder.detect(Uint8List(8), 300, 420), isEmpty);
    });

    test('top band wins when the AI says top', () {
      // two figures: one near the top, one at the bottom (both big enough)
      final w = 300, h = 420;
      final px = page(figX0: 40, figY0: 40, figX1: 260, figY1: 160);
      for (var y = 260; y < 390; y++) {
        for (var x = 40; x < 260; x++) {
          final i = (y * w + x) * 4;
          px[i] = 200;
          px[i + 1] = 60;
          px[i + 2] = 60;
        }
      }
      final boxes = FigureFinder.detect(px, w, h);
      expect(boxes.length, greaterThanOrEqualTo(2));
      final top = FigureFinder.choose(boxes, where: 'top')!;
      expect(top.centerY, lessThan(0.5));
      final bottom = FigureFinder.choose(boxes, where: 'bottom')!;
      expect(bottom.centerY, greaterThan(0.5));
    });

    test('a hint picks the nearest box when no band is given', () {
      final boxes = [
        const FigureBox(0.1, 0.05, 0.6, 0.20),
        const FigureBox(0.1, 0.60, 0.9, 0.90),
      ];
      final chosen =
          FigureFinder.choose(boxes, hint: const [0.2, 0.65, 0.8, 0.85])!;
      expect(chosen.top, greaterThan(0.5));
    });

    test('falls back to the biggest box', () {
      final boxes = [
        const FigureBox(0.1, 0.05, 0.3, 0.12),
        const FigureBox(0.1, 0.40, 0.9, 0.80),
      ];
      expect(FigureFinder.choose(boxes)!.top, 0.40);
      expect(FigureFinder.choose(const []), isNull);
    });

    test('a coloured figure beats a big grey text column in the same band', () {
      // A page dense with dark text on the left half, one green figure on the
      // right — the column is bigger, the figure is what the AI meant.
      final w = 300, h = 420;
      final px = page(figX0: 0, figY0: 0, figX1: 0, figY1: 0);
      for (var y = 100; y < 330; y++) {
        for (var x = 20; x < 150; x++) {
          if ((y ~/ 6) % 3 != 0) {
            final i = (y * w + x) * 4;
            px[i] = 35;
            px[i + 1] = 35;
            px[i + 2] = 35;
          }
        }
      }
      for (var y = 140; y < 290; y++) {
        for (var x = 175; x < 285; x++) {
          final i = (y * w + x) * 4;
          px[i] = 40;
          px[i + 1] = 150;
          px[i + 2] = 70;
        }
      }
      final boxes = FigureFinder.detect(px, w, h);
      expect(boxes, isNotEmpty);
      final chosen = FigureFinder.choose(boxes, where: 'middle')!;
      expect(chosen.coloured, isTrue);
      expect(chosen.left, greaterThan(0.5));
    });

    test('padding stays inside the page', () {
      final p = FigureFinder.pad(const FigureBox(0.0, 0.02, 0.99, 0.98));
      expect(p.left, greaterThanOrEqualTo(0.0));
      expect(p.right, lessThanOrEqualTo(1.0));
      expect(p.top, greaterThanOrEqualTo(0.0));
      expect(p.bottom, lessThanOrEqualTo(1.0));
    });
  });
}
