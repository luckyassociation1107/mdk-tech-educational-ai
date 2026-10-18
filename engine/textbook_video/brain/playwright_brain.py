"""Playwright brain (spec §3 with the user's chosen architecture).

The "cloud AI" is the already-built PDF Summarizer website, driven by our
Playwright automation in pdf-summarizer-automation/ :

    POST   /api/runs                upload PDF -> summary, keeps a LIVE
                                    headless session for that textbook
    POST   /api/runs/:id/chat       "Ask PDF" question in the same session
    POST   /api/runs/:id/close      ends the session / provider-side file use

Therefore this application needs NO AI API key. One run on that server ==
one isolated textbook session here (§4). The server auto-starts locally
when it is not already running.
"""
from __future__ import annotations

import json
import subprocess
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from ..errors import BrainUnavailableError
from .base import Brain, LessonContent
from .lesson_parser import LESSON_PROMPT, parse_lesson_text


class PlaywrightBrain(Brain):
    name = "playwright"

    def __init__(self, config):
        self.cfg = config
        self.base = config.brain_server_url.rstrip("/")

    # ---------- http helpers ----------
    def _req(self, method, path, data=None, ctype="application/json", timeout=60):
        body, headers = None, {}
        if data is not None:
            body = data if isinstance(data, (bytes,)) else json.dumps(data).encode()
            headers["Content-Type"] = ctype
        req = urllib.request.Request(self.base + path, data=body, method=method, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)

    def _healthy(self) -> bool:
        try:
            return bool(self._req("GET", "/api/health", timeout=4).get("ok"))
        except Exception:
            return False

    def ensure_server(self):
        if self._healthy():
            return
        project = Path(self.cfg.brain_project_dir) if self.cfg.brain_project_dir else Path(__file__).resolve().parents[4] / "pdf-summarizer-automation"
        if not (project / "server.js").exists():
            raise BrainUnavailableError(
                "Playwright brain server not found. Set PDF_SUMMARIZER_PROJECT to the pdf-summarizer-automation folder, "
                "or start it with: node server.js (in that folder).")
        if not (project / "node_modules").exists():
            raise BrainUnavailableError(
                "Brain server dependencies missing. Run: npm install && npx playwright install chromium "
                f"(in {project})")
        subprocess.Popen(["node", "server.js"], cwd=str(project),
                         env={"PATH": "/usr/local/bin:/usr/bin:/bin", "PORT": self.base.rsplit(":", 1)[-1].split("/")[0] or "3000"},
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(30):
            if self._healthy():
                return
            time.sleep(1)
        raise BrainUnavailableError("Playwright brain server did not start in time.")

    # ---------- Brain interface ----------
    def create_session(self, pdf_path, session_id, language="en-IN", grade=None):
        self.ensure_server()
        # multipart upload, mirroring our own UI's call
        boundary = "----tb" + uuid.uuid4().hex
        parts = b""
        for k, v in [("length", "detailed"), ("language", "AUTO")]:
            parts += f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n\r\n{v}\r\n".encode()
        data = Path(pdf_path).read_bytes()
        parts += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"pdf\"; filename=\"{Path(pdf_path).name}\"\r\n"
                  "Content-Type: application/pdf\r\n\r\n").encode() + data + b"\r\n"
        parts += f"--{boundary}--\r\n".encode()
        job = self._req("POST", "/api/runs", parts, ctype=f"multipart/form-data; boundary={boundary}", timeout=120)
        run_id = job["id"]
        # wait for the summary (== document analysis on that site)
        summary = ""
        for _ in range(90):
            j = self._req("GET", f"/api/runs/{run_id}")
            if j["status"] == "done":
                summary = j.get("summary") or ""
                break
            if j["status"] == "failed":
                raise BrainUnavailableError(f"Brain failed to read the PDF: {j.get('error')}")
            time.sleep(3)
        else:
            raise BrainUnavailableError("Timed out waiting for the brain to read the textbook.")
        return {"kind": "playwright", "run_id": run_id, "session_id": session_id, "summary": summary}

    def analyze(self, brain_session) -> str:
        return brain_session.get("summary", "")

    def _chat(self, run_id: str, prompt: str, timeout_loops: int = 80) -> str:
        """One Ask-PDF chat round-trip in the SAME live session (§4)."""
        self._req("POST", f"/api/runs/{run_id}/chat", {"question": prompt})
        for _ in range(timeout_loops):
            j = self._req("GET", f"/api/runs/{run_id}")
            chat = j.get("chat") or []
            if j.get("chatStatus") == "idle" and chat and chat[-1]["role"] == "assistant":
                return chat[-1]["content"]
            if j.get("chatStatus") == "idle" and chat and chat[-1]["role"] == "user":
                time.sleep(2)
            time.sleep(3)
        raise BrainUnavailableError("Timed out waiting for the brain's chat answer.")

    def ask(self, brain_session, question, index, language="en-IN") -> str:
        """Direct chat — no lesson prompt, no video. Same session, same PDF."""
        return self._chat(brain_session["run_id"],
                          f"{question}\n\nAnswer briefly and clearly for a student, using the attached textbook. "
                          f"Preferred language code: {language}. Do not invent page numbers.")

    def generate_lesson(self, brain_session, question, mode, index, language="en-IN") -> LessonContent:
        run_id = brain_session["run_id"]
        prompt = LESSON_PROMPT.format(question=question, mode=mode, language=language)
        before = self._chat(run_id, prompt)
        content = parse_lesson_text(before, question)
        # Detailed classes must actually be detailed: if the site answered
        # too briefly, ask once for a fuller teaching expansion and keep
        # whichever version teaches more. Failure keeps the first answer.
        if mode != "quick_explanation" and len(content.detailed_explanation or "") < 900:
            try:
                more = self._chat(run_id,
                                  "Expand your DETAILED EXPLANATION for the same topic into a much longer, "
                                  "slower, step-by-step classroom teaching (at least 12 sentences): define every "
                                  "term, explain why each rule works, and add identification tips. Reply with only "
                                  "the expanded explanation paragraphs, no headings.")
                if len(more) > len(content.detailed_explanation or ""):
                    content.detailed_explanation = more.strip()
            except Exception:
                pass
        if not content.summary:
            content.summary = brain_session.get("summary", "")[:600]
        return content

    def disconnect(self, brain_session) -> dict:
        try:
            self._req("POST", f"/api/runs/{brain_session['run_id']}/close", {})
            return {"provider_delete": "session_closed_on_brain_server"}
        except Exception as e:  # honest reporting, §19.13
            return {"provider_delete": f"failed: {e}"}
