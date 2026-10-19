import 'package:http/http.dart' as http;

import 'catalog_codec.dart';
import 'nostr_crypto.dart';
import 'nostr_service.dart';
import 'store.dart';

/// Cloud link catalog. Primary transport is **Nostr**: teachers publish
/// entry tokens to free public relays with the school's shared catalog
/// key; every device reads them back by public key. With the school's
/// **catalog secret** set, each entry is AES-256-GCM ENCRYPTED on the
/// phone before publishing — relays store only ciphertext, and only
/// devices holding the secret can visualize the catalog. No account, no
/// company storage, no practical entry limit.
///
/// Legacy fallback (optional): Google Form (anonymous write) → Google
/// Sheet (read). Everything degrades quietly to the on-device catalog
/// when unset or offline.
class CatalogService {
  static bool _validKey(String s) => NostrCrypto.isHexKey(s.trim());

  /// All publisher keys this device reads from: its own key (derived
  /// from the private key) plus every npub listed in Settings (one per
  /// line). Each teacher can hold their OWN key — the founder approves
  /// publishers simply by adding their npub to the list, and revokes by
  /// removing it. No single shared key has to live on every phone.
  static List<String> readPubkeys(AppSettings s) {
    final out = <String>[];
    void add(String k) {
      final v = k.trim().toLowerCase();
      if (_validKey(v) && !out.contains(v)) out.add(v);
    }

    if (_validKey(s.catalogNsec)) {
      try {
        add(NostrCrypto.pubkeyHex(s.catalogNsec.trim()));
      } catch (_) {}
    }
    for (final part in s.catalogNpub.split(RegExp(r'[\s,;]+'))) {
      add(part);
    }
    return out;
  }

  static bool canPost(AppSettings s) => _validKey(s.catalogNsec) || (s.catalogFormUrl.trim().isNotEmpty && s.catalogEntryId.trim().isNotEmpty);
  static bool canRead(AppSettings s) => readPubkeys(s).isNotEmpty || s.catalogSheetUrl.trim().isNotEmpty;

  static Future<bool> post(AppSettings s, CatalogEntry e) async {
    if (_validKey(s.catalogNsec)) {
      final ok = await NostrCatalog.publish(s.catalogNsec.trim(), e, catalogSecret: s.catalogSecret);
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
        body: {s.catalogEntryId.trim(): CatalogCodec.encode(e, catalogSecret: s.catalogSecret)},
      ).timeout(const Duration(seconds: 25));
      return resp.statusCode >= 200 && resp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  static Future<List<CatalogEntry>> fetch(AppSettings s) async {
    final byUrl = <String, CatalogEntry>{};
    final pubs = readPubkeys(s);
    if (pubs.isNotEmpty) {
      for (final e in await NostrCatalog.fetch(pubs, catalogSecret: s.catalogSecret)) {
        if (e.u.isNotEmpty) byUrl.putIfAbsent(e.u, () => e);
      }
    }
    if (s.catalogSheetUrl.trim().isNotEmpty) {
      try {
        final url = CatalogCodec.sheetToGviz(s.catalogSheetUrl);
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (resp.statusCode == 200) {
          for (final e in CatalogCodec.parseSheetBody(resp.body, catalogSecret: s.catalogSecret)) {
            if (e.u.isNotEmpty) byUrl.putIfAbsent(e.u, () => e);
          }
        }
      } catch (_) {}
    }
    final out = byUrl.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
    return out;
  }
}
