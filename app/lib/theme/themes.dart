import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ─────────────────────────────────────────────────────────────────────
///  Theme engine
///  6 built-in palettes (3 dark + 3 light) and unlimited custom themes.
///  A custom theme can be exported as JSON text/file and imported back.
///  Nothing here is a package: pure Flutter + SharedPreferences.
/// ─────────────────────────────────────────────────────────────────────

class AppPalette {
  final String id;
  final String name;
  final bool isLight; // light themes flip text/background contrast
  final Color bg;
  final Color bg2;
  final Color card;
  final Color cardLight;
  final Color stroke;
  final Color text;
  final Color muted;
  final Color primary; // main brand colour (buttons, links)
  final Color secondary; // gradient partner
  final Color accent; // highlights (teal-ish)
  final Color amber;
  final Color red;
  final Color green;
  final List<Color> heroColors; // 3 stop hero gradient
  final bool isCustom;

  const AppPalette({
    required this.id,
    required this.name,
    required this.isLight,
    required this.bg,
    required this.bg2,
    required this.card,
    required this.cardLight,
    required this.stroke,
    required this.text,
    required this.muted,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.amber,
    required this.red,
    required this.green,
    required this.heroColors,
    this.isCustom = false,
  });

  LinearGradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: heroColors,
      );

  LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primary, secondary],
      );

  AppPalette copyWith({
    String? id,
    String? name,
    bool? isLight,
    Color? bg,
    Color? bg2,
    Color? card,
    Color? cardLight,
    Color? stroke,
    Color? text,
    Color? muted,
    Color? primary,
    Color? secondary,
    Color? accent,
    Color? amber,
    Color? red,
    Color? green,
    List<Color>? heroColors,
    bool? isCustom,
  }) =>
      AppPalette(
        id: id ?? this.id,
        name: name ?? this.name,
        isLight: isLight ?? this.isLight,
        bg: bg ?? this.bg,
        bg2: bg2 ?? this.bg2,
        card: card ?? this.card,
        cardLight: cardLight ?? this.cardLight,
        stroke: stroke ?? this.stroke,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        accent: accent ?? this.accent,
        amber: amber ?? this.amber,
        red: red ?? this.red,
        green: green ?? this.green,
        heroColors: heroColors ?? this.heroColors,
        isCustom: isCustom ?? this.isCustom,
      );

  static String hex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color parseHex(String s, {Color fallback = const Color(0xFF6366F1)}) {
    var v = s.trim().replaceAll('#', '');
    if (v.length == 8) v = v.substring(2); // drop AA
    if (v.length != 6) return fallback;
    final n = int.tryParse(v, radix: 16);
    return n == null ? fallback : Color(0xFF000000 | n);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isLight': isLight,
        'bg': hex(bg),
        'card': hex(card),
        'text': hex(text),
        'primary': hex(primary),
        'secondary': hex(secondary),
        'accent': hex(accent),
        'isCustom': isCustom,
      };

  factory AppPalette.fromJson(Map m) {
    final bg = parseHex('${m['bg'] ?? '#0B1020'}');
    final card = parseHex('${m['card'] ?? '#171F3D'}');
    final text = parseHex('${m['text'] ?? '#F2F5FF'}');
    final primary = parseHex('${m['primary'] ?? '#6366F1'}');
    final secondary = parseHex('${m['secondary'] ?? '#A855F7'}');
    final accent = parseHex('${m['accent'] ?? '#2DD4BF'}');
    return AppPalette.fromFiveColors(
      id: '${m['id'] ?? 'custom_${DateTime.now().millisecondsSinceEpoch}'}',
      name: '${m['name'] ?? 'My theme'}',
      bg: bg,
      card: card,
      text: text,
      primary: primary,
      secondary: secondary,
      accent: accent,
    );
  }

  /// Builds a complete, readable palette from just five colours — the same
  /// five a student picks in the Theme Studio. Light/dark is detected from
  /// the background luminance so text and borders always stay legible.
  static AppPalette fromFiveColors({
    required String id,
    required String name,
    required Color bg,
    required Color card,
    required Color text,
    required Color primary,
    required Color secondary,
    required Color accent,
  }) {
    final isLight = bg.computeLuminance() > 0.5;
    Color mix(Color a, Color b, double t) =>
        Color.lerp(a, b, t.clamp(0.0, 1.0))!;
    return AppPalette(
      id: id,
      name: name,
      isLight: isLight,
      bg: bg,
      bg2: mix(bg, card, 0.45),
      card: card,
      cardLight:
          isLight ? mix(card, text, 0.06) : mix(card, Colors.white, 0.07),
      stroke: isLight ? mix(card, text, 0.16) : mix(card, Colors.white, 0.16),
      text: text,
      muted: isLight ? mix(text, bg, 0.45) : mix(text, bg, 0.50),
      primary: primary,
      secondary: secondary,
      accent: accent,
      amber: isLight ? const Color(0xFFD97706) : const Color(0xFFFBBF24),
      red: isLight ? const Color(0xFFDC2626) : const Color(0xFFF87171),
      green: isLight ? const Color(0xFF059669) : const Color(0xFF34D399),
      heroColors: [primary, secondary, accent],
      isCustom: true,
    );
  }
}

// ─────────────────────────── built-in themes ───────────────────────────

final List<AppPalette> kBuiltInThemes = [
  // ── DARK 1: Midnight Indigo (the original premium look)
  const AppPalette(
    id: 'midnight',
    name: 'Midnight Indigo',
    isLight: false,
    bg: Color(0xFF0B1020),
    bg2: Color(0xFF111833),
    card: Color(0xFF171F3D),
    cardLight: Color(0xFF1F2A52),
    stroke: Color(0xFF2A3766),
    text: Color(0xFFF2F5FF),
    muted: Color(0xFF9AA7D4),
    primary: Color(0xFF6366F1),
    secondary: Color(0xFFA855F7),
    accent: Color(0xFF2DD4BF),
    amber: Color(0xFFFBBF24),
    red: Color(0xFFF87171),
    green: Color(0xFF34D399),
    heroColors: [Color(0xFF4338CA), Color(0xFF7C3AED), Color(0xFF0D9488)],
  ),
  // ── DARK 2: Neon Graphite
  const AppPalette(
    id: 'graphite',
    name: 'Neon Graphite',
    isLight: false,
    bg: Color(0xFF0A0A0B),
    bg2: Color(0xFF121215),
    card: Color(0xFF17171B),
    cardLight: Color(0xFF202027),
    stroke: Color(0xFF2E2E36),
    text: Color(0xFFF5F5F7),
    muted: Color(0xFFA1A1AA),
    primary: Color(0xFF22D3EE),
    secondary: Color(0xFF84CC16),
    accent: Color(0xFF34D399),
    amber: Color(0xFFF59E0B),
    red: Color(0xFFF87171),
    green: Color(0xFF4ADE80),
    heroColors: [Color(0xFF0E7490), Color(0xFF065F46), Color(0xFF111827)],
  ),
  // ── DARK 3: Royal Aurora
  const AppPalette(
    id: 'royal',
    name: 'Royal Aurora',
    isLight: false,
    bg: Color(0xFF0B0A1F),
    bg2: Color(0xFF14113A),
    card: Color(0xFF1B1750),
    cardLight: Color(0xFF241E63),
    stroke: Color(0xFF322A7A),
    text: Color(0xFFF4F1FF),
    muted: Color(0xFFA79DE0),
    primary: Color(0xFF8B5CF6),
    secondary: Color(0xFFEC4899),
    accent: Color(0xFFF59E0B),
    amber: Color(0xFFFBBF24),
    red: Color(0xFFFF8A8A),
    green: Color(0xFF4ADE80),
    heroColors: [Color(0xFF4C1D95), Color(0xFFBE185D), Color(0xFFF59E0B)],
  ),
  // ── LIGHT 1: Daylight Paper
  const AppPalette(
    id: 'daylight',
    name: 'Daylight Paper',
    isLight: true,
    bg: Color(0xFFF6F7FB),
    bg2: Color(0xFFEEF1F8),
    card: Color(0xFFFFFFFF),
    cardLight: Color(0xFFF1F4FA),
    stroke: Color(0xFFD8DEEC),
    text: Color(0xFF0F172A),
    muted: Color(0xFF5B6780),
    primary: Color(0xFF4F46E5),
    secondary: Color(0xFF7C3AED),
    accent: Color(0xFF0D9488),
    amber: Color(0xFFD97706),
    red: Color(0xFFDC2626),
    green: Color(0xFF059669),
    heroColors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF0D9488)],
  ),
  // ── LIGHT 2: Warm Sand
  const AppPalette(
    id: 'sand',
    name: 'Warm Sand',
    isLight: true,
    bg: Color(0xFFFBF7F0),
    bg2: Color(0xFFF5EDE0),
    card: Color(0xFFFFFFFF),
    cardLight: Color(0xFFF7F0E4),
    stroke: Color(0xFFE4D8C4),
    text: Color(0xFF2B2118),
    muted: Color(0xFF7A6A55),
    primary: Color(0xFFC2410C),
    secondary: Color(0xFFB45309),
    accent: Color(0xFF0F766E),
    amber: Color(0xFFD97706),
    red: Color(0xFFB91C1C),
    green: Color(0xFF15803D),
    heroColors: [Color(0xFFC2410C), Color(0xFFB45309), Color(0xFF0F766E)],
  ),
  // ── LIGHT 3: Mint Studio
  const AppPalette(
    id: 'mint',
    name: 'Mint Studio',
    isLight: true,
    bg: Color(0xFFF1FAF6),
    bg2: Color(0xFFE6F4EE),
    card: Color(0xFFFFFFFF),
    cardLight: Color(0xFFEEF8F3),
    stroke: Color(0xFFCFE6DD),
    text: Color(0xFF0B2B22),
    muted: Color(0xFF4E7266),
    primary: Color(0xFF0D9488),
    secondary: Color(0xFF059669),
    accent: Color(0xFF2563EB),
    amber: Color(0xFFB45309),
    red: Color(0xFFDC2626),
    green: Color(0xFF16A34A),
    heroColors: [Color(0xFF0D9488), Color(0xFF0F766E), Color(0xFF2563EB)],
  ),
];

// ─────────────────────────── theme manager ───────────────────────────

class ThemeManager {
  /// Incremented every time the palette changes; the whole app listens.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static AppPalette _palette = kBuiltInThemes.first;
  static String _currentId = 'midnight';
  static List<AppPalette> _customs = [];

  static AppPalette get palette => _palette;
  static String get currentId => _currentId;
  static List<AppPalette> get customs => List.unmodifiable(_customs);
  static List<AppPalette> get all => [...kBuiltInThemes, ..._customs];
  static AppPalette get current => _palette;

  static const _kId = 'theme_current_id';
  static const _kCustoms = 'theme_customs_json';

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _currentId = p.getString(_kId) ?? 'midnight';
    try {
      final raw = p.getString(_kCustoms);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          _customs =
              list.whereType<Map>().map((m) => AppPalette.fromJson(m)).toList();
        }
      }
    } catch (_) {
      _customs = [];
    }
    _palette = _resolve(_currentId);
    revision.value++;
  }

  static AppPalette _resolve(String id) {
    for (final t in kBuiltInThemes) {
      if (t.id == id) return t;
    }
    for (final t in _customs) {
      if (t.id == id) return t;
    }
    return kBuiltInThemes.first;
  }

  static Future<void> select(String id) async {
    _currentId = id;
    _palette = _resolve(id);
    revision.value++;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kId, id);
  }

  /// Live preview without saving (used while dragging custom colours).
  static void preview(AppPalette palette) {
    _palette = palette;
    revision.value++;
  }

  static Future<void> restoreSaved() async {
    _palette = _resolve(_currentId);
    revision.value++;
  }

  static Future<void> saveCustom(AppPalette palette) async {
    final idx = _customs.indexWhere((t) => t.id == palette.id);
    if (idx >= 0) {
      _customs[idx] = palette;
    } else {
      _customs.add(palette);
    }
    await _persistCustoms();
    await select(palette.id);
  }

  static Future<void> deleteCustom(String id) async {
    _customs.removeWhere((t) => t.id == id);
    await _persistCustoms();
    if (_currentId == id) {
      await select('midnight');
    }
  }

  static Future<void> _persistCustoms() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kCustoms, jsonEncode(_customs.map((e) => e.toJson()).toList()));
    revision.value++;
  }

  /// One theme → JSON text (shareable / saveable).
  static String exportTheme([AppPalette? palette]) {
    final t = palette ?? _palette;
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'AI Textbook Classroom',
      'kind': 'theme',
      'version': 1,
      'theme': {
        ...t.toJson(),
        'id': t.isCustom
            ? t.id
            : 'imported_${DateTime.now().millisecondsSinceEpoch}'
      },
    });
  }

  /// Import one or many themes from exported JSON. Returns imported themes.
  static Future<List<AppPalette>> importTheme(String raw) async {
    final data = jsonDecode(raw);
    final out = <AppPalette>[];
    void one(Map m) {
      final p = AppPalette.fromJson({
        ...m.map((k, v) => MapEntry(k.toString(), v)),
        'id': 'custom_${DateTime.now().microsecondsSinceEpoch}_${out.length}',
      });
      out.add(p);
    }

    if (data is Map && data['theme'] is Map) {
      one(data['theme'] as Map);
    } else if (data is Map && data['themes'] is List) {
      for (final t in data['themes'] as List) {
        if (t is Map) one(t);
      }
    } else if (data is List) {
      for (final t in data) {
        if (t is Map) one(t);
      }
    } else if (data is Map && data['bg'] != null) {
      one(data);
    } else {
      throw const FormatException('Not a theme file');
    }
    if (out.isEmpty) throw const FormatException('No themes found in file');
    _customs.addAll(out);
    await _persistCustoms();
    await select(out.first.id);
    return out;
  }

  static String exportAll() => const JsonEncoder.withIndent('  ').convert({
        'app': 'AI Textbook Classroom',
        'kind': 'themes',
        'version': 1,
        'themes': _customs.map((e) => e.toJson()).toList(),
      });
}
