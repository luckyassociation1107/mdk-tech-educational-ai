import 'catalog_codec.dart';
import 'nostr_crypto.dart';
import 'nostr_service.dart';
import 'store.dart';
import 'package:http/http.dart' as http;

/// Cloud link catalog. Primary transport is **Nostr**: teachers publish
/// encoded link entries to free public relays with the school's shared
/// catalog key; every device reads them back by public key. No account,
/// no company storage and no practical entry limit.
///
/// Legacy fallback (optional): a Google Form (anonymous write) feeding a
/// Google Sheet (read). Everything degrades quietly to the on-device
/// catalog when unset or offline.
class CatalogService {
  static bool _validKey(String s) => NostrCrypto.isHexKey(s.trim());

  /// Public key used for reading: derived from the private key when this
  /// device publishes, otherwise the shared catalog npub from Settings.
  static String? readPubkey(AppSettings s) {
    if (_validKey(s.catalogNsec)) {
      try {
        return NostrCrypto.pubkeyHex(s.catalogNsec.trim());
      } catch (_) {}
    }
    if (_validKey(s.catalogNpub)) return s.catalogNpub.trim().toLowerCase();
    return null;
  }

  static bool canPost(AppSettings s) => _validKey(s.catalogNsec) || (s.catalogFormUrl.trim().isNotEmpty && s.catalogEntryId.trim().isNotEmpty);
  static bool canRead(AppSettings s) => readPubkey(s) != null || s.catalogSheetUrl.trim().isNotEmpty;

  static Future<bool> post(AppSettings s, CatalogEntry e) async {
    if (_validKey(s.catalogNsec)) {
      final ok = await NostrCatalog.publish(s.catalogNsec.trim(), e);
      if (ok) return true;
    }
    return _postForm(s, e);
  }

  static Future<bool> _postForm(AppSettings s, CatalogEntry e) async {
    if (s.catalogFormUrl.trim().isEmpty || s.catalogEntryId.trim().isEmpty) return false;
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
    final byUrl = <String, CatalogEntry>{};
    final pub = readPubkey(s);
    if (pub != null) {
      for (final e in await NostrCatalog.fetch(pub)) {
        if (e.u.isNotEmpty) byUrl.putIfAbsent(e.u, () => e);
      }
    }
    if (s.catalogSheetUrl.trim().isNotEmpty) {
      try {
        final url = CatalogCodec.sheetToGviz(s.catalogSheetUrl);
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (resp.statusCode == 200) {
          for (final e in CatalogCodec.parseSheetBody(resp.body)) {
            if (e.u.isNotEmpty) byUrl.putIfAbsent(e.u, () => e);
          }
        }
      } catch (_) {}
    }
    final out = byUrl.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
    return out;
  }
}
