"""Typed errors with user-safe messages (spec §22)."""


class EngineError(Exception):
    code = "engine_error"
    retryable = False


class InvalidPdfError(EngineError):
    code = "invalid_pdf"


class PasswordProtectedPdfError(EngineError):
    code = "password_protected_pdf"


class BrainUnavailableError(EngineError):
    code = "brain_unavailable"
    retryable = True


class BrainExpiredError(EngineError):
    code = "brain_session_expired"
    retryable = True


class PlanValidationError(EngineError):
    code = "plan_validation_failed"


class AssetMissingError(EngineError):
    code = "asset_missing"


class TtsUnavailableError(EngineError):
    code = "tts_unavailable"


class InsufficientStorageError(EngineError):
    code = "insufficient_storage"


class RenderError(EngineError):
    code = "render_failed"


class SessionClosedError(EngineError):
    code = "session_closed"
