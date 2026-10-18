import 'package:flutter/material.dart';

import '../auth_models.dart';
import '../auth_store.dart';
import '../engine_gateway.dart';
import '../exam_store.dart';
import '../store.dart';
import '../widgets.dart';
import 'home_screen.dart';

/// Principal console for ONE school: the whole staff (teachers) and the
/// students are controlled here, plus the school's test performance.
class PrincipalHomeScreen extends StatefulWidget {
  final AppUser principal;
  final EngineGateway gateway;
  final AppSettings settings;
  final VoidCallback onSignOut;
  const PrincipalHomeScreen({super.key, required this.principal, required this.gateway, required this.settings, required this.onSignOut});

  @override
  State<PrincipalHomeScreen> createState() => _PrincipalHomeScreenState();
}

class _PrincipalHomeScreenState extends State<PrincipalHomeScreen> {
  School? _school;
  List<AppUser> _staff = [];
  Map<String, ({int tests, double avg})> _scores = {};
  bool _loading = true;

  String get _schoolId => widget.principal.schoolId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final schools = await AuthStore.schools();
    final users = await AuthStore.users();
    final staff = users.where((u) => u.schoolId == _schoolId && u.role != UserRole.principal).toList();
    final scores = <String, ({int tests, double avg})>{};
    for (final u in staff.where((u) => u.role == UserRole.student)) {
      final rs = await ExamStore.loadAllFor(u.id);
      if (rs.isNotEmpty) {
        scores[u.id] = (tests: rs.length, avg: rs.map((r) => r.percentage).reduce((a, b) => a + b) / rs.length);
      }
    }
    if (!mounted) return;
    setState(() {
      _school = schools.where((s) => s.id == _schoolId).firstOrNull;
      _staff = staff;
      _scores = scores;
      _loading = false;
    });
  }

  List<AppUser> get _teachers => _staff.where((u) => u.role == UserRole.teacher).toList();
  List<AppUser> get _students => _staff.where((u) => u.role == UserRole.student).toList();

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _addUser(UserRole role) async {
    final name = TextEditingController();
    final username = TextEditingController();
    final password = TextEditingController();
    final className = TextEditingController();
    final isStudent = role == UserRole.student;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(isStudent ? 'Add student' : 'Add teacher', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 10),
            TextField(controller: username, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Login username')),
            const SizedBox(height: 10),
            TextField(controller: password, obscureText: true, style: const TextStyle(color: AppColors.text), decoration: const InputDecoration(labelText: 'Password (min 4)')),
            const SizedBox(height: 10),
            TextField(
              controller: className,
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(labelText: isStudent ? 'Class (e.g. Class 10-A)' : 'Classes handled (comma separated)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthStore.addUser(
        role: role,
        name: name.text,
        username: username.text,
        password: password.text,
        schoolId: _schoolId,
        className: className.text,
      );
      _snack('${isStudent ? 'Student' : 'Teacher'} added');
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

  Widget _userTile(AppUser u) {
    final score = _scores[u.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GradientCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: u.role == UserRole.teacher ? AppColors.indigo : AppColors.teal,
            child: Text(u.name.isEmpty ? '?' : u.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14, decoration: u.active ? null : TextDecoration.lineThrough)),
              Text('@${u.username}${u.className.isNotEmpty ? ' • ${u.className}' : ''}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (u.role == UserRole.student)
                Text(score == null ? 'No tests yet' : '${score.tests} test(s) • avg ${score.avg.toStringAsFixed(0)}%',
                    style: TextStyle(color: score == null ? AppColors.muted : AppColors.teal, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
          IconButton(tooltip: 'Reset password', onPressed: () => _resetPassword(u), icon: const Icon(Icons.key_rounded, size: 19, color: AppColors.muted)),
          Switch(
            value: u.active,
            onChanged: (v) async {
              await AuthStore.setUserActive(u.id, v);
              _load();
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final testedAvg = _scores.isEmpty ? null : _scores.values.map((s) => s.avg).reduce((a, b) => a + b) / _scores.length;
    final totalTests = _scores.values.fold<int>(0, (a, s) => a + s.tests);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 40), children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_school?.name ?? 'My school', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.text)),
                  Text('Principal: ${widget.principal.name}', style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ]),
              ),
              IconButton(tooltip: 'Sign out', onPressed: widget.onSignOut, icon: const Icon(Icons.logout_rounded, color: AppColors.muted)),
            ]),
            const SizedBox(height: 18),
            GradientCard(
              gradient: AppColors.heroGradient,
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _Stat('${_teachers.length}', 'Teachers'),
                _Stat('${_students.length}', 'Students'),
                _Stat('$totalTests', 'Tests taken'),
                _Stat(testedAvg == null ? '—' : '${testedAvg.toStringAsFixed(0)}%', 'School avg'),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(onPressed: () => _addUser(UserRole.teacher), icon: const Icon(Icons.co_present_rounded, size: 18), label: const Text('Add teacher')),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _addUser(UserRole.student),
                  icon: const Icon(Icons.face_rounded, size: 18),
                  label: const Text('Add student'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.teal, foregroundColor: const Color(0xFF06231F)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => HomeScreen(gateway: widget.gateway, settings: widget.settings, user: widget.principal),
              )),
              icon: const Icon(Icons.movie_creation_rounded, size: 18),
              label: const Text('Open teaching tools (upload, publish, tests)'),
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
            else ...[
              const SectionTitle('Teachers (staff)'),
              if (_teachers.isEmpty)
                const Text('No teachers yet. Add your staff — they can upload textbooks, generate classes and publish tests.',
                    style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13)),
              ..._teachers.map(_userTile),
              const SectionTitle('Students (read-only)'),
              if (_students.isEmpty)
                const Text('No students yet. Students can only read published classes, watch, ask doubts and take tests — they cannot upload anything.',
                    style: TextStyle(color: AppColors.muted, height: 1.5, fontSize: 13)),
              ..._students.map(_userTile),
            ],
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
