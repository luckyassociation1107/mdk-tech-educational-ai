import 'dart:convert';
import 'dart:io';

/// One shared-PDF link in the cloud catalog.
class CatalogEntry {
  final String t; // title
  final String u; // Gofile download page
  final String by; // teacher name
  final String cls; // class or '' for whole school
  final int ts; // epoch millis

  const CatalogEntry({required this.t, required this.u, this.by = '', this.cls = '', required this.ts});

  Map<String, dynamic> toJson() => {'t': t, 'u': u, 'by': by, 'cls': cls, 'ts': ts};

  factory CatalogEntry.fromJson(Map<String, dynamic> j) => CatalogEntry(
        t: (j['t'] ?? '').toString(),
        u: (j['u'] ?? '').toString(),
        by: (j['by'] ?? '').toString(),
        cls: (j['cls'] ?? '').toString(),
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// Catalog entries travel as ONE encoded string:
///   MDKCAT1.<base64(gzip(json))>   (preferred)
///   MDKRAW1.<base64(json)>         (fallback)
/// They sit inside a Google Form answer -> Google Sheet cell, so nothing
/// readable ever appears on a public page. This is obfuscation, not
/// encryption - Gofile links are share links by design.
class CatalogCodec {
  static const _gzPrefix = 'MDKCAT1.';
  static const _rawPrefix = 'MDKRAW1.';
  static final _tokenRe = RegExp(r'MDK(?:CAT|RAW)1\.[A-Za-z0-9+/=]+');

  static String encode(CatalogEntry e) {
    final bytes = utf8.encode(jsonEncode(e.toJson()));
    try {
      final gz = gzip.encode(bytes);
      if (gz.length < bytes.length) return '$_gzPrefix${base64.encode(gz)}';
    } catch (_) {}
    return '$_rawPrefix${base64.encode(bytes)}';
  }

  static CatalogEntry? tryDecode(String? text) {
    if (text == null) return null;
    final m = _tokenRe.firstMatch(text);
    if (m == null) return null;
    final token = m.group(0)!;
    try {
      final payload = token.substring(token.indexOf('.') + 1);
      final raw = base64.decode(payload);
      final jsonBytes = token.startsWith(_gzPrefix) ? gzip.decode(raw) : raw;
      final j = jsonDecode(utf8.decode(jsonBytes));
      if (j is Map) return CatalogEntry.fromJson(j.map((k, v) => MapEntry(k.toString(), v)));
    } catch (_) {}
    return null;
  }

  /// Parses a Google Sheets gviz JSON response
  /// (https://docs.google.com/spreadsheets/d/<ID>/gviz/tq?tqx=out:json).
  static List<CatalogEntry> parseSheetBody(String body) {
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start < 0 || end <= start) return const [];
    try {
      final root = jsonDecode(body.substring(start, end + 1)) as Map<String, dynamic>;
      final rows = (((root['table'] as Map?)?['rows']) as List?) ?? const [];
      final out = <CatalogEntry>[];
      final seen = <String>{};
      for (final r in rows) {
        final cells = ((r as Map)['c'] as List?) ?? const [];
        for (final c in cells) {
          if (c is Map && c['v'] is String) {
            final e = tryDecode(c['v'] as String);
            if (e != null && e.u.isNotEmpty && seen.add(e.u)) out.add(e);
          }
        }
      }
      out.sort((a, b) => b.ts.compareTo(a.ts));
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Accepts a normal Sheet URL and returns its gviz JSON URL.
  static String sheetToGviz(String url) {
    final u = url.trim();
    if (u.contains('gviz')) return u;
    final m = RegExp(r'/spreadsheets/d/([A-Za-z0-9-_]+)').firstMatch(u);
    if (m == null) return u;
    return 'https://docs.google.com/spreadsheets/d/${m.group(1)}/gviz/tq?tqx=out:json';
  }

  /// Accepts a Form view URL (or a pre-filled link) and returns the
  /// formResponse endpoint used for anonymous submissions.
  static String formToResponse(String url) {
    var u = url.trim();
    u = u.replaceAll('/viewform', '/formResponse');
    if (u.contains('?')) u = u.substring(0, u.indexOf('?'));
    if (!u.endsWith('/formResponse')) u = '$u/formResponse';
    return u;
  }
}
