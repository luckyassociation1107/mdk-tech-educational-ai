"""AI Textbook-to-Video Classroom Designer — local Python engine.

AI (via the Playwright brain) produces educational content; this
package validates it into a JSON scene plan and renders the real MP4.
"""
from .config import EngineConfig
from .service import ClassroomService
from .session_manager import SessionManager

__all__ = ["EngineConfig", "ClassroomService", "SessionManager"]
