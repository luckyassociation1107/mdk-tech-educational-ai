import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../exam_store.dart';
import '../study_stats.dart';
import '../theme/themes.dart';
import '../store.dart';
import '../ui/premium_ui.dart';
import '../vault/emoji_vault.dart';
import '../widgets.dart';

/// The child gate: pick a profile, sign in with a PIN, or create a new
/// child profile. Everything lives in the encrypted emoji vault on this
/// phone. A "continue without profile" path keeps the app usable.
class ChildGateScreen extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback onLoggedIn;
  final bool canSkip;
  const ChildGateScreen({
    super.key,
    required this.settings,
    required this.onLoggedIn,
    this.canSkip = true,
  });

  @override
  State<ChildGateScreen> createState() => _ChildGateScreenState();
}

class _ChildGateScreenState extends State<ChildGateScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await VaultStore.load();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _openSignup() async {
    final created = await Navigator.of(context).push<bool>(PageTransition.route(
      SignupScreen(onDone: () => Navigator.of(context).pop(true)),
    ));
    if (created == true) {
      setState(() {});
      _finishLogin();
    }
  }

  Future<void> _pickProfile(ChildProfile p) async {
    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PinPad(title: 'Hi ${p.name}!', avatar: p.avatar, subtitle: 'Enter your PIN', confirm: false),
    );
    if (pin == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final profile = await VaultStore.login(p.id, pin);
    if (!mounted) return;
    if (profile == null) {
      setState(() {
        _busy = false;
        _error = 'That PIN is not correct. Try again.';
      });
      return;
    }
    _finishLogin();
  }

  Future<void> _finishLogin() async {
    final p = VaultStore.current;
    if (p != null) {
      ExamStore.scopeUserId = p.id;
      ProgressStore.scope = 'child_${p.id}';
      StudyStats.scope = 'child_${p.id}';
    }
    widget.onLoggedIn();
  }

  Future<void> _skip() async {
    ExamStore.scopeUserId = 'learner';
    ProgressStore.scope = '';
    StudyStats.scope = '';
    widget.onLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = VaultStore.profiles;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AuroraBackground(
        dense: true,
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 26, 20, 30),
                  children: [
                    Row(children: [
                      const GlowIcon(Icons.auto_stories_rounded, color: Color(0xFF6366F1), size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          GradientText('Who is learning?', size: 21),
                          Text('Each child gets a private PIN-locked space',
                              style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    if (profiles.isEmpty)
                      _emptyState()
                    else ...[
                      const Text('Choose your profile',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final p in profiles)
                            RiseIn(
                              key: ValueKey(p.id),
                              child: _profileTile(p),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.red.withOpacity(0.45)),
                          ),
                          child: Row(children: [
                            Icon(Icons.error_outline_rounded, color: AppColors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 12.5))),
                          ]),
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: _busy ? null : _openSignup,
                      icon: Icon(Icons.person_add_alt_1_rounded, size: 19),
                      label: const Text('Create a new profile'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.indigo,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () async {
                        await Navigator.of(context).push(PageTransition.route(VaultTransferScreen(onImported: () {})));
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.qr_code_2_rounded, size: 19),
                      label: const Text('Restore from emoji code'),
                    ),
                    if (widget.canSkip) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _skip,
                        child: Text('Continue without a profile',
                            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _vaultInfo(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return GlassCard(
      child: Column(children: [
        Icon(Icons.child_care_rounded, color: AppColors.teal, size: 44),
        const SizedBox(height: 10),
        Text('First time here?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        const SizedBox(height: 6),
        Text(
          'Create a profile with a name, a favourite emoji and a 4–6 digit PIN. '
          'Marks, XP, streaks and activity logs are encrypted and stored on this phone only.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.5),
        ),
        const SizedBox(height: 14),
      ]),
    );
  }

  Widget _profileTile(ChildProfile p) {
    return GestureDetector(
      onTap: _busy ? null : () => _pickProfile(p),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        tint: AppColors.teal,
        alpha: 0.10,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(p.avatar, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            Text(
              p.lastLogin == 0 ? 'new profile' : 'last visit ${_ago(p.lastLogin)}',
              style: TextStyle(color: AppColors.muted, fontSize: 10.5),
            ),
          ]),
          const SizedBox(width: 10),
          Icon(Icons.lock_rounded, color: AppColors.muted, size: 16),
        ]),
      ),
    );
  }

  String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  Widget _vaultInfo() {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.enhanced_encryption_rounded, color: AppColors.amber, size: 18),
          const SizedBox(width: 8),
          Text('Emoji vault', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const Spacer(),
          Text('${VaultStore.profiles.length} profile${VaultStore.profiles.length == 1 ? '' : 's'}',
              style: TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
        const SizedBox(height: 6),
        Text(
          'Profiles, marks and logs are sealed with a key derived from each PIN (PBKDF2, never stored). '
          'The vault itself is written as an emoji code you can export to a file and restore on another phone.',
          style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
        ),
      ]),
    );
  }
}

/// Sign up: name, avatar emoji, PIN twice.
class SignupScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SignupScreen({super.key, required this.onDone});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameCtrl = TextEditingController();
  String _avatar = '🐼';
  String? _pin;
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _setPin() async {
    final pin = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PinPad(
        title: 'Choose your PIN',
        avatar: _avatar,
        subtitle: '4–6 digits — you will use this to open your space',
        confirm: true,
        firstPin: null,
      ),
    );
    if (pin != null) setState(() => _pin = pin);
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please type your name.');
      return;
    }
    if (_pin == null) {
      setState(() => _error = 'Please choose a PIN.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final p = await VaultStore.createProfile(name: _nameCtrl.text, avatar: _avatar, pin: _pin!);
      await VaultStore.login(p.id, _pin!);
      await VaultStore.log('signup', 'Profile created with avatar $_avatar');
      if (!mounted) return;
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(backgroundColor: AppColors.bg, title: const Text('New profile', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          children: [
            Center(
              child: Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.heroGradient,
                  boxShadow: [BoxShadow(color: AppColors.indigo.withOpacity(0.5), blurRadius: 26, offset: const Offset(0, 10))],
                ),
                child: Text(_avatar, style: const TextStyle(fontSize: 44)),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              maxLength: 20,
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Your name', hintText: 'e.g. Aarav'),
            ),
            const SizedBox(height: 6),
            Text('Pick your emoji', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _avatarChoices)
                  GestureDetector(
                    onTap: () => setState(() => _avatar = e),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _avatar == e ? AppColors.teal.withOpacity(0.22) : AppColors.card,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: _avatar == e ? AppColors.teal : AppColors.stroke, width: _avatar == e ? 2 : 1),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            GradientCard(
              onTap: _busy ? null : _setPin,
              child: Row(children: [
                Icon(_pin == null ? Icons.pin_rounded : Icons.lock_rounded, color: _pin == null ? AppColors.muted : AppColors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_pin == null ? 'Choose a PIN' : 'PIN set (${_pin!.length} digits)',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                    Text('Used to open your private encrypted space',
                        style: TextStyle(color: AppColors.muted, fontSize: 11.5)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ]),
            ),
            if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error, style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, size: 19),
              label: const Text('Create my profile'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 15)),
            ),
            const SizedBox(height: 10),
            Text(
              'Your PIN is never stored. Only a slow hash is kept, and your data can only be opened with the PIN.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  static const _avatarChoices = [
    '🐼', '🦊', '🐯', '🐨', '🦁', '🐸', '🐧', '🦉', '🐙', '🦄', '🚀', '⭐', '🌈', '🎨', '⚽', '📚'
  ];
}

/// Numeric PIN pad with big buttons, used for sign-in and sign-up.
class PinPad extends StatefulWidget {
  final String title;
  final String avatar;
  final String subtitle;
  final bool confirm;
  final String? firstPin;
  const PinPad({
    super.key,
    required this.title,
    required this.avatar,
    required this.subtitle,
    required this.confirm,
    this.firstPin,
  });

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';
  String? _first;
  bool _show = false;
  String _hint = '';

  void _tap(String d) {
    if (_pin.length >= 6) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += d;
      _hint = '';
    });
    if (_pin.length >= 4) {
      // auto-submit only on the max length or when the user taps Done
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (_pin.length < 4) {
      setState(() => _hint = 'PIN needs at least 4 digits');
      return;
    }
    if (widget.confirm) {
      if (_first == null) {
        setState(() {
          _first = _pin;
          _pin = '';
          _hint = 'Type the same PIN again';
        });
        return;
      }
      if (_first != _pin) {
        setState(() {
          _first = null;
          _pin = '';
          _hint = 'PINs did not match — start again';
        });
        return;
      }
    }
    Navigator.of(context).pop(_pin);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.palette;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.stroke)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 42, height: 4, decoration: BoxDecoration(color: colors.muted.withOpacity(0.4), borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 16),
            Text(widget.avatar, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 6),
            Text(widget.title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 3),
            Text(_hint.isEmpty ? widget.subtitle : _hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _hint.isEmpty ? AppColors.muted : AppColors.amber,
                    fontSize: 12,
                    fontWeight: _hint.isEmpty ? FontWeight.w500 : FontWeight.w800)),
            const SizedBox(height: 16),
            GestureDetector(
              onLongPress: () => setState(() => _show = !_show),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 6; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? AppColors.teal : Colors.transparent,
                      border: Border.all(color: i < _pin.length ? AppColors.teal : AppColors.stroke, width: 1.6),
                    ),
                    child: i < _pin.length && _show
                        ? Center(child: Text(_pin[i], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.bg)))
                        : null,
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (final d in row) _digit(d, colors),
                ]),
              ),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _padButton(icon: Icons.fingerprint_rounded, disabled: true, onTap: () {}),
              _digit('0', colors),
              _padButton(icon: Icons.backspace_rounded, onTap: _back),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_pin.length >= 4 ? 'Done' : 'Enter PIN'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _digit(String d, AppPalette colors) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _tap(d),
      child: Container(
        width: 74,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.stroke),
        ),
        child: Text(d, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: AppColors.text)),
      ),
    );
  }

  Widget _padButton({IconData? icon, bool disabled = false, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: disabled ? null : onTap,
      child: Container(
        width: 74,
        height: 58,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: disabled ? Colors.transparent : AppColors.cardLight,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: disabled ? Colors.transparent : AppColors.stroke),
        ),
        child: Icon(icon, color: disabled ? Colors.transparent : AppColors.muted, size: 22),
      ),
    );
  }
}

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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Emoji code copied — keep it private!')));
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Import emoji code'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Paste the full emoji code from your other phone. It replaces the current vault.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 10),
          TextField(controller: ctrl, minLines: 4, maxLines: 8, style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
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
      if (!mounted) return;
      setState(() {
        _busy = false;
        _code = VaultStore.exportEmoji();
      });
      widget.onImported();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored $n profile${n == 1 ? '' : 's'}')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Emoji vault code', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.enhanced_encryption_rounded, color: AppColors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text('Your encrypted backup', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ]),
                const SizedBox(height: 6),
                Text(
                  'This emoji code holds every profile in the vault, already encrypted with each child\'s PIN. '
                  'Save it somewhere safe — without it, deleting the app deletes the accounts.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Text('${_code.runes.length} emoji • ${(_code.runes.length * 4 / 1024).toStringAsFixed(1)} KB',
                      style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
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
                  style: const TextStyle(fontSize: 15, height: 1.7, letterSpacing: 0.5),
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
                  style: FilledButton.styleFrom(backgroundColor: AppColors.indigo, padding: const EdgeInsets.symmetric(vertical: 13)),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Why emojis?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                const SizedBox(height: 5),
                Text(
                  'The vault is encrypted bytes; emojis are simply a friendly alphabet for those bytes. '
                  'Anyone who receives the code still needs the child\'s PIN to open anything.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.5),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
