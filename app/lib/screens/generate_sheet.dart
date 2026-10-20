import 'package:flutter/material.dart';

import '../engine_gateway.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class GenerateConfig {
  final String question;
  final String mode;
  final bool pageReading;
  const GenerateConfig(this.question, this.mode, this.pageReading);
}

Future<GenerateConfig?> showGenerateSheet(
  BuildContext context, {
  required String bookTitle,
  required SeriesPart part,
  required SeriesPart? nextPart,
  required AppSettings settings,
}) {
  return showModalBottomSheet<GenerateConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bg2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => _GenerateSheet(bookTitle: bookTitle, part: part, settings: settings),
  );
}

class _GenerateSheet extends StatefulWidget {
  final String bookTitle;
  final SeriesPart part;
  final AppSettings settings;
  const _GenerateSheet({required this.bookTitle, required this.part, required this.settings});

  @override
  State<_GenerateSheet> createState() => _GenerateSheetState();
}

class _GenerateSheetState extends State<_GenerateSheet> {
  late final TextEditingController _q;
  String _mode = 'detailed_teaching';
  bool _pageReading = true;

  @override
  void initState() {
    super.initState();
    _q = TextEditingController(
      text: 'Teach ${widget.bookTitle} — Part ${widget.part.part} (${widget.part.pageLabel}) in detail, page by page with examples',
    );
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 22),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(width: 44, height: 5, decoration: BoxDecoration(color: AppColors.stroke, borderRadius: BorderRadius.circular(99))),
        ),
        const SizedBox(height: 16),
        Text('Generate Part ${widget.part.part} class', style:  TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.text)),
        Text(widget.part.pageLabel, style:  TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        TextField(
          controller: _q,
          maxLines: 3,
          minLines: 2,
          style:  TextStyle(color: AppColors.text),
          decoration: const InputDecoration(labelText: 'What should the teacher teach?', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
         Text('Teaching depth', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: kModes.entries.map((e) {
          final selected = _mode == e.key;
          return ChoiceChip(
            label: Text(e.value),
            selected: selected,
            onSelected: (_) => setState(() => _mode = e.key),
          );
        }).toList()),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _pageReading,
          onChanged: (v) => setState(() => _pageReading = v),
          title:  Text('Read the textbook page by page', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
          subtitle:  Text('Shows each page, highlights the part being read, then writes notes.',
              style: TextStyle(color: AppColors.muted)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.stroke)),
          child: Row(children: [
             Icon(Icons.info_outline_rounded, color: AppColors.teal, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.settings.brain == 'offline'
                    ? 'On-device mode: lessons are built from the textbook text on this phone. Voice uses the device teacher voice/captions.'
                    : 'Online AI mode: the brain server in Settings will teach from this textbook. Rendering still happens on this phone.',
                style:  TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.45),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(GenerateConfig(_q.text.trim(), _mode, _pageReading)),
            icon: const Icon(Icons.auto_stories_rounded),
            label: const Text('Start my class'),
          ),
        ),
      ]),
    );
  }
}
