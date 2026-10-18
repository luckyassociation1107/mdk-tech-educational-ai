"""Brain interface (spec §3, §6, §14).

A "brain" turns (textbook, question) into educational lesson CONTENT.
It never renders video and never returns executable code. The local
planner converts this content into the validated JSON scene plan, and
textbook page numbers always come from local PDF search (§6: never
invent page references).
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class LessonContent:
    title: str
    summary: str = ""                      # document/topic summary from the brain
    concept: str = ""
    simple_explanation: str = ""
    detailed_explanation: str = ""
    real_life_examples: List[str] = field(default_factory=list)
    common_mistakes: List[str] = field(default_factory=list)
    worked_example: str = ""
    quiz: List[dict] = field(default_factory=list)   # [{question, answer}]
    covered_by_textbook: Optional[bool] = None       # None = unknown
    raw: str = ""


class Brain(ABC):
    name = "abstract"

    @abstractmethod
    def create_session(self, pdf_path, session_id: str, language: str = "en-IN", grade=None) -> dict:
        """Attach the PDF and return brain-session info (kept per textbook session, §4)."""

    @abstractmethod
    def analyze(self, brain_session: dict) -> str:
        """Return a structure/summary analysis of the attached textbook."""

    @abstractmethod
    def generate_lesson(self, brain_session: dict, question: str, mode: str,
                        index, language: str = "en-IN") -> LessonContent:
        """Produce lesson content for one student question."""

    def ask(self, brain_session: dict, question: str, index, language: str = "en-IN") -> str:
        """Plain chat answer inside the same textbook session (no video).
        Default: derive from a quick lesson; providers override with a
        direct chat call so no video plan is wasted on a chat question."""
        c = self.generate_lesson(brain_session, question, "quick_explanation", index, language)
        parts = [c.simple_explanation or c.concept, c.detailed_explanation, c.summary]
        return "\n\n".join(p for p in parts if p).strip()

    def disconnect(self, brain_session: dict) -> dict:
        """Best-effort provider-side cleanup (§19). Returns a status dict."""
        return {"provider_delete": "not_supported"}
