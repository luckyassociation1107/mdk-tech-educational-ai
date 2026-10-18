"""Android entry point, called from MainActivity via Chaquopy.

Runs the SAME textbook_video engine package on the device
(synced into this folder by tools/sync_engine_to_android.sh).
On Android, narration uses the device TextToSpeech via the Kotlin
layer for scene audio when a voice exists; otherwise the engine's
captions mode keeps the video fully watchable (see docs).
"""
import json
from pathlib import Path


def _service(data_dir: str, brain_name: str, brain_server_url: str = ""):
    import os
    import sys
    here = str(Path(__file__).resolve().parent)
    if here not in sys.path:
        sys.path.insert(0, here)
    if brain_server_url:
        os.environ["PDF_SUMMARIZER_SERVER"] = brain_server_url
    from textbook_video import ClassroomService, EngineConfig
    from textbook_video.brain.offline_brain import OfflineBrain
    from textbook_video.brain.playwright_brain import PlaywrightBrain

    cfg = EngineConfig(data_dir=Path(data_dir) / "textbook_video_data")
    brain = PlaywrightBrain(cfg) if brain_name != "offline" else OfflineBrain()
    return ClassroomService(cfg, brain)


def handle(method: str, args_json: str, data_dir: str) -> str:
    args = json.loads(args_json or "{}")
    svc = _service(data_dir, args.get("brain", "playwright"), args.get("brainServerUrl", ""))
    if method == "createSession":
        s = svc.create_session(args["pdfPath"], args.get("language", "en-IN"), args.get("grade"))
        return json.dumps({"session_id": s.id, "title": s.meta["title"],
                           "page_count": s.meta["page_count"], "brain": s.meta["brain"], "state": "active"})
    if method == "generateVideo":
        w, h = (args.get("resolution") or "1280x720").split("x")
        return json.dumps(svc.generate_video(
            args["sessionId"], args["question"], args.get("mode", "detailed_teaching"),
            width=int(w), height=int(h), theme=args.get("theme", "auto"),
            include_page_reading=bool(args.get("pageReading", False)),
            page_range=args.get("pageRange"),
            part_label=args.get("partLabel", ""), next_part_label=args.get("nextPartLabel", "")))
    if method == "chapterSeries":
        return json.dumps(svc.chapter_series(args["sessionId"], pages_per_part=int(args.get("pagesPerPart", 6))), default=str)
    if method == "completePart":
        return json.dumps(svc.complete_part(args["sessionId"], int(args["part"])), default=str)
    if method == "askChat":
        out = svc.ask_chat(args["sessionId"], args["question"])
        return json.dumps({"answer": out["answer"], "chat": out["chat"]}, default=str)
    if method == "sessionVideos":
        return json.dumps(svc.session_videos(args["sessionId"]), default=str)
    if method == "disconnect":
        return json.dumps(svc.sessions.disconnect(args["sessionId"]))
    if method == "listSessions":
        return json.dumps(svc.sessions.list_sessions(), default=str)
    raise ValueError(f"Unknown method: {method}")
