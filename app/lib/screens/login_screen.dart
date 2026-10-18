import 'package:flutter/material.dart';

import '../auth_models.dart';
import '../auth_store.dart';
import '../widgets.dart';

/// One entry point for the whole institution. On the very first launch
/// (no accounts exist) this becomes the Founder setup: the creator makes
/// the Admin account that will create schools and principals.
class LoginScreen extends StatefulWidget {
  final Future<void> Function(AppUser user) onSignedIn;
  const LoginScreen({super.key, required this.onSignedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _founderSetup = false;
  bool _ready = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final has = await AuthStore.hasAdmin();
    if (!mounted) return;
    setState(() {
      _founderSetup = !has;
      _ready = true;
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      AppUser user;
      if (_founderSetup) {
        if (_name.text.trim().isEmpty) throw StateError('Please enter your name.');
        if (_password.text != _confirm.text) throw StateError('Passwords do not match.');
        user = await AuthStore.addUser(
          role: UserRole.admin,
          name: _name.text,
          username: _username.text,
          password: _password.text,
        );
      } else {
        final u = await AuthStore.authenticate(_username.text, _password.text);
        if (u == null) throw StateError('Invalid username or password, or this account is deactivated.');
        user = u;
      }
      await AuthStore.signIn(user.id);
      if (!mounted) return;
      await widget.onSignedIn(user);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.bg, AppColors.bg2, AppColors.bg]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(28)),
                  child: const Icon(Icons.school_rounded, size: 54, color: Colors.white),
                ),
                const SizedBox(height: 18),
                const Text('AI Textbook Classroom', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: AppColors.text)),
                const SizedBox(height: 5),
                Text(_founderSetup ? 'Founder setup — create the Admin account' : 'Institution login',
                    style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 22),
                if (!_ready)
                  const CircularProgressIndicator()
                else
                  GradientCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_founderSetup) ...[
                        TextField(controller: _name, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Founder name', prefixIcon: Icon(Icons.person_rounded, color: AppColors.muted))),
                        const SizedBox(height: 12),
                      ],
                      TextField(controller: _username, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email_rounded, color: AppColors.muted))),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        style: const TextStyle(color: AppColors.text),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_rounded, color: AppColors.muted),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AppColors.muted),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      if (_founderSetup) ...[
                        const SizedBox(height: 12),
                        TextField(controller: _confirm, obscureText: _obscure, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_clock_rounded, color: AppColors.muted))),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Icon(_founderSetup ? Icons.admin_panel_settings_rounded : Icons.login_rounded, size: 19),
                        label: Text(_founderSetup ? 'Create Admin & continue' : 'Login'),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      ),
                    ]),
                  ),
                const SizedBox(height: 18),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: const [
                  _RoleChip(icon: Icons.admin_panel_settings_rounded, label: 'Admin (Founder)'),
                  _RoleChip(icon: Icons.account_balance_rounded, label: 'Principal'),
                  _RoleChip(icon: Icons.co_present_rounded, label: 'Teacher'),
                  _RoleChip(icon: Icons.face_rounded, label: 'Student • read-only'),
                ]),
                const SizedBox(height: 14),
                const Text('Admin creates schools & principals. Principals control their school staff. Students only read, watch and take tests.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _RoleChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.stroke)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.teal),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.text, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}
