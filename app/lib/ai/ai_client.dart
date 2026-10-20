import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ai_config.dart';

/// Something the model failed to do — the message is always written so a
/// teacher can act on it (bad key, no credit, file too big, no internet).
class AiException implements Exception {
  final String message;
  final int? statusCode;
  AiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// One piece of a request: either text or the PDF file itself.
class AiPart {
  final String? text;
  final Uint8List? pdf;
  final String filename;

  AiPart.text(String value)
      : text = value,
        pdf = null,
        filename = '';

  AiPart.pdf(Uint8List bytes, this.filename)
      : pdf = bytes,
        text = null;
}

/// A ready-to-send HTTP call. Kept as a plain value so the wire format can
/// be unit-tested without any network.
class AiCall {
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  const AiCall({required this.url, required this.headers, required this.body});

  String get bodyJson => jsonEncode(body);
}

/// The only AI gateway in the app.
///
/// There is no shared or borrowed endpoint here: the teacher pastes their
/// own API key in Settings, and every request — PDF reading, lesson
/// scripting, doubt clearing — goes to that account. Providers whose API
/// can read a PDF directly (OpenAI, Gemini, Claude) receive the actual
/// file, so nothing has to be parsed on the device first.
class AiClient {
  AiClient({HttpClient Function()? clientFactory})
      : _newClient = clientFactory ?? HttpClient.new;

  final HttpClient Function() _newClient;

  /// Refuse obviously-too-large uploads before spending a request.
  static const int maxPdfBytes = 18 * 1024 * 1024;

  // ------------------------------------------------------------- request

  static String _base(String url) {
    var b = url.trim();
    if (b.isEmpty) b = AiProvider.gemini.defaultBaseUrl;
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  static AiCall build(
    AiConfig cfg, {
    required List<AiPart> parts,
    bool json = false,
    int maxTokens = 4096,
  }) {
    final base = _base(cfg.baseUrl.isEmpty ? cfg.provider.defaultBaseUrl : cfg.baseUrl);
    final model = cfg.model.trim().isEmpty ? cfg.provider.defaultModel : cfg.model.trim();
    final pdf = parts.where((p) => p.pdf != null).toList();
    if (pdf.isNotEmpty && pdf.first.pdf!.length > maxPdfBytes) {
      throw AiException(
          'This PDF is ${(pdf.first.pdf!.length / 1048576).toStringAsFixed(1)} MB. '
          'The AI upload limit is 18 MB — compress the PDF or split the chapter.');
    }
    if (pdf.isNotEmpty && !cfg.provider.acceptsPdf) {
      throw AiException(
          'A custom endpoint cannot receive a PDF file. Choose OpenAI, Gemini or Claude for PDF upload.');
    }

    switch (cfg.provider) {
      case AiProvider.openai:
        return AiCall(
          url: Uri.parse('$base/v1/responses'),
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer ${cfg.apiKey.trim()}',
          },
          body: {
            'model': model,
            'input': [
              {
                'role': 'user',
                'content': [
                  for (final p in parts)
                    if (p.text != null)
                      {'type': 'input_text', 'text': p.text}
                    else
                      {
                        'type': 'input_file',
                        'filename': p.filename.isEmpty ? 'textbook.pdf' : p.filename,
                        'file_data':
                            'data:application/pdf;base64,${base64Encode(p.pdf!)}',
                      }
                ],
              }
            ],
            'max_output_tokens': maxTokens,
            if (json) 'text': {'format': {'type': 'json_object'}},
          },
        );

      case AiProvider.gemini:
        return AiCall(
          url: Uri.parse(
              '$base/v1beta/models/$model:generateContent?key=${Uri.encodeQueryComponent(cfg.apiKey.trim())}'),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          body: {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  for (final p in parts)
                    if (p.text != null)
                      {'text': p.text}
                    else
                      {
                        'inline_data': {
                          'mime_type': 'application/pdf',
                          'data': base64Encode(p.pdf!),
                        }
                      }
                ],
              }
            ],
            'generationConfig': {
              'maxOutputTokens': maxTokens,
              'temperature': 0.3,
              if (json) 'responseMimeType': 'application/json',
            },
          },
        );

      case AiProvider.anthropic:
        return AiCall(
          url: Uri.parse('$base/v1/messages'),
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            'x-api-key': cfg.apiKey.trim(),
            'anthropic-version': '2023-06-01',
          },
          body: {
            'model': model,
            'max_tokens': maxTokens,
            'messages': [
              {
                'role': 'user',
                'content': [
                  for (final p in parts)
                    if (p.text != null)
                      {'type': 'text', 'text': p.text}
                    else
                      {
                        'type': 'document',
                        'source': {
                          'type': 'base64',
                          'media_type': 'application/pdf',
                          'data': base64Encode(p.pdf!),
                        }
                      }
                ],
              }
            ],
            if (json) 'system': 'Return only valid JSON.',
          },
        );

      case AiProvider.custom:
        return AiCall(
          url: Uri.parse('$base/v1/chat/completions'),
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer ${cfg.apiKey.trim()}',
          },
          body: {
            'model': model,
            'messages': [
              {
                'role': 'user',
                'content': parts
                    .where((p) => p.text != null)
                    .map((p) => p.text!)
                    .join('\n\n'),
              }
            ],
            'max_tokens': maxTokens,
            if (json) 'response_format': {'type': 'json_object'},
          },
        );
    }
  }

  // ------------------------------------------------------------ response

  /// Pull the assistant's text out of each provider's reply shape.
  static String parseResponse(AiProvider provider, String raw) {
    dynamic j;
    try {
      j = jsonDecode(raw);
    } catch (_) {
      throw AiException('The AI sent a reply the app could not read.');
    }
    if (j is! Map) throw AiException('The AI sent an unexpected reply.');

    // Every provider reports failures in its own way — surface the message.
    if (j['error'] != null) {
      final e = j['error'];
      final msg = e is Map ? (e['message'] ?? '$e') : '$e';
      throw AiException('$msg');
    }

    switch (provider) {
      case AiProvider.openai:
        final direct = j['output_text'];
        if (direct is String && direct.trim().isNotEmpty) return direct;
        final buf = StringBuffer();
        final out = j['output'];
        if (out is List) {
          for (final item in out) {
            if (item is! Map) continue;
            final content = item['content'];
            if (content is! List) continue;
            for (final c in content) {
              if (c is Map && c['text'] is String) buf.write(c['text']);
            }
          }
        }
        if (buf.isEmpty) {
          // A few compatible gateways still answer in chat-completions shape.
          final choices = j['choices'];
          if (choices is List && choices.isNotEmpty && choices.first is Map) {
            final m = (choices.first as Map)['message'];
            if (m is Map && m['content'] is String) return m['content'] as String;
          }
          throw AiException('The AI returned an empty answer.');
        }
        return buf.toString();

      case AiProvider.gemini:
        final cands = j['candidates'];
        if (cands is List && cands.isNotEmpty) {
          final first = cands.first;
          if (first is Map) {
            final c = first['content'];
            if (c is Map && c['parts'] is List) {
              final buf = StringBuffer();
              for (final p in (c['parts'] as List)) {
                if (p is Map && p['text'] is String) buf.write(p['text']);
              }
              if (buf.isNotEmpty) return buf.toString();
            }
          }
        }
        final reason = (j['promptFeedback'] is Map)
            ? ((j['promptFeedback'] as Map)['blockReason'] ?? '')
            : '';
        throw AiException(reason.toString().isEmpty
            ? 'The AI returned an empty answer.'
            : 'The AI refused this request ($reason).');

      case AiProvider.anthropic:
        final content = j['content'];
        if (content is List) {
          final buf = StringBuffer();
          for (final c in content) {
            if (c is Map && c['type'] == 'text' && c['text'] is String) {
              buf.write(c['text']);
            }
          }
          if (buf.isNotEmpty) return buf.toString();
        }
        throw AiException('The AI returned an empty answer.');

      case AiProvider.custom:
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map) {
            final m = first['message'];
            if (m is Map && m['content'] is String) return m['content'] as String;
          }
        }
        throw AiException('The AI returned an empty answer.');
    }
  }

  // ------------------------------------------------------------- network

  Future<String> generate(
    AiConfig cfg, {
    required List<AiPart> parts,
    bool json = false,
    int maxTokens = 4096,
    Duration timeout = const Duration(minutes: 4),
  }) async {
    if (!cfg.ready) {
      throw AiException(
          'No AI key yet. Open Settings → AI & Prompts and paste your key.');
    }
    final call = build(cfg, parts: parts, json: json, maxTokens: maxTokens);
    final client = _newClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final res = await _send(client, call, timeout);
      return parseResponse(cfg.provider, res);
    } on AiException {
      rethrow;
    } on SocketException catch (e) {
      throw AiException('No internet connection (${e.message}).');
    } on TimeoutException {
      throw AiException('The AI took too long to answer. Try a smaller part.');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _send(HttpClient client, AiCall call, Duration timeout) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final req = await client.openUrl('POST', call.url).timeout(timeout);
        call.headers.forEach(req.headers.set);
        req.add(utf8.encode(call.bodyJson));
        final res = await req.close().timeout(timeout);
        final text = await res.transform(utf8.decoder).join();
        if (res.statusCode == 200 || res.statusCode == 201) return text;
        final retryable = res.statusCode == 429 || res.statusCode >= 500;
        if (retryable && attempt == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          continue;
        }
        throw AiException(_explain(res.statusCode, text), statusCode: res.statusCode);
      } on SocketException {
        if (attempt == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        rethrow;
      }
    }
  }

  static String _explain(int status, String body) {
    var detail = body.trim();
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] != null) {
        final e = j['error'];
        detail = e is Map ? '${e['message'] ?? e}' : '$e';
      }
    } catch (_) {}
    if (detail.length > 220) detail = detail.substring(0, 220);
    switch (status) {
      case 401:
        return 'The AI key was rejected (401). Check the key in Settings.';
      case 402:
      case 403:
        return 'The AI account cannot do this (HTTP $status). $detail';
      case 404:
        return 'Model not found (404). Check the model name in Settings. $detail';
      case 413:
        return 'The PDF is too large for this model (413).';
      case 429:
        return 'Rate limit or no credit left (429). Try later or check the account.';
      default:
        return 'AI request failed (HTTP $status). $detail';
    }
  }

  /// Small round-trip used by the "Test connection" button.
  Future<String> testConnection(AiConfig cfg) async {
    final out = await generate(
      cfg,
      parts: [AiPart.text('Reply with exactly this word and nothing else: READY')],
      maxTokens: 16,
      timeout: const Duration(seconds: 45),
    );
    return out.trim();
  }
}
