"""Parse free-text brain answers into LessonContent.

The Playwright brain is a general chat AI on a website, so its reply is
text — we ask for labelled sections and parse them defensively. If labels
are missing we fall back to paragraph heuristics instead of failing.
"""
from __future__ import annotations

import re

from .base import LessonContent

SECTION_ALIASES = {
    "title": "title",
    "concept": "concept",
    "simple explanation": "simple",
    "simple": "simple",
    "detailed explanation": "detailed",
    "detailed": "detailed",
    "real-life examples": "examples",
    "real life examples": "examples",
    "examples": "examples",
    "common mistakes": "mistakes",
    "mistakes": "mistakes",
    "worked example": "worked",
    "summary": "summary",
    "quiz": "quiz",
}

LESSON_PROMPT = """Student question: {question}
Video mode: {mode}. Preferred response language code: {language}.

Teach this topic like an expert school teacher using ONLY the attached textbook first.
This will become a LONG, detailed classroom video — do NOT be brief. Explain
slowly, step by step, the way a teacher teaches a full class period: define
every new term, give the reason behind every step, connect each idea to the
previous one, and repeat the key idea in different words.
If the textbook does not cover it, start the CONCEPT section with "NOT COVERED:".

Reply in EXACTLY these labelled sections, each heading on its own line:
TITLE: <short lesson title>
CONCEPT: <core idea in 3-4 lines>
SIMPLE EXPLANATION: <simple language with a daily-life comparison, 1 paragraph>
DETAILED EXPLANATION: <very detailed teaching: at least 10-14 sentences in
several short paragraphs. Cover meaning, definitions, notation, types or
parts, how to identify them, and why each rule works. One idea per sentence.>
REAL-LIFE EXAMPLES: <3 daily-life examples, one per line starting with - >
COMMON MISTAKES: <2-3 mistakes with the correction, one per line starting with - >
WORKED EXAMPLE: <one worked example solved in 4-6 numbered steps with the final answer>
SUMMARY: <4-5 line recap of every key point>
QUIZ: <3 lines in the form Q: ... | A: ...>

Do not invent page numbers. Do not write code."""


def _bullets(block: str):
    items = [re.sub(r"^[-•*]\s*", "", ln).strip() for ln in block.splitlines() if ln.strip()]
    return [i for i in items if i and i.lower() != "none"]


def parse_lesson_text(text: str, question: str, fallback_title: str = "") -> LessonContent:
    raw = (text or "").strip()
    # some sites glue sections onto one line ("SetsCONCEPT: ...") — split them apart
    raw = re.sub(r'(?<=[a-z0-9}\)\."])\s*(TITLE|CONCEPT|SIMPLE EXPLANATION|DETAILED EXPLANATION|REAL-LIFE EXAMPLES|REAL LIFE EXAMPLES|COMMON MISTAKES|WORKED EXAMPLE|SUMMARY|QUIZ)\s*:',
                 r'\n\1:', raw)
    sections, current, buf = {}, None, []
    heading_re = re.compile(r"^\s*(TITLE|CONCEPT|SIMPLE EXPLANATION|DETAILED EXPLANATION|REAL-LIFE EXAMPLES|REAL LIFE EXAMPLES|COMMON MISTAKES|WORKED EXAMPLE|SUMMARY|QUIZ)\s*:\s*(.*)$", re.I)
    for line in raw.splitlines():
        m = heading_re.match(line)
        if m:
            if current:
                sections[current] = "\n".join(buf).strip()
            current = SECTION_ALIASES[m.group(1).lower()]
            buf = [m.group(2)] if m.group(2) else []
        elif current:
            buf.append(line)
    if current:
        sections[current] = "\n".join(buf).strip()

    if not sections:  # fallback: whole answer is the detailed explanation
        paras = [p.strip() for p in re.split(r"\n\s*\n", raw) if p.strip()]
        sections = {"detailed": raw, "simple": paras[0] if paras else "", "summary": paras[-1] if len(paras) > 1 else ""}

    quiz = []
    for ln in (sections.get("quiz") or "").splitlines():
        m = re.match(r"\s*Q\s*:\s*(.+?)\s*\|\s*A\s*:\s*(.+)", ln, re.I)
        if m:
            quiz.append({"question": m.group(1).strip(), "answer": m.group(2).strip()})

    concept = sections.get("concept", "")
    raw_title = sections.get("title") or fallback_title or question
    # sites sometimes glue sections on one line ("SetsCONCEPT: ...") — cut there
    for marker in ("CONCEPT:", "SIMPLE EXPLANATION:", "DETAILED EXPLANATION:", "SUMMARY:"):
        cut = raw_title.find(marker, 4)
        if cut > 0:
            raw_title = raw_title[:cut]
    raw_title = raw_title.rstrip(" :-")
    return LessonContent(
        title=(raw_title.strip().splitlines()[0][:90] if raw_title.strip() else question[:90]),
        concept=concept,
        simple_explanation=sections.get("simple", ""),
        detailed_explanation=sections.get("detailed", ""),
        real_life_examples=_bullets(sections.get("examples", "")),
        common_mistakes=_bullets(sections.get("mistakes", "")),
        worked_example="" if (sections.get("worked", "").strip().lower() == "none") else sections.get("worked", ""),
        summary=sections.get("summary", ""),
        quiz=quiz,
        covered_by_textbook=False if concept.upper().startswith("NOT COVERED") else None,
        raw=raw,
    )
