/// Subject-aware teaching helpers (pure Dart, fully on-device).
///
/// Whatever textbook is uploaded — maths, science, social studies,
/// English/Telugu/Hindi grammar & vocabulary, vocational trades — the
/// subject is detected from the book's own words, and the lesson
/// player then teaches in that subject's style. Everything here is
/// extractive: scenes are built from the textbook's real sentences.
/// Daily-life examples come from a small built-in bank of universal
/// classroom illustrations and are always labelled as examples, never
/// presented as textbook text.
class SubjectInfo {
  final String id; // maths | science | social | language | vocational | general
  final String label;
  const SubjectInfo(this.id, this.label);
}

class SubjectEngine {
  static const _labels = {
    'maths': 'Mathematics',
    'science': 'Science',
    'social': 'Social Studies',
    'language': 'Language • Grammar & Vocabulary',
    'vocational': 'Vocational / Trade',
    'general': 'General',
  };

  static const _keywords = <String, List<String>>{
    'maths': [
      'equation',
      'triangle',
      'angle',
      'fraction',
      'decimal',
      'algebra',
      'geometry',
      'solve',
      'theorem',
      'perimeter',
      'area of',
      'integer',
      'ratio',
      'percentage',
      'polynomial',
      'quadratic',
      'trigonometry',
      'probability',
      'mensuration',
      'arithmetic',
      'number system',
      'coordinate',
      'exponent'
    ],
    'science': [
      'experiment',
      'energy',
      'force',
      'organism',
      'cell',
      'chemical',
      'reaction',
      'photosynthesis',
      'electric current',
      'magnetic',
      'temperature',
      'acid',
      'base',
      'atom',
      'molecule',
      'gravity',
      'ecosystem',
      'nutrition',
      'respiration',
      'circuit',
      'lens',
      'sound wave',
      'friction'
    ],
    'social': [
      'century',
      'kingdom',
      'empire',
      'constitution',
      'democracy',
      'parliament',
      'freedom struggle',
      'dynasty',
      'revolution',
      'colony',
      'independence',
      'climate',
      'agriculture',
      'industry',
      'map',
      'latitude',
      'resources',
      'government',
      'citizen',
      'election',
      'river valley'
    ],
    'language': [
      'grammar',
      'verb',
      'noun',
      'pronoun',
      'adjective',
      'adverb',
      'tense',
      'sentence',
      'synonym',
      'antonym',
      'vocabulary',
      'passage',
      'poem',
      'poet',
      'author',
      'prose',
      'letter writing',
      'essay',
      'comprehension',
      'singular',
      'plural',
      'preposition',
      'conjunction',
      'voice',
      'speech'
    ],
    'vocational': [
      'workshop',
      'machine',
      'tool',
      'safety',
      'trade',
      'welding',
      'electrician',
      'fitting',
      'carpentry',
      'tailoring',
      'practical',
      'job role',
      'equipment',
      'maintenance',
      'installation',
      'wireman',
      'plumbing',
      'automobile',
      'computer fundamentals',
      'retail',
      'health care',
      'beautician',
      'agriculture work'
    ],
  };

  static SubjectInfo detect(String title, List<String> pageTexts) {
    final text =
        '${title.toLowerCase()} ${pageTexts.take(8).join(' ').toLowerCase()}';
    final scores = <String, int>{};
    _keywords.forEach((subject, words) {
      var s = 0;
      for (final w in words) {
        if (text.contains(w)) s += w.contains(' ') ? 3 : 2;
      }
      // Title words weigh the most.
      for (final w in words) {
        if (title.toLowerCase().contains(w)) s += 4;
      }
      scores[subject] = s;
    });
    // Numeric density is a strong maths signal.
    final sample = pageTexts.take(4).join(' ');
    if (sample.isNotEmpty) {
      final digits = RegExp(r'\d').allMatches(sample).length;
      if (digits / sample.length > 0.02)
        scores['maths'] = (scores['maths'] ?? 0) + 6;
      final ops = RegExp(r'[=+×÷√π%^]').allMatches(sample).length;
      if (ops > 6) scores['maths'] = (scores['maths'] ?? 0) + 5;
    }
    var best = 'general';
    var bestScore = 4; // need real evidence
    scores.forEach((k, v) {
      if (v > bestScore) {
        bestScore = v;
        best = k;
      }
    });
    return SubjectInfo(best, _labels[best]!);
  }

  static List<String> sentences(String text) => text
      .replaceAll(RegExp(r'\s+'), ' ')
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  /// Vocabulary entries from glossary-style lines in the book itself:
  /// "serene – calm and peaceful", "serene: calm", "Serene (calm)".
  static List<({String word, String meaning, String usage})> vocabWords(
      List<String> pageTexts,
      {int max = 6}) {
    final out = <({String word, String meaning, String usage})>[];
    final seen = <String>{};
    final lineRe =
        RegExp(r'^\s*([A-Za-z][A-Za-z\-]{2,24})\s*(?:–|-|:|=)\s*(.{4,90})$');
    final parenRe = RegExp(r'\b([A-Za-z][A-Za-z\-]{2,24})\s*\(([^)]{4,60})\)');
    for (final page in pageTexts) {
      for (final rawLine in page.split('\n')) {
        final line = rawLine.trim();
        String? w, m;
        final lm = lineRe.firstMatch(line);
        if (lm != null && !line.contains(RegExp(r'\d'))) {
          w = lm.group(1);
          m = lm.group(2);
        } else {
          final pm = parenRe.firstMatch(line);
          if (pm != null) {
            w = pm.group(1);
            m = pm.group(2);
          }
        }
        if (w == null || m == null) continue;
        final word = w.trim();
        final key = word.toLowerCase();
        const stop = {
          'the',
          'and',
          'for',
          'with',
          'this',
          'that',
          'from',
          'chapter',
          'unit',
          'lesson',
          'page',
          'class',
          'school'
        };
        if (stop.contains(key) || !seen.add(key)) continue;
        final usage = sentences(page).firstWhere(
            (s) => s.toLowerCase().contains(key) && s.length > 25,
            orElse: () => '');
        out.add((word: word, meaning: m.trim(), usage: usage));
        if (out.length >= max) return out;
      }
    }
    return out;
  }

  /// Grammar rule sentences: the book's own "we use / is used / always /
  /// never" style lines.
  static List<String> grammarRules(List<String> allSentences, {int max = 4}) {
    final cues = [
      'we use',
      'is used',
      'are used',
      'is formed',
      'are formed',
      'always',
      'never',
      'do not',
      'does not',
      'has to',
      'have to',
      'should',
      'must'
    ];
    final out = <String>[];
    for (final s in allSentences) {
      final t = s.toLowerCase();
      if (s.length > 30 && s.length < 220 && cues.any(t.contains)) out.add(s);
      if (out.length >= max) break;
    }
    return out;
  }

  /// Worked-example / instruction steps: sentences carrying step,
  /// first/then/next/finally, or verb-first instructions.
  static List<String> stepsFrom(List<String> allSentences, {int max = 5}) {
    final out = <String>[];
    final cue = RegExp(
        r'^(first|then|next|now|finally|step|solution|given|find|let|take|measure|cut|join|connect|draw|add|subtract|multiply|divide|check|note)',
        caseSensitive: false);
    for (final s in allSentences) {
      if (s.length > 18 &&
          s.length < 200 &&
          (cue.hasMatch(s) ||
              s.toLowerCase().contains('therefore') ||
              s.contains('='))) out.add(s);
      if (out.length >= max) break;
    }
    return out;
  }

  static List<int> yearsIn(String text) {
    final years = RegExp(r'\b(1[0-9]{3}|20[0-2][0-9])\b')
        .allMatches(text)
        .map((m) => int.parse(m.group(0)!))
        .toSet()
        .toList()
      ..sort();
    return years.take(6).toList();
  }

  /// Daily-life connect for a key point. Universal classroom examples —
  /// clearly framed AS examples; the textbook sentence stays the fact.
  static String dailyLifeFor(String subjectId, String sentence) {
    final t = sentence.toLowerCase();
    const bank = <String, String>{
      'fraction':
          'Sharing a roti, a pizza or a chocolate bar equally at home — that is this same fraction, on your plate.',
      'percentage':
          'Shop discounts and your exam marks — both are this same percentage idea you use every day.',
      'interest':
          'Money kept in a bank or borrowed from a moneylender grows exactly by this interest rule.',
      'triangle':
          'Ladder leaning on a wall, a bicycle frame, a roof — triangles hold your daily world together.',
      'area':
          'Tiling a floor, painting a wall, sowing a field — you pay and plan by this same area.',
      'photosynthesis':
          'Every plant in your home and fields is cooking its food this way, in sunlight, right now.',
      'evaporation':
          'Wet clothes drying on the line and water cooling in a clay pot — evaporation at your home.',
      'friction':
          'Bicycle brakes, matchsticks and walking without slipping — friction working for you daily.',
      'electric':
          'Torch, fan and the lights at home run on this same electric rule — respect it and stay safe.',
      'force':
          'Pushing a cart, kicking a ball, opening a door — you use this force idea all day.',
      'democracy':
          'Choosing a class leader or a panchayat member by vote — that is democracy alive near you.',
      'constitution':
          'Rules of a game everyone agrees to follow — a constitution is that rulebook for a whole country.',
      'river':
          'The stream or river near your village shapes farms, villages and trade, just like in this lesson.',
      'soil':
          'The soil in your fields decides what grows well — farmers read it exactly like this chapter.',
      'machine':
          'On the job, this same step keeps the machine, the work and YOU safe — measure twice, act once.',
      'safety':
          'Helmets, gloves and switching off power before repair — safety first, on every job, every day.',
    };
    for (final e in bank.entries) {
      if (t.contains(e.key)) return e.value;
    }
    switch (subjectId) {
      case 'maths':
        return 'Counting change at a shop, measuring rice, sharing food — the same numbers from this page work there.';
      case 'science':
        return 'Look around your home and fields today — this same idea is quietly at work there. Watch for it.';
      case 'social':
        return 'Your own village or town — its leaders, markets, water and work — runs on these same ideas.';
      case 'vocational':
        return 'At the workplace, follow these very steps in this order — that is how a skilled worker earns trust.';
      case 'language':
        return 'Use this in your own words today — speaking to a friend, writing a note, or reading a signboard.';
      default:
        return 'Connect it to your day: where have you seen this around your home or school?';
    }
  }
}

/// Lab / experiment intelligence for physics, chemistry & biology —
/// parsed from the textbook's own activity text (aim, materials,
/// procedure, observation, result), plus figure label mining.

class LabInfo {
  final String aim;
  final List<String> materials;
  final List<String> procedure;
  final List<String> observation;
  final List<String> result;
  final List<String> safety;
  const LabInfo(
      {this.aim = '',
      this.materials = const [],
      this.procedure = const [],
      this.observation = const [],
      this.result = const [],
      this.safety = const []});
  bool get isLab => procedure.isNotEmpty || aim.isNotEmpty;
}

class LabEngine2 {
  static bool looksLikeLab(List<String> sentences) {
    final t = sentences.join(' ').toLowerCase();
    final hits = [
      'experiment',
      'activity',
      'procedure',
      'observation',
      'apparatus',
      'test tube',
      'beaker',
      'aim:',
      'materials required',
      'hypothesis',
      'laboratory',
      'practical'
    ].where(t.contains).length;
    return hits >= 2;
  }

  static LabInfo parse(List<String> sentences) {
    var aim = '';
    final materials = <String>[],
        procedure = <String>[],
        observation = <String>[],
        result = <String>[],
        safety = <String>[];
    var section = '';
    for (final raw in sentences) {
      final s = raw.trim();
      final t = s.toLowerCase();
      if (t.startsWith('aim') ||
          t.contains('aim of the experiment') ||
          t.startsWith('objective')) {
        section = 'aim';
        aim = s;
        continue;
      }
      if (t.contains('materials required') ||
          t.contains('apparatus') ||
          t.startsWith('materials') ||
          t.contains('you need') ||
          t.contains('things required')) {
        section = 'materials';
        materials.add(s);
        continue;
      }
      if (t.startsWith('procedure') ||
          t.startsWith('method') ||
          t.contains('steps to follow')) {
        section = 'procedure';
        continue;
      }
      if (t.startsWith('observation') ||
          t.contains('you will observe') ||
          t.contains('we observe')) {
        section = 'observation';
        observation.add(s);
        continue;
      }
      if (t.startsWith('result') ||
          t.startsWith('conclusion') ||
          t.contains('inference')) {
        section = 'result';
        result.add(s);
        continue;
      }
      // Safety callouts need strong danger cues — ordinary procedure
      // lines ("hot water", "note carefully") stay in the procedure.
      if (RegExp(
              r'\bdo not\b|\bnever\b|warning|danger|be careful|avoid|protective|gloves|goggles|safety rules',
              caseSensitive: false)
          .hasMatch(s)) {
        safety.add(s);
        continue;
      }
      switch (section) {
        case 'materials':
          materials.add(s);
          break;
        case 'procedure':
          procedure.add(s);
          break;
        case 'observation':
          observation.add(s);
          break;
        case 'result':
          result.add(s);
          break;
      }
      // Untagged instruction lines usually belong to the procedure.
      if (section.isEmpty &&
          RegExp(r'^(take|add|pour|mix|heat|place|keep|note|record|measure|observe|repeat|fill|drop|hold|connect|switch|light|boil|cool|filter|stir)',
                  caseSensitive: false)
              .hasMatch(s)) {
        procedure.add(s);
      }
    }
    String trim(String x) => x.length > 240 ? x.substring(0, 240) : x;
    List<String> cap(List<String> l, int n) => l.map(trim).take(n).toList();
    return LabInfo(
        aim: trim(aim),
        materials: cap(materials, 4),
        procedure: cap(procedure, 8),
        observation: cap(observation, 3),
        result: cap(result, 3),
        safety: cap(safety, 3));
  }

  static String subSubjectOf(String text) {
    final t = text.toLowerCase();
    int score(String w) => w.allMatches(t).length;
    final physics = [
      'force',
      'motion',
      'velocity',
      'lens',
      'mirror',
      'circuit',
      'current',
      'magnet',
      'friction',
      'gravity',
      'pressure',
      'light',
      'sound',
      'pendulum',
      'lever',
      'energy'
    ].fold(0, (a, w) => a + score(w));
    final chemistry = [
      'acid',
      'base',
      'reaction',
      'compound',
      'element',
      'test tube',
      'solution',
      'metal',
      'salt',
      'chemical',
      'oxide',
      'atom',
      'molecule',
      'burning',
      'gas'
    ].fold(0, (a, w) => a + score(w));
    final biology = [
      'cell',
      'leaf',
      'plant',
      'organism',
      'blood',
      'heart',
      'photosynthesis',
      'animal',
      'tissue',
      'organ',
      'seed',
      'flower',
      'nutrition',
      'respiration'
    ].fold(0, (a, w) => a + score(w));
    if (physics >= chemistry && physics >= biology && physics >= 3)
      return 'physics';
    if (chemistry >= biology && chemistry >= 3) return 'chemistry';
    if (biology >= 3) return 'biology';
    return 'science';
  }
}
