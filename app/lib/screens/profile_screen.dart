import 'package:flutter/material.dart';

import '../store.dart';
import '../ui/premium_ui.dart';
import '../vault/emoji_vault.dart';
import '../widgets.dart';
import 'vault_transfer_screen.dart';

/// The learner's space: avatar, activity log (encrypted) and the local emoji
/// backup. There is nothing to sign in to, out of, or to sync to a server —
/// one learner lives on this device.
class ProfileScreen extends StatefulWidget {
  final AppSettings settings;
  const ProfileScreen({super.key, required this.settings});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  Future<void> _changeName() async {
    final ctrl = TextEditingController(text: VaultStore.current?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Your name'),
        content: TextField(controller: ctrl, maxLength: 20),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await VaultStore.updateProfile(name: name);
    await VaultStore.log('profile', 'Name changed to $name');
    if (mounted) setState(() {});
  }

  Future<void> _changeAvatar() async {
    const choices = ['🐼', '🦊', '🐯', '🐨', '🦁', '🐸', '🐧', '🦉', '🐙', '🦄', '🚀', '⭐', '🌈', '🎨', '⚽', '📚'];
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Choose an emoji'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in choices)
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(e),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: VaultStore.current?.avatar == e ? AppColors.teal.withOpacity(0.2) : AppColors.cardLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 22)),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        ],
      ),
    );
    if (picked == null) return;
    await VaultStore.updateProfile(avatar: picked);
    await VaultStore.log('profile', 'Avatar changed to $picked');
    if (mounted) setState(() {});
  }

  String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  IconData _icon(String type) => switch (type) {
        'login' => Icons.login_rounded,
        'logout' => Icons.logout_rounded,
        'signup' => Icons.person_add_alt_1_rounded,
        'class' => Icons.play_circle_rounded,
        'test' => Icons.quiz_rounded,
        'pin' => Icons.password_rounded,
        'profile' => Icons.edit_rounded,
        _ => Icons.circle,
      };

  @override
  Widget build(BuildContext context) {
    final p = VaultStore.current;
    final logs = VaultStore.logs;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('My space', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 26),
          children: [
            GlassCard(
              child: Row(children: [
                GestureDetector(
                  onTap: _changeAvatar,
                  child: Container(
                    width: 68,
                    height: 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppColors.heroGradient,
                      boxShadow: [BoxShadow(color: AppColors.indigo.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))],
                    ),
                    child: Text(p?.avatar ?? '🐼', style: const TextStyle(fontSize: 32)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p?.name ?? 'Guest', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                    Text(
                      p == null
                          ? 'One learner on this device'
                          : 'One learner on this device • data stays here',
                      style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                    if (p != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('member since ${_time(p.createdAt).split(' ').first}',
                            style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                      ),
                  ]),
                ),
                if (p != null)
                  IconButton(onPressed: _changeName, icon: Icon(Icons.edit_rounded, size: 18, color: AppColors.muted)),
              ]),
            ),
            const SizedBox(height: 12),
            GlassCard(
              onTap: () => Navigator.of(context).push(PageTransition.route(
                  VaultTransferScreen(onImported: () {}))),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
              child: Row(children: [
                Icon(Icons.qr_code_2_rounded, size: 18, color: AppColors.teal),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Emoji backup',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5)),
                    Text('Copy your progress as an emoji code · restore it later',
                        style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.muted),
              ]),
            ),
            const SizedBox(height: 10),
            const SectionTitle('Activity log'),
            if (logs.isEmpty)
              GlassCard(
                child: Text('No activity yet. Classes, tests and marks appear here — encrypted on this phone.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
              )
            else
              ...logs.take(40).map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(children: [
                        Icon(_icon('${l['type']}'), size: 17, color: AppColors.teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${l['msg']}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            Text(_time((l['at'] as num?)?.toInt() ?? 0),
                                style: TextStyle(color: AppColors.muted, fontSize: 10)),
                          ]),
                        ),
                      ]),
                    ),
                  )),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.all(13),
              child: Row(children: [
                Icon(Icons.lock_rounded, size: 16, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Logs and marks are sealed on this phone with a device key. '
                    'They never leave it unless you export the emoji code.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            if (_busy) const Center(child: CircularProgressIndicator()),
            TextButton(
              onPressed: () => setState(() {}),
              child: Text('refresh', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, Color color) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
        ),
      ]),
    );
  }
}
