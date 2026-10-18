"""CLI for the prototype (used by tests, demos and the Android bridge).

Examples:
  python -m textbook_video.cli demo --brain offline
  python -m textbook_video.cli create --pdf book.pdf --brain playwright
  python -m textbook_video.cli ask --session session_x --question "Explain photosynthesis with daily-life examples"
  python -m textbook_video.cli disconnect --session session_x
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import ClassroomService, EngineConfig
from .brain.offline_brain import OfflineBrain
from .brain.playwright_brain import PlaywrightBrain
from .sample_textbook import make_sample_textbook
from .session_manager import SessionManager


def _service(args) -> ClassroomService:
    cfg = EngineConfig()
    brain = PlaywrightBrain(cfg) if args.brain == "playwright" else OfflineBrain()
    return ClassroomService(cfg, brain)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="textbook-video")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("create"); p.add_argument("--pdf", required=True); p.add_argument("--brain", default="playwright", choices=["playwright", "offline"]); p.add_argument("--language", default="en-IN"); p.add_argument("--grade", type=int)
    p = sub.add_parser("ask"); p.add_argument("--session", required=True); p.add_argument("--question", required=True); p.add_argument("--brain", default="playwright", choices=["playwright", "offline"]); p.add_argument("--mode", default="detailed_teaching", choices=["quick_explanation", "detailed_teaching", "complete_concept_mastery"]); p.add_argument("--width", type=int); p.add_argument("--height", type=int); p.add_argument("--fps", type=int); p.add_argument("--theme", choices=["auto", "green_board", "black_board", "white_board", "dark_board", "light_board", "ruled_board", "graph_board"]); p.add_argument("--page-reading", action="store_true"); p.add_argument("--pages", default=""); p.add_argument("--part-label", default=""); p.add_argument("--next-part-label", default="")
    p = sub.add_parser("chat"); p.add_argument("--session", required=True); p.add_argument("--question", required=True); p.add_argument("--brain", default="playwright", choices=["playwright", "offline"])
    p = sub.add_parser("series"); p.add_argument("--session", required=True); p.add_argument("--brain", default="playwright"); p.add_argument("--pages-per-part", type=int, default=6)
    p = sub.add_parser("videos"); p.add_argument("--session", required=True); p.add_argument("--brain", default="playwright")
    p = sub.add_parser("disconnect"); p.add_argument("--session", required=True); p.add_argument("--brain", default="playwright")
    p = sub.add_parser("list")
    p = sub.add_parser("demo"); p.add_argument("--brain", default="offline", choices=["playwright", "offline"]); p.add_argument("--question", default="I do not understand photosynthesis. Explain it with daily-life examples."); p.add_argument("--mode", default="detailed_teaching")

    args = ap.parse_args(argv)

    try:
        if args.cmd == "create":
            svc = _service(args)
            s = svc.create_session(args.pdf, args.language, args.grade)
            print(json.dumps({"session_id": s.id, "title": s.meta["title"], "pages": s.meta["page_count"],
                              "brain_summary_preview": (s.meta.get("brain_summary") or "")[:300]}, indent=2, ensure_ascii=False))
        elif args.cmd == "ask":
            svc = _service(args)
            page_range = [int(x) for x in args.pages.split(",") if x.strip()] or None
            out = svc.generate_video(args.session, args.question, args.mode, width=args.width,
                                     height=args.height, fps=args.fps, theme=args.theme,
                                     include_page_reading=args.page_reading, page_range=page_range,
                                     part_label=args.part_label, next_part_label=args.next_part_label,
                                     progress=lambda s, d="": print(f"[{s}] {d}", flush=True))
            print(json.dumps(out, indent=2, ensure_ascii=False))
        elif args.cmd == "chat":
            svc = _service(args)
            out = svc.ask_chat(args.session, args.question)
            print(json.dumps({"answer": out["answer"], "messages_in_chat": len(out["chat"])}, indent=2, ensure_ascii=False))
        elif args.cmd == "series":
            svc = _service(args)
            print(json.dumps(svc.chapter_series(args.session, pages_per_part=args.pages_per_part), indent=2, ensure_ascii=False))
        elif args.cmd == "videos":
            svc = _service(args)
            print(json.dumps(svc.session_videos(args.session), indent=2, ensure_ascii=False))
        elif args.cmd == "disconnect":
            cfg = EngineConfig(); mgr = SessionManager(cfg)
            print(json.dumps(mgr.disconnect(args.session), indent=2, ensure_ascii=False))
        elif args.cmd == "list":
            cfg = EngineConfig()
            print(json.dumps(SessionManager(cfg).list_sessions(), indent=2, ensure_ascii=False))
        elif args.cmd == "demo":
            cfg = EngineConfig()
            pdf = make_sample_textbook(cfg.data_dir / "sample_textbook.pdf")
            svc = _service(args)
            s = svc.create_session(pdf, "en-IN", 10)
            print(f"Session: {s.id} | {s.meta['title']} ({s.meta['page_count']} pages)")
            out = svc.generate_video(s.id, args.question, args.mode,
                                     progress=lambda st, d="": print(f"[{st}] {d}", flush=True))
            print(json.dumps(out, indent=2, ensure_ascii=False))
            print("Exports preserved:", svc.sessions.exports_of(s.id))
            return out
    except Exception as e:
        print(f"ERROR [{type(e).__name__}]: {e}", file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
