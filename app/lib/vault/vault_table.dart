import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'emoji_vault.dart';

/// ─────────────────────────────────────────────────────────────────────
///  VaultTables — turns the vault JSON into real, readable TABLES and
///  back again.
///
///      vault JSON ─► tables (rows × columns) ─► JSON ─► gzip ─► seal
///                 ─► base64 ─► EMOJI ─► Nostr relay
///
///  and the exact reverse on the way back:
///
///      EMOJI ─► base64 ─► open (PIN/sync key) ─► gunzip ─► JSON
///            ─► tables ─► vault JSON + device progress restored
///
///  Nothing leaves the phone unencrypted: the relay only ever sees a
///  string of fruit, animals and stars.
/// ─────────────────────────────────────────────────────────────────────
class VaultTable {
  final String name;
  final List<String> columns;
  final List<List<dynamic>> rows;

  const VaultTable(this.name, this.columns, this.rows);

  Map<String, dynamic> toJson() => {
        'columns': columns,
        'rows': rows,
      };

  static VaultTable fromJson(String name, Map m) => VaultTable(
        name,
        ((m['columns'] as List?) ?? const []).map((e) => '$e').toList(),
        ((m['rows'] as List?) ?? const [])
            .whereType<List>()
            .map((r) => List<dynamic>.from(r))
            .toList(),
      );

  int get rowCount => rows.length;
}

class VaultTables {
  /// Device progress that belongs to a child, collected from
  /// SharedPreferences. Keys not in this list (theme, app settings, the
  /// vault blob itself) are never uploaded.
  static const List<String> progressPrefixes = [
    'child_',
    'xp_',
    'done_',
    'pos_',
    'study_',
    'exam_results_',
    'bookmarks_',
    'word_bank_',
    'streak',
    'seen_badges',
    'flash_',
  ];

  static const String _vaultKey = 'emoji_vault_blob';

  /// vault JSON + device progress → table document (pure JSON).
  static Future<Map<String, dynamic>> build() async {
    final root = VaultStore.exportRoot();
    final prefs = await SharedPreferences.getInstance();
    final progress = <List<dynamic>>[];
    for (final key in prefs.getKeys()) {
      if (key == _vaultKey) continue;
      if (!progressPrefixes.any(key.startsWith)) continue;
      final value = prefs.get(key);
      if (value == null) continue;
      final String type;
      final String text;
      if (value is String) {
        type = 'string';
        text = value;
      } else if (value is int) {
        type = 'int';
        text = '$value';
      } else if (value is double) {
        type = 'double';
        text = '$value';
      } else if (value is bool) {
        type = 'bool';
        text = '$value';
      } else if (value is List) {
        type = 'list';
        text = jsonEncode(value);
      } else {
        continue;
      }
      progress.add([key, type, text]);
    }
    progress.sort((a, b) => '${a[0]}'.compareTo('${b[0]}'));
    return tableDocFromRoot(root, progress: progress);
  }

  /// The actual conversion: JSON object → tables.
  static Map<String, dynamic> tableDocFromRoot(
    Map<String, dynamic> root, {
    List<List<dynamic>> progress = const [],
  }) {
    final profiles = <List<dynamic>>[];
    for (final p in (root['profiles'] as List?) ?? const []) {
      if (p is! Map) continue;
      profiles.add([
        '${p['id']}',
        '${p['name'] ?? ''}',
        '${p['avatar'] ?? ''}',
        (p['createdAt'] as num?)?.toInt() ?? 0,
        (p['lastLogin'] as num?)?.toInt() ?? 0,
        (p['loginCount'] as num?)?.toInt() ?? 0,
        '${p['salt'] ?? ''}',
        '${p['verifier'] ?? ''}',
      ]);
    }

    // Sealed cells: still encrypted with the child's PIN. The relay can
    // read these three strings but never the child's data.
    final sealed = <List<dynamic>>[];
    final vault = root['vault'];
    if (vault is Map) {
      vault.forEach((id, cell) {
        if (cell is! Map) return;
        sealed.add(['$id', '${cell['n']}', '${cell['c']}', '${cell['t']}']);
      });
    }

    final settings = <List<dynamic>>[];
    final st = root['settings'];
    if (st is Map) {
      st.forEach((k, v) => settings.add(['$k', '$v']));
    }

    // Activity: everything the logged-in child did (already encrypted at
    // rest; this is only used for the on-screen preview).
    final activity = <List<dynamic>>[];
    final current = VaultStore.current;
    if (current != null) {
      for (final l in (current.data['logs'] as List?) ?? const []) {
        if (l is! Map) continue;
        activity.add([
          current.id,
          (l['at'] as num?)?.toInt() ?? 0,
          '${l['type'] ?? ''}',
          '${l['msg'] ?? ''}',
        ]);
      }
    }

    return {
      'format': 'emoji-vault-table',
      'version': 1,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'app': 'AI Textbook Classroom',
      'tables': {
        'profiles': VaultTable(
          'profiles',
          ['id', 'name', 'avatar', 'created', 'last_login', 'logins', 'salt', 'verifier'],
          profiles,
        ).toJson(),
        'sealed': VaultTable(
          'sealed_cells',
          ['profile', 'nonce', 'cipher', 'tag'],
          sealed,
        ).toJson(),
        'settings': VaultTable('settings', ['key', 'value'], settings).toJson(),
        'progress': VaultTable('progress', ['key', 'type', 'value'], progress).toJson(),
        'activity': VaultTable(
          'activity',
          ['profile', 'at', 'type', 'message'],
          activity,
        ).toJson(),
      },
    };
  }

  /// Tables → vault JSON again (the reverse of [tableDocFromRoot]).
  static Map<String, dynamic> rootFromTables(Map<String, dynamic> doc) {
    final tables = (doc['tables'] as Map?) ?? const {};
    final root = <String, dynamic>{
      'app': 'AI Textbook Classroom',
      'kind': 'emoji-vault',
      'version': 1,
      'profiles': <Map<String, dynamic>>[],
      'vault': <String, Map<String, dynamic>>{},
      'settings': <String, dynamic>{},
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

    final p = tables['profiles'];
    if (p is Map) {
      final cols = ((p['columns'] as List?) ?? const []).map((e) => '$e').toList();
      for (final row in ((p['rows'] as List?) ?? const []).whereType<List>()) {
        final m = <String, dynamic>{};
        for (var i = 0; i < cols.length && i < row.length; i++) {
          m[cols[i]] = row[i];
        }
        root['profiles'].add({
          'id': '${m['id']}',
          'name': '${m['name'] ?? 'Learner'}',
          'avatar': '${m['avatar'] ?? '🐼'}',
          'salt': '${m['salt'] ?? ''}',
          'verifier': '${m['verifier'] ?? ''}',
          'createdAt': (m['created'] as num?)?.toInt() ?? 0,
          'lastLogin': (m['last_login'] as num?)?.toInt() ?? 0,
          'loginCount': (m['logins'] as num?)?.toInt() ?? 0,
        });
      }
    }

    final s = tables['sealed'];
    if (s is Map) {
      final cols = ((s['columns'] as List?) ?? const []).map((e) => '$e').toList();
      for (final row in ((s['rows'] as List?) ?? const []).whereType<List>()) {
        final m = <String, dynamic>{};
        for (var i = 0; i < cols.length && i < row.length; i++) {
          m[cols[i]] = '${row[i]}';
        }
        if (m['profile'] == null) continue;
        root['vault'][m['profile']] = {
          'n': m['nonce'],
          'c': m['cipher'],
          't': m['tag'],
        };
      }
    }

    final st = tables['settings'];
    if (st is Map) {
      final cols = ((st['columns'] as List?) ?? const []).map((e) => '$e').toList();
      for (final row in ((st['rows'] as List?) ?? const []).whereType<List>()) {
        if (row.length < 2) continue;
        final k = '${row[cols.indexOf('key') >= 0 ? cols.indexOf('key') : 0]}';
        root['settings'][k] = '${row[cols.indexOf('value') >= 0 ? cols.indexOf('value') : 1]}';
      }
    }
    return root;
  }

  /// Progress rows → SharedPreferences again.
  static Future<int> restoreProgress(Map<String, dynamic> doc) async {
    final tables = (doc['tables'] as Map?) ?? const {};
    final t = tables['progress'];
    if (t is! Map) return 0;
    final prefs = await SharedPreferences.getInstance();
    var n = 0;
    for (final row in ((t['rows'] as List?) ?? const []).whereType<List>()) {
      if (row.length < 3) continue;
      final key = '${row[0]}';
      final type = '${row[1]}';
      final text = '${row[2]}';
      if (key == _vaultKey) continue;
      try {
        switch (type) {
          case 'int':
            await prefs.setInt(key, int.parse(text));
            break;
          case 'double':
            await prefs.setDouble(key, double.parse(text));
            break;
          case 'bool':
            await prefs.setBool(key, text == 'true');
            break;
          case 'list':
            final list = (jsonDecode(text) as List).map((e) => '$e').toList();
            await prefs.setStringList(key, list);
            break;
          default:
            await prefs.setString(key, text);
        }
        n++;
      } catch (_) {}
    }
    return n;
  }

  static List<VaultTable> listOf(Map<String, dynamic> doc) {
    final tables = (doc['tables'] as Map?) ?? const {};
    return tables.entries
        .where((e) => e.value is Map)
        .map((e) => VaultTable.fromJson('${e.key}', e.value as Map))
        .toList();
  }
}

/// ─────────────────────────────────────────────────────────────────────
///  EmojiPacket — JSON → gzip → encrypted → base64 → emoji, and back.
/// ─────────────────────────────────────────────────────────────────────
class EmojiPacket {
  static const String _hint = 'emoji-table-v1';

  static Uint8List keyFromSyncSecret(String secretHex) => VaultCrypto.pbkdf2(
        secretHex,
        utf8.encode('emoji-vault-nostr-v1'),
        rounds: 30000,
        length: 32,
      );

  static String pack(Map<String, dynamic> doc, Uint8List key) {
    final gz = gzip.encode(utf8.encode(jsonEncode(doc)));
    final sealed = VaultCrypto.seal(base64UrlEncode(gz), key);
    final envelope = jsonEncode({
      'v': 1,
      'k': 'gzip+b64+hmac',
      'hint': _hint,
      's': sealed,
    });
    return EmojiCodec.encode(utf8.encode(envelope));
  }

  static Map<String, dynamic>? unpack(String emoji, Uint8List key) {
    try {
      final raw = utf8.decode(EmojiCodec.decode(emoji));
      final env = jsonDecode(raw);
      if (env is! Map) return null;
      final sealed = env['s'];
      if (sealed is! Map) return null;
      final b64 = VaultCrypto.open(sealed, key);
      if (b64 == null) return null;
      final doc = jsonDecode(utf8.decode(gzip.decode(base64Url.decode(b64))));
      if (doc is! Map) return null;
      if ('${doc['format']}' != 'emoji-vault-table') return null;
      return doc.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  /// Sanity check for the UI: how big is this packet on the wire?
  static int wireBytes(String emoji) => utf8.encode(emoji).length;
}
