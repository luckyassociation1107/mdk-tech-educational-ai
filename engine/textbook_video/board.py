"""Digital teaching board renderer (spec §10, §11, §12).

Frames are drawn with Pillow and STREAMED to FFmpeg — no frame files are
kept on disk (§17, §18). All drawing ops come from the validated schema
registry; nothing executable ever arrives from the AI.
"""
from __future__ import annotations

import math
import textwrap
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
_HAND_DIR = Path(__file__).parent / "assets" / "fonts"
FONT_HAND = str(_HAND_DIR / "Kalam-Regular.ttf")   # real handwriting (teacher feel)
FONT_HAND_B = str(_HAND_DIR / "Kalam-Bold.ttf")
_fonts = {}


def font(size: int, bold=False, hand=False):
    key = (max(10, int(size)), bold, hand)
    if key not in _fonts:
        path = (FONT_HAND_B if bold else FONT_HAND) if hand else (FONT_B if bold else FONT)
        try:
            _fonts[key] = ImageFont.truetype(path, key[0])
        except Exception:
            try:
                _fonts[key] = ImageFont.truetype(FONT_B if bold else FONT, key[0])
            except Exception:
                _fonts[key] = ImageFont.load_default()
    return _fonts[key]


def wrap(draw, text, fnt, width):
    avg = max(1, int(width / max(8, fnt.size * 0.52)))
    out = []
    for para in str(text).split("\n"):
        out.extend(textwrap.wrap(para, width=avg) or [""])
    return out


THEMES = {
    # style: chalk (black/green boards) | marker (white/graph) | pen (ruled notebook)
    "green_board": dict(bg=(11, 61, 46), fg=(245, 245, 220), accent=(250, 204, 21), dim=(167, 201, 184), box=(16, 84, 62), style="chalk", pattern="chalk"),
    "black_board": dict(bg=(22, 22, 24), fg=(245, 245, 245), accent=(253, 224, 71), dim=(163, 163, 163), box=(38, 38, 40), style="chalk", pattern="chalk"),
    "dark_board": dict(bg=(15, 23, 42), fg=(241, 245, 249), accent=(45, 212, 191), dim=(148, 163, 184), box=(30, 41, 59), style="chalk", pattern="chalk"),
    "white_board": dict(bg=(252, 252, 250), fg=(17, 24, 39), accent=(220, 38, 38), dim=(100, 116, 139), box=(241, 245, 249), style="marker", pattern="white"),
    "light_board": dict(bg=(248, 250, 252), fg=(15, 23, 42), accent=(13, 148, 136), dim=(100, 116, 139), box=(226, 232, 240), style="marker", pattern="white"),
    "ruled_board": dict(bg=(255, 253, 238), fg=(30, 64, 175), accent=(220, 38, 38), dim=(147, 197, 253), box=(239, 246, 255), style="pen", pattern="ruled"),
    "graph_board": dict(bg=(248, 250, 252), fg=(15, 23, 42), accent=(37, 99, 235), dim=(148, 163, 184), box=(239, 246, 255), style="marker", pattern="graph"),
}

from .board_themes import SCENE_BOARDS  # noqa: E402  (board picked per scene in auto mode)


class BoardRenderer:
    def __init__(self, plan, asset_paths: dict, panel_paths: dict):
        self.plan = plan
        self.W, self.H = plan.video.width, plan.video.height
        self.th = THEMES.get(plan.layout.board_theme, THEMES["green_board"])
        self.assets = {k: Image.open(v).convert("RGB") for k, v in asset_paths.items() if Path(v).exists()}
        self.panels = {int(k): Image.open(v).convert("RGB") for k, v in panel_paths.items() if Path(v).exists()}
        self._timing = {}
        self._char_totals = {}

    def theme_for(self, scene):
        """Per-scene board (auto mode), else the plan's single board."""
        name = getattr(scene, "board_theme", None) or self.plan.layout.board_theme
        if name == "auto":
            name = SCENE_BOARDS.get(getattr(scene, "kind", "explanation"), "green_board")
        return THEMES.get(name, THEMES["green_board"])

    # ---------- voice-synced writing (§16) ----------
    def set_scene_timing(self, scene_id: str, duration: float, narration: str, words=None):
        """Register the REAL spoken-word timings for a scene.

        words: [{text, start, duration}] from the TTS service. Writing is
        paced by how many spoken characters have actually been uttered at
        each moment, so a word forms on the board as it is spoken.
        """
        total = sum(len(w.get("text", "")) + 1 for w in words) if words else 0
        self._timing[scene_id] = {"duration": duration, "words": words or [], "words_total": total,
                                  "narration_chars": max(1, len(narration or ""))}

    # A teacher's hand starts moving WITH the word, not after it. We give
    # writing a small head-start so text is never seen lagging the voice.
    WRITE_LEAD_SECONDS = 0.30

    def spoken_ratio(self, scene, elapsed: float) -> float:
        """Fraction of the narration actually spoken by `elapsed`.

        Counts a word PARTIALLY while it is being uttered (proportional to
        progress through the word), so handwriting flows continuously with
        the voice instead of jumping word-by-word after each word ends.
        """
        t = self._timing.get(scene.scene_id)
        if not t:
            return 0.0
        if t["words"]:
            spoken = 0.0
            for w in t["words"]:
                start = float(w.get("start", 0))
                dur = max(0.01, float(w.get("duration", 0.2)))
                n = len(w.get("text", "")) + 1
                if elapsed >= start + dur:
                    spoken += n
                elif elapsed > start:
                    spoken += n * (elapsed - start) / dur
            return max(0.0, min(1.0, spoken / max(1, t["words_total"])))
        return max(0.0, min(1.0, elapsed / max(0.01, t["duration"])))

    @staticmethod
    def _element_chars(el) -> int:
        if el.type == "textbook_image":
            return 150
        if el.type == "textbook_page":
            return 220
        if el.type == "diagram":
            return 120 + sum(len(s) for op in el.diagram for s in (op.steps or []))
        return len(el.text or "") + sum(len(i) for i in (el.items or []))

    def scene_char_total(self, scene) -> int:
        if scene.scene_id not in self._char_totals:
            self._char_totals[scene.scene_id] = max(1, sum(self._element_chars(e) for e in (scene.board_elements or [])))
        return self._char_totals[scene.scene_id]

    # ---------- layout helpers ----------
    def _panel_rect(self):
        w, h = int(self.W * 0.26), int(self.H * 0.34)
        m = int(self.W * 0.015)
        pos = self.plan.layout.textbook_panel_position.value
        x = m if "left" in pos else self.W - w - m
        y = m if "top" in pos else int(self.H * 0.52)
        return (x, y, x + w, y + h)

    def _content_rect(self):
        m = int(self.W * 0.045)
        top = int(self.H * 0.05)
        bottom = int(self.H * 0.84)  # captions live below this
        left, right = m, self.W - m
        if self.plan.layout.textbook_panel_enabled and self.panels:
            px0, py0, px1, py1 = self._panel_rect()
            pos = self.plan.layout.textbook_panel_position.value
            if "right" in pos:
                right = px0 - m
            else:
                left = px1 + m
        return (left, top, right, bottom)

    # ---------- frame ----------
    def _draw_background(self, d, th):
        W, H = self.W, self.H
        pattern = th.get("pattern")
        if pattern == "chalk":
            d.rectangle([0, 0, W - 1, H - 1], outline=(120, 72, 20), width=max(6, int(H * 0.012)))
            for gy in range(int(H * 0.12), int(H * 0.84), int(H * 0.09)):
                d.line([W * 0.03, gy, W * 0.97, gy], fill=(255, 255, 255, 14), width=1)
        elif pattern == "ruled":
            for gy in range(int(H * 0.1), int(H * 0.86), int(H * 0.072)):
                d.line([0, gy, W, gy], fill=(147, 197, 253, 130), width=1)
            d.line([W * 0.035, 0, W * 0.035, H], fill=(248, 113, 113, 170), width=2)  # notebook margin
            for hy in (int(H * 0.25), int(H * 0.5), int(H * 0.75)):
                d.ellipse([W * 0.012, hy, W * 0.012 + 14, hy + 14], outline=(148, 163, 184), width=2)
        elif pattern == "graph":
            step = max(14, int(H * 0.032))
            for gx in range(0, W, step):
                major = (gx // step) % 5 == 0
                d.line([gx, 0, gx, H], fill=(37, 99, 235, 46 if major else 20), width=2 if major else 1)
            for gy in range(0, H, step):
                major = (gy // step) % 5 == 0
                d.line([0, gy, W, gy], fill=(37, 99, 235, 46 if major else 20), width=2 if major else 1)
        elif pattern == "white":
            d.rectangle([0, H - int(H * 0.035), W, H], fill=(226, 232, 240))  # marker tray
            for i, col in enumerate([(220, 38, 38), (37, 99, 235), (22, 163, 74), (17, 24, 39)]):
                mx = W * 0.06 + i * 46
                d.rounded_rectangle([mx, H - int(H * 0.028), mx + 34, H - int(H * 0.01)], 4, fill=col)

    def frame(self, scene, elapsed: float, duration: float):
        self.th = self.theme_for(scene)
        W, H, th = self.W, self.H, self.th
        img = Image.new("RGB", (W, H), th["bg"])
        d = ImageDraw.Draw(img, "RGBA")
        self._draw_background(d, th)

        # textbook reference panel (§10) — small, aspect preserved, original recognisable.
        # Suppressed when the scene already shows the full page for reading/highlighting.
        has_full_page = any(e.type == "textbook_page" for e in (scene.board_elements or []))
        panel_img = None
        if not has_full_page and self.plan.layout.textbook_panel_enabled and scene.textbook_references:
            panel_img = self.panels.get(scene.textbook_references[0].page)
        if panel_img is not None:
            x0, y0, x1, y1 = self._panel_rect()
            d.rounded_rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 22], 10, fill=(255, 255, 255))
            fitted = panel_img.copy()
            fitted.thumbnail((x1 - x0, y1 - y0))
            img.paste(fitted, (x0 + (x1 - x0 - fitted.width) // 2, y0 + (y1 - y0 - fitted.height) // 2))
            pulse = 160 + int(80 * math.sin(elapsed * 3))
            d.rounded_rectangle([x0 - 4, y0 - 4, x1 + 4, y1 + 22], 10, outline=(*th["accent"], pulse), width=3)
            d.text((x0 + 2, y1 + 5), f"Textbook page {scene.textbook_references[0].page}",
                   font=font(H * 0.02, True), fill=(15, 23, 42))

        # board elements, written IN SYNC with the spoken words (§11, §16).
        # Two fractions: `frac` = what the voice has said (captions follow
        # this exactly); writing uses a small lead so the hand is never
        # behind the voice. Elements with a planner sync-window are written
        # exactly during their own spoken sentences.
        cx0, cy0, cx1, cy1 = self._content_rect()
        if scene.scene_id in self._timing:
            frac = self.spoken_ratio(scene, elapsed)
            write_frac = self.spoken_ratio(scene, elapsed + self.WRITE_LEAD_SECONDS)
        else:
            frac = max(0.0, min(1.0, elapsed / max(duration, 0.01)))
            write_frac = frac
        els = scene.board_elements or []
        weights = {"heading": 0.22, "textbook_image": 0.52, "textbook_page": 0.80, "diagram": 0.5}.get
        total = sum(weights(e.type, 0.34) for e in els) or 1
        budget = write_frac * self.scene_char_total(scene)
        y = cy0
        for i, el in enumerate(els):
            slot = (cy1 - cy0) * (weights(el.type, 0.34) / total)
            if el.sync_start is not None and el.sync_end is not None:
                local = max(0.0, min(1.0, (write_frac - el.sync_start) / max(0.001, el.sync_end - el.sync_start)))
            else:
                chars = self._element_chars(el)
                local = max(0.0, min(1.0, budget / chars)) if chars else write_frac
                budget -= chars
            if local > 0 or el.type == "textbook_page":
                self._draw_element(img, d, el, (cx0, y, cx1, y + slot), local, elapsed, sync_frac=frac)
            y += slot

        # captions (§15): current sentence chunk at the bottom
        if self.plan.layout.captions_enabled:
            sents = [s for s in scene.narration.replace("\n", " ").split(". ") if s]
            idx = min(len(sents) - 1, int(frac * len(sents))) if sents else 0
            cap = (sents[idx].strip() + ("." if idx < len(sents) else "")) if sents else ""
            cap_y = int(H * 0.865)
            d.rounded_rectangle([int(W * 0.03), cap_y, int(W * 0.97), H - int(H * 0.02)], 12, fill=(0, 0, 0, 165))
            lines = wrap(d, cap, font(H * 0.026), int(W * 0.9))[:2]
            for j, ln in enumerate(lines):
                tw = d.textlength(ln, font=font(H * 0.026))
                d.text(((W - tw) / 2, cap_y + 8 + j * H * 0.032), ln, font=font(H * 0.026), fill=(255, 255, 255))

        # progress indicator (§11)
        d.rectangle([0, H - 5, int(W * frac), H], fill=th["accent"])
        return img

    # ---------- human-writing helpers ----------
    def _partial(self, text, local):
        """Reveal text character-by-character, like a hand writing it."""
        n = max(0, min(len(text), int(len(text) * max(0.0, min(1.0, local)))))
        return text[:n]

    def _wavy_line(self, d, x0, x1, y, color, width=3):
        pts = []
        steps = max(2, int((x1 - x0) / 9))
        for i in range(steps + 1):
            pts.append((x0 + (x1 - x0) * i / steps, y + 2.2 * math.sin(i * 1.7)))
        d.line(pts, fill=color, width=width)

    def _draw_pen(self, d, x, y):
        """A chalk / marker / pen nib following the writing point."""
        style = self.th.get("style", "chalk")
        bob = 2.0 * math.sin(y * 0.05 + x * 0.02)
        y += bob
        if style == "chalk":
            d.polygon([(x, y), (x + 26, y + 8), (x + 22, y + 16), (x - 4, y + 8)], fill=(248, 250, 252), outline=(203, 213, 225))
            d.ellipse([x + 20, y + 2, x + 34, y + 14], fill=(254, 240, 138))  # teacher finger tip hint
        elif style == "pen":
            d.polygon([(x, y + 12), (x + 8, y - 18), (x + 17, y - 15), (x + 10, y + 14)], fill=(29, 78, 216))
            d.polygon([(x, y + 12), (x + 8, y - 2), (x + 11, y + 10)], fill=(191, 219, 254))
        else:  # marker
            d.polygon([(x, y + 12), (x + 10, y - 20), (x + 20, y - 17), (x + 12, y + 14)], fill=(17, 24, 39))
            d.polygon([(x, y + 12), (x + 9, y), (x + 13, y + 10)], fill=self.th["accent"])

    def _write_lines(self, d, lines, x, y, fnt, color, local, line_h):
        """Write wrapped lines progressively; pen follows the active line."""
        total = sum(len(ln) for ln in lines) or 1
        budget = int(total * max(0.0, min(1.0, local)))
        yy = y
        for ln in lines:
            take = max(0, min(len(ln), budget))
            part = ln[:take]
            if part:
                d.text((x, yy), part, font=fnt, fill=color)
            if take < len(ln):
                if part:
                    self._draw_pen(d, x + d.textlength(part, font=fnt) + 3, yy + fnt.size * 0.55)
                return yy
            budget -= len(ln)
            yy += line_h
        return yy

    # ---------- element drawing (approved registry only, §12) ----------
    def _draw_element(self, img, d, el, rect, local, elapsed, sync_frac=0.0):
        x0, y0, x1, y1 = [int(v) for v in rect]
        th, H = self.th, self.H
        alpha = int(255 * min(1.0, local * 1.6))

        if el.type == "heading":
            size = H * (0.046 if len(el.text or "") <= 42 else 0.037)
            lines = wrap(d, el.text or "", font(size, True, hand=True), x1 - x0)[:3]
            yy = self._write_lines(d, lines, x0, y0 + 4, font(size, True, hand=True), th["accent"], local, size * 1.22)
            if local > 0.62 and lines:  # hand-drawn underline, drawn after writing
                uw = (x1 - x0) * min(1.0, (local - 0.62) / 0.38)
                self._wavy_line(d, x0, x0 + uw, yy + size * 1.28, th["accent"], width=3)
        elif el.type in ("paragraph", "definition", "caption_note"):
            if el.type == "definition":
                d.rounded_rectangle([x0, y0 + 2, x1, y1 - 4], 12, fill=th["box"])
                x0 += 16; x1 -= 12; y0 += 10
            lines = wrap(d, el.text or "", font(H * 0.031, hand=True), x1 - x0)
            self._write_lines(d, lines, x0, y0, font(H * 0.031, hand=True), th["fg"], local, H * 0.041)
        elif el.type in ("bullet_list", "step_list"):
            yy = y0
            items = el.items[:6]
            # Reveal items by their CHARACTER share, not equal shares: a
            # long first point must not delay the second point past the
            # moment the voice reaches it (the old "text after voice" bug).
            total_chars = sum(len(it) for it in items) or 1
            spent = 0.0
            for i, it in enumerate(items):
                share = len(it) / total_chars
                item_local = max(0.0, min(1.0, (local - spent) / max(0.001, share))) if share else local
                spent += share
                if item_local <= 0:
                    break
                marker = f"{i + 1}." if el.type == "step_list" else "•"
                d.text((x0, yy), marker, font=font(H * 0.031, True, hand=True), fill=th["accent"])
                lines = wrap(d, it, font(H * 0.03, hand=True), x1 - x0 - 42)
                yy = self._write_lines(d, lines, x0 + 42, yy, font(H * 0.03, hand=True), th["fg"], item_local, H * 0.04) + H * 0.04 + 4
        elif el.type == "equation":
            txt = self._partial(el.text or "", local)
            tw = d.textlength(txt, font=font(H * 0.048, True, hand=True))
            d.text(((x0 + x1 - tw) / 2, y0 + 10), txt, font=font(H * 0.048, True, hand=True), fill=th["fg"])
            if txt and local < 1: self._draw_pen(d, (x0 + x1 + tw) / 2 + 4, y0 + 10 + H * 0.028)
        elif el.type == "table":
            yy = y0
            for row in el.items[:6]:
                d.rounded_rectangle([x0, yy, x1, yy + H * 0.045], 6, outline=th["dim"])
                d.text((x0 + 12, yy + 5), self._partial(row, local), font=font(H * 0.028, hand=True), fill=th["fg"]); yy += H * 0.052
        elif el.type == "textbook_image":
            asset = self.assets.get(el.asset_id)
            if asset is not None:
                fitted = asset.copy(); fitted.thumbnail((x1 - x0, y1 - y0))
                scale = 0.6 + 0.4 * local  # zoom_region animation
                if scale < 1:
                    fitted = fitted.resize((max(10, int(fitted.width * scale)), max(10, int(fitted.height * scale))))
                img.paste(fitted, (x0 + (x1 - x0 - fitted.width) // 2, y0 + (y1 - y0 - fitted.height) // 2))
                d.rounded_rectangle([x0, y0, x1, y1], 10, outline=th["accent"], width=2)
        elif el.type == "textbook_page":
            # Page-by-page reading with a TRUE highlight: `regions` are the
            # actual passage rectangles located in the PDF, and
            # `region_windows` say WHEN each passage is being read aloud.
            # Left: whole page with the live highlight box. Right: a
            # MAGNIFIED view of the passage being read, so the text is
            # actually readable — like a teacher pointing at the book.
            asset = self.assets.get(el.asset_id)
            if asset is not None:
                regions = el.regions or [[0.05, 0.08, 0.95, 0.30]]
                windows = el.region_windows or [[0.0, 1.0]]
                active = 0
                for i, (ws_, we_) in enumerate(windows):
                    if sync_frac >= ws_:
                        active = i
                # page overview (left ~36% of the slot)
                ow = int((x1 - x0) * 0.36)
                fitted = asset.copy(); fitted.thumbnail((ow, y1 - y0))
                px = x0 + (ow - fitted.width) // 2
                py = y0 + (y1 - y0 - fitted.height) // 2
                d.rounded_rectangle([px - 5, py - 5, px + fitted.width + 5, py + fitted.height + 5], 8, fill=(255, 255, 255))
                img.paste(fitted, (px, py))

                def to_page_px(r):
                    return (px + r[0] * fitted.width, py + r[1] * fitted.height,
                            px + r[2] * fitted.width, py + r[3] * fitted.height)

                for i, r in enumerate(regions):  # finished passages stay faintly marked
                    if i < active:
                        rx0, ry0, rx1, ry1 = to_page_px(r)
                        d.rounded_rectangle([rx0, ry0, rx1, ry1], 3, outline=(34, 197, 94, 200), width=2)
                r = regions[min(active, len(regions) - 1)]
                rx0, ry0, rx1, ry1 = to_page_px(r)
                overlay = Image.new("RGBA", (max(1, int(rx1 - rx0)), max(1, int(ry1 - ry0))), (250, 204, 21, 110))
                img.paste(overlay, (int(rx0), int(ry0)), overlay)
                pulse = 3 + int(1.5 * math.sin(elapsed * 4))
                d.rounded_rectangle([rx0 - 3, ry0 - 3, rx1 + 3, ry1 + 3], 5, outline=(220, 38, 38), width=max(3, pulse))
                d.polygon([(rx0 - 26, (ry0 + ry1) / 2), (rx0 - 10, (ry0 + ry1) / 2 - 9),
                           (rx0 - 10, (ry0 + ry1) / 2 + 9)], fill=(220, 38, 38))

                # magnified passage (right side) — the part being read NOW
                zx0, zy0, zx1, zy1 = x0 + ow + int(self.W * 0.03), y0, x1, y1
                pad_x, pad_y = 0.035, 0.030
                cx0n = max(0.0, r[0] - pad_x); cy0n = max(0.0, r[1] - pad_y)
                cx1n = min(1.0, r[2] + pad_x); cy1n = min(1.0, max(r[3] + pad_y, r[1] + 0.13))
                crop = asset.crop((int(cx0n * asset.width), int(cy0n * asset.height),
                                   int(cx1n * asset.width), int(cy1n * asset.height)))
                label_h = int(self.H * 0.045)
                avail_h = (zy1 - zy0) - label_h - 8
                crop.thumbnail((zx1 - zx0, avail_h))
                d.text((zx0, zy0), "We are reading this part:", font=font(self.H * 0.028, True, hand=True), fill=th["accent"])
                cxx = zx0 + (zx1 - zx0 - crop.width) // 2
                cyy = zy0 + label_h + (avail_h - crop.height) // 2
                d.rounded_rectangle([cxx - 5, cyy - 5, cxx + crop.width + 5, cyy + crop.height + 5], 8, fill=(255, 255, 255))
                img.paste(crop, (cxx, cyy))
                d.rounded_rectangle([cxx - 5, cyy - 5, cxx + crop.width + 5, cyy + crop.height + 5], 8,
                                    outline=(220, 38, 38), width=3)
                # the exact lines inside the zoom, highlighted as they are read
                ws_, we_ = windows[min(active, len(windows) - 1)]
                rprog = max(0.0, min(1.0, (sync_frac - ws_) / max(0.001, we_ - ws_)))
                hx0 = cxx + (r[0] - cx0n) / max(0.001, cx1n - cx0n) * crop.width
                hx1 = cxx + (r[2] - cx0n) / max(0.001, cx1n - cx0n) * crop.width
                hy0 = cyy + (r[1] - cy0n) / max(0.001, cy1n - cy0n) * crop.height
                hy1 = cyy + (r[3] - cy0n) / max(0.001, cy1n - cy0n) * crop.height
                zoverlay = Image.new("RGBA", (max(1, int(hx1 - hx0)), max(1, int(hy1 - hy0))), (250, 204, 21, 90))
                img.paste(zoverlay, (int(hx0), int(hy0)), zoverlay)
                d.line([hx0, hy1 + 6, hx0 + (hx1 - hx0) * rprog, hy1 + 6], fill=(220, 38, 38), width=4)
        elif el.type == "diagram":
            self._draw_diagram(d, el, (x0, y0, x1, y1), local)

    def _draw_diagram(self, d, el, rect, local):
        x0, y0, x1, y1 = rect
        th, H = self.th, self.H
        for op in el.diagram:
            if op.op == "process_flow":
                steps = op.steps[:4] or ["Step"]
                n = len(steps)
                bw = (x1 - x0) / (n * 1.35)
                bh = min(y1 - y0, H * 0.14)
                yy = y0 + (y1 - y0 - bh) / 2
                shown = max(1, int(n * local + 0.999))
                for i, step in enumerate(steps[:shown]):
                    bx = x0 + i * (bw * 1.35)
                    d.rounded_rectangle([bx, yy, bx + bw, yy + bh], 12, fill=th["box"], outline=th["accent"], width=2)
                    lines = wrap(d, step, font(H * 0.024, True, hand=True), bw - 14)[:3]
                    for j, ln in enumerate(lines):
                        tw = d.textlength(ln, font=font(H * 0.024, True, hand=True))
                        d.text((bx + (bw - tw) / 2, yy + 10 + j * H * 0.03), ln, font=font(H * 0.024, True, hand=True), fill=th["fg"])
                    if i < n - 1:
                        ax = bx + bw + 6
                        d.line([ax, yy + bh / 2, ax + bw * 0.35 - 12, yy + bh / 2], fill=th["accent"], width=4)
                        d.polygon([(ax + bw * 0.35 - 12, yy + bh / 2 - 7), (ax + bw * 0.35 - 12, yy + bh / 2 + 7),
                                   (ax + bw * 0.35, yy + bh / 2)], fill=th["accent"])
            elif op.op in ("line", "arrow", "connector") and len(op.points) >= 2:
                pts = [(x0 + p[0] * (x1 - x0), y0 + p[1] * (y1 - y0)) for p in op.points]
                d.line(pts, fill=th["accent"], width=3)
                if op.op == "arrow":
                    d.ellipse([pts[-1][0] - 6, pts[-1][1] - 6, pts[-1][0] + 6, pts[-1][1] + 6], fill=th["accent"])
            elif op.op == "circle" and op.points:
                cx, cy = x0 + op.points[0][0] * (x1 - x0), y0 + op.points[0][1] * (y1 - y0)
                r = H * 0.06
                d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=th["accent"], width=3)
            elif op.op in ("rectangle", "highlight_box") and op.points:
                cx, cy = x0 + op.points[0][0] * (x1 - x0), y0 + op.points[0][1] * (y1 - y0)
                d.rounded_rectangle([cx - 60, cy - 30, cx + 60, cy + 30], 8, outline=th["accent"], width=3)
            elif op.op in ("label", "text") and op.points:
                cx, cy = x0 + op.points[0][0] * (x1 - x0), y0 + op.points[0][1] * (y1 - y0)
                d.text((cx, cy), op.text or op.label or "", font=font(H * 0.024, True), fill=th["fg"])
