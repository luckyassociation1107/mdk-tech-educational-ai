import 'dart:convert';

/// Models do not always obey "JSON only". These helpers take whatever came
/// back — fenced code, a sentence of chat, a trailing comma — and return the
/// object, or null when there is genuinely nothing usable.
class JsonUtils {
  /// First `{…}` block in [raw], brace-matched (strings and escapes are
  /// respected), parsed as a map.
  static Map<String, dynamic>? object(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;

    // Drop a ```json fence if the model wrapped the answer.
    if (text.startsWith('```')) {
      final firstLine = text.indexOf('\n');
      if (firstLine >= 0) text = text.substring(firstLine + 1);
      final fence = text.lastIndexOf('```');
      if (fence >= 0) text = text.substring(0, fence);
      text = text.trim();
    }

    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    var end = -1;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) return null;

    var slice = text.substring(start, end + 1);
    try {
      final j = jsonDecode(slice);
      if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      // Try once more after removing the usual model mistakes.
      slice = slice
          .replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m.group(1)!)
          .replaceAll(RegExp(r'[\u201c\u201d]'), '"');
      try {
        final j = jsonDecode(slice);
        if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {}
    }
    return null;
  }

  static String str(dynamic v, {String fallback = ''}) {
    if (v == null) return fallback;
    final s = v is String ? v : '$v';
    return s.trim();
  }

  static int integer(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse('${v ?? ''}'.trim()) ?? fallback;
  }

  /// A normalised [x0,y0,x1,y1] box inside the page, or null.
  ///
  /// The model is told to send fractions 0..1 with the origin at the top
  /// left; this also tolerates percentages (0..100) and swapped corners.
  static List<double>? bbox(dynamic v) {
    if (v is! List || v.length < 4) return null;
    final nums = <double>[];
    for (final e in v.take(4)) {
      if (e is num) {
        nums.add(e.toDouble());
      } else {
        final d = double.tryParse('$e'.trim());
        if (d == null) return null;
        nums.add(d);
      }
    }
    if (nums.any((n) => n.isNaN || n.isInfinite)) return null;
    // Percentages → fractions (only when the box really looks like one).
    if (nums.every((n) => n >= 0 && n <= 100) && nums.any((n) => n > 2.0)) {
      for (var i = 0; i < 4; i++) {
        nums[i] = nums[i] / 100;
      }
    }
    var x0 = nums[0], y0 = nums[1], x1 = nums[2], y1 = nums[3];
    if (x0 > x1) {
      final t = x0;
      x0 = x1;
      x1 = t;
    }
    if (y0 > y1) {
      final t = y0;
      y0 = y1;
      y1 = t;
    }
    x0 = x0.clamp(0.0, 1.0);
    y0 = y0.clamp(0.0, 1.0);
    x1 = x1.clamp(0.0, 1.0);
    y1 = y1.clamp(0.0, 1.0);
    if (x1 - x0 < 0.04 || y1 - y0 < 0.04) return null; // too small to crop
    return [x0, y0, x1, y1];
  }

  /// Text that is safe to speak: collapsed whitespace, no markdown glyphs.
  static String speech(String text) => text
      .replaceAll(RegExp(r'[*_`#>]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
