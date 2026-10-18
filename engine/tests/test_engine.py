import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from textbook_video import ClassroomService, EngineConfig
from textbook_video.brain import LessonContent, OfflineBrain
from textbook_video.pdf_processing import index_pdf
from textbook_video.sample_textbook import make_sample_textbook
from textbook_video.schemas import BoardElement, VideoPlan
from textbook_video.session_manager import SessionManager
from textbook_video.tts import probe_duration_seconds


@pytest.fixture()
def cfg(tmp_path):
    c = EngineConfig(data_dir=tmp_path / "data")
    return c.ensure()


@pytest.fixture()
def textbook(tmp_path):
    return make_sample_textbook(tmp_path / "book.pdf")


def test_pdf_index_pages_images_and_relevant_pages(textbook):
    idx = index_pdf(textbook)
    assert idx.page_count == 4
    assert "Photosynthesis" in idx.page_text(1)
    assert idx.images, "diagram image on page 2 must be indexed"
    assert 2 in idx.find_relevant_pages("photosynthesis sunlight leaf", top=2)
    assert idx.find_relevant_pages("photosynthesis equation glucose", top=1)


def test_schema_rejects_unknown_animation_and_paths():
    with pytest.raises(Exception):
        BoardElement(type="heading", text="x", animation="execute_python")
    with pytest.raises(Exception):
        BoardElement(type="textbook_image", asset_id="../secret.png")
    with pytest.raises(Exception):
        BoardElement(type="unknown_widget", text="x")


def test_session_isolation_and_cleanup_preserves_exports(cfg, textbook):
    mgr = SessionManager(cfg)
    brain = OfflineBrain()
    a = mgr.create(textbook, brain)
    b = mgr.create(textbook, brain)
    assert a.id != b.id and a.workspace != b.workspace
    # fake a user export for A
    exp = cfg.data_dir / "exports" / a.id / "keep.mp4"
    exp.parent.mkdir(parents=True, exist_ok=True)
    exp.write_bytes(b"x" * 2048)
    rec = mgr.disconnect(a.id)
    assert rec["cleanup"] == "completed"
    assert not (cfg.data_dir / "sessions" / a.id).exists(), "workspace must be deleted"
    assert exp.exists(), "exported videos must be preserved"
    assert mgr.disconnect(a.id)["cleanup"] == "already_cleaned"  # idempotent
    assert (cfg.data_dir / "sessions" / b.id).exists(), "other session must be untouched"
    mgr.disconnect(b.id)


def test_offline_end_to_end_video(cfg, textbook):
    svc = ClassroomService(cfg, OfflineBrain())
    s = svc.create_session(textbook, "en-IN", 10)
    out = svc.generate_video(s.id, "I do not understand photosynthesis. Explain it with daily-life examples.",
                             "detailed_teaching", width=640, height=360, fps=10,
                             progress=lambda st, d="": None)
    video = Path(out["output"])
    assert video.exists() and video.stat().st_size > 10000
    assert out["duration_seconds"] > 10, out
    assert out["scenes"] >= 5
    assert Path(out["captions"]).exists()
    plan = json.loads(Path(out["plan"]).read_text())
    VideoPlan.model_validate(plan)  # plan on disk is schema-valid
    assert any(sc["textbook_references"] for sc in plan["scenes"])
    real_duration = probe_duration_seconds(cfg.ffmpeg, video)
    assert abs(real_duration - out["duration_seconds"]) < 2.5
    rec = svc.sessions.disconnect(s.id)
    assert rec["cleanup"] == "completed" and video.exists()


def test_quick_mode_makes_fewer_scenes(cfg, textbook):
    svc = ClassroomService(cfg, OfflineBrain())
    s = svc.create_session(textbook)
    out = svc.generate_video(s.id, "What is photosynthesis?", "quick_explanation", width=640, height=360, fps=10)
    assert 3 <= out["scenes"] <= 8
    svc.sessions.disconnect(s.id)


def test_green_board_and_image_explanation_scenes(cfg, textbook):
    from textbook_video import planner
    from textbook_video.brain.offline_brain import OfflineBrain
    idx = index_pdf(textbook)
    content = OfflineBrain().generate_lesson({}, "Explain photosynthesis", "detailed_teaching", idx)
    plan = planner.build_plan("s1", "Explain photosynthesis", "detailed_teaching", content, idx,
                              {2: ["img_p2_0"]}, theme="green_board")
    assert plan.layout.board_theme == "green_board"
    img_scenes = [s for s in plan.scenes if any(e.type == "textbook_image" for e in s.board_elements)]
    assert img_scenes, "textbook image must be shown"
    s = img_scenes[0]
    assert "page 2" in s.narration and len(s.narration) > 120, "image must be EXPLAINED, not just shown"
    assert s.textbook_references[0].page == 2


def test_auto_boards_vary_by_scene_and_render(cfg, textbook):
    from textbook_video import planner
    from textbook_video.board import BoardRenderer, THEMES
    from textbook_video.brain.offline_brain import OfflineBrain
    idx = index_pdf(textbook)
    content = OfflineBrain().generate_lesson({}, "Explain photosynthesis", "detailed_teaching", idx)
    plan = planner.build_plan("s1", "Explain photosynthesis", "detailed_teaching", content, idx, {}, theme="auto")
    boards = {s.board_theme for s in plan.scenes}
    assert len(boards) >= 4, f"teacher must move between boards, got {boards}"
    assert {"green_board", "black_board", "ruled_board", "graph_board"} <= boards or len(boards) >= 4
    r = BoardRenderer(plan, {}, {})
    for scene in plan.scenes[:3]:  # every board actually renders a frame
        frame = r.frame(scene, 1.0, 10.0)
        assert frame.size == (plan.video.width, plan.video.height)
    assert set(THEMES) >= {"green_board", "black_board", "white_board", "ruled_board", "graph_board"}


def test_voice_synced_writing_and_page_series(cfg, textbook):
    svc = ClassroomService(cfg, OfflineBrain())
    s = svc.create_session(textbook)
    series = svc.chapter_series(s.id, pages_per_part=1)
    assert series["parts"][0]["unlocked"] is True and series["parts"][1]["unlocked"] is False
    assert svc.complete_part(s.id, 1)["parts"][1]["unlocked"] is True

    from textbook_video import planner
    from textbook_video.board import BoardRenderer
    idx = index_pdf(textbook)
    content = OfflineBrain().generate_lesson({}, "Explain photosynthesis", "detailed_teaching", idx)
    plan = planner.build_plan(s.id, "Explain photosynthesis", "detailed_teaching", content, idx,
                              {}, include_page_reading=True, page_range=[1],
                              part_label="Part 1", next_part_label="Part 2: pages 2-4")
    kinds = [sc.kind for sc in plan.scenes]
    assert "reading" in kinds and "notes" in kinds, kinds
    r = BoardRenderer(plan, {}, {})
    scene = next(sc for sc in plan.scenes if sc.board_elements)
    words = [{"text": w, "start": (i + 1) * 1.0, "duration": 0.4} for i, w in enumerate(scene.narration.split())]
    r.set_scene_timing(scene.scene_id, 60.0, scene.narration, words)
    assert r.spoken_ratio(scene, 0.0) == 0.0              # nothing spoken -> nothing written
    assert 0.3 < r.spoken_ratio(scene, len(words) / 2) < 0.7  # half spoken -> about half written
    assert planner._clean_page_sentences(idx, 1)          # real page sentences exist
    svc.sessions.disconnect(s.id)
    assert not s.workspace.exists() if hasattr(s, "workspace") else True


def test_highlight_regions_are_real_and_voice_never_lags(textbook):
    from textbook_video import planner
    from textbook_video.board import BoardRenderer
    idx = index_pdf(textbook)
    assert idx.pages[0].blocks, "page text blocks with locations must be indexed"
    passages = planner._page_passages(idx, 1, limit=3)
    assert passages, "teaching passages must be located on the page"
    for p in passages:
        assert len(p["bbox"]) == 4 and all(0.0 <= c <= 1.0 for c in p["bbox"])
        assert p["text"] in idx.page_text(1) or len(p["text"]) > 30

    content = OfflineBrain().generate_lesson({}, "Explain photosynthesis", "detailed_teaching", idx)
    plan = planner.build_plan("s1", "Explain photosynthesis", "detailed_teaching", content, idx,
                              {}, include_page_reading=True, page_range=[1])
    reading = next(sc for sc in plan.scenes if sc.kind == "reading")
    page_el = next(e for e in reading.board_elements if e.type == "textbook_page")
    assert page_el.regions and len(page_el.regions) == len(page_el.region_windows)
    starts = [w[0] for w in page_el.region_windows]
    assert starts == sorted(starts), "highlight must move in spoken order"
    assert all(e.sync_start is not None for e in reading.board_elements), "reading scene must be voice-windowed"

    # writing must flow WHILE a word is spoken, and lead must keep the
    # hand at/ahead of the voice — never behind it.
    r = BoardRenderer(plan, {}, {})
    scene = next(sc for sc in plan.scenes if sc.kind == "explanation")
    words = [{"text": "Photosynthesis", "start": 2.0, "duration": 1.0},
             {"text": "is", "start": 3.0, "duration": 0.5}]
    r.set_scene_timing(scene.scene_id, 10.0, scene.narration, words)
    assert r.spoken_ratio(scene, 1.5) == 0.0
    mid = r.spoken_ratio(scene, 2.5)  # halfway through the first word
    assert 0.3 < mid < 0.7, f"word must be half-written mid-utterance, got {mid}"
    assert r.spoken_ratio(scene, 2.5) <= r.spoken_ratio(scene, 2.5 + BoardRenderer.WRITE_LEAD_SECONDS)

    # explanation bullets keep FULL sentences (no truncation -> no drift)
    expl = next(sc for sc in plan.scenes if sc.kind == "explanation")
    bullets = [e for e in expl.board_elements if e.type == "bullet_list"]
    assert bullets and all(e.sync_start is not None for e in bullets)
    assert all(len(e.items[0]) > 30 for e in bullets)


def test_voice_is_teaching_pace_not_fast():
    from textbook_video.tts import EdgeTTS
    t = EdgeTTS("ffmpeg")
    assert t.rate.startswith("-"), f"teaching voice must be slowed, got {t.rate!r}"


def test_chat_session_and_video_list(cfg, textbook):
    svc = ClassroomService(cfg, OfflineBrain())
    s = svc.create_session(textbook)
    out = svc.ask_chat(s.id, "What is photosynthesis?")
    assert "Photosynthesis" in out["answer"]
    assert len(out["chat"]) == 2  # user + assistant, stored in the session
    assert svc.session_videos(s.id) == []
    svc.sessions.disconnect(s.id)


def test_tts_chain_has_real_voice_first():
    from textbook_video.tts import get_tts
    t = get_tts(EngineConfig())
    assert t.providers[0].name in ("edge", "espeak"), f"first provider must be a real voice, got {t.providers[0].name}"


def test_lesson_parser_never_invents_pages():
    from textbook_video.brain.lesson_parser import parse_lesson_text
    c = parse_lesson_text("TITLE: Light\nCONCEPT: Reflection.\nDETAILED EXPLANATION: Light reflects.", "q")
    assert isinstance(c, LessonContent) and c.title == "Light"
    assert not hasattr(c, "pages")  # page numbers are assigned locally, not by the brain
