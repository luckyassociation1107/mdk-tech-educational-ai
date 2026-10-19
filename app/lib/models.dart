/// Plain data models parsed from the engine bridge maps.
class TextbookItem {
  final String sessionId;
  final String title;
  final int pageCount;
  final String state;
  final String brain;
  final String subjectLabel;

  const TextbookItem({
    required this.sessionId,
    required this.title,
    required this.pageCount,
    required this.state,
    required this.brain,
    this.subjectLabel = '',
  });

  factory TextbookItem.fromMap(Map<dynamic, dynamic> m) => TextbookItem(
        sessionId: (m['session_id'] ?? m['sessionId'] ?? '').toString(),
        title: (m['title'] ?? 'Textbook').toString(),
        pageCount: (m['page_count'] as num?)?.toInt() ?? (m['pageCount'] as num?)?.toInt() ?? 0,
        state: (m['state'] ?? 'active').toString(),
        brain: (m['brain'] ?? '').toString(),
        subjectLabel: (m['subject_label'] ?? '').toString(),
      );

  String get shortTitle {
    final t = title.replaceAll(RegExp(r'\.(pdf|pmd)$', caseSensitive: false), '');
    return t.length > 42 ? '${t.substring(0, 42)}…' : t;
  }
}

class SeriesPart {
  final int part;
  final List<int> pages;
  final List<String> keyPoints;
  final bool unlocked;
  final bool completed;

  const SeriesPart({
    required this.part,
    required this.pages,
    required this.keyPoints,
    required this.unlocked,
    required this.completed,
  });

  factory SeriesPart.fromMap(Map<dynamic, dynamic> m) => SeriesPart(
        part: (m['part'] as num?)?.toInt() ?? 0,
        pages: ((m['pages'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        keyPoints: ((m['key_points'] as List?) ?? const []).map((e) => e.toString()).toList(),
        unlocked: m['unlocked'] == true,
        completed: m['completed'] == true,
      );

  String get pageLabel => pages.isEmpty ? '' : (pages.length == 1 ? 'Page ${pages.first}' : 'Pages ${pages.first}–${pages.last}');
}

class VideoItem {
  final String videoId;
  final String question;
  final String status;
  final String? file;
  final String? output;

  const VideoItem({required this.videoId, required this.question, required this.status, this.file, this.output});

  factory VideoItem.fromMap(Map<dynamic, dynamic> m) => VideoItem(
        videoId: (m['video_id'] ?? '').toString(),
        question: (m['question'] ?? '').toString(),
        status: (m['status'] ?? '').toString(),
        file: m['file']?.toString(),
        output: m['output']?.toString(),
      );

  String? get playablePath {
    if (file != null && file!.isNotEmpty) return file;
    if (output != null && output!.isNotEmpty) return output;
    return null;
  }
}

class ChatMsg {
  final String role; // user | assistant
  final String content;
  const ChatMsg(this.role, this.content);
  bool get isUser => role == 'user';
}

class CaptionLine {
  final Duration start;
  final Duration end;
  final String text;
  const CaptionLine(this.start, this.end, this.text);

  static Duration _ts(String s) {
    final p = s.trim().replaceAll(',', '.').split(':');
    if (p.length != 3) return Duration.zero;
    final sec = double.tryParse(p[2]) ?? 0;
    return Duration(hours: int.tryParse(p[0]) ?? 0, minutes: int.tryParse(p[1]) ?? 0, milliseconds: (sec * 1000).round());
  }

  static List<CaptionLine> parseSrt(String content) {
    final out = <CaptionLine>[];
    for (final block in content.split(RegExp(r'\r?\n\r?\n'))) {
      final lines = block.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
      final ti = lines.indexWhere((l) => l.contains('-->'));
      if (ti < 0 || ti + 1 >= lines.length) continue;
      final parts = lines[ti].split('-->');
      if (parts.length != 2) continue;
      out.add(CaptionLine(_ts(parts[0]), _ts(parts[1]), lines.sublist(ti + 1).join(' ')));
    }
    return out;
  }
}
