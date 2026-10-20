import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_prompts.dart';

/// Which AI service is used. Everything the classroom needs — reading the
/// PDF, designing the lesson script — goes through this one setting.
enum AiProvider { openai, gemini, anthropic, custom }

extension AiProviderInfo on AiProvider {
  String get label => switch (this) {
        AiProvider.openai => 'OpenAI',
        AiProvider.gemini => 'Google Gemini',
        AiProvider.anthropic => 'Anthropic Claude',
        AiProvider.custom => 'Custom (OpenAI-compatible)',
      };

  String get defaultModel => switch (this) {
        AiProvider.openai => 'gpt-4.1-mini',
        AiProvider.gemini => 'gemini-2.5-flash',
        AiProvider.anthropic => 'claude-sonnet-4-5',
        AiProvider.custom => 'gpt-4o-mini',
      };

  String get defaultBaseUrl => switch (this) {
        AiProvider.openai => 'https://api.openai.com',
        AiProvider.gemini => 'https://generativelanguage.googleapis.com',
        AiProvider.anthropic => 'https://api.anthropic.com',
        AiProvider.custom => 'https://api.openai.com',
      };

  /// Can this provider read the PDF file itself?
  bool get acceptsPdf => this != AiProvider.custom;

  String get keyHint => switch (this) {
        AiProvider.openai => 'sk-…  (platform.openai.com → API keys)',
        AiProvider.gemini => 'AIza…  (aistudio.google.com → API key)',
        AiProvider.anthropic => 'sk-ant-…  (console.anthropic.com)',
        AiProvider.custom => 'whatever your server expects',
      };
}

/// Everything that decides how the AI is called, plus the three teacher
/// prompts. The API key lives in the platform keystore (flutter_secure_storage);
/// the rest is ordinary preferences.
class AiConfig {
  AiProvider provider;
  String apiKey;
  String model;
  String baseUrl;
  String extractPrompt;
  String scriptPrompt;
  String askPrompt;

  AiConfig({
    this.provider = AiProvider.gemini,
    this.apiKey = '',
    String? model,
    String? baseUrl,
    String? extractPrompt,
    String? scriptPrompt,
    String? askPrompt,
  })  : model = (model == null || model.isEmpty)
            ? provider.defaultModel
            : model,
        baseUrl = (baseUrl == null || baseUrl.isEmpty)
            ? provider.defaultBaseUrl
            : baseUrl,
        extractPrompt = extractPrompt ?? AiPrompts.extract,
        scriptPrompt = scriptPrompt ?? AiPrompts.script,
        askPrompt = askPrompt ?? AiPrompts.ask;

  bool get ready => apiKey.trim().isNotEmpty;

  /// Shown in the UI so a teacher can see what the app is about to use.
  String get summary {
    if (!ready) return 'No AI key yet — add one to read PDFs';
    return '${provider.label} · ${model.isEmpty ? provider.defaultModel : model}';
  }

  AiConfig copyWith({
    AiProvider? provider,
    String? apiKey,
    String? model,
    String? baseUrl,
    String? extractPrompt,
    String? scriptPrompt,
    String? askPrompt,
    bool resetPrompts = false,
  }) =>
      AiConfig(
        provider: provider ?? this.provider,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        extractPrompt: resetPrompts ? AiPrompts.extract : (extractPrompt ?? this.extractPrompt),
        scriptPrompt: resetPrompts ? AiPrompts.script : (scriptPrompt ?? this.scriptPrompt),
        askPrompt: resetPrompts ? AiPrompts.ask : (askPrompt ?? this.askPrompt),
      );

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'model': model,
        'base_url': baseUrl,
        'extract_prompt': extractPrompt,
        'script_prompt': scriptPrompt,
        'ask_prompt': askPrompt,
      };

  static AiConfig fromJson(Map<String, dynamic> j, {String key = ''}) {
    final p = AiProvider.values.firstWhere(
      (e) => e.name == (j['provider'] ?? ''),
      orElse: () => AiProvider.gemini,
    );
    return AiConfig(
      provider: p,
      apiKey: key,
      model: (j['model'] ?? '').toString(),
      baseUrl: (j['base_url'] ?? '').toString(),
      extractPrompt: (j['extract_prompt'] ?? '').toString().trim().isEmpty
          ? null
          : j['extract_prompt'].toString(),
      scriptPrompt: (j['script_prompt'] ?? '').toString().trim().isEmpty
          ? null
          : j['script_prompt'].toString(),
      askPrompt: (j['ask_prompt'] ?? '').toString().trim().isEmpty
          ? null
          : j['ask_prompt'].toString(),
    );
  }

  // ---------------------------------------------------------------- storage

  static const String _prefsKey = 'ai_config_v1';
  static const String _keySlot = 'ai_api_key_v1';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  static AiConfig? _cached;

  /// The config the whole app reads. Loaded once at startup.
  static AiConfig get current => _cached ??= AiConfig();

  static Future<AiConfig> load() async {
    final p = await SharedPreferences.getInstance();
    String key = '';
    try {
      key = await _secure.read(key: _keySlot) ?? '';
    } catch (_) {
      // A device without a keystore (or a test) simply has no stored key.
    }
    final raw = p.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return _cached = AiConfig(apiKey: key);
    }
    try {
      final j = jsonDecode(raw);
      if (j is Map) {
        return _cached = AiConfig.fromJson(
            j.map((k, v) => MapEntry(k.toString(), v)), key: key);
      }
    } catch (_) {}
    return _cached = AiConfig(apiKey: key);
  }

  Future<void> save() async {
    _cached = this;
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, jsonEncode(toJson()));
    try {
      if (apiKey.trim().isEmpty) {
        await _secure.delete(key: _keySlot);
      } else {
        await _secure.write(key: _keySlot, value: apiKey.trim());
      }
    } catch (_) {
      // Keep the app usable even if the keystore is unavailable.
    }
  }

  static void resetForTest(AiConfig cfg) => _cached = cfg;
}
