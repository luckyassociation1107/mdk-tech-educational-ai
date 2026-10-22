import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_prompts.dart';
import 'web_ai_engine.dart';

/// Settings for the **free** AI mode.
///
/// There is no API key, no provider and no model here on purpose: the app
/// drives the public PDF-teacher website inside its own WebView, so reading a
/// book costs nothing and there is nothing to paste. All the teacher can tune
/// is the three prompts.
class AiConfig {
  String extractPrompt;
  String scriptPrompt;
  String askPrompt;

  AiConfig({
    String? extractPrompt,
    String? scriptPrompt,
    String? askPrompt,
  })  : extractPrompt = extractPrompt ?? AiPrompts.extract,
        scriptPrompt = scriptPrompt ?? AiPrompts.script,
        askPrompt = askPrompt ?? AiPrompts.ask;

  /// The free mode needs an in-app browser: Android's system WebView, or
  /// Microsoft Edge WebView2 on Windows. Nothing else is required — no key,
  /// no account, no login. The engine is the only place that decides this,
  /// so every screen agrees with it.
  bool get ready => WebAiEngine.instance.supported;

  /// Shown in the UI so a teacher can see what the app is about to use.
  String get summary => ready
      ? 'Free website AI · ${WebAiEngine.instance.engineName} · no key, no cost'
      : 'Free AI needs a WebView — the Android or the Windows app';

  AiConfig copyWith({
    String? extractPrompt,
    String? scriptPrompt,
    String? askPrompt,
    bool resetPrompts = false,
  }) =>
      AiConfig(
        extractPrompt:
            resetPrompts ? AiPrompts.extract : (extractPrompt ?? this.extractPrompt),
        scriptPrompt:
            resetPrompts ? AiPrompts.script : (scriptPrompt ?? this.scriptPrompt),
        askPrompt: resetPrompts ? AiPrompts.ask : (askPrompt ?? this.askPrompt),
      );

  Map<String, dynamic> toJson() => {
        'extract_prompt': extractPrompt,
        'script_prompt': scriptPrompt,
        'ask_prompt': askPrompt,
      };

  static AiConfig fromJson(Map<String, dynamic> j) => AiConfig(
        extractPrompt: _promptOrNull(j['extract_prompt']),
        scriptPrompt: _promptOrNull(j['script_prompt']),
        askPrompt: _promptOrNull(j['ask_prompt']),
      );

  static String? _promptOrNull(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : v.toString();
  }

  // ---------------------------------------------------------------- storage

  static const String _prefsKey = 'ai_config_v2';

  static AiConfig? _cached;

  /// The config the whole app reads. Loaded once at startup.
  static AiConfig get current => _cached ??= AiConfig();

  static Future<AiConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey) ?? p.getString('ai_config_v1');
    if (raw != null && raw.isNotEmpty) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          return _cached =
              AiConfig.fromJson(j.map((k, v) => MapEntry(k.toString(), v)));
        }
      } catch (_) {}
    }
    return _cached = AiConfig();
  }

  Future<void> save() async {
    _cached = this;
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, jsonEncode(toJson()));
  }

  static void resetForTest(AiConfig cfg) => _cached = cfg;
}
