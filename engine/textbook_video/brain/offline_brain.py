"""Deterministic offline brain — runs with NO network and NO API key.

Used for automated tests, CI, and as an honest fallback when the
Playwright brain site is unreachable. It composes lessons only from
sentences actually extracted from the textbook, so nothing is invented.
"""
from __future__ import annotations

import re

from .base import Brain, LessonContent


def _sentences(text: str):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", text or "")) if len(s.strip()) > 25]


class OfflineBrain(Brain):
    name = "offline"

    def create_session(self, pdf_path, session_id, language="en-IN", grade=None):
        return {"kind": "offline", "session_id": session_id}

    def analyze(self, brain_session) -> str:
        return "Offline analysis: structure derived from locally extracted textbook text."

    def ask(self, brain_session, question, index, language="en-IN") -> str:
        pages = index.find_relevant_pages(question, top=2)
        sents = []
        for pg in pages:
            sents.extend(_sentences(index.page_text(pg)))
        if not sents:
            return "This textbook does not seem to cover that topic (no matching text found locally)."
        return " ".join(sents[:4]) + f"\n\n(See textbook page {pages[0]}.)"

    def generate_lesson(self, brain_session, question, mode, index, language="en-IN") -> LessonContent:
        pages = index.find_relevant_pages(question, top=2)
        sents = []
        for pg in pages:
            sents.extend(_sentences(index.page_text(pg)))
        if not sents:
            return LessonContent(title=question, concept="NOT COVERED: no matching textbook text was found locally.",
                                 covered_by_textbook=False)
        simple = sents[0]
        detailed = " ".join(sents[:6])
        # Prefer the textbook's own chapter/section heading as the lesson title
        first_line = next((ln.strip() for ln in index.page_text(pages[0]).splitlines() if ln.strip()), "")
        heading = re.sub(r"^Chapter\s*\d+\s*[:\-]\s*", "", first_line).strip()
        lesson_title = heading[:110] if len(question) > 55 and heading else re.sub(r"\s+", " ", question).strip().capitalize()[:110]
        examples = [f"Think of this in daily life: {sents[1][0].lower() + sents[1][1:]}" ] if len(sents) > 1 else []
        return LessonContent(
            title=lesson_title,
            concept=sents[0],
            simple_explanation=simple,
            detailed_explanation=detailed,
            real_life_examples=examples,
            common_mistakes=["Reading the definition without connecting it to the diagram and examples."],
            summary=" ".join(sents[-2:]) if len(sents) > 2 else simple,
            quiz=[{"question": f"What is the main idea explained on page {pages[0]}?", "answer": sents[0][:160]}],
            covered_by_textbook=True,
            raw=detailed,
        )
