import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/premium_ui.dart';
import '../vault/emoji_vault.dart';
import '../vault/nostr_sync.dart';
import '../vault/vault_table.dart';
import '../widgets.dart';

/// Emoji cloud vault — the encrypted table database kept on free Nostr
/// relays, plus the readable TABLE view of what the emojis actually are.
class VaultSyncScreen extends StatefulWidget {
  const VaultSyncScreen({super.key});

  @override
  State<VaultSyncScreen> createState() => _VaultSyncScreenState();
}

class _VaultSyncScreenState extends State<VaultSyncScreen> {
  bool _busy = false;
  String _stage = '';
  Map<String, dynamic>? _doc;
  SyncReport? _lastBackup;
  FetchReport? _lastFetch;
  final List<String> _log = [];
  late List<String> _relays;

  @override
  void initState() {
    super.initState();
    _relays = VaultStore.savedRelays.isEmpty
        ? List<String>.from(NostrSync.defaultRelays)
        : List<String>.from(VaultStore.savedRelays);
  }

  void _say(String s) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, s);
      if (_log.length > 40) _log.removeLast();
    });
  }

  Future<void> _backup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _stage = 'Building tables…';
    });
    try {
      final doc = await VaultTables.build();
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _stage = 'Encrypting + writing emojis…';
      });
      final report = await NostrSync.backup(relays: _relays);
      if (!mounted) return;
      setState(() {
        _lastBackup = report;
        _stage = '';
        _busy = false;
      });
      if (report.ok) {
        await VaultStore.setLastSync(
            DateTime.now().millisecondsSinceEpoch, report.eventId ?? '');
      }
      _say(report.ok
          ? '☁️ Backup stored on ${report.okCount}/${report.relays.length} relays · ${_kb(report.bytes)} of emojis'
          : '⚠️ ${report.error ?? 'Backup failed'}');
      for (final r in report.relays) {
        _say('${r.ok ? '✅' : '❌'} ${_short(r.url)} — ${r.message}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
      });
      _say('⚠️ $e');
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _stage = 'Searching the relays…';
    });
    try {
      final fetch = await NostrSync.fetch(relays: _relays);
      if (!mounted) return;
      if (!fetch.found || fetch.emoji == null) {
        setState(() {
          _busy = false;
          _stage = '';
          _lastFetch = fetch;
        });
        _say('🔍 ${fetch.error ?? 'Nothing found'}');
        for (final r in fetch.relays) {
          _say('${r.ok ? '✅' : '❌'} ${_short(r.url)} — ${r.message}');
        }
        return;
      }
      setState(() => _stage = 'Decrypting emojis → tables…');
      final secret = await VaultStore.nostrSecret();
      final doc = EmojiPacket.unpack(fetch.emoji!, EmojiPacket.keyFromSyncSecret(secret));
      if (!mounted) return;
      setState(() {
        _lastFetch = fetch;
        _doc = doc;
        _busy = false;
        _stage = '';
      });
      _say(doc == null
          ? '🔒 Found a packet but it could not be opened (wrong key).'
          : '📥 Decrypted ${VaultTables.listOf(doc).length} tables from ${_short(fetch.sourceRelay ?? '')}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
      });
      _say('⚠️ $e');
    }
  }

  Future<void> _apply() async {
    final doc = _doc;
    if (doc == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Restore this backup?'),
        content: const Text(
            'Child profiles, PIN verifiers and encrypted data will be replaced by the '
            'backup. Progress marks (XP, completed parts, test results) will be merged in.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await VaultStore.applyRoot(VaultTables.rootFromTables(doc));
      final n = await VaultTables.restoreProgress(doc);
      await VaultStore.log('sync', 'Restored $n progress entries from emoji backup');
      _say('✅ Restored ${n} progress entries + all profiles');
    } catch (e) {
      _say('⚠️ $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copyEmoji() async {
    try {
      final doc = await VaultTables.build();
      final secret = await VaultStore.nostrSecret();
      final emoji = EmojiPacket.pack(doc, EmojiPacket.keyFromSyncSecret(secret));
      await Clipboard.setData(ClipboardData(text: emoji));
      if (mounted) setState(() => _doc = doc);
      _say('📋 Emoji code copied (${emoji.runes.length} emojis) — paste it on any phone');
    } catch (e) {
      _say('⚠️ $e');
    }
  }

  Future<void> _pasteEmoji() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _say('⚠️ Clipboard is empty');
      return;
    }
    try {
      final secret = await VaultStore.nostrSecret();
      final doc = EmojiPacket.unpack(text, EmojiPacket.keyFromSyncSecret(secret));
      if (doc == null) {
        _say('❌ That emoji code is not a vault packet for this device key');
        return;
      }
      setState(() => _doc = doc);
      _say('✅ Decoded ${VaultTables.listOf(doc).length} tables from the emoji code');
    } catch (e) {
      _say('⚠️ $e');
    }
  }

  Future<void> _editRelays() async {
    final ctrl = TextEditingController(text: _relays.join('\n'));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Relays'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('One wss:// relay per line. Free public relays need no account.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 8,
                minLines: 3,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(hintText: 'wss://relay.damus.io'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.text = NostrSync.defaultRelays.join('\n');
            },
            child: const Text('Reset'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (res == null) return;
    final parsed = res
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.startsWith('wss://') || e.startsWith('ws://'))
        .toSet()
        .toList();
    if (parsed.isEmpty) {
      _say('⚠️ No valid relay (must start with wss://)');
      return;
    }
    await VaultStore.setRelays(parsed);
    setState(() => _relays = parsed);
    _say('🔗 ${parsed.length} relays saved');
  }

  static String _kb(int bytes) =>
      bytes > 1024 ? '${(bytes / 1024).toStringAsFixed(1)} KB' : '$bytes B';

  static String _short(String url) =>
      url.replaceFirst('wss://', '').replaceFirst('ws://', '');

  String _time(int ms) {
    if (ms == 0) return 'never';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tables = _doc == null ? <VaultTable>[] : VaultTables.listOf(_doc!);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Emoji cloud vault',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          IconButton(
            onPressed: _editRelays,
            icon: Icon(Icons.hub_rounded, size: 19, color: AppColors.muted),
          ),
        ],
      ),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          children: [
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('🗄️', style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'JSON → tables → encrypted → emojis → free Nostr relay',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, height: 1.35),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 9),
                  Text(
                    'The vault is turned into real tables, gzipped, sealed with a key derived from this '
                    'device secret (PBKDF2 + HMAC), written as emojis and published to public relays — '
                    'no signup, no payment. Restoring reverses the whole chain: emojis → base64 → decrypt '
                    '→ gunzip → tables → vault JSON + progress.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.55),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.schedule_rounded, size: 13, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text('Last backup: ${_time(VaultStore.lastSync)}',
                        style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    const Spacer(),
                    if (VaultStore.lastEventId.isNotEmpty)
                      Text('id ${VaultStore.lastEventId.substring(0, 8)}…',
                          style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _bigButton('Backup now', Icons.cloud_upload_rounded, AppColors.indigo, _backup),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigButton('Restore', Icons.cloud_download_rounded, AppColors.teal, _restore),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _smallButton('Copy emoji', Icons.copy_rounded, _copyEmoji),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _smallButton('Paste emoji', Icons.paste_rounded, _pasteEmoji),
              ),
            ]),
            if (_busy) ...[
              const SizedBox(height: 14),
              Row(children: [
                const SizedBox(
                    width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(_stage, style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
              ]),
            ],
            if (_doc != null) ...[
              const SectionTitle('Decrypted tables'),
              Row(children: [
                Expanded(
                  child: Text(
                    '${tables.length} tables · ${tables.fold<int>(0, (a, t) => a + t.rowCount)} rows',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: _apply,
                  child: const Text('Restore this data', style: TextStyle(fontSize: 12)),
                ),
              ]),
              ...tables.map((t) => _tableCard(t)),
            ] else
              GlassCard(
                child: Text(
                  'Take a backup or restore one to see the tables here — every emoji you see on the relay '
                  'becomes a row and column again.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
                ),
              ),
            const SectionTitle('Relays'),
            ..._relays.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.bolt_rounded, size: 15, color: AppColors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_short(r),
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ),
                      Text(_statusFor(r),
                          style: TextStyle(
                              fontSize: 10.5,
                              color: _statusFor(r) == '—'
                                  ? AppColors.muted
                                  : (_statusFor(r).startsWith('ok')
                                      ? AppColors.teal
                                      : AppColors.red))),
                    ]),
                  ),
                )),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Row(children: [
                Expanded(
                  child: Text('Auto-backup after every finished class/test',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value: VaultStore.autoBackup,
                  activeColor: AppColors.teal,
                  onChanged: (v) async {
                    await VaultStore.setAutoBackup(v);
                    setState(() {});
                    _say(v ? '🔁 Auto-backup ON' : '⏸️ Auto-backup OFF');
                  },
                ),
              ]),
            ),
            if (_log.isNotEmpty) const SectionTitle('Activity'),
            ..._log.take(14).map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(l,
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 10.8, height: 1.4)),
                )),
            const SizedBox(height: 8),
            GlassCard(
              padding: const EdgeInsets.all(13),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Free relays can prune old events, and anyone can read the emojis — but they are '
                    'encrypted, so only this device key can open them. Treat the emoji code like a '
                    'password: it carries that key. The phone copy is always your primary backup.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.8, height: 1.5),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _statusFor(String url) {
    for (final r in _lastBackup?.relays ?? const <RelayResult>[]) {
      if (r.url == url) return r.ok ? 'ok' : 'fail';
    }
    for (final r in _lastFetch?.relays ?? const <RelayResult>[]) {
      if (r.url == url) return r.ok ? 'ok' : 'fail';
    }
    return '—';
  }

  Widget _bigButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return GlassCard(
      onTap: _busy ? null : onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 7),
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
      ]),
    );
  }

  Widget _smallButton(String label, IconData icon, VoidCallback onTap) {
    return GlassCard(
      onTap: _busy ? null : onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 15, color: AppColors.muted),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
      ]),
    );
  }

  Widget _tableCard(VaultTable t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(t.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 12.5, color: AppColors.teal)),
              const Spacer(),
              Text('${t.rowCount} rows × ${t.columns.length} cols',
                  style: TextStyle(color: AppColors.muted, fontSize: 10)),
            ]),
            const SizedBox(height: 8),
            if (t.rows.isEmpty)
              Text('(empty)',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            if (t.rows.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: t.columns
                          .map((c) => Container(
                                width: 116,
                                padding: const EdgeInsets.only(right: 8, bottom: 4),
                                child: Text(c,
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.amber)),
                              ))
                          .toList(),
                    ),
                    Container(height: 1, color: AppColors.stroke),
                    ...t.rows.take(12).map((row) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: List.generate(t.columns.length, (i) {
                            final v = i < row.length ? '${row[i]}' : '';
                            final shown = v.length > 26 ? '${v.substring(0, 26)}…' : v;
                            return Container(
                              width: 116,
                              padding: const EdgeInsets.only(right: 8, top: 5),
                              child: Text(shown,
                                  style: TextStyle(
                                      fontSize: 10, height: 1.3, color: AppColors.text)),
                            );
                          }),
                        )),
                    if (t.rows.length > 12)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('+${t.rows.length - 12} more rows',
                            style: TextStyle(color: AppColors.muted, fontSize: 10)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
