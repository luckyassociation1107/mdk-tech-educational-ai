import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/premium_ui.dart';
import 'widgets.dart';

/// The running app version. Bumped together with pubspec.yaml on every release.
const String kAppVersion = '0.20.0';

const String kRepo = 'luckyassociation1107/mdk-tech-educational-ai';

class UpdateInfo {
  final String version;
  final String apkUrl;
  final String notes;
  const UpdateInfo(
      {required this.version, required this.apkUrl, this.notes = ''});

  bool get isNewer => _compare(version, kAppVersion) > 0;

  static int _compare(String a, String b) {
    final pa = a
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pb = b
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// Checks GitHub Releases for a newer build. Uses dart:io directly so the
/// app keeps zero extra dependencies. Never blocks the UI: returns null
/// when offline or on any error (the app just stays quiet).
class Updater {
  static Future<UpdateInfo?> latest(
      {Duration timeout = const Duration(seconds: 8)}) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      final req = await client
          .getUrl(
              Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'))
          .timeout(timeout);
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'AI-Textbook-Classroom');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      final body = await utf8.decoder.bind(res).join().timeout(timeout);
      final data = jsonDecode(body);
      if (data is! Map) return null;
      final tag = (data['tag_name'] ?? '').toString();
      final assets = (data['assets'] as List?) ?? const [];
      String apk = '';
      for (final a in assets) {
        if (a is Map && '${a['name']}'.toLowerCase().endsWith('.apk')) {
          apk = (a['browser_download_url'] ?? '').toString();
          break;
        }
      }
      if (apk.isEmpty) return null;
      return UpdateInfo(
        version: tag.replaceAll('v', ''),
        apkUrl: apk,
        notes: (data['body'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Opens a link in the phone's browser (Android) / default browser.
  static Future<bool> openUrl(String url) async {
    try {
      final ok = await const MethodChannel('com.mdk.textbook_video/engine')
          .invokeMethod<bool>('openUrl', {'url': url});
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// A slim "update available" banner. Installing over the app keeps every
/// mark, class and download — nothing is uninstalled.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  UpdateInfo? _info;
  bool _checking = true;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final info = await Updater.latest();
    if (!mounted) return;
    setState(() {
      _info = (info != null && info.isNewer) ? info : null;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return const SizedBox.shrink();
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RiseIn(
        index: 0,
        child: GlassCard(
          tint: AppColors.amber,
          alpha: 0.12,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(children: [
            const GlowIcon(Icons.system_update_rounded,
                color: Color(0xFFF59E0B), size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Update ${info.version} is ready',
                        style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text(
                        'Installs straight over your app — nothing is deleted.',
                        style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11.5,
                            height: 1.35)),
                  ]),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _opened
                  ? null
                  : () async {
                      final ok = await Updater.openUrl(info.apkUrl);
                      if (!mounted) return;
                      setState(() => _opened = ok);
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: SelectableText(info.apkUrl)));
                      }
                    },
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: const Color(0xFF111827),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              child: Text(_opened ? 'Opening…' : 'Update'),
            ),
          ]),
        ),
      ),
    );
  }
}
