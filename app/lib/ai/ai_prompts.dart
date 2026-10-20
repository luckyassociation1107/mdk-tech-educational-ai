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
///   {figures}         the figure catalogue (page + caption + bbox)
class AiPrompts {
  static const String extract = '''
You are a textbook digitiser for a school classroom app.
Read the attached PDF and return ONE JSON object — no prose, no markdown fences.

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
  "bbox" is the tight box around the figure as fractions of the page
  width/height (0..1, origin at the TOP-LEFT corner).
  Example: a figure occupying the middle half of the page is
  [0.10, 0.30, 0.90, 0.70].
- Never invent text or figures. If a page carries no readable text,
  return "" and an empty figures list.
- Return every page in the range, in order, even when it is empty.
''';

  static const String script = '''
You are an expert school teacher designing ONE video lesson for a child.

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

FIGURES YOU MAY USE (page + tight bbox as fractions of the page, 0..1)
{figures}

Return ONE JSON object, no markdown fences:

{
  "scenes": [
    {"kind": "title",   "heading": "short title", "narration": "what the teacher says"},
    {"kind": "board",   "heading": "board heading", "boardText": "3-6 short lines", "narration": "..."},
    {"kind": "figure",  "heading": "figure heading", "page": 12, "bbox": [0.1,0.3,0.9,0.7],
                        "caption": "what it shows", "narration": "..."},
    {"kind": "quick",   "heading": "quick check", "question": "...", "options": ["a","b","c"],
                        "answer": "a", "narration": "..."},
    {"kind": "daily",   "heading": "in daily life", "narration": "..."},
    {"kind": "summary", "heading": "what we learnt", "boardText": "3-4 short lines", "narration": "..."}
  ]
}

Rules
- 8 to 14 scenes. First scene is "title", last scene is "summary".
- narration: 35-80 words, spoken by a friendly teacher. Simple English,
  keep technical words in English, explain them in the same breath.
- boardText: at most 6 short lines (under 60 characters each), never a
  paragraph — it is written on a board while the teacher speaks.
- Use "figure" only for a figure that appears in the catalogue above,
  and copy its page and bbox EXACTLY. Never invent coordinates.
- Use at least one "quick" scene with three options and one correct answer.
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
