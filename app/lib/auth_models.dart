import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Institutional roles. Hierarchy: Admin (founder/creator) creates schools
/// and one Principal per school; the Principal controls the whole staff
/// (teachers) and students of that school; Students are read-only.
enum UserRole { admin, principal, teacher, student }

extension UserRoleX on UserRole {
  String get label => switch (this) {
        UserRole.admin => 'Admin • Founder',
        UserRole.principal => 'Principal',
        UserRole.teacher => 'Teacher',
        UserRole.student => 'Student',
      };
  bool get canUpload => this == UserRole.admin || this == UserRole.principal || this == UserRole.teacher;
  bool get canPublish => this == UserRole.principal || this == UserRole.teacher;
  static UserRole fromName(String s) => UserRole.values.firstWhere((r) => r.name == s, orElse: () => UserRole.student);
}

class School {
  final String id;
  final String name;
  final String city;
  bool active;

  School({required this.id, required this.name, this.city = '', this.active = true});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'city': city, 'active': active};

  factory School.fromJson(Map<String, dynamic> j) => School(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? 'School').toString(),
        city: (j['city'] ?? '').toString(),
        active: j['active'] != false,
      );
}

class AppUser {
  final String id;
  final UserRole role;
  final String name;
  final String username; // unique, lowercase
  final String passwordHash;
  final String salt;
  final String schoolId; // '' for admin
  final String className; // student: "Class 10-A"; teacher: classes they handle, comma separated
  bool active;

  AppUser({
    required this.id,
    required this.role,
    required this.name,
    required this.username,
    required this.passwordHash,
    required this.salt,
    this.schoolId = '',
    this.className = '',
    this.active = true,
  });

  bool checkPassword(String password) => hashPassword(password, salt) == passwordHash;

  static String hashPassword(String password, String salt) =>
      sha256.convert(utf8.encode('$salt::$password')).toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'name': name,
        'username': username,
        'passwordHash': passwordHash,
        'salt': salt,
        'schoolId': schoolId,
        'className': className,
        'active': active,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: (j['id'] ?? '').toString(),
        role: UserRoleX.fromName((j['role'] ?? 'student').toString()),
        name: (j['name'] ?? '').toString(),
        username: (j['username'] ?? '').toString(),
        passwordHash: (j['passwordHash'] ?? '').toString(),
        salt: (j['salt'] ?? '').toString(),
        schoolId: (j['schoolId'] ?? '').toString(),
        className: (j['className'] ?? '').toString(),
        active: j['active'] != false,
      );
}

/// A textbook/lesson series a teacher (or principal) published to a class.
/// Empty className means the whole school can read it.
class PublishedBook {
  final String sessionId;
  final String title;
  final String schoolId;
  final String className;
  final String publishedBy; // teacher/principal name
  final DateTime when;

  const PublishedBook({
    required this.sessionId,
    required this.title,
    required this.schoolId,
    required this.className,
    required this.publishedBy,
    required this.when,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'title': title,
        'schoolId': schoolId,
        'className': className,
        'publishedBy': publishedBy,
        'when': when.toIso8601String(),
      };

  factory PublishedBook.fromJson(Map<String, dynamic> j) => PublishedBook(
        sessionId: (j['sessionId'] ?? '').toString(),
        title: (j['title'] ?? 'Textbook').toString(),
        schoolId: (j['schoolId'] ?? '').toString(),
        className: (j['className'] ?? '').toString(),
        publishedBy: (j['publishedBy'] ?? '').toString(),
        when: DateTime.tryParse((j['when'] ?? '').toString()) ?? DateTime.now(),
      );
}
