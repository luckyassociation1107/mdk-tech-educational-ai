import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'emoji_vault.dart';
import 'secp256k1.dart';
import 'vault_table.dart';

/// ─────────────────────────────────────────────────────────────────────
///  NostrSync — free, public Nostr relays used as the cloud database.
///
///  No signup, no API key, no paid tier: an event is just a signed JSON
///  message that any relay will keep. We publish ONE replaceable event
///  (kind 30078, "app data", d-tag `emoji-vault`) whose content is the
///  emoji packet — i.e. the encrypted, gzipped, emoji-encoded table JSON.
///
///  Safety: the content is encrypted BEFORE it is signed, so a relay only
///  stores emojis. Re-publishing replaces the old event (same d-tag +
///  author), so it always stays one row.
///
///  Honest limit: public relays are free and therefore not a guarantee —
///  some prune old events. That is why the app publishes to several
///  relays at once AND keeps the local vault + emoji code backup.
/// ─────────────────────────────────────────────────────────────────────
class RelayResult {
  final String url;
  final bool ok;
  final String message;
  RelayResult(this.url, this.ok, this.message);
}

class SyncReport {
  final bool ok;
  final String? eventId;
  final int bytes;
  final List<RelayResult> relays;
  final String? error;
  SyncReport({
    required this.ok,
    this.eventId,
    required this.bytes,
    required this.relays,
    this.error,
  });

  int get okCount => relays.where((r) => r.ok).length;
}

class FetchReport {
  final bool found;
  final String? emoji;
  final int createdAt;
  final String? sourceRelay;
  final List<RelayResult> relays;
  final String? error;
  FetchReport({
    required this.found,
    this.emoji,
    this.createdAt = 0,
    this.sourceRelay,
    required this.relays,
    this.error,
  });
}

class NostrSync {
  /// Free public relays. Several of them on purpose — if one is down or
  /// prunes data, another still has the copy.
  static const List<String> defaultRelays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://nostr.mom',
    'wss://relay.primal.net',
    'wss://relay.snort.social',
    'wss://nostr-pub.wellorder.net',
  ];

  static const int kind = 30078;
  static const String dTag = 'emoji-vault';

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String s) {
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _jsonCompact(Object? value) => jsonEncode(value);

  /// Build + sign a NIP-01 event. Returns the event map ready to send.
  static Map<String, dynamic> buildEvent({
    required String secretHex,
    required String content,
    int? createdAt,
    List<List<String>>? extraTags,
  }) {
    final sk = _hexToBytes(secretHex);
    final pk = _hex(Secp256k1.publicKeyX(sk));
    final ts = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final tags = <List<String>>[
      ['d', dTag],
      ['t', 'emoji-vault'],
      ...[
        ...?extraTags,
      ],
    ];
    final serialized = _jsonCompact([0, pk, ts, kind, tags, content]);
    final id = _hex(sha256.convert(utf8.encode(serialized)).bytes);
    final aux = Uint8List.fromList(
        List<int>.generate(32, (_) => math.Random.secure().nextInt(256)));
    final sig = _hex(
        Secp256k1.schnorrSign(_hexToBytes(secretHex), _hexToBytes(id), aux));
    return {
      'id': id,
      'pubkey': pk,
      'created_at': ts,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }

  /// Local self-check: the signature of an event we just built verifies.
  static bool verifyEvent(Map ev) {
    try {
      final serialized = _jsonCompact([
        0,
        ev['pubkey'],
        ev['created_at'],
        ev['kind'],
        ev['tags'],
        ev['content'],
      ]);
      final id = _hex(sha256.convert(utf8.encode(serialized)).bytes);
      if (id != ev['id']) return false;
      return Secp256k1.schnorrVerify(
          _hexToBytes('${ev['pubkey']}'),
          _hexToBytes('${ev['id']}'),
          _hexToBytes('${ev['sig']}'));
    } catch (_) {
      return false;
    }
  }

  static String packSecret(Map<String, dynamic> tableDoc, String secretHex) =>
      EmojiPacket.pack(tableDoc, EmojiPacket.keyFromSyncSecret(secretHex));

  static Map<String, dynamic>? unpackSecret(String emoji, String secretHex) =>
      EmojiPacket.unpack(emoji, EmojiPacket.keyFromSyncSecret(secretHex));

  /// Fire-and-forget backup used after a class or test when the child has
  /// switched auto-backup on. Failures are ignored on purpose: the phone
  /// copy is always the source of truth.
  static Future<void> autoAfterActivity() async {
    try {
      if (!VaultStore.autoBackup) return;
      await backup(timeout: const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Full backup: vault + progress → tables → emoji → signed event → relays.
  static Future<SyncReport> backup({
    List<String>? relays,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final secret = await VaultStore.nostrSecret();
    final doc = await VaultTables.build();
    final content = packSecret(doc, secret);
    final event = buildEvent(secretHex: secret, content: content);

    if (!verifyEvent(event)) {
      return SyncReport(
        ok: false,
        bytes: content.length,
        relays: const [],
        error: 'Local signature check failed — nothing was sent.',
      );
    }

    final targets = relays ?? _targets();
    final results = <RelayResult>[];
    final enough = Completer<void>();
    final futures = targets.map((r) async {
      final res = await _publishTo(r, event, timeout);
      results.add(res);
      if (!enough.isCompleted && results.where((x) => x.ok).length >= 3) {
        enough.complete();
      }
      return res;
    }).toList();
    // Return as soon as 3 relays have confirmed (then a short grace period
    // for the others) — never wait the full timeout for one slow relay.
    await Future.any([
      Future.wait(futures),
      enough.future.then((_) => Future.delayed(const Duration(milliseconds: 900))),
    ]);
    final okAny = results.any((r) => r.ok);
    return SyncReport(
      ok: okAny,
      eventId: event['id'] as String,
      bytes: content.length,
      relays: results,
      error: okAny ? null : 'No relay accepted the event. Try again later.',
    );
  }

  /// Pull the newest event from the relays, decrypt it and turn the
  /// emojis back into tables → vault JSON.
  static Future<FetchReport> fetch({
    List<String>? relays,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final secret = await VaultStore.nostrSecretCached ??
        await VaultStore.nostrSecret();
    final pk = _hex(Secp256k1.publicKeyX(_hexToBytes(secret)));
    final targets = relays ?? _targets();
    final results = <RelayResult>[];
    Map<String, dynamic>? best;
    String? bestRelay;

    final found = Completer<void>();
    final futures = targets.map((relay) async {
      try {
        final events = await _queryRelay(relay, pk, timeout);
        results.add(RelayResult(relay, true, '${events.length} event(s)'));
        for (final ev in events) {
          final b = best;
          if (b == null ||
              (ev['created_at'] as num? ?? 0) >
                  (b['created_at'] as num? ?? 0)) {
            best = ev;
            bestRelay = relay;
          }
        }
        if (best != null && !found.isCompleted) found.complete();
      } catch (e) {
        results.add(RelayResult(relay, false, _short(e)));
      }
    }).toList();
    await Future.any([
      Future.wait(futures),
      found.future.then((_) => Future.delayed(const Duration(milliseconds: 900))),
    ]);

    final newest = best;
    if (newest == null) {
      return FetchReport(
        found: false,
        relays: results,
        error: 'No backup found on these relays yet.',
      );
    }
    final content = '${newest['content']}';
    return FetchReport(
      found: true,
      emoji: content,
      createdAt: (newest['created_at'] as num? ?? 0).toInt(),
      sourceRelay: bestRelay,
      relays: results,
    );
  }

  static List<String> _targets() {
    final saved = VaultStore.savedRelays;
    return saved.isEmpty ? defaultRelays : saved;
  }

  static String _short(Object e) {
    final s = '$e';
    return s.length > 120 ? '${s.substring(0, 117)}…' : s;
  }

  static Future<RelayResult> _publishTo(
      String url, Map<String, dynamic> event, Duration timeout) async {
    WebSocket? ws;
    StreamSubscription? sub;
    try {
      ws = await WebSocket.connect(url).timeout(timeout);
      final done = Completer<RelayResult>();
      sub = ws.listen((data) {
        try {
          final msg = jsonDecode('$data');
          if (msg is List && msg.isNotEmpty && msg[0] == 'OK') {
            final ok = msg.length > 2 && msg[2] == true;
            final note = msg.length > 3 ? '${msg[3]}' : '';
            if (!done.isCompleted) {
              done.complete(RelayResult(
                  url, ok, ok ? 'stored' : (note.isEmpty ? 'rejected' : note)));
            }
          } else if (msg is List && msg.isNotEmpty && msg[0] == 'NOTICE') {
            if (!done.isCompleted) {
              done.complete(RelayResult(url, false, '${msg[1]}'));
            }
          }
        } catch (_) {}
      }, onError: (e) {
        if (!done.isCompleted) done.complete(RelayResult(url, false, _short(e)));
      }, onDone: () {
        if (!done.isCompleted) {
          done.complete(RelayResult(url, false, 'connection closed'));
        }
      });
      ws.add(jsonEncode(['EVENT', event]));
      final r = await done.future
          .timeout(timeout, onTimeout: () => RelayResult(url, false, 'timeout'));
      return r;
    } catch (e) {
      return RelayResult(url, false, _short(e));
    } finally {
      try {
        await sub?.cancel();
        await ws?.close();
      } catch (_) {}
    }
  }

  static Future<List<Map<String, dynamic>>> _queryRelay(
      String url, String pubkey, Duration timeout) async {
    WebSocket? ws;
    StreamSubscription? sub;
    final events = <Map<String, dynamic>>[];
    try {
      ws = await WebSocket.connect(url).timeout(timeout);
      final done = Completer<void>();
      final subId = 'emoji-vault-${DateTime.now().millisecondsSinceEpoch}';
      sub = ws.listen((data) {
        try {
          final msg = jsonDecode('$data');
          if (msg is! List || msg.isEmpty) return;
          if (msg[0] == 'EVENT' && msg.length > 2 && msg[1] == subId) {
            final ev = msg[2];
            if (ev is Map &&
                '${ev['kind']}' == '$kind' &&
                '${ev['pubkey']}' == pubkey) {
              events.add(ev.map((k, v) => MapEntry(k.toString(), v)));
            }
          } else if (msg[0] == 'EOSE' && msg.length > 1 && msg[1] == subId) {
            if (!done.isCompleted) done.complete();
          }
        } catch (_) {}
      }, onError: (_) {
        if (!done.isCompleted) done.complete();
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      });
      ws.add(jsonEncode([
        'REQ',
        subId,
        {
          'kinds': [kind],
          'authors': [pubkey],
          '#d': [dTag],
          'limit': 5,
        }
      ]));
      await done.future.timeout(timeout, onTimeout: () {});
      try {
        ws.add(jsonEncode(['CLOSE', subId]));
      } catch (_) {}
      return events;
    } finally {
      try {
        await sub?.cancel();
        await ws?.close();
      } catch (_) {}
    }
  }
}
