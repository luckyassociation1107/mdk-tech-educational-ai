"""PDF processing (spec §9).

Desktop uses PyMuPDF. On Android there is no PyMuPDF wheel, so indexing
falls back to pypdf (pure Python, shipped by Chaquopy) for text/pages and
page pictures come from the Kotlin PdfRenderer bridge
(TEXTBOOK_PAGE_PNG_DIR / `render_page_crop` Pillow fallback).
Coordinates in this module are always NORMALISED (0..1, top-left origin);
conversion from PDF points (bottom-left origin) happens exactly here.
With the pypdf fallback, block boxes are vertical estimates from
paragraph order — honest approximations, and page highlighting then uses
the same estimated bands instead of failing outright.
"""
from __future__ import annotations

import hashlib
import os
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import List, Optional

from .errors import InvalidPdfError, PasswordProtectedPdfError


@dataclass
class PageInfo:
    page: int  # 1-based
    width_pt: float
    height_pt: float
    rotation: int
    text: str
    image_ids: List[str] = field(default_factory=list)
    # text blocks in reading order: {"text": str, "bbox": [x0,y0,x1,y1] normalised}
    # — these are what make TRUE passage highlighting possible.
    blocks: List[dict] = field(default_factory=list)


@dataclass
class PdfIndex:
    document_id: str
    title: str
    page_count: int
    pages: List[PageInfo]
    # image_id -> {page, bbox_normalised, width_px, height_px, ext}
    images: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return asdict(self)

    @staticmethod
    def from_dict(d: dict) -> "PdfIndex":
        pages = [PageInfo(**p) for p in d["pages"]]
        return PdfIndex(document_id=d["document_id"], title=d["title"], page_count=d["page_count"], pages=pages, images=d.get("images", {}))

    def page_text(self, page: int) -> str:
        return self.pages[page - 1].text if 1 <= page <= self.page_count else ""

    def find_relevant_pages(self, query: str, top: int = 2) -> List[int]:
        """Deterministic keyword scoring — page numbers returned here are
        REAL pages found by searching the extracted text, never invented."""
        terms = [t for t in re.findall(r"[a-zA-Z]{3,}", query.lower()) if t not in _STOP]
        if not terms:
            return [1] if self.page_count else []
        scored = []
        for p in self.pages:
            text = p.text.lower()
            score = sum(text.count(t) * (1 + len(t) / 12.0) for t in terms)
            scored.append((score, p.page))
        scored.sort(reverse=True)
        return [pg for sc, pg in scored if sc > 0][:top] or [1]


_STOP = {"the", "and", "what", "explain", "with", "this", "that", "from", "give", "does", "how", "why",
         "please", "video", "examples", "example", "topic", "concept", "student", "question"}


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def index_pdf(pdf_path: Path) -> PdfIndex:
    if not pdf_path.exists():
        raise InvalidPdfError(f"PDF not found: {pdf_path.name}")
    try:
        import pymupdf  # noqa: F401
    except ImportError:
        return _index_pdf_pypdf(pdf_path)
    return _index_pdf_fitz(pdf_path)


def _index_pdf_fitz(pdf_path: Path) -> PdfIndex:
    import pymupdf

    try:
        doc = pymupdf.open(pdf_path)
    except Exception as e:
        raise InvalidPdfError(f"Cannot open PDF ({pdf_path.name}): {e}") from e
    if doc.needs_pass:
        raise PasswordProtectedPdfError("This PDF is password-protected. Please provide an unlocked copy.")
    if doc.page_count == 0:
        raise InvalidPdfError("This PDF has no pages.")

    title = (doc.metadata or {}).get("title") or pdf_path.stem
    pages, images = [], {}
    for i, page in enumerate(doc):
        rect = page.rect
        page_no = i + 1
        img_ids = []
        for img_idx, img in enumerate(page.get_images(full=True)):
            xref = img[0]
            try:
                pix = pymupdf.Pixmap(doc, xref)
                w, h = pix.width, pix.height
            except Exception:
                continue
            if w < 40 or h < 40:  # ignore tiny decorations/bullets
                continue
            image_id = f"img_p{page_no}_{img_idx}"
            bbox_n = None
            try:
                rects = page.get_image_rects(xref)
                if rects:
                    r = rects[0]
                    bbox_n = [r.x0 / rect.width, r.y0 / rect.height, r.x1 / rect.width, r.y1 / rect.height]
            except Exception:
                pass
            images[image_id] = {"page": page_no, "bbox_normalised": bbox_n, "width_px": w, "height_px": h, "xref": xref}
            img_ids.append(image_id)
        blocks = []
        try:
            for b in page.get_text("blocks"):
                # (x0, y0, x1, y1, text, block_no, block_type) — type 0 = text
                if len(b) >= 7 and b[6] == 0 and (b[4] or "").strip():
                    blocks.append({"text": re.sub(r"\s+", " ", b[4]).strip(),
                                   "bbox": [b[0] / rect.width, b[1] / rect.height,
                                            b[2] / rect.width, b[3] / rect.height]})
        except Exception:
            blocks = []
        blocks.sort(key=lambda bl: (round(bl["bbox"][1], 2), bl["bbox"][0]))  # reading order
        pages.append(PageInfo(page=page_no, width_pt=rect.width, height_pt=rect.height,
                              rotation=page.rotation, text=page.get_text("text") or "",
                              image_ids=img_ids, blocks=blocks))
    return PdfIndex(document_id=file_sha256(pdf_path)[:16], title=title, page_count=doc.page_count, pages=pages, images=images)


def _paragraph_blocks(text: str) -> List[dict]:
    """Estimated blocks for the pypdf fallback: paragraphs in reading
    order spread over the page height by their share of characters."""
    paras = []
    for chunk in re.split(r"\n\s*\n|\n", text or ""):
        t = re.sub(r"\s+", " ", chunk).strip()
        if len(t) >= 2:
            paras.append(t)
    if not paras:
        return []
    total = sum(len(p) for p in paras) or 1
    blocks, y = [], 0.04
    for t in paras:
        frac = max(0.03, len(t) / total * 0.9)
        y2 = 0.96 if y + frac > 0.96 else y + frac
        blocks.append({"text": t, "bbox": [0.05, round(y, 3), 0.95, round(y2, 3)]})
        y = y2 + 0.012
    return blocks


def _index_pdf_pypdf(pdf_path: Path) -> PdfIndex:
    """Android fallback: pypdf (pure Python) text extraction."""
    try:
        from pypdf import PdfReader
    except ImportError as e:
        raise InvalidPdfError(
            "This device cannot read PDFs yet (no PDF engine available). "
            "Please update the app or use the online brain mode."
        ) from e
    try:
        reader = PdfReader(str(pdf_path))
    except Exception as e:
        raise InvalidPdfError(f"Cannot open PDF ({pdf_path.name}): {e}") from e
    if reader.is_encrypted:
        raise PasswordProtectedPdfError("This PDF is password-protected. Please provide an unlocked copy.")
    if len(reader.pages) == 0:
        raise InvalidPdfError("This PDF has no pages.")

    title = pdf_path.stem
    try:
        meta_title = (reader.metadata or {}).get("/Title") if reader.metadata else None
        if meta_title:
            title = str(meta_title)
    except Exception:
        pass

    pages = []
    for i, page in enumerate(reader.pages):
        try:
            text = page.extract_text() or ""
        except Exception:
            text = ""
        try:
            box = page.mediabox
            width_pt, height_pt = float(box.width), float(box.height)
        except Exception:
            width_pt, height_pt = 595.0, 842.0
        pages.append(PageInfo(page=i + 1, width_pt=width_pt, height_pt=height_pt,
                              rotation=0, text=text, image_ids=[], blocks=_paragraph_blocks(text)))
    return PdfIndex(document_id=file_sha256(pdf_path)[:16], title=title,
                    page_count=len(pages), pages=pages, images={})


def _page_png_candidates(pdf_path: Path, page: int) -> List[Path]:
    out = []
    env_dir = os.environ.get("TEXTBOOK_PAGE_PNG_DIR") or ""
    if env_dir:
        out += [Path(env_dir) / f"page_{page}.png", Path(env_dir) / f"page_{page:02d}.png"]
    out.append(pdf_path.with_name(f"{pdf_path.stem}_pages") / f"page_{page}.png")
    return out


def render_page_crop(pdf_path: Path, out_png: Path, page: int, crop_normalised=None, zoom: float = 1.6) -> Path:
    """Render a full page or a normalised crop (top-left origin) to PNG,
    preserving aspect ratio (§9, §10). On Android, uses the PNG the
    Kotlin PdfRenderer produced and crops it with Pillow."""
    try:
        import pymupdf
    except ImportError:
        pymupdf = None
    if pymupdf is not None:
        doc = pymupdf.open(pdf_path)
        pg = doc[page - 1]
        rect = pg.rect
        if crop_normalised:
            x0, y0, x1, y1 = crop_normalised
            clip = pymupdf.Rect(rect.width * x0, rect.height * y0, rect.width * x1, rect.height * y1)
        else:
            clip = rect
        pix = pg.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), clip=clip)
        out_png.parent.mkdir(parents=True, exist_ok=True)
        pix.save(out_png)
        return out_png

    from PIL import Image

    src = next((p for p in _page_png_candidates(pdf_path, page) if p.exists()), None)
    if src is None:
        raise InvalidPdfError(
            f"Page {page} picture is not available on this device yet. "
            "Re-open the textbook so the app can prepare its pages."
        )
    img = Image.open(src).convert("RGB")
    w, h = img.size
    if crop_normalised:
        x0, y0, x1, y1 = crop_normalised
        img = img.crop((int(w * x0), int(h * y0), int(w * x1), int(h * y1)))
    out_png.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_png)
    return out_png


def extract_embedded_image(pdf_path: Path, out_dir: Path, image_id: str, index: PdfIndex) -> Optional[Path]:
    """Extract ONE embedded image on demand (§9, §18) — no bulk duplication."""
    try:
        import pymupdf
    except ImportError:
        return None  # pypdf fallback indexes carry no embedded images

    info = index.images.get(image_id)
    if not info:
        return None
    doc = pymupdf.open(pdf_path)
    pix = pymupdf.Pixmap(doc, info["xref"])
    # CMYK / ICC images cannot be saved as PNG directly — convert to RGB (§9)
    try:
        if pix.n > 3 or (pix.colorspace and pix.colorspace.name not in ("DeviceRGB", "DeviceGray")):
            pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
    except Exception:
        pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
    out = out_dir / f"{image_id}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    pix.save(out)
    return out
