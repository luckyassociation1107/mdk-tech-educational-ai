import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

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

  bool checkPassword(String password) => verifyPassword(password, salt, passwordHash);

  static bool isLegacyHash(String stored) => !stored.startsWith('pbkdf2\$');

  /// Current scheme: PBKDF2-HMAC-SHA256, 100k iterations, stored as
  /// `pbkdf2$<iterations>$<hex>`. Slow on purpose — offline cracking of a
  /// stolen data file must be expensive.
  static String hashPassword(String password, String salt) {
    const iterations = 100000;
    return 'pbkdf2\$$iterations\$${_toHex(_pbkdf2(password, salt, iterations))}';
  }

  static bool verifyPassword(String password, String salt, String stored) {
    try {
      if (stored.startsWith('pbkdf2\$')) {
        final parts = stored.split('\$');
        if (parts.length != 3) return false;
        final iterations = int.tryParse(parts[1]) ?? 100000;
        return _toHex(_pbkdf2(password, salt, iterations)) == parts[2];
      }
      // Legacy (<= v0.9): single-round salted SHA-256. Accepted once at
      // login, then the account is migrated to PBKDF2.
      return sha256.convert(utf8.encode('$salt::$password')).toString() == stored;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _pbkdf2(String password, String saltHex, int iterations) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    derivator.init(Pbkdf2Parameters(_fromHex(saltHex), iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _fromHex(String hex) {
    final h = hex.length.isOdd ? '0$hex' : hex;
    final out = Uint8List(h.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

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
class PublishedBook {  final String sessionId;
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

/// A PDF a teacher shared through Gofile, published to a class/school.
/// Free Gofile links survive on real downloads and may retire after
/// ~10 days of inactivity, so [uploadedAtMillis] drives an honest
/// countdown plus one-tap refresh (a genuine re-upload by the teacher).
class SharedPdf {
  final String id;
  final String title;
  final String fileId;
  final String downloadPage;
  final int sizeBytes;
  final String schoolId;
  final String className;
  final String uploadedById;
  final String uploadedByName;
  final int uploadedAtMillis;
  final String localPath; // teacher device only; '' for everyone else

  const SharedPdf({
    required this.id,
    required this.title,
    required this.fileId,
    required this.downloadPage,
    required this.sizeBytes,
    required this.schoolId,
    required this.className,
    required this.uploadedById,
    required this.uploadedByName,
    required this.uploadedAtMillis,
    this.localPath = '',
  });

  /// Rough free-shelf lifetime left, based on the last upload/refresh.
  int get approxDaysLeft {
    final ageMs = DateTime.now().millisecondsSinceEpoch - uploadedAtMillis;
    final left = 10 - (ageMs ~/ Duration.millisecondsPerDay);
    return left < 0 ? 0 : left;
  }

  SharedPdf refreshed({required String fileId, required String downloadPage, required int sizeBytes}) => SharedPdf(
        id: id,
        title: title,
        fileId: fileId,
        downloadPage: downloadPage,
        sizeBytes: sizeBytes,
        schoolId: schoolId,
        className: className,
        uploadedById: uploadedById,
        uploadedByName: uploadedByName,
        uploadedAtMillis: DateTime.now().millisecondsSinceEpoch,
        localPath: localPath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'fileId': fileId,
        'downloadPage': downloadPage,
        'sizeBytes': sizeBytes,
        'schoolId': schoolId,
        'className': className,
        'uploadedById': uploadedById,
        'uploadedByName': uploadedByName,
        'uploadedAtMillis': uploadedAtMillis,
        'localPath': localPath,
      };

  factory SharedPdf.fromJson(Map<String, dynamic> j) => SharedPdf(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? 'PDF').toString(),
        fileId: (j['fileId'] ?? '').toString(),
        downloadPage: (j['downloadPage'] ?? '').toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        schoolId: (j['schoolId'] ?? '').toString(),
        className: (j['className'] ?? '').toString(),
        uploadedById: (j['uploadedById'] ?? '').toString(),
        uploadedByName: (j['uploadedByName'] ?? '').toString(),
        uploadedAtMillis: (j['uploadedAtMillis'] as num?)?.toInt() ?? 0,
        localPath: (j['localPath'] ?? '').toString(),
      );
}
