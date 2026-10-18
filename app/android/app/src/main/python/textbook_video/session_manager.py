"""Session manager (spec §4, §5, §18, §19).

Layout under data_dir:
  sessions/<session_id>/session.json     minimal metadata (no textbook text)
  sessions/<session_id>/workspace/       ALL temporary assets (deleted on disconnect)
  exports/<session_id>/<video>.mp4       user-owned exports (NEVER deleted by cleanup)
  cleanup_records/<session_id>.json      minimal cleanup status record only

Cleanup is idempotent and preserves exported videos.
"""
from __future__ import annotations

import json
import shutil
import time
import uuid
from pathlib import Path

from .config import EngineConfig
from .errors import InvalidPdfError, SessionClosedError
from .pdf_processing import index_pdf


class Session:
    def __init__(self, cfg: EngineConfig, meta: dict):
        self.cfg, self.meta = cfg, meta

    @property
    def id(self):
        return self.meta["session_id"]

    @property
    def workspace(self) -> Path:
        return self.cfg.data_dir / "sessions" / self.id / "workspace"

    @property
    def state(self):
        return self.meta.get("state", "active")

    def save(self):
        p = self.cfg.data_dir / "sessions" / self.id / "session.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(self.meta, indent=2))


class SessionManager:
    def __init__(self, cfg: EngineConfig):
        self.cfg = cfg.ensure()
        self._brains = {}  # session_id -> (brain, brain_session)

    # ---------- creation ----------
    def create(self, pdf_path, brain, language="en-IN", grade=None) -> Session:
        pdf_path = Path(pdf_path)
        if not pdf_path.exists():
            raise InvalidPdfError(f"PDF not found: {pdf_path.name}")
        session_id = "session_" + uuid.uuid4().hex[:12]
        index = index_pdf(pdf_path)  # validates PDF / password (spec §22)
        meta = {
            "session_id": session_id, "document_id": index.document_id,
            "title": index.title, "page_count": index.page_count,
            "pdf_path": str(pdf_path),  # referenced, not duplicated (§18)
            "language": language, "grade": grade, "state": "active",
            "created_at": time.time(), "brain": getattr(brain, "name", "unknown"),
            "brain_session": None, "videos": [],
        }
        s = Session(self.cfg, meta)
        s.workspace.mkdir(parents=True, exist_ok=True)
        (s.workspace / "index.json").write_text(json.dumps(index.to_dict()))
        s.save()
        brain_session = brain.create_session(pdf_path, session_id, language, grade)
        meta["brain_session"] = {k: v for k, v in brain_session.items() if k != "summary"}
        meta["brain_summary"] = brain.analyze(brain_session)
        self._brains[session_id] = (brain, brain_session)
        s.save()
        return s

    def get(self, session_id: str) -> Session:
        p = self.cfg.data_dir / "sessions" / session_id / "session.json"
        if not p.exists():
            raise SessionClosedError(f"Session not found (already disconnected?): {session_id}")
        return Session(self.cfg, json.loads(p.read_text()))

    def brain_for(self, session: Session):
        if session.id in self._brains:
            return self._brains[session.id]
        raise SessionClosedError(
            "Brain session is not attached in this process (app restarted). "
            "Create a new textbook session to re-attach the PDF — the provider file is not assumed to live forever (§4).")

    def list_sessions(self):
        out = []
        for p in sorted((self.cfg.data_dir / "sessions").glob("*/session.json")):
            m = json.loads(p.read_text())
            out.append({k: m.get(k) for k in ("session_id", "title", "page_count", "state", "created_at", "brain")})
        return out

    def exports_of(self, session_id):
        d = self.cfg.data_dir / "exports" / session_id
        return [str(p) for p in d.glob("*.mp4")] if d.exists() else []

    # ---------- disconnect & cleanup (idempotent, §19) ----------
    def disconnect(self, session_id: str) -> dict:
        record_path = self.cfg.data_dir / "cleanup_records" / f"{session_id}.json"
        session_dir = self.cfg.data_dir / "sessions" / session_id
        if record_path.exists() and not session_dir.exists():
            return {"session_id": session_id, "cleanup": "already_cleaned", "exports_preserved": self.exports_of(session_id)}

        provider = {"provider_delete": "not_attached"}
        if session_id in self._brains:
            brain, brain_session = self._brains.pop(session_id)
            provider = brain.disconnect(brain_session)

        # Delete the whole temporary workspace + session metadata. Exports live elsewhere and survive.
        if session_dir.exists():
            shutil.rmtree(session_dir, ignore_errors=True)
        record = {"session_id": session_id, "cleanup": "completed", "cleaned_at": time.time(),
                  **provider, "exports_preserved": self.exports_of(session_id)}
        record_path.write_text(json.dumps(record, indent=2))
        return record

    def cleanup_stale(self, max_age_seconds: int = 24 * 3600) -> list:
        """Crash/interruption recovery on startup (§19): remove workspaces of
        sessions older than the policy window that never disconnected cleanly."""
        cleaned, now = [], time.time()
        for meta in self.list_sessions():
            if now - float(meta.get("created_at") or now) > max_age_seconds:
                cleaned.append(self.disconnect(meta["session_id"]))
        return cleaned
