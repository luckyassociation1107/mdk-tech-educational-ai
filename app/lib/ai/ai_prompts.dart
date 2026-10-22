/// Default prompt templates.
///
/// Every one of these strings is editable in
/// Settings → AI & Prompts, so a teacher can tune the "custom prompts"
/// the app sends to the model without touching code. Placeholders in
/// curly braces are filled in by the app:
///
///   {start} {end}     first and last page of the batch being extracted
///   {total}           pages in the whole PDF
///   {title}           book title
///   {subject}         maths | science | social | language | vocational | general
///   {language}        explanation language asked for in Settings
///   {grade}           class / grade, when the teacher set one
///   {part}            part number of the lesson being designed
///   {pages}           pages covered by this lesson
///   {content}         the extracted textbook text of those pages
///   {figures}         the figure catalogue (page + caption + where)
class AiPrompts {
  static const String extract = '''
You are a textbook digitiser for a school classroom app.
Read the attached PDF and return ONE JSON object — no prose, no markdown fences.
Reply with the JSON only: no explanation before or after it.

Pages to return: {start} to {end} of {total}.

{
  "title": "book or chapter title",
  "subject": "maths|science|social|language|vocational|general",
  "pages": [
    {
      "page": 1,
      "text": "ALL readable body text of the page in reading order, cleaned",
      "figures": [
        {"caption": "short caption or what the figure shows",
         "where": "top|middle|bottom",
         "bbox": [0.08, 0.22, 0.94, 0.61]}
      ]
    }
  ]
}

Rules
- "text": every readable sentence of that page (headings, paragraphs,
  lists, labels, table cells). Remove running headers, footers and page
  numbers. Keep the original words exactly — never paraphrase.
- "figures": only real diagrams, photos, maps, charts, graphs or tables
  that a teacher would point at. Skip logos, rules and decorations.
- "where": roughly where the figure sits on the page — top, middle or
  bottom. This is required; it is how a text-only reader locates it.
- "bbox": OPTIONAL. Include it only if you can actually see the page
  layout. It is the tight box around the figure as fractions of the page
  width/height (0..1, origin at the TOP-LEFT corner); a figure filling the
  middle half is [0.10, 0.30, 0.90, 0.70]. Never guess these numbers —
  when in doubt, send "where" only.
- Never invent text or figures. If a page carries no readable text,
  return "" and an empty figures list.
- Return every page in the range, in order, even when it is empty.
''';

  static const String script = '''
You are an expert school teacher designing ONE video lesson for a child.
You are also the director: what is on the board must change every few seconds.

Book: {title}
Subject: {subject}
Explanation language: {language}
Class / grade: {grade}
Lesson: part {part}, pages {pages}

THE TEACHER'S OWN PROMPT FOR THIS LESSON
Every sentence you write must serve this goal.

{teacher_note}

TEXTBOOK CONTENT (extracted from the PDF — the only source of facts)
---8<---
{content}
---8<---

FIGURES YOU MAY USE (page + caption + where it sits on the page)
{figures}

DESIGN IT LIKE A CLASS, NOT A SUMMARY (three acts)
- HOOK (first 2 scenes): open with a real-life question the child has felt
  ("bus lo brake vesthe enduku munduku vongutham?"). Do not answer it yet.
- JOURNEY (middle): build step by step — concrete example first, then the
  term, then the rule or formula, then one application.
- PAYOFF (last 2 scenes): answer the opening question, then summarise.
- Never use the same "kind" three times in a row: board → quick → daily →
  steps → board → figure. The screen must keep changing.
- Give every important idea ONE memory hook: a daily-life example, a
  comparison, or a short question. Never a list of bare facts.
- Speak warmly to one child: "chudandi…", "okkasari oohinchukondi…",
  "meeku telusa…". Never say "in this video" or "as you can see".

Return ONE JSON object, no markdown fences:

{
  "scenes": [
    {"kind": "title",    "template": "T01", "heading": "చిన్న శీర్షిక", "boardText": "optional one-line subtitle", "narration": "..."},
    {"kind": "board",    "template": "T23", "heading": "board heading", "boardText": "3-6 short lines", "narration": "..."},
    {"kind": "daily",    "template": "T41", "heading": "in daily life", "boardText": "optional 2 lines", "narration": "..."},
    {"kind": "steps",    "template": "T26", "heading": "step by step", "boardText": "3-6 steps, one per line", "narration": "..."},
    {"kind": "timeline", "template": "T31", "heading": "how it happened", "boardText": "3-6 moments, one per line", "narration": "..."},
    {"kind": "compare",  "template": "T51", "heading": "two ideas", "boardText": "Left title | Right title\npoint | point\npoint | point", "narration": "..."},
    {"kind": "vocab",    "template": "T57", "heading": "the word", "boardText": "its meaning in one line", "narration": "..."},
    {"kind": "formula",  "template": "T56", "heading": "the rule", "boardText": "F = m × a", "narration": "..."},
    {"kind": "quote",    "template": "T58", "heading": "remember this", "boardText": "the sentence to remember", "extra": "who said it (optional)", "narration": "..."},
    {"kind": "figure",   "template": "T46", "heading": "figure heading", "page": 12,
                         "caption": "the caption printed in the book",
                         "where": "top|middle|bottom", "narration": "..."},
    {"kind": "quick",    "template": "T41", "heading": "quick check", "boardText": "the question",
                         "options": ["a","b","c"], "answer": "a", "narration": "..."},
    {"kind": "summary",  "template": "T29", "heading": "what we learnt", "boardText": "3-4 short lines", "narration": "..."}
  ]
}

Field rules
- 8 to 14 scenes. First scene is "title", last scene is "summary".
- narration: 35-80 words, spoken by a friendly teacher, simple sentences.
  Every scene needs it, even the title (it is what the voice says).
- boardText: at most 6 short lines (under 60 characters each), never a
  paragraph. For "compare" the lines are "left | right" with the two column
  titles on the first line. For "vocab" it is the meaning. For "quick" it is
  the question. For "quote" it is the sentence, and "extra" is the author.
- template: OPTIONAL look hint, only from T01-T60 (T01-T06 title, T07-T13
  heading, T26-T38 lists, T41-Q&A, T46 figures, T51-T54 compare, T56 formula,
  T57 vocab, T58 quote). It changes the paint, never the content. Omit it
  when unsure — never invent an id.
- "figure": ONLY for a figure listed in the catalogue above; copy its page,
  caption and "where" exactly. Never invent a page number or coordinates.
- "quick": 2-4 options, exactly one correct answer, and the answer text must
  match one option word for word.
- Teach ONLY what the textbook content says. Never add outside facts.
''';

  static const String ask = '''
You are a patient school teacher. Answer the student's question using
ONLY the textbook pages below. If the answer is not in them, say so
plainly and suggest which part of the book to read.

Textbook: {title}
Pages {pages}
---8<---
{content}
---8<---

Student question: {question}

Answer in {language}. Keep it under 180 words, use short sentences and
one daily-life example. Mark the page number where you found it.
''';

  /// Small request used by the "Test connection" button.
  static const String ping =
      'Reply with exactly this word and nothing else: READY';

  static String fill(String template, Map<String, String> values) {
    var out = template;
    values.forEach((k, v) {
      out = out.replaceAll('{$k}', v);
    });
    return out;
  }
}
