import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../ui/premium_ui.dart';
import '../vault/emoji_vault.dart';
import '../widgets.dart';

/// Export / import the whole vault as one emoji code + file backup.
class VaultTransferScreen extends StatefulWidget {
  final VoidCallback onImported;
  const VaultTransferScreen({super.key, required this.onImported});

  @override
  State<VaultTransferScreen> createState() => _VaultTransferScreenState();
}

class _VaultTransferScreenState extends State<VaultTransferScreen> {
  String _code = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _code = VaultStore.exportEmoji();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emoji code copied — keep it private!')));
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Import emoji code'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Paste the full emoji code from your other phone. It replaces the current vault.',
              style: TextStyle(
                  color: AppColors.muted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          TextField(
              controller: ctrl,
              minLines: 4,
              maxLines: 8,
              style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final n = await VaultStore.importEmoji(raw);
      await VaultStore.openLocal(); // the restored data becomes this learner
      if (!mounted) return;
      setState(() {
        _busy = false;
        _code = VaultStore.exportEmoji();
      });
      widget.onImported();
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restored $n progress bundle${n == 1 ? '' : 's'}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Emoji vault code',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.enhanced_encryption_rounded,
                          color: AppColors.amber, size: 20),
                      const SizedBox(width: 8),
                      Text('Your encrypted backup',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      'This emoji code is your whole progress, encrypted on this device. '
                      'Save it somewhere safe — without it, deleting the app deletes the accounts.',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text(
                          '${_code.runes.length} emoji • ${(_code.runes.length * 4 / 1024).toStringAsFixed(1)} KB',
                          style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ]),
                  ]),
            ),
            const SizedBox(height: 12),
            Container(
              height: 190,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.stroke),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _code,
                  style: const TextStyle(
                      fontSize: 15, height: 1.7, letterSpacing: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy code'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.indigo,
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Import'),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Why emojis?',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(height: 5),
                    Text(
                      'The vault is encrypted bytes; emojis are simply a friendly alphabet for those bytes. '
                      'Anyone who receives the code can open it — keep it private, like a password.',
                      style: TextStyle(
                          color: AppColors.muted, fontSize: 11.5, height: 1.5),
                    ),
                  ]),
            ),
          ],
        ),
      ),
    );
  }
}
