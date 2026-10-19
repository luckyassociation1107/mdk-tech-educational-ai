import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'catalog_codec.dart';
import 'nostr_crypto.dart';

/// Catalog transport over public Nostr relays.
///
/// WRITE: teachers publish kind-1 events signed with the school's shared
/// catalog key. Content is only the encoded `MDKCAT1.` token.
/// READ: any device queries relays by the catalog public key and decodes
/// the tokens. Relays replicate each other, are free, need no account,
/// and have no practical storage cap for text links. Several relays are
/// always used in parallel; success on any one is enough.
class NostrCatalog {
  static const List<String> relays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.primal.net',
    'wss://relay.snort.social',
  ];

  static const _tag = 'mdk-textbook-catalog';

  static Future<bool> publish(String secretHex, CatalogEntry entry) async {
    Map<String, dynamic> event;
    try {
      event = NostrCrypto.signedEvent(
        secretHex: secretHex,
        kind: 1,
        tags: [
          ['t', _tag]
        ],
        content: CatalogCodec.encode(entry),
        createdAt: entry.ts ~/ 1000,
      );
    } catch (_) {
      return false;
    }
    final results = await Future.wait(relays.map((r) => _publishOne(r, event)));
    return results.any((x) => x);
  }

  static Future<bool> _publishOne(String relay, Map<String, dynamic> event) async {
    WebSocketChannel? ch;
    try {
      ch = WebSocketChannel.connect(Uri.parse(relay));
      await ch.ready.timeout(const Duration(seconds: 8));
      ch.sink.add(jsonEncode(['EVENT', event]));
      final id = event['id'];
      await for (final raw in ch.stream.timeout(const Duration(seconds: 8))) {
        try {
          final msg = jsonDecode(raw.toString());
          if (msg is List && msg.length >= 3 && msg[0] == 'OK' && msg[1] == id) {
            return msg[2] == true;
          }
          if (msg is List && msg.isNotEmpty && msg[0] == 'CLOSED') return false;
        } catch (_) {}
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      try {
        await ch?.sink.close();
      } catch (_) {}
    }
  }

  static Future<List<CatalogEntry>> fetch(String pubkeyHex) async {
    final byUrl = <String, CatalogEntry>{};
    await Future.wait(relays.map((r) async {
      final entries = await _fetchOne(r, pubkeyHex);
      for (final e in entries) {
        byUrl.putIfAbsent(e.u, () => e);
      }
    }));
    final out = byUrl.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
    return out;
  }

  static Future<List<CatalogEntry>> _fetchOne(String relay, String pubkeyHex) async {
    WebSocketChannel? ch;
    final out = <CatalogEntry>[];
    final seen = <String>{};
    try {
      ch = WebSocketChannel.connect(Uri.parse(relay));
      await ch.ready.timeout(const Duration(seconds: 8));
      ch.sink.add(jsonEncode([
        'REQ',
        'catalog',
        {
          'authors': [pubkeyHex],
          'kinds': [1],
          'limit': 1000
        }
      ]));
      await for (final raw in ch.stream.timeout(const Duration(seconds: 12))) {
        try {
          final msg = jsonDecode(raw.toString());
          if (msg is List && msg.length >= 3 && msg[0] == 'EVENT') {
            final ev = msg[2];
            if (ev is Map && ev['pubkey'] == pubkeyHex && seen.add((ev['id'] ?? '').toString())) {
              final e = CatalogCodec.tryDecode(ev['content']?.toString());
              if (e != null && e.u.isNotEmpty) out.add(e);
            }
          } else if (msg is List && msg.isNotEmpty && (msg[0] == 'EOSE' || msg[0] == 'CLOSED')) {
            break;
          }
        } catch (_) {}
      }
    } catch (_) {
      // one dead relay must not break the catalog
    } finally {
      try {
        await ch?.sink.close();
      } catch (_) {}
    }
    return out;
  }
}
