import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

/// Geometry for showing a textbook page inside a video card without ever
/// squashing it.
///
/// The bug this file exists for: the page used to be drawn with
/// `BoxFit.fill` on the whole card, so a tall A4 page became a fat, blurry
/// rectangle. Everything here keeps the page's own shape.
class MediaFit {
  /// Aspect ratio (width / height) read from the PNG header.
  ///
  /// Returns null when the bytes are not a PNG or are truncated — the caller
  /// then uses the A4 default.
  static double? pngAspect(List<int> head) {
    if (head.length < 24) return null;
    if (head[0] != 0x89 || head[1] != 0x50 || head[2] != 0x4E) return null;
    final w = (head[16] << 24) | (head[17] << 16) | (head[18] << 8) | head[19];
    final h = (head[20] << 24) | (head[21] << 16) | (head[22] << 8) | head[23];
    if (w <= 0 || h <= 0) return null;
    return w / h;
  }

  /// Same as [pngAspect] but with unsigned bytes (a Uint8List from a file).
  static double? pngAspectBytes(Uint8List head) => pngAspect(head.toList());

  /// A4 portrait, used before a page render exists.
  static const double a4 = 210 / 297;

  /// The largest box with [aspect] that fits inside [box], centred by the
  /// caller. Never larger than the box, never distorted.
  static Size fitInside(Size box, double aspect) {
    if (box.width <= 0 || box.height <= 0) return Size.zero;
    final ar = aspect <= 0 ? a4 : aspect;
    var w = box.width;
    var h = w / ar;
    if (h > box.height) {
      h = box.height;
      w = h * ar;
    }
    return Size(w, h);
  }

  /// How much to magnify the fitted page so [zone] (page fractions) fills
  /// most of the card. Clamped, so a tiny zone does not turn into a blur.
  static double zoomFor(double zoneWidth) =>
      math.min(3.4, 0.92 / math.max(0.18, zoneWidth));

  /// Keeps a pan inside the page: you cannot drag the page off the card.
  static double clampPan(double value, double display, double scale,
      double box) {
    final max = math.max(0.0, (display * scale - box) / 2);
    return value.clamp(-max, max).toDouble();
  }
}
