import 'package:flutter/material.dart';

import '../auth_models.dart';
import '../auth_store.dart';
import '../widgets.dart';

/// Founder/Admin console: create schools, appoint one Principal per
/// school, deactivate accounts. Principals then run their own schools.
class AdminHomeScreen extends StatefulWidget {
  final AppUser admin;
  final VoidCallback onSignOut;
  const AdminHomeScreen({super.key, required this.admin, required this.onSignOut});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  List<School> _schools = [];
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AuthStore.schools();
    final u = await AuthStore.users();
    if (!mounted) return;
    setState(() {
      _schools = s;
      _users = u;
      _loading = false;
    });
  }

  AppUser? _principalOf(String schoolId) {
    for (final u in _users) {
      if (u.role == UserRole.principal && u.schoolId == schoolId && u.active) return u;
    }
    return null;
  }

  int _count(UserRole r, [String? schoolId]) =>
      _users.where((u) => u.role == r && (schoolId == null || u.schoolId == schoolId)).length;

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _createSchool() async {
    final name = TextEditingController();
    final city = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Create school', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'School name')),
          const SizedBox(height: 10),
          TextField(controller: city, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'City / branch')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await AuthStore.addSchool(name.text, city.text);
      _load();
    }
  }

  Future<void> _setPrincipal(School school) async {
    final name = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Principal for ${school.name}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('One active principal per school. Setting a new one deactivates the previous principal.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45)),
          const SizedBox(height: 12),
          TextField(controller: name, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Principal name')),
          const SizedBox(height: 10),
          TextField(controller: username, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Login username')),
          const SizedBox(height: 10),
          TextField(controller: password, obscureText: true, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Password (min 4)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Appoint')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthStore.addUser(role: UserRole.principal, name: name.text, username: username.text, password: password.text, schoolId: school.id);
      _snack('Principal appointed for ${school.name}');
      _load();
    } catch (e) {
      _snack(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _resetPassword(AppUser u) async {
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Reset password — ${u.name}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
        content: TextField(controller: pw, obscureText: true, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'New password (min 4)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok == true && pw.text.length >= 4) {
      await AuthStore.resetPassword(u.id, pw.text);
      _snack('Password updated for ${u.username}');
    } else if (ok == true) {
      _snack('Password must be at least 4 characters.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSchool,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('New school'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 96), children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.admin.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text)),
                  const Text('Admin • Founder & Creator', style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              IconButton(tooltip: 'Sign out', onPressed: widget.onSignOut, icon: const Icon(Icons.logout_rounded, color: AppColors.muted)),
            ]),
            const SizedBox(height: 18),
            GradientCard(
              gradient: AppColors.heroGradient,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Stat('${_schools.where((s) => s.active).length}', 'Schools'),
                _Stat('${_count(UserRole.principal)}', 'Principals'),
                _Stat('${_count(UserRole.teacher)}', 'Teachers'),
                _Stat('${_count(UserRole.student)}', 'Students'),
              ]),
            ),
            const SectionTitle('Schools & principals'),
            if (_loading)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
            else if (_schools.isEmpty)
              const EmptyState(
                icon: Icons.account_balance_rounded,
                title: 'No schools yet',
                message: 'Tap “New school”, then appoint a Principal. The principal will add teachers and students for that school.',
              )
            else
              ..._schools.map((s) {
                final p = _principalOf(s.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Opacity(
                    opacity: s.active ? 1 : 0.6,
                    child: GradientCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(13)),
                            child: const Icon(Icons.account_balance_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.text, fontSize: 15)),
                              Text([s.city, '${_count(UserRole.teacher, s.id)} teachers • ${_count(UserRole.student, s.id)} students'].where((e) => e.isNotEmpty).join(' • '),
                                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ]),
                          ),
                          Switch(value: s.active, onChanged: (v) async { await AuthStore.setSchoolActive(s.id, v); _load(); }),
                        ]),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.cardLight, borderRadius: BorderRadius.circular(14)),
                          child: Row(children: [
                            const Icon(Icons.person_pin_rounded, color: AppColors.teal),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(p == null ? 'No principal appointed yet' : 'Principal: ${p.name}  (@${p.username})',
                                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
                            ),
                            if (p != null)
                              IconButton(tooltip: 'Reset principal password', onPressed: () => _resetPassword(p), icon: const Icon(Icons.key_rounded, size: 19, color: AppColors.muted)),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _setPrincipal(s),
                            icon: const Icon(Icons.person_add_alt_rounded, size: 18),
                            label: Text(p == null ? 'Appoint principal' : 'Change principal'),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            const Text('You are the founder: schools and principals are created here. Each principal manages their own staff and students inside their school login.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5)),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]);
}
