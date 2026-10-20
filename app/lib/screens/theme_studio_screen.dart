import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../store.dart';
import '../theme/themes.dart';
import '../ui/premium_ui.dart';
import '../widgets.dart';

/// Theme Studio — 6 built-in palettes (3 dark + 3 light), a custom theme
/// builder with live preview, and export/import of themes as JSON.
class ThemeStudioScreen extends StatefulWidget {
  final AppSettings settings;
  const ThemeStudioScreen({super.key, required this.settings});

  @override
  State<ThemeStudioScreen> createState() => _ThemeStudioScreenState();
}

class _ThemeStudioScreenState extends State<ThemeStudioScreen> {
  String _tab = 'builtin'; // builtin | custom | transfer

  // custom builder state
  final _nameCtrl = TextEditingController(text: 'My theme');
  Color _cBg = const Color(0xFF0B1020);
  Color _cCard = const Color(0xFF171F3D);
  Color _cText = const Color(0xFFF2F5FF);
  Color _cPrimary = const Color(0xFF6366F1);
  Color _cSecondary = const Color(0xFFA855F7);
  Color _cAccent = const Color(0xFF2DD4BF);
  String? _editingId;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  AppPalette _buildPalette() => AppPalette.fromFiveColors(
        id: _editingId ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name:
            _nameCtrl.text.trim().isEmpty ? 'My theme' : _nameCtrl.text.trim(),
        bg: _cBg,
        card: _cCard,
        text: _cText,
        primary: _cPrimary,
        secondary: _cSecondary,
        accent: _cAccent,
      );

  Future<void> _select(AppPalette t) async {
    await ThemeManager.select(t.id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${t.name} applied')));
  }

  Future<void> _exportCurrent() async {
    final json = ThemeManager.exportTheme();
    await Clipboard.setData(ClipboardData(text: json));
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/classroom/themes');
      if (!await folder.exists()) await folder.create(recursive: true);
      final safe =
          ThemeManager.palette.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
      final f = File('${folder.path}/theme_$safe.json');
      await f.writeAsString(json);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Theme copied + saved to ${f.path}'),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Theme copied to clipboard')));
    }
  }

  Future<void> _exportAll() async {
    final json = ThemeManager.exportAll();
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All custom themes copied to clipboard')));
  }

  Future<void> _import() async {
    final ctrl = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Import theme',
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              'Paste theme JSON (from Export) below, or load the newest saved theme file.',
              style: TextStyle(
                  color: AppColors.muted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            minLines: 4,
            maxLines: 8,
            style: const TextStyle(fontSize: 11.5),
            decoration: const InputDecoration(hintText: '{ "theme": { ... } }'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final raw = await Clipboard.getData(Clipboard.kTextPlain);
                if (raw?.text != null) ctrl.text = raw!.text!;
              },
              icon: const Icon(Icons.content_paste_rounded, size: 16),
              label: const Text('Paste from clipboard'),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final imported = await ThemeManager.importTheme(raw);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Imported ${imported.length} theme${imported.length == 1 ? '' : 's'}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
  }

  Future<void> _importFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/classroom/themes');
      if (!await folder.exists()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No saved theme files yet — export one first.')));
        return;
      }
      final files = folder
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      if (files.isEmpty) return;
      if (!mounted) return;
      final chosen = await showDialog<File>(
        context: context,
        builder: (ctx) => SimpleDialog(
          backgroundColor: AppColors.card,
          title: const Text('Open theme file'),
          children: [
            for (final f in files.take(10))
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(f),
                child: Text(f.uri.pathSegments.last,
                    style: const TextStyle(fontSize: 13)),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      final imported =
          await ThemeManager.importTheme(await chosen.readAsString());
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${imported.first.name}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not import file: $e')));
    }
  }

  Future<void> _saveCustom() async {
    final palette = _buildPalette();
    await ThemeManager.saveCustom(palette);
    if (!mounted) return;
    setState(() {});
    await showCelebration(context,
        title: 'Theme saved!',
        subtitle:
            '${palette.name} is now your active theme. It is also exported to your theme list.',
        big: false);
    if (!mounted) return;
    setState(() => _tab = 'builtin');
  }

  void _previewCustom() {
    ThemeManager.preview(_buildPalette());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Theme Studio',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        actions: [
          IconButton(
              tooltip: 'Export current theme',
              onPressed: _exportCurrent,
              icon: Icon(Icons.ios_share_rounded, color: AppColors.teal)),
          IconButton(
              tooltip: 'Import theme',
              onPressed: _import,
              icon: Icon(Icons.download_rounded, color: AppColors.teal)),
        ],
      ),
      body: AuroraBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
          children: [
            _previewBanner(),
            const SizedBox(height: 14),
            Row(children: [
              _tabChip('builtin', 'Built-in'),
              const SizedBox(width: 8),
              _tabChip('custom', 'Create'),
              const SizedBox(width: 8),
              _tabChip('transfer', 'Export / Import'),
            ]),
            const SizedBox(height: 14),
            if (_tab == 'builtin') ..._builtInTab(),
            if (_tab == 'custom') ..._customTab(),
            if (_tab == 'transfer') ..._transferTab(),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(String id, String label) {
    final sel = _tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: sel ? AppColors.accentGradient : null,
            color: sel ? null : AppColors.card,
            borderRadius: BorderRadius.circular(13),
            border:
                Border.all(color: sel ? Colors.transparent : AppColors.stroke),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  color: sel ? Colors.white : AppColors.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                )),
          ),
        ),
      ),
    );
  }

  Widget _previewBanner() {
    final t = ThemeManager.palette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: t.primary.withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 10))
        ],
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
              color: Colors.white24, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.palette_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
            Text(
                '${t.isLight ? 'Light' : 'Dark'}${t.isCustom ? ' • custom' : ' • built-in'}',
                style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ]),
        ),
        Row(children: [
          for (final c in [t.bg, t.card, t.primary, t.secondary, t.accent])
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54)),
              ),
            ),
        ]),
      ]),
    );
  }

  List<Widget> _builtInTab() {
    Widget group(String title, List<AppPalette> items, int offset) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 3, bottom: 8, top: 6),
          child: Text(title,
              style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
        ),
        ...List.generate(
            items.length,
            (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RiseIn(index: offset + i, child: _themeTile(items[i])),
                )),
      ]);
    }

    final darks = kBuiltInThemes.where((t) => !t.isLight).toList();
    final lights = kBuiltInThemes.where((t) => t.isLight).toList();
    return [
      group('Dark themes (3)', darks, 0),
      const SizedBox(height: 8),
      group('Light themes (3)', lights, 3),
    ];
  }

  Widget _themeTile(AppPalette t) {
    final sel = ThemeManager.currentId == t.id;
    return GestureDetector(
      onTap: () => _select(t),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: sel ? AppColors.teal : AppColors.stroke,
              width: sel ? 1.8 : 1),
        ),
        child: Row(children: [
          Container(
            width: 74,
            height: 56,
            decoration: BoxDecoration(
              gradient: t.heroGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black26),
            ),
            child: Center(
              child: Container(
                width: 40,
                height: 22,
                decoration: BoxDecoration(
                    color: t.bg, borderRadius: BorderRadius.circular(6)),
                child: Center(
                  child: Container(
                    width: 20,
                    height: 4,
                    decoration: BoxDecoration(
                        color: t.text.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(99)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(t.name,
                    style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (t.isLight ? AppColors.amber : AppColors.indigo)
                        .withOpacity(0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(t.isLight ? 'LIGHT' : 'DARK',
                      style: TextStyle(
                        color: t.isLight ? AppColors.amber : AppColors.teal,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.7,
                      )),
                ),
              ]),
              const SizedBox(height: 7),
              Row(children: [
                for (final c in [
                  t.bg,
                  t.card,
                  t.primary,
                  t.secondary,
                  t.accent,
                  t.text
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.stroke)),
                    ),
                  ),
              ]),
            ]),
          ),
          if (sel)
            Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 22),
        ]),
      ),
    );
  }

  List<Widget> _customTab() => [
        GradientCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Build your own',
                style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
            const SizedBox(height: 4),
            Text(
                'Pick six colours. Light or dark is detected automatically, and text, borders and muted tones are generated so everything stays readable.',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 12, height: 1.4)),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              style: TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                  labelText: 'Theme name', hintText: 'e.g. My Blue Night'),
              onChanged: (_) => _previewCustom(),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _colorRow(
            'Background',
            _cBg,
            (c) => setState(() {
                  _cBg = c;
                  _previewCustom();
                })),
        _colorRow(
            'Card surface',
            _cCard,
            (c) => setState(() {
                  _cCard = c;
                  _previewCustom();
                })),
        _colorRow(
            'Text',
            _cText,
            (c) => setState(() {
                  _cText = c;
                  _previewCustom();
                })),
        _colorRow(
            'Primary (buttons)',
            _cPrimary,
            (c) => setState(() {
                  _cPrimary = c;
                  _previewCustom();
                })),
        _colorRow(
            'Secondary (gradient)',
            _cSecondary,
            (c) => setState(() {
                  _cSecondary = c;
                  _previewCustom();
                })),
        _colorRow(
            'Accent (highlights)',
            _cAccent,
            (c) => setState(() {
                  _cAccent = c;
                  _previewCustom();
                })),
        const SizedBox(height: 14),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Live preview',
                style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _buildPalette().card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _buildPalette().stroke),
              ),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      gradient: _buildPalette().accentGradient,
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(Icons.school_rounded,
                      color: _buildPalette().text, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Chapter 4 — Photosynthesis',
                            style: TextStyle(
                                color: _buildPalette().text,
                                fontWeight: FontWeight.w900,
                                fontSize: 13.5)),
                        const SizedBox(height: 3),
                        Text('Explanation, quiz and flashcards',
                            style: TextStyle(
                                color: _buildPalette().muted, fontSize: 11.5)),
                      ]),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: _buildPalette().accent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(99)),
                  child: Text('Play',
                      style: TextStyle(
                          color: _buildPalette().accent,
                          fontWeight: FontWeight.w900,
                          fontSize: 11)),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _cBg = const Color(0xFF0B1020);
                  _cCard = const Color(0xFF171F3D);
                  _cText = const Color(0xFFF2F5FF);
                  _cPrimary = const Color(0xFF6366F1);
                  _cSecondary = const Color(0xFFA855F7);
                  _cAccent = const Color(0xFF2DD4BF);
                  _editingId = null;
                });
                _previewCustom();
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: _saveCustom,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save & apply'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.indigo),
            ),
          ),
        ]),
        if (ThemeManager.customs.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('My themes',
              style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14)),
          const SizedBox(height: 8),
          ...ThemeManager.customs.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Expanded(child: _themeTile(t)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: () {
                      setState(() {
                        _editingId = t.id;
                        _nameCtrl.text = t.name;
                        _cBg = t.bg;
                        _cCard = t.card;
                        _cText = t.text;
                        _cPrimary = t.primary;
                        _cSecondary = t.secondary;
                        _cAccent = t.accent;
                        _tab = 'custom';
                      });
                      _previewCustom();
                    },
                    icon: Icon(Icons.edit_rounded,
                        size: 18, color: AppColors.muted),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () async {
                      await ThemeManager.deleteCustom(t.id);
                      if (mounted) setState(() {});
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 19, color: AppColors.red),
                  ),
                ]),
              )),
        ],
      ];

  List<Widget> _transferTab() => [
        GradientCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Export / Import',
                style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
            const SizedBox(height: 6),
            Text(
                'A theme is a small JSON file. Export it to keep a backup, send it to a friend, or move it to another phone — then import it back.',
                style: TextStyle(
                    color: AppColors.muted, fontSize: 12, height: 1.45)),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _exportCurrent,
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: const Text('Export current theme'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 13)),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ThemeManager.customs.isEmpty ? null : _exportAll,
                  icon: const Icon(Icons.layers_rounded, size: 18),
                  label: const Text('Export all custom'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _import,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Paste JSON'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _importFile,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: const Text('Open saved theme file'),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Format',
                style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9)),
            const SizedBox(height: 8),
            SelectableText(
              ThemeManager.exportTheme(),
              style: TextStyle(
                  color: AppColors.text,
                  fontSize: 10.5,
                  height: 1.45,
                  fontFamily: 'monospace'),
            ),
          ]),
        ),
      ];

  Widget _colorRow(String label, Color value, ValueChanged<Color> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GradientCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: value,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.stroke),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13))),
          Text(AppPalette.hex(value),
              style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace')),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final c = await showColorPicker(context, value);
              if (c != null) onPick(c);
            },
            icon: Icon(Icons.tune_rounded, color: AppColors.teal, size: 20),
          ),
        ]),
      ),
    );
  }
}

/// A compact HSV colour picker (hue / saturation / brightness + hex entry).
Future<Color?> showColorPicker(BuildContext context, Color initial) {
  HSVColor hsv = HSVColor.fromColor(initial);
  final hexCtrl = TextEditingController(text: AppPalette.hex(initial));
  final palettes = <List<Color>>[
    [
      const Color(0xFF0B1020),
      const Color(0xFF171F3D),
      const Color(0xFF111827),
      const Color(0xFF0A0A0B),
      const Color(0xFF14113A),
      const Color(0xFF1B1750),
      const Color(0xFF052E2B),
      const Color(0xFF2E1065),
    ],
    [
      const Color(0xFFFFFFFF),
      const Color(0xFFF6F7FB),
      const Color(0xFFF1FAF6),
      const Color(0xFFFBF7F0),
      const Color(0xFFEEF1F8),
      const Color(0xFFF7F0E4),
      const Color(0xFF0F172A),
      const Color(0xFF2B2118),
    ],
    [
      const Color(0xFF6366F1),
      const Color(0xFF7C3AED),
      const Color(0xFF2DD4BF),
      const Color(0xFF0D9488),
      const Color(0xFFF59E0B),
      const Color(0xFFEC4899),
      const Color(0xFF22D3EE),
      const Color(0xFF84CC16),
    ],
  ];
  return showModalBottomSheet<Color>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) {
      final current = hsv.toColor();
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: current,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.stroke)),
                  ),
                  const SizedBox(width: 12),
                  Text('Pick a colour',
                      style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel')),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(current),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.indigo),
                    child: const Text('Use'),
                  ),
                ]),
                const SizedBox(height: 12),
                Container(
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: LinearGradient(colors: [
                      for (var i = 0; i <= 12; i++)
                        HSVColor.fromAHSV(1, (i * 30) % 360, 0.9, 0.95)
                            .toColor(),
                    ]),
                  ),
                  child: SliderTheme(
                    data: SliderTheme.of(ctx).copyWith(
                      trackHeight: 26,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.white,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 9),
                    ),
                    child: Slider(
                      value: hsv.hue,
                      min: 0,
                      max: 360,
                      onChanged: (v) => setSt(() {
                        hsv = hsv.withHue(v);
                        hexCtrl.text = AppPalette.hex(hsv.toColor());
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _sliderRow(ctx, setSt, 'Saturation', hsv.saturation, (v) {
                  hsv = hsv.withSaturation(v);
                  hexCtrl.text = AppPalette.hex(hsv.toColor());
                }),
                _sliderRow(ctx, setSt, 'Brightness', hsv.value, (v) {
                  hsv = hsv.withValue(v);
                  hexCtrl.text = AppPalette.hex(hsv.toColor());
                }),
                const SizedBox(height: 10),
                TextField(
                  controller: hexCtrl,
                  style:
                      TextStyle(color: AppColors.text, fontFamily: 'monospace'),
                  decoration: const InputDecoration(labelText: 'Hex'),
                  onSubmitted: (v) {
                    setSt(() {
                      hsv = HSVColor.fromColor(
                          AppPalette.parseHex(v, fallback: hsv.toColor()));
                    });
                  },
                ),
                const SizedBox(height: 14),
                for (final row in palettes) ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final c in row)
                      GestureDetector(
                        onTap: () => setSt(() {
                          hsv = HSVColor.fromColor(c);
                          hexCtrl.text = AppPalette.hex(c);
                        }),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: current.value == c.value
                                    ? AppColors.teal
                                    : AppColors.stroke,
                                width: current.value == c.value ? 2 : 1),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                ],
              ]),
        ),
      );
    }),
  );
}

Widget _sliderRow(BuildContext ctx, StateSetter setSt, String label,
    double value, ValueChanged<double> onChanged) {
  return Row(children: [
    SizedBox(
        width: 82,
        child: Text(label,
            style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700))),
    Expanded(
      child: Slider(
        value: value.clamp(0.0, 1.0),
        onChanged: (v) => setSt(() => onChanged(v)),
        activeColor: AppColors.teal,
        inactiveColor: AppColors.stroke,
      ),
    ),
    SizedBox(
        width: 40,
        child: Text('${(value * 100).round()}',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5))),
  ]);
}
