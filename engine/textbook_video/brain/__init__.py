"""Brain providers. Default: PlaywrightBrain (no API key needed)."""
from .base import Brain, LessonContent
from .offline_brain import OfflineBrain

__all__ = ["Brain", "LessonContent", "OfflineBrain"]
