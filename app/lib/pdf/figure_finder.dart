import 'dart:math' as math;
import 'dart:typed_data';

/// A rectangle found on a page picture, in normalised page coordinates
/// (0..1, origin at the top-left) — exactly the format the cropper wants.
class FigureBox {
  final double left;
  final double top;
  final double right;
  final double bottom;
  /// True when the blob carries colour — a chart or photo rather than a
  /// column of grey text that happened to look dense.
  final bool coloured;
  const FigureBox(this.left, this.top, this.right, this.bottom,
      {this.coloured = false});

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
  double get centerY => (top + bottom) / 2;

  List<double> get bbox => [left, top, right, bottom];

  @override
  String toString() =>
      'FigureBox(${left.toStringAsFixed(3)}, ${top.toStringAsFixed(3)}, '
      '${right.toStringAsFixed(3)}, ${bottom.toStringAsFixed(3)})';
}

/// Finds the figures on a rendered textbook page **locally**, so the free
/// website mode still has real coordinates.
///
/// The website model reads text, not pixels: it can say *"this page has a
/// leaf cross-section figure, around the middle"* but never a usable box.
/// This class answers the "where": it looks at the page image, finds the
/// large chart/photo/line-drawing blobs (the things that are not body text)
/// and returns their boxes. The caption from the AI and the box from here
/// are then combined.
///
/// The maths runs on a coarse cell grid, so a full page costs a few
/// milliseconds and no extra dependency.
class FigureFinder {
  /// Cell size in pixels of the analysis grid (bigger = faster, coarser).
  static const int cell = 8;

  /// A pixel is "ink" when it is clearly darker than paper.
  static const int inkLuma = 232;

  /// A pixel is "coloured" when its channels disagree enough.
  static const int chroma = 26;

  /// Smallest figure, as a fraction of the page.
  static const double minArea = 0.035;
  static const double minWidth = 0.18;
  static const double minHeight = 0.05;

  /// Detect candidate figure boxes, largest first.
  static List<FigureBox> detect(
    Uint8List rgba,
    int width,
    int height, {
    int maxBoxes = 4,
  }) {
    if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
      return const [];
    }
    final cols = (width / cell).ceil();
    final rows = (height / cell).ceil();
    if (cols < 4 || rows < 4) return const [];

    // ---- 1. coarse map: is this cell ink / colour?
    final ink = Uint8List(cols * rows);
    final colour = Uint8List(cols * rows);
    for (var cy = 0; cy < rows; cy++) {
      for (var cx = 0; cx < cols; cx++) {
        var inkPx = 0;
        var colourPx = 0;
        var seen = 0;
        final y0 = cy * cell;
        final x0 = cx * cell;
        for (var y = y0; y < math.min(y0 + cell, height); y += 2) {
          for (var x = x0; x < math.min(x0 + cell, width); x += 2) {
            final i = (y * width + x) * 4;
            final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
            seen++;
            final luma = (r * 299 + g * 587 + b * 114) ~/ 1000;
            if (luma < inkLuma) inkPx++;
            final hi = math.max(r, math.max(g, b));
            final lo = math.min(r, math.min(g, b));
            if (hi - lo > chroma) colourPx++;
          }
        }
        if (seen == 0) continue;
        final inkRatio = inkPx / seen;
        final colourRatio = colourPx / seen;
        // Dense dark cells or coloured cells belong to a figure; thin text
        // strokes stay below 0.30 unless the line is solid.
        if (inkRatio > 0.32 || colourRatio > 0.18) ink[cy * cols + cx] = 1;
        if (colourRatio > 0.18) colour[cy * cols + cx] = 1;
      }
    }

    // ---- 2. join neighbouring cells so a labelled figure stays one blob
    final dilated = Uint8List(cols * rows);
    for (var cy = 0; cy < rows; cy++) {
      for (var cx = 0; cx < cols; cx++) {
        if (ink[cy * cols + cx] == 0) continue;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
            dilated[ny * cols + nx] = 1;
          }
        }
      }
    }

    // ---- 3. flood fill into components
    final seenCell = Uint8List(cols * rows);
    final boxes = <FigureBox>[];
    for (var start = 0; start < dilated.length; start++) {
      if (dilated[start] == 0 || seenCell[start] == 1) continue;
      var minx = cols, miny = rows, maxx = 0, maxy = 0, count = 0;
      var colourCells = 0;
      final stack = <int>[start];
      seenCell[start] = 1;
      while (stack.isNotEmpty) {
        final idx = stack.removeLast();
        final cx = idx % cols, cy = idx ~/ cols;
        count++;
        if (colour[idx] == 1) colourCells++;
        if (cx < minx) minx = cx;
        if (cx > maxx) maxx = cx;
        if (cy < miny) miny = cy;
        if (cy > maxy) maxy = cy;
        for (final d in [-1, 1, -cols, cols]) {
          final n = idx + d;
          if (n < 0 || n >= dilated.length) continue;
          if (d == -1 && cx == 0) continue;
          if (d == 1 && cx == cols - 1) continue;
          if (dilated[n] == 0 || seenCell[n] == 1) continue;
          seenCell[n] = 1;
          stack.add(n);
        }
      }

      final left = minx / cols;
      final top = miny / rows;
      final right = (maxx + 1) / cols;
      final bottom = (maxy + 1) / rows;
      final box = FigureBox(left, top, right, bottom,
          coloured: count > 0 && colourCells > count * 0.12);

      // Reject text bands: wide, thin, mostly empty.
      final fill = count / (cols * rows);
      if (box.width < minWidth || box.height < minHeight) continue;
      if (box.area < minArea) continue;
      if (box.width > 0.98 && box.height < 0.08) continue; // header/footer rule
      if (fill < 0.055) continue; // scattered artefacts
      if (colourCells == 0 && box.height < 0.10) continue; // a bold title
      if (colourCells == 0 && box.area > 0.5) continue; // a grey text column
      boxes.add(box);
    }

    boxes.sort((a, b) => b.area.compareTo(a.area));
    return boxes.take(maxBoxes).toList();
  }

  /// Pick the box the AI meant, given its rough hint ("top" / "middle" /
  /// "bottom") and, when it gave one, its own guess.
  static FigureBox? choose(
    List<FigureBox> boxes, {
    String? where,
    List<double>? hint,
  }) {
    if (boxes.isEmpty) return null;
    final band = _bandFor(where);
    if (band != null) {
      final inBand = boxes
          .where((b) => b.centerY >= band.$1 && b.centerY <= band.$2)
          .toList()
        ..sort((a, b) {
          // A coloured blob beats a grey one; then the bigger one wins.
          if (a.coloured != b.coloured) return a.coloured ? -1 : 1;
          return b.area.compareTo(a.area);
        });
      if (inBand.isNotEmpty) return inBand.first;
    }
    if (hint != null && hint.length == 4) {
      final hx = (hint[0] + hint[2]) / 2;
      final hy = (hint[1] + hint[3]) / 2;
      FigureBox? best;
      var bestD = double.infinity;
      for (final b in boxes) {
        final dx = ((b.left + b.right) / 2) - hx;
        final dy = b.centerY - hy;
        final d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          best = b;
        }
      }
      if (best != null && bestD < 0.16) return best;
    }
    final byArea = [...boxes]..sort((a, b) => b.area.compareTo(a.area));
    return byArea.first;
  }

  static (double, double)? _bandFor(String? where) {
    switch ((where ?? '').trim().toLowerCase()) {
      case 'top':
      case 'upper':
        return (0.0, 0.5);
      case 'middle':
      case 'center':
      case 'centre':
        return (0.18, 0.85);
      case 'bottom':
      case 'lower':
        return (0.45, 1.0);
      default:
        return null;
    }
  }

  /// Grow a box slightly so captions and arrowheads are not cut off.
  static FigureBox pad(FigureBox b, {double margin = 0.012, double maxSpan = 0.92}) {
    var left = math.max(0.0, b.left - margin);
    var top = math.max(0.0, b.top - margin);
    var right = math.min(1.0, b.right + margin);
    var bottom = math.min(1.0, b.bottom + margin);
    if (right - left > maxSpan) {
      final mid = (left + right) / 2;
      left = mid - maxSpan / 2;
      right = mid + maxSpan / 2;
    }
    if (bottom - top < 0.06) {
      bottom = math.min(1.0, top + 0.06);
    }
    return FigureBox(left.clamp(0.0, 1.0), top.clamp(0.0, 1.0),
        right.clamp(0.0, 1.0), bottom.clamp(0.0, 1.0));
  }
}
