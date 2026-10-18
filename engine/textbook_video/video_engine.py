"""Local Python video engine (spec §17): validated JSON -> MP4.

Frames are piped to FFmpeg (streaming, bounded memory). Scene duration
is ALWAYS the measured narration duration — never the AI's guess (§16).
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from .board import BoardRenderer
from .errors import RenderError
from .schemas import VideoPlan
from .tts import get_tts, probe_duration_seconds, split_sentences

STATES = ["Preparing request", "Analyzing textbook", "Generating lesson plan", "Generating scene JSON",
          "Preparing assets", "Generating narration", "Rendering scenes", "Combining video",
          "Validating output", "Completed", "Failed", "Cancelled"]


class VideoEngine:
    def __init__(self, config):
        self.cfg = config

    def _run(self, cmd, **kw):
        p = subprocess.run(cmd, capture_output=True, text=True, **kw)
        if p.returncode != 0:
            raise RenderError(f"FFmpeg failed: {' '.join(map(str, cmd[:3]))} … {(p.stderr or '')[-400:]}")
        return p

    def render(self, plan: VideoPlan, asset_paths: dict, panel_paths: dict, workspace: Path,
               export_path: Path, progress=lambda state, detail="": None, should_continue=lambda: True) -> dict:
        ff = self.cfg.ffmpeg
        workspace.mkdir(parents=True, exist_ok=True)
        (workspace / "segments").mkdir(exist_ok=True)
        (workspace / "audio").mkdir(exist_ok=True)
        renderer = BoardRenderer(plan, asset_paths, panel_paths)
        tts = get_tts(self.cfg, plan.lesson.language)
        fps = plan.video.fps

        segments, srt_lines, elapsed_total, srt_idx = [], [], 0.0, 1
        for si, scene in enumerate(plan.scenes):
            if not should_continue():
                progress("Cancelled", scene.scene_id)
                raise RenderError("Rendering cancelled (session closing or user request).")
            progress("Generating narration", f"{scene.scene_id} via {tts.name}")
            wav = workspace / "audio" / f"{scene.scene_id}.wav"
            words = None
            if hasattr(tts, "synth_timed"):
                _, words = tts.synth_timed(scene.narration, wav, plan.lesson.language)
            else:
                tts.synth(scene.narration, wav, plan.lesson.language)
            duration = max(2.5, probe_duration_seconds(ff, wav))
            # Register REAL word timings: board writing now follows the voice.
            renderer.set_scene_timing(scene.scene_id, duration, scene.narration, words)
            # captions (SRT) timed from the REAL word timings when we have
            # them: each sentence ends when its last word is spoken (§15, §16)
            sents = split_sentences(scene.narration) or [scene.narration]
            bounds = [0.0]
            if words:
                ends, acc = [], 0
                for w in words:
                    acc += len(w.get("text", "")) + 1
                    ends.append((acc, float(w.get("start", 0)) + float(w.get("duration", 0.2))))
                acc, wi = 0, 0
                for s in sents:
                    acc += len(s) + 1
                    while wi < len(ends) - 1 and ends[wi][0] < acc:
                        wi += 1
                    bounds.append(min(duration, ends[wi][1] if ends else duration))
                bounds[-1] = duration
            else:
                per = duration / len(sents)
                bounds += [(k + 1) * per for k in range(len(sents))]
            for k, s in enumerate(sents):
                def ts(t):
                    return f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{t % 60:06.3f}".replace(".", ",")
                srt_lines.append(f"{srt_idx}\n{ts(elapsed_total + bounds[k])} --> {ts(elapsed_total + bounds[k + 1])}\n{s}\n")
                srt_idx += 1

            progress("Rendering scenes", f"{scene.scene_id} {si + 1}/{len(plan.scenes)} ({duration:.1f}s)")
            raw_seg = workspace / "segments" / f"{scene.scene_id}.video.mp4"
            seg = workspace / "segments" / f"{scene.scene_id}.mp4"
            cmd = [ff, "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{plan.video.width}x{plan.video.height}",
                   "-r", str(fps), "-i", "-", "-an", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                   "-preset", "veryfast", str(raw_seg)]
            proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                frames = max(1, int(duration * fps))
                for fi in range(frames):
                    frame = renderer.frame(scene, fi / fps, duration)
                    proc.stdin.write(frame.tobytes())
                proc.stdin.close()
                err = proc.stderr.read().decode(errors="ignore")
                if proc.wait() != 0:
                    raise RenderError(f"FFmpeg scene render failed: {err[-400:]}")
            except BrokenPipeError:
                raise RenderError("FFmpeg closed the frame pipe unexpectedly.")
            self._run([ff, "-y", "-i", str(raw_seg), "-i", str(wav), "-c:v", "copy", "-c:a", "aac",
                       "-b:a", "128k", "-t", f"{duration:.2f}", str(seg)])
            raw_seg.unlink(missing_ok=True)
            segments.append(seg)
            elapsed_total += duration

        progress("Combining video", f"{len(segments)} scenes")
        concat = workspace / "segments" / "concat.txt"
        concat.write_text("".join(f"file '{s.name}'\n" for s in segments))
        export_path.parent.mkdir(parents=True, exist_ok=True)
        # concat paths are segment-dir relative; run inside that dir for safety
        p = subprocess.run([ff, "-y", "-f", "concat", "-safe", "0", "-i", "concat.txt", "-c", "copy", str(export_path)],
                           cwd=str(workspace / "segments"), capture_output=True, text=True)
        if p.returncode != 0:
            raise RenderError(f"FFmpeg concat failed: {(p.stderr or '')[-400:]}")

        progress("Validating output", export_path.name)
        total = probe_duration_seconds(ff, export_path)
        if not export_path.exists() or export_path.stat().st_size < 10000 or total <= 0:
            raise RenderError("Output validation failed: file missing, too small, or has no duration.")
        decode = subprocess.run([ff, "-v", "error", "-i", str(export_path), "-f", "null", "-"],
                                capture_output=True, text=True)
        if decode.returncode != 0:
            raise RenderError(f"Output validation failed: FFmpeg cannot decode the video: {decode.stderr[-300:]}")
        srt_path = export_path.with_suffix(".srt")
        srt_path.write_text("\n".join(srt_lines), encoding="utf-8")
        progress("Completed", f"{total:.1f}s")
        return {"output": str(export_path), "captions": str(srt_path), "duration_seconds": round(total, 2),
                "scenes": len(plan.scenes), "tts_provider": tts.name,
                "resolution": f"{plan.video.width}x{plan.video.height}", "fps": fps}
