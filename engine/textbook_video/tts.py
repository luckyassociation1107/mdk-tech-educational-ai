"""Modular TTS (spec §15, §16).

Providers (tried in order by TTSChain, §15):
- EdgeTTS    : cloud neural voices, human-like. en-IN-NeerjaNeural,
               te-IN-ShrutiNeural (female) / te-IN-MohanNeural. No API
               key. Needs network; on failure the chain falls through.
- EspeakTTS  : espeak/espeak-ng binary if present (robotic but offline)
- CaptionsTTS: no voice available -> timed SILENT audio + captions. The
  video stays fully watchable and durations are still measured, never
  guessed by the AI. On Android the app uses the device TextToSpeech
  engine through the platform channel (see app/), which is where a
  Telugu voice, if installed on the device, is used.
Credentials are never placed in JSON or logs.
"""
from __future__ import annotations

import asyncio
import os
import re
import shutil
import subprocess
from pathlib import Path

EDGE_VOICES = {"te": "te-IN-ShrutiNeural", "hi": "hi-IN-SwaraNeural", "en": "en-IN-NeerjaNeural"}


def split_sentences(text: str):
    return [s.strip() for s in re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", text or "")) if s.strip()]


def probe_duration_seconds(ffmpeg: str, media: Path) -> float:
    p = subprocess.run([ffmpeg, "-i", str(media)], capture_output=True, text=True)
    m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", p.stderr or "")
    if not m:
        return 0.0
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))


class EdgeTTS:
    """Human-like cloud TTS (spec §15 mode 2). No API key required."""

    name = "edge"

    def __init__(self, ffmpeg: str, voice: str = "", rate: str = ""):
        self.ffmpeg = ffmpeg
        self.voice_override = voice or os.environ.get("TTS_VOICE", "")
        # Teaching pace: the default neural rate feels ~1.5x to students —
        # a real teacher speaks slowly and pauses. -20% by default.
        self.rate = rate or os.environ.get("TTS_RATE", "-20%")

    def synth(self, text: str, out_wav: Path, language: str = "en-IN") -> Path:
        out_wav, _ = self.synth_timed(text, out_wav, language)
        return out_wav

    def synth_timed(self, text: str, out_wav: Path, language: str = "en-IN"):
        """Synthesise AND return exact word timings from the voice service.

        Returns (wav_path, words) where words = [{text, start, duration}]
        in seconds. The renderer uses these so a word appears on the board
        when it is spoken — never seconds later.
        """
        import edge_tts

        voice = self.voice_override or EDGE_VOICES.get(language.lower()[:2], EDGE_VOICES["en"])
        out_wav.parent.mkdir(parents=True, exist_ok=True)
        mp3 = out_wav.with_suffix(".edge.mp3")

        # The voice service can silently end a stream early (seen in the
        # wild: a 330-char intro arrived as 2.5s of audio). NEVER accept
        # truncated narration — validate against the word timings and the
        # text length, and retry once; on continued failure raise so the
        # chain falls back to the next voice instead of shipping a scene
        # whose board writing has nothing true to sync to.
        last_error = None
        for _attempt in range(2):
            words = []

            async def _save():
                communicate = edge_tts.Communicate(text, voice, rate=self.rate, boundary="WordBoundary")
                with open(mp3, "wb") as f:
                    async for chunk in communicate.stream():
                        if chunk["type"] == "audio":
                            f.write(chunk["data"])
                        elif chunk["type"] == "WordBoundary":
                            words.append({"text": chunk["text"],
                                          "start": chunk["offset"] / 10_000_000,
                                          "duration": chunk["duration"] / 10_000_000})

            try:
                asyncio.run(_save())
                if not mp3.exists() or mp3.stat().st_size < 1000:
                    raise RuntimeError("Edge TTS returned no audio")
                subprocess.run([self.ffmpeg, "-y", "-i", str(mp3), "-ar", "44100", "-ac", "1", str(out_wav)],
                               check=True, capture_output=True)
                mp3.unlink(missing_ok=True)
                dur = probe_duration_seconds(self.ffmpeg, out_wav)
                last_word_end = max((w["start"] + w["duration"] for w in words), default=0.0)
                # at teaching pace speech is ~11 chars/s; /25 is a very
                # conservative floor that only a truncated stream can hit
                min_expected = max(0.9 * last_word_end, len(text) / 25.0)
                if dur < min_expected:
                    raise RuntimeError(
                        f"Edge TTS audio truncated ({dur:.1f}s for {len(text)} chars, "
                        f"expected >= {min_expected:.1f}s)")
                if words and dur > last_word_end + 12:
                    raise RuntimeError("Edge TTS audio over-long vs word timings")
                return out_wav, words
            except Exception as e:  # retry once, then let the chain fall back
                last_error = e
                mp3.unlink(missing_ok=True)
        raise RuntimeError(f"Edge TTS failed after retry: {last_error}")


class TTSChain:
    """Try each provider in order; report which one actually spoke."""

    def __init__(self, providers):
        self.providers = providers
        self.name = "+".join(p.name for p in providers)

    def synth(self, text: str, out_wav: Path, language: str = "en-IN") -> Path:
        errors = []
        for p in self.providers:
            try:
                p.synth(text, out_wav, language)
                self.name = p.name  # the provider that actually produced audio
                return out_wav
            except Exception as e:  # fall through to the next voice (§22)
                errors.append(f"{p.name}: {e}")
        raise RuntimeError("All TTS providers failed: " + " | ".join(errors))

    def synth_timed(self, text: str, out_wav: Path, language: str = "en-IN"):
        """Like synth, but returns word timings when the voice provides them."""
        errors = []
        for p in self.providers:
            try:
                if hasattr(p, "synth_timed"):
                    out, words = p.synth_timed(text, out_wav, language)
                    self.name = p.name
                    return out, words
                p.synth(text, out_wav, language)
                self.name = p.name
                return out_wav, None  # no timings from this provider
            except Exception as e:
                errors.append(f"{p.name}: {e}")
        raise RuntimeError("All TTS providers failed: " + " | ".join(errors))


class EspeakTTS:
    name = "espeak"

    def __init__(self, ffmpeg: str, speed_wpm: int = 140):  # calm teaching pace, not rushed
        self.ffmpeg, self.speed = ffmpeg, speed_wpm
        self.bin = shutil.which("espeak-ng") or shutil.which("espeak")

    def available(self) -> bool:
        return bool(self.bin)

    def synth(self, text: str, out_wav: Path, language: str = "en-IN") -> Path:
        voice = "te" if language.lower().startswith("te") else "en"
        out_wav.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([self.bin, "-v", voice, "-s", str(self.speed), "-w", str(out_wav), text],
                       check=True, capture_output=True)
        return out_wav


class CaptionsTTS:
    name = "captions"

    def __init__(self, ffmpeg: str, chars_per_second: float = 13.5):
        self.ffmpeg, self.cps = ffmpeg, chars_per_second

    def synth(self, text: str, out_wav: Path, language: str = "en-IN") -> Path:
        duration = max(2.5, len(text) / self.cps)
        out_wav.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([self.ffmpeg, "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
                        "-t", f"{duration:.2f}", str(out_wav)], check=True, capture_output=True)
        return out_wav


def get_tts(config, language: str = "en-IN"):
    """auto (default): Edge (human-like) -> espeak (offline) -> captions.
    Force one with TTS_MODE=edge|espeak|captions."""
    if config.tts_mode == "captions":
        return CaptionsTTS(config.ffmpeg, config.chars_per_second)
    chain = []
    if config.tts_mode in ("auto", "edge"):
        chain.append(EdgeTTS(config.ffmpeg))
    if config.tts_mode in ("auto", "espeak"):
        e = EspeakTTS(config.ffmpeg)
        if e.available():
            chain.append(e)
    chain.append(CaptionsTTS(config.ffmpeg, config.chars_per_second))
    return TTSChain(chain) if len(chain) > 1 else chain[0]
