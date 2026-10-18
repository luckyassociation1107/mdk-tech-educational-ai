"""Orchestration: session + question -> validated plan -> local MP4 (§5, §20).

Job states follow §20. Failed jobs can be retried; the plan JSON stays in
the session workspace so a retry re-renders without re-asking the brain.
"""
from __future__ import annotations

import json
import shutil
import time
from pathlib import Path
from re import split as re_split

from . import planner
from .errors import AssetMissingError, PlanValidationError, SessionClosedError
from .pdf_processing import PdfIndex, extract_embedded_image, render_page_crop
from .schemas import VideoPlan
from .session_manager import SessionManager
from .video_engine import VideoEngine


class ClassroomService:
    def __init__(self, cfg, brain, sessions: SessionManager = None):
        self.cfg = cfg
        self.brain = brain
        self.sessions = sessions or SessionManager(cfg)
        self.engine = VideoEngine(cfg)

    def create_session(self, pdf_path, language="en-IN", grade=None):
        return self.sessions.create(pdf_path, self.brain, language, grade)

    # ---------- chat inside the same textbook session (no video) ----------
    def chapter_series(self, session_id: str, topics=None, pages_per_part: int = 6) -> dict:
        """Divide a whole chapter into sequential, unlockable parts (§5/§16).

        Parts are built from the real PDF ({pages, key points} per part)
        — never invented. Part 1 is unlocked; each finished part unlocks
        the next. `topics` optionally names sub-topics for brain requests.
        """
        session = self.sessions.get(session_id)
        index = PdfIndex.from_dict(json.loads((session.workspace / "index.json").read_text()))
        total = index.page_count
        parts = []
        p = 1
        while p <= total:
            rng = list(range(p, min(total, p + pages_per_part - 1) + 1))
            key = []
            for pg in rng:
                joined = " ".join((index.page_text(pg) or "").split())
                sents = [s.strip() for s in re_split(r"(?<=[.!?])\s+", joined)
                         if len(s.strip()) > 40 and "click here" not in s.lower()][:2]
                key.extend(sents)
            parts.append({
                "part": len(parts) + 1,
                "pages": rng,
                "key_points": [s[:220] for s in key[:6]],
                "unlocked": len(parts) == 0,   # only Part 1 starts unlocked
                "completed": False,
            })
            p += pages_per_part
        series = {"session_id": session_id, "total_pages": total,
                  "topics": topics or [], "parts": parts,
                  "brain_backbone": True}
        session.meta["chapter_series"] = series
        session.save()
        return series

    def complete_part(self, session_id: str, part: int) -> dict:
        """Mark a part finished → unlock the next part (§5 unlocking)."""
        session = self.sessions.get(session_id)
        series = session.meta.get("chapter_series") or self.chapter_series(session_id)
        for prt in series["parts"]:
            if prt["part"] == int(part):
                prt["completed"] = True
            if prt["part"] == int(part) + 1:
                prt["unlocked"] = True
        session.meta["chapter_series"] = series
        session.save()
        return series

    def ask_chat(self, session_id: str, question: str) -> dict:
        session = self.sessions.get(session_id)
        if session.state != "active":
            raise SessionClosedError("Session is closing/closed; create a new session.")
        brain, brain_session = self._brain_for(session)
        index = PdfIndex.from_dict(json.loads((session.workspace / "index.json").read_text()))
        answer = brain.ask(brain_session, question, index, session.meta.get("language", "en-IN"))
        history = session.meta.setdefault("chat", [])
        history.append({"role": "user", "content": question, "at": time.time()})
        history.append({"role": "assistant", "content": answer, "at": time.time()})
        session.save()
        chat_file = session.workspace / "chat.json"
        chat_file.write_text(json.dumps(history, indent=2, ensure_ascii=False))
        return {"answer": answer, "chat": history}

    def session_videos(self, session_id: str):
        session = self.sessions.get(session_id)
        videos = session.meta.get("videos", [])
        exports = {p.name: str(p) for p in (self.cfg.data_dir / "exports" / session_id).glob("*.mp4")} \
            if (self.cfg.data_dir / "exports" / session_id).exists() else {}
        return [{**v, "file": exports.get(f"{v['video_id']}.mp4")} for v in videos]

    def _brain_for(self, session):
        try:
            return self.sessions.brain_for(session)
        except SessionClosedError:
            stored = session.meta.get("brain_session") or {}
            if not stored:
                raise
            brain_session = {**stored, "session_id": session.id, "summary": session.meta.get("brain_summary", "")}
            self.sessions._brains[session.id] = (self.brain, brain_session)
            return self.brain, brain_session

    # ---------- assets: extract only what this video needs (§9, §18) ----------
    def _prepare_assets(self, session, index: PdfIndex, pages):
        ws = session.workspace / "assets"
        ws.mkdir(parents=True, exist_ok=True)
        asset_paths, panel_paths, ids_for_page = {}, {}, {}
        pdf = Path(session.meta["pdf_path"])
        for page in pages:
            ids_for_page.setdefault(page, [])
            # real embedded figures from this page (up to 2 — extracted on demand only, §9)
            for image_id in (index.pages[page - 1].image_ids if page <= index.page_count else [])[:2]:
                try:
                    out = extract_embedded_image(pdf, ws, image_id, index)
                except Exception:
                    out = None  # one un-extractable figure never kills the lesson
                if out:
                    asset_paths[image_id] = out
                    ids_for_page[page].append(image_id)
            # textbook panel always shows the recognisable page itself (§10)
            panel = render_page_crop(pdf, ws / f"page_{page}.png", page, zoom=1.4)
            panel_paths[page] = panel
            asset_paths[f"page_render_{page}"] = panel  # full-page reading/highlight scenes
        return asset_paths, panel_paths, ids_for_page

    # ---------- main entry ----------
    def generate_video(self, session_id: str, question: str, mode="detailed_teaching",
                       export_name=None, width=None, height=None, fps=None,
                       theme=None, panel_position="top_right", progress=lambda s, d="": None,
                       include_page_reading=False, page_range=None,
                       part_label="", next_part_label="") -> dict:
        session = self.sessions.get(session_id)
        if session.state != "active":
            raise SessionClosedError("Session is closing/closed; create a new session.")
        # Re-attach from the stored provider reference when needed (e.g. a new
        # CLI process). If the provider file expired, the brain call fails
        # honestly (§4) — it is never assumed alive forever.
        brain, brain_session = self._brain_for(session)
        ws = session.workspace
        index = PdfIndex.from_dict(json.loads((ws / "index.json").read_text()))

        progress("Analyzing textbook", question)
        content = brain.generate_lesson(brain_session, question, mode, index, session.meta.get("language", "en-IN"))
        progress("Generating lesson plan", content.title)

        pages = index.find_relevant_pages(question + " " + content.title, top=2) or [1]
        # prepare panels for cited pages, figures, and every page read aloud in series mode
        asset_pages = sorted(set(pages) | set(index.find_relevant_pages(question + " " + content.title, top=4))
                             | set(page_range or []))
        asset_paths, panel_paths, ids_for_page = self._prepare_assets(session, index, asset_pages)
        progress("Preparing assets", f"pages {pages}")

        plan = planner.build_plan(
            session_id, question, mode, content, index, ids_for_page,
            language=session.meta.get("language", "en-IN"), grade=session.meta.get("grade"),
            width=width or self.cfg.default_width, height=height or self.cfg.default_height,
            fps=fps or self.cfg.default_fps, theme=theme or self.cfg.theme,
            panel_position=panel_position,
            include_page_reading=include_page_reading, page_range=page_range,
            part_label=part_label, next_part_label=next_part_label)
        # strict validation round-trip (the plan must survive JSON -> schema)
        try:
            plan = VideoPlan.model_validate_json(plan.model_dump_json())
        except Exception as e:
            raise PlanValidationError(f"Generated plan failed schema validation: {e}") from e
        missing = plan.referenced_asset_ids() - set(asset_paths)
        # page-render assets are panels, not board assets; only embedded ids must exist
        missing = {m for m in missing if m.startswith("img_")}
        if missing:
            raise AssetMissingError(f"Plan references missing assets: {sorted(missing)}")

        plan_path = ws / "plans" / f"{plan.video_id}.json"
        plan_path.parent.mkdir(parents=True, exist_ok=True)
        plan_path.write_text(plan.model_dump_json(indent=2))

        job = {"video_id": plan.video_id, "question": question, "mode": mode, "status": "Rendering scenes",
               "plan": str(plan_path), "created_at": time.time(), "output": None, "error": None}
        session.meta.setdefault("videos", []).append(job)
        session.save()

        export_path = self.cfg.data_dir / "exports" / session_id / (export_name or f"{plan.video_id}.mp4")
        try:
            result = self.engine.render(plan, asset_paths, panel_paths, ws / f"render_{plan.video_id}",
                                        export_path, progress=progress)
            job.update(status="Completed", output=result["output"])
            result.update(video_id=plan.video_id, title=content.title, plan=str(plan_path),
                          textbook_pages=pages, job_status="Completed")
            return result
        except Exception as e:
            job.update(status="Failed", error=str(e))
            raise
        finally:
            session.save()
            # intermediate render files are eligible for immediate cleanup (§18)
            shutil.rmtree(ws / f"render_{plan.video_id}", ignore_errors=True)
