"""Configuration from environment only — never hardcode credentials (spec §3, §23).

The default "brain" is the already-built Playwright automation that drives
https://pdf-summarizer-app-2e8ds.ondigitalocean.app/ — that website is the
cloud AI, so NO AI API key is needed in this application.
"""
import os
import shutil
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


def _ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"  # will fail loudly at render time with a clear error


@dataclass
class EngineConfig:
    data_dir: Path = field(default_factory=lambda: Path(os.environ.get("TEXTBOOK_VIDEO_DATA", Path(tempfile.gettempdir()) / "textbook_video_data")))
    brain_mode: str = field(default_factory=lambda: os.environ.get("BRAIN_MODE", "playwright"))  # playwright | offline
    brain_server_url: str = field(default_factory=lambda: os.environ.get("PDF_SUMMARIZER_SERVER", "http://127.0.0.1:3000"))
    brain_project_dir: str = field(default_factory=lambda: os.environ.get("PDF_SUMMARIZER_PROJECT", ""))
    ffmpeg: str = field(default_factory=_ffmpeg)
    default_width: int = 1280
    default_height: int = 720
    default_fps: int = 15  # rendering fps is configurable; the plan records the target fps (spec §17)
    theme: str = "auto"  # teacher moves between green/black/white/ruled/graph boards
    tts_mode: str = field(default_factory=lambda: os.environ.get("TTS_MODE", "auto"))  # auto | espeak | captions
    chars_per_second: float = 13.5  # only for captions-mode duration estimation
    max_workspace_mb: int = 500

    def ensure(self) -> "EngineConfig":
        (self.data_dir / "sessions").mkdir(parents=True, exist_ok=True)
        (self.data_dir / "exports").mkdir(parents=True, exist_ok=True)
        (self.data_dir / "cleanup_records").mkdir(parents=True, exist_ok=True)
        return self
