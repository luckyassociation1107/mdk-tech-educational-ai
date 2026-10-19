import 'package:http/http.dart' as http;

import 'catalog_codec.dart';
import 'store.dart';

/// Cloud link catalog on top of a Google Form + Sheet pair:
///
///  WRITE (teacher devices): when a textbook PDF is uploaded it is auto
///  sent to Gofile, and the resulting link is submitted anonymously to
///  the Form (no Google sign-in in the app - the Form is the anonymous
///  "report function"). One encoded string per entry.
///
///  READ (every device): the linked Sheet is fetched as public gviz
///  JSON and decoded. Entries never appear on any public web page.
///
/// Setup lives in Settings (form URL, entry id, sheet URL). Everything
/// degrades quietly: without setup, or offline, the app simply uses its
/// on-device catalog as before.
class CatalogService {
  static bool canPost(AppSettings s) => s.catalogFormUrl.trim().isNotEmpty && s.catalogEntryId.trim().isNotEmpty;
  static bool canRead(AppSettings s) => s.catalogSheetUrl.trim().isNotEmpty;

  static Future<bool> post(AppSettings s, CatalogEntry e) async {
    if (!canPost(s)) return false;
    try {
      final url = CatalogCodec.formToResponse(s.catalogFormUrl);
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {s.catalogEntryId.trim(): CatalogCodec.encode(e)},
      ).timeout(const Duration(seconds: 25));
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  static Future<List<CatalogEntry>> fetch(AppSettings s) async {
    if (!canRead(s)) return const [];
    try {
      final url = CatalogCodec.sheetToGviz(s.catalogSheetUrl);
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
      if (resp.statusCode != 200) return const [];
      return CatalogCodec.parseSheetBody(resp.body);
    } catch (_) {
      return const [];
    }
  }
}
