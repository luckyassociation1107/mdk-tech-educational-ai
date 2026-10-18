import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_models.dart';

/// The institution database: schools, user accounts, published library and
/// the current login session — all stored on this device. Access rules
/// follow the hierarchy: Admin > Principal (one per school) > Teachers >
/// Students (read-only). Swap this store for a cloud backend later and
/// the screens stay the same.
class AuthStore {
  static const _schoolsKey = 'inst_schools_v1';
  static const _usersKey = 'inst_users_v1';
  static const _publishedKey = 'inst_published_v1';
  static const _sessionKey = 'inst_session_user_id';

  static String _id(String prefix) =>
      '$prefix${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(9999)}';
  static String _salt() => Random.secure().nextInt(1 << 32).toRadixString(16);

  // ---------- schools ----------
  static Future<List<School>> schools() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_schoolsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>().map((e) => School.fromJson(e.map((k, v) => MapEntry(k.toString(), v)))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<School> addSchool(String name, String city) async {
    final all = await schools();
    final s = School(id: _id('sch'), name: name.trim(), city: city.trim());
    all.add(s);
    final p = await SharedPreferences.getInstance();
    await p.setString(_schoolsKey, jsonEncode(all.map((e) => e.toJson()).toList()));
    return s;
  }

  static Future<void> setSchoolActive(String id, bool active) async {
    final all = await schools();
    for (final s in all) {
      if (s.id == id) s.active = active;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_schoolsKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  // ---------- users ----------
  static Future<List<AppUser>> users() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_usersKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>().map((e) => AppUser.fromJson(e.map((k, v) => MapEntry(k.toString(), v)))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveUsers(List<AppUser> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_usersKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<bool> hasAdmin() async => (await users()).any((u) => u.role == UserRole.admin);

  /// Creates an account. Throws a readable error on duplicate username.
  /// One active principal per school: adding a new one deactivates the old.
  static Future<AppUser> addUser({
    required UserRole role,
    required String name,
    required String username,
    required String password,
    String schoolId = '',
    String className = '',
  }) async {
    final un = username.trim().toLowerCase();
    if (un.isEmpty || password.length < 4) {
      throw StateError('Username is required and password must be at least 4 characters.');
    }
    final all = await users();
    if (all.any((u) => u.username == un)) {
      throw StateError('Username "$un" is already taken.');
    }
    if (role == UserRole.principal) {
      for (final u in all) {
        if (u.role == UserRole.principal && u.schoolId == schoolId) u.active = false;
      }
    }
    final salt = _salt();
    final user = AppUser(
      id: _id('usr'),
      role: role,
      name: name.trim(),
      username: un,
      passwordHash: AppUser.hashPassword(password, salt),
      salt: salt,
      schoolId: schoolId,
      className: className.trim(),
    );
    all.add(user);
    await _saveUsers(all);
    return user;
  }

  static Future<void> setUserActive(String id, bool active) async {
    final all = await users();
    for (final u in all) {
      if (u.id == id) u.active = active;
    }
    await _saveUsers(all);
  }

  static Future<void> resetPassword(String id, String newPassword) async {
    final all = await users();
    for (final u in all) {
      if (u.id == id) {
        // salt is kept; hash is replaced with the new password's hash
        final updated = AppUser(
          id: u.id,
          role: u.role,
          name: u.name,
          username: u.username,
          passwordHash: AppUser.hashPassword(newPassword, u.salt),
          salt: u.salt,
          schoolId: u.schoolId,
          className: u.className,
          active: u.active,
        );
        all[all.indexOf(u)] = updated;
      }
    }
    await _saveUsers(all);
  }

  static Future<AppUser?> authenticate(String username, String password) async {
    final un = username.trim().toLowerCase();
    final all = await users();
    for (final u in all) {
      if (u.username == un && u.active && u.checkPassword(password)) return u;
    }
    return null;
  }

  // ---------- session ----------
  static Future<void> signIn(String userId) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_sessionKey, userId);
  }

  static Future<void> signOut() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_sessionKey);
  }

  static Future<AppUser?> currentUser() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_sessionKey);
    if (id == null) return null;
    final all = await users();
    for (final u in all) {
      if (u.id == id && u.active) return u;
    }
    return null;
  }

  // ---------- published library ----------
  static Future<List<PublishedBook>> published() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_publishedKey);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).whereType<Map>().map((e) => PublishedBook.fromJson(e.map((k, v) => MapEntry(k.toString(), v)))).toList();
      list.sort((a, b) => b.when.compareTo(a.when));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _savePublished(List<PublishedBook> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_publishedKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> publish({
    required String sessionId,
    required String title,
    required String schoolId,
    required String className,
    required String publishedBy,
  }) async {
    final all = await published();
    all.removeWhere((b) => b.sessionId == sessionId && b.schoolId == schoolId && b.className == className);
    all.add(PublishedBook(
      sessionId: sessionId,
      title: title,
      schoolId: schoolId,
      className: className.trim(),
      publishedBy: publishedBy,
      when: DateTime.now(),
    ));
    await _savePublished(all);
  }

  static Future<void> unpublish(String sessionId, String schoolId, String className) async {
    final all = await published();
    all.removeWhere((b) => b.sessionId == sessionId && b.schoolId == schoolId && b.className == className);
    await _savePublished(all);
  }

  /// What a student may read: own school, whole-school or matching class.
  static Future<List<PublishedBook>> visibleTo(AppUser student) async {
    final all = await published();
    return all.where((b) => b.schoolId == student.schoolId && (b.className.isEmpty || b.className == student.className)).toList();
  }

  // ---------- shared PDFs (Gofile shelf) ----------
  static const _sharedKey = 'inst_shared_pdfs_v1';

  static Future<List<SharedPdf>> sharedPdfs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_sharedKey);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).whereType<Map>().map((e) => SharedPdf.fromJson(e.map((k, v) => MapEntry(k.toString(), v)))).toList();
      list.sort((a, b) => b.uploadedAtMillis.compareTo(a.uploadedAtMillis));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveShared(List<SharedPdf> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_sharedKey, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> addSharedPdf(SharedPdf pdf) async {
    final all = await sharedPdfs();
    all.add(pdf);
    await _saveShared(all);
  }

  static Future<void> updateSharedPdf(SharedPdf pdf) async {
    final all = await sharedPdfs();
    final i = all.indexWhere((e) => e.id == pdf.id);
    if (i >= 0) all[i] = pdf;
    await _saveShared(all);
  }

  static Future<void> removeSharedPdf(String id) async {
    final all = await sharedPdfs();
    all.removeWhere((e) => e.id == id);
    await _saveShared(all);
  }

  static Future<List<SharedPdf>> visibleSharedPdfs(AppUser student) async {
    final all = await sharedPdfs();
    return all.where((b) => b.schoolId == student.schoolId && (b.className.isEmpty || b.className == student.className)).toList();
  }
}
