"""Versioned, strict JSON schema for AI/planner video plans (spec §13).

Rules enforced here:
- only approved board-element types, diagram ops and animations (§12)
- asset references are IDs, never file paths or embedded image data
- crop coordinates are normalised 0..1
- unknown operations are rejected, never executed

Implemented with plain dataclasses (no pydantic): pydantic-core has no
Android wheel, and the SAME engine code must run on the phone via
Chaquopy. Validation behaviour is unchanged — invalid plans raise
ValueError, and plans round-trip through JSON exactly as before.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional

SCHEMA_VERSION = "1.0"

APPROVED_ANIMATIONS = {"fade_in", "reveal", "draw_line", "highlight", "pulse", "zoom_region", "move", "crossfade", "none"}
APPROVED_ELEMENTS = {"heading", "paragraph", "bullet_list", "definition", "equation", "table",
                     "textbook_image", "textbook_page", "diagram", "step_list", "caption_note"}
APPROVED_DIAGRAM_OPS = {"line", "arrow", "circle", "rectangle", "polygon", "label", "text",
                        "axis", "graph_line", "connector", "highlight_box", "process_flow"}
SCENE_KINDS = {"intro", "objectives", "concept", "explanation", "diagram", "reading", "notes", "example",
               "worked_example", "mistakes", "summary", "quiz", "revision"}
SOURCE_BASES = {"textbook", "explanation", "real_life_example", "uncertain"}


def _in(value, allowed, what):
    if value not in allowed:
        raise ValueError(f"unsupported {what}: {value!r} (approved: {sorted(allowed)})")
    return value


def _num_box(values, what, n=None):
    vals = [float(v) for v in values]
    if n is not None and len(vals) != n:
        raise ValueError(f"{what} must have {n} values")
    if any(not (0.0 <= v <= 1.0) for v in vals):
        raise ValueError(f"{what} values must be in 0..1")
    return vals


class Mode(str, Enum):
    quick = "quick_explanation"
    detailed = "detailed_teaching"
    mastery = "complete_concept_mastery"


class PanelPosition(str, Enum):
    top_left = "top_left"
    top_right = "top_right"
    bottom_left = "bottom_left"
    bottom_right = "bottom_right"


BOARD_THEMES = ["green_board", "black_board", "white_board", "dark_board", "light_board",
                "ruled_board", "graph_board"]


@dataclass
class TextbookRef:
    page: int
    image_id: Optional[str] = None
    crop: Optional[List[float]] = None  # [x0, y0, x1, y1] normalised to the page

    def __post_init__(self):
        self.page = int(self.page)
        if self.page < 1:
            raise ValueError("page must be >= 1")
        if self.crop is not None:
            self.crop = _num_box(self.crop, "crop", 4)
            if self.crop[0] >= self.crop[2] or self.crop[1] >= self.crop[3]:
                raise ValueError("crop must be [x0,y0,x1,y1] normalised 0..1 with x0<x1, y0<y1")

    def to_dict(self):
        return {"page": self.page, "image_id": self.image_id, "crop": self.crop}

    @classmethod
    def from_dict(cls, d):
        return cls(page=d["page"], image_id=d.get("image_id"), crop=d.get("crop"))


@dataclass
class DiagramOp:
    op: str
    points: List[List[float]] = field(default_factory=list)  # normalised coords
    text: Optional[str] = None
    label: Optional[str] = None
    steps: List[str] = field(default_factory=list)  # for process_flow

    def __post_init__(self):
        _in(self.op, APPROVED_DIAGRAM_OPS, "diagram op")
        self.points = [_num_box(p, "diagram points", 2) for p in self.points]

    def to_dict(self):
        return {"op": self.op, "points": self.points, "text": self.text, "label": self.label, "steps": self.steps}

    @classmethod
    def from_dict(cls, d):
        return cls(op=d["op"], points=d.get("points") or [], text=d.get("text"),
                   label=d.get("label"), steps=d.get("steps") or [])


@dataclass
class BoardElement:
    type: str
    text: Optional[str] = None
    items: List[str] = field(default_factory=list)
    asset_id: Optional[str] = None
    diagram: List[DiagramOp] = field(default_factory=list)
    animation: str = "fade_in"
    # Voice-sync window: fraction of the scene's SPOKEN narration during
    # which this element is written (0..1). Set by the planner, which knows
    # exactly where each board sentence sits inside the narration — this is
    # what keeps writing locked to the voice instead of a generic timer.
    sync_start: Optional[float] = None
    sync_end: Optional[float] = None
    # textbook_page only: REAL passage rectangles (normalised to the page)
    # located in the PDF, plus the spoken-narration window of each passage.
    regions: List[List[float]] = field(default_factory=list)
    region_windows: List[List[float]] = field(default_factory=list)

    def __post_init__(self):
        _in(self.type, APPROVED_ELEMENTS, "board element")
        _in(self.animation, APPROVED_ANIMATIONS, "animation")
        self.diagram = [op if isinstance(op, DiagramOp) else DiagramOp.from_dict(op) for op in self.diagram]
        for name in ("sync_start", "sync_end"):
            v = getattr(self, name)
            if v is not None and not (0.0 <= float(v) <= 1.0):
                raise ValueError("sync window values must be in 0..1")
        if (self.sync_start is None) != (self.sync_end is None):
            raise ValueError("sync_start and sync_end must be set together")
        if self.sync_start is not None and float(self.sync_start) >= float(self.sync_end):
            raise ValueError("sync window must satisfy sync_start < sync_end")
        self.regions = [_num_box(r, "regions", 4) for r in self.regions]
        for r in self.regions:
            if r[0] >= r[2] or r[1] >= r[3]:
                raise ValueError("regions must be [x0,y0,x1,y1] normalised 0..1 with x0<x1, y0<y1")
        self.region_windows = [_num_box(w, "region_windows", 2) for w in self.region_windows]
        for w in self.region_windows:
            if w[0] > w[1]:
                raise ValueError("region_windows must be [start,end] in 0..1")
        if len(self.regions) != len(self.region_windows):
            raise ValueError("regions and region_windows must have the same length")
        if self.type in ("textbook_image", "textbook_page") and not self.asset_id:
            raise ValueError(f"{self.type} element requires an asset_id")
        if self.asset_id and ("/" in self.asset_id or "\\" in self.asset_id or self.asset_id.startswith(".")):
            raise ValueError("asset_id must be a plain identifier, not a path")

    def to_dict(self):
        return {"type": self.type, "text": self.text, "items": self.items, "asset_id": self.asset_id,
                "diagram": [op.to_dict() for op in self.diagram], "animation": self.animation,
                "sync_start": self.sync_start, "sync_end": self.sync_end,
                "regions": self.regions, "region_windows": self.region_windows}

    @classmethod
    def from_dict(cls, d):
        return cls(type=d["type"], text=d.get("text"), items=d.get("items") or [],
                   asset_id=d.get("asset_id"), diagram=d.get("diagram") or [],
                   animation=d.get("animation", "fade_in"),
                   sync_start=d.get("sync_start"), sync_end=d.get("sync_end"),
                   regions=d.get("regions") or [], region_windows=d.get("region_windows") or [])


@dataclass
class Scene:
    scene_id: str
    title: str
    board_theme: Optional[str] = None
    kind: str = "explanation"
    narration: str = ""
    board_elements: List[BoardElement] = field(default_factory=list)
    textbook_references: List[TextbookRef] = field(default_factory=list)
    source_basis: str = "textbook"

    def __post_init__(self):
        _in(self.kind, SCENE_KINDS, "scene kind")
        _in(self.source_basis, SOURCE_BASES, "source_basis")
        if self.board_theme is not None:
            _in(self.board_theme, BOARD_THEMES, "board_theme")
        if not self.narration:
            raise ValueError("narration must not be empty")
        self.board_elements = [e if isinstance(e, BoardElement) else BoardElement.from_dict(e) for e in self.board_elements]
        self.textbook_references = [r if isinstance(r, TextbookRef) else TextbookRef.from_dict(r) for r in self.textbook_references]

    def to_dict(self):
        return {"scene_id": self.scene_id, "title": self.title, "board_theme": self.board_theme,
                "kind": self.kind, "narration": self.narration,
                "board_elements": [e.to_dict() for e in self.board_elements],
                "textbook_references": [r.to_dict() for r in self.textbook_references],
                "source_basis": self.source_basis}

    @classmethod
    def from_dict(cls, d):
        return cls(scene_id=d["scene_id"], title=d["title"], board_theme=d.get("board_theme"),
                   kind=d.get("kind", "explanation"), narration=d["narration"],
                   board_elements=d.get("board_elements") or [],
                   textbook_references=d.get("textbook_references") or [],
                   source_basis=d.get("source_basis", "textbook"))


@dataclass
class Lesson:
    title: str
    subject: str = "General"
    language: str = "en-IN"
    grade: Optional[int] = None
    mode: Mode = Mode.detailed

    def __post_init__(self):
        if not isinstance(self.mode, Mode):
            self.mode = Mode(self.mode)
        if self.grade is not None:
            self.grade = int(self.grade)

    def to_dict(self):
        return {"title": self.title, "subject": self.subject, "language": self.language,
                "grade": self.grade, "mode": self.mode.value}

    @classmethod
    def from_dict(cls, d):
        return cls(title=d["title"], subject=d.get("subject", "General"), language=d.get("language", "en-IN"),
                   grade=d.get("grade"), mode=d.get("mode", Mode.detailed.value))


@dataclass
class VideoSettings:
    width: int = 1280
    height: int = 720
    fps: int = 30

    def __post_init__(self):
        if not (320 <= int(self.width) <= 3840):
            raise ValueError("width must be in 320..3840")
        if not (240 <= int(self.height) <= 2160):
            raise ValueError("height must be in 240..2160")
        if not (5 <= int(self.fps) <= 60):
            raise ValueError("fps must be in 5..60")

    def to_dict(self):
        return {"width": self.width, "height": self.height, "fps": self.fps}

    @classmethod
    def from_dict(cls, d):
        return cls(width=d.get("width", 1280), height=d.get("height", 720), fps=d.get("fps", 30))


@dataclass
class Layout:
    textbook_panel_enabled: bool = True
    textbook_panel_position: PanelPosition = PanelPosition.top_right
    board_theme: str = "auto"
    captions_enabled: bool = True

    def __post_init__(self):
        if not isinstance(self.textbook_panel_position, PanelPosition):
            self.textbook_panel_position = PanelPosition(self.textbook_panel_position)
        _in(self.board_theme, ["auto"] + BOARD_THEMES, "board_theme")

    def to_dict(self):
        return {"textbook_panel_enabled": self.textbook_panel_enabled,
                "textbook_panel_position": self.textbook_panel_position.value,
                "board_theme": self.board_theme, "captions_enabled": self.captions_enabled}

    @classmethod
    def from_dict(cls, d):
        return cls(textbook_panel_enabled=d.get("textbook_panel_enabled", True),
                   textbook_panel_position=d.get("textbook_panel_position", "top_right"),
                   board_theme=d.get("board_theme", "auto"),
                   captions_enabled=d.get("captions_enabled", True))


@dataclass
class QuizItem:
    question: str
    answer: str

    def to_dict(self):
        return {"question": self.question, "answer": self.answer}

    @classmethod
    def from_dict(cls, d):
        return cls(question=d["question"], answer=d["answer"])


@dataclass
class VideoPlan:
    session_id: str
    video_id: str
    lesson: Lesson
    video: VideoSettings = field(default_factory=VideoSettings)
    layout: Layout = field(default_factory=Layout)
    scenes: List[Scene] = field(default_factory=list)
    quiz: List[QuizItem] = field(default_factory=list)
    asset_ids: List[str] = field(default_factory=list)
    schema_version: str = SCHEMA_VERSION

    def __post_init__(self):
        if self.schema_version != SCHEMA_VERSION:
            raise ValueError(f"unsupported schema_version: {self.schema_version!r}")
        if not isinstance(self.lesson, Lesson):
            self.lesson = Lesson.from_dict(self.lesson)
        if not isinstance(self.video, VideoSettings):
            self.video = VideoSettings.from_dict(self.video)
        if not isinstance(self.layout, Layout):
            self.layout = Layout.from_dict(self.layout)
        self.scenes = [s if isinstance(s, Scene) else Scene.from_dict(s) for s in self.scenes]
        if not self.scenes:
            raise ValueError("a plan needs at least one scene")
        self.quiz = [q if isinstance(q, QuizItem) else QuizItem.from_dict(q) for q in self.quiz]
        ids = [s.scene_id for s in self.scenes]
        if len(ids) != len(set(ids)):
            raise ValueError("scene_id values must be unique")

    def to_dict(self):
        return {"schema_version": self.schema_version, "session_id": self.session_id, "video_id": self.video_id,
                "lesson": self.lesson.to_dict(), "video": self.video.to_dict(), "layout": self.layout.to_dict(),
                "scenes": [s.to_dict() for s in self.scenes],
                "quiz": [q.to_dict() for q in self.quiz], "asset_ids": self.asset_ids}

    def model_dump_json(self, indent=None):
        """JSON of the plan (name kept for call-site compatibility)."""
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)

    @classmethod
    def from_dict(cls, d):
        return cls(session_id=d["session_id"], video_id=d["video_id"], lesson=d["lesson"],
                   video=d.get("video") or {}, layout=d.get("layout") or {},
                   scenes=d.get("scenes") or [], quiz=d.get("quiz") or [],
                   asset_ids=d.get("asset_ids") or [], schema_version=d.get("schema_version", SCHEMA_VERSION))

    @classmethod
    def model_validate(cls, d) -> "VideoPlan":
        """Validate a plan from a dict (name kept for compatibility)."""
        return cls.from_dict(d)

    @classmethod
    def model_validate_json(cls, payload: str) -> "VideoPlan":
        """Parse + validate a plan from JSON (name kept for compatibility)."""
        return cls.from_dict(json.loads(payload))

    def referenced_asset_ids(self) -> set:
        out = set(self.asset_ids)
        for s in self.scenes:
            for el in s.board_elements:
                if el.asset_id:
                    out.add(el.asset_id)
        return out
