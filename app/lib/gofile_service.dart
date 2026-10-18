import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GofileUpload {
  final String fileId;
  final String name;
  final int size;
  final String downloadPage;
  const GofileUpload({required this.fileId, required this.name, required this.size, required this.downloadPage});
}

/// Gofile is used ONLY as a free file shelf for PDFs (videos always come
/// from the Playwright-based engine, never from uploads). Each teacher
/// device keeps its own guest-account token: the first upload creates a
/// guest account automatically, later uploads reuse it, so the teacher's
/// PDFs stay under one account. Free links live while they are used;
/// after ~10 days without a download Gofile may retire them — the app
/// shows a countdown and the teacher refreshes with one tap. No fake
/// downloads are ever generated to game that clock.
class GofileService {
  static String _tokenKey(String userId) => 'gofile_token_$userId';

  static Future<String?> tokenFor(String userId) async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_tokenKey(userId));
  }

  static Future<GofileUpload> uploadPdf({required File file, required String userId}) async {
    final token = await tokenFor(userId);
    final req = http.MultipartRequest('POST', Uri.parse('https://upload.gofile.io/uploadfile'));
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await req.send().timeout(const Duration(minutes: 10));
    final body = await streamed.stream.bytesToString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    if (json['status'] != 'ok') {
      throw StateError('Gofile upload failed: ${json['status']}');
    }
    final data = (json['data'] as Map).map((k, v) => MapEntry(k.toString(), v));
    final guest = data['guestToken']?.toString();
    if (guest != null && guest.isNotEmpty) {
      final p = await SharedPreferences.getInstance();
      await p.setString(_tokenKey(userId), guest);
    }
    return GofileUpload(
      fileId: (data['id'] ?? '').toString(),
      name: (data['name'] ?? file.uri.pathSegments.last).toString(),
      size: (data['size'] as num?)?.toInt() ?? await file.length(),
      downloadPage: (data['downloadPage'] ?? '').toString(),
    );
  }

  /// Best-effort removal from Gofile when a teacher unpublishes a PDF.
  static Future<void> deleteFile({required String fileId, required String userId}) async {
    final token = await tokenFor(userId);
    if (token == null || fileId.isEmpty) return;
    try {
      await http
          .delete(Uri.parse('https://api.gofile.io/contents/$fileId'), headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      // Unpublishing inside the app is what matters; the free shelf copy
      // expires on its own if it cannot be deleted.
    }
  }
}
