"""Convert LessonContent into a validated VideoPlan (spec §6–§8, §13).

Textbook page numbers come ONLY from local PDF text search. Images come
ONLY from the local asset registry. The brain's prose becomes scenes;
long narrations are split into multiple scenes, never truncated to fit
a guessed duration (§8, §16).
"""
from __future__ import annotations

import re
import uuid

from .brain.base import LessonContent
from .board_themes import SCENE_BOARDS
from .pdf_processing import PdfIndex
from .schemas import BoardElement, DiagramOp, Lesson, Mode, Scene, TextbookRef, VideoPlan, VideoSettings, Layout


def _sentences(text: str, limit: int = 6):
    out = [s.strip() for s in re.split(r"(?<=[.!?])\s+", re.sub(r"\s+", " ", text or "")) if s.strip()]
    return out[:limit]


def _chunks(text: str, size: int = 620):
    """Split narration into scene-sized chunks at sentence boundaries."""
    sents, out, cur = _sentences(text, limit=40), [], ""
    for s in sents:
        if len(cur) + len(s) > size and cur:
            out.append(cur.strip()); cur = s
        else:
            cur = (cur + " " + s).strip()
    if cur:
        out.append(cur.strip())
    return out or ([text.strip()] if text and text.strip() else [])


_PAGE_NOISE = ("click here", "amazon", "published", "rationalised", "textbook", "http")


def _clean_page_sentences(index, page, limit=8):
    """Real sentences from ONE textbook page (ads/headers removed)."""
    text = index.page_text(page) or ""
    lines = []
    for ln in text.splitlines():
        s = ln.strip()
        if len(s) < 12:
            continue
        low = s.lower()
        if any(n in low for n in _PAGE_NOISE):
            continue
        if s.isupper() and len(s) < 40:  # running headers
            continue
        lines.append(s)
    joined = re.sub(r"\s+", " ", " ".join(lines))
    sents = [s.strip() for s in re.split(r"(?<=[.!?])\s+", joined) if len(s.strip()) > 30]
    # prioritise teaching sentences: definitions, examples, solutions, key terms
    def score(s):
        low = s.lower()
        return sum(k in low for k in ("definition", "example", "solution", "means", "called", "set", "venn",
                                      "union", "intersection", "subset", "element", "diagram", "note"))
    sents.sort(key=score, reverse=True)
    return sents[:limit]


def _norm_words(s: str):
    return re.findall(r"[a-z0-9]+", (s or "").lower())


def _page_passages(index, page, limit=4):
    """Teaching passages from ONE page, each with its REAL location.

    Sentences are taken from the page's text blocks, so every passage has
    a true bbox on the page — that is what the highlight box draws.
    Returned in reading order (top-to-bottom), best teaching lines first
    chosen, then re-sorted into reading order.
    """
    info = index.pages[page - 1] if 1 <= page <= index.page_count else None
    if info is None:
        return []
    cands = []
    for bl in (info.blocks or []):
        text = bl.get("text", "")
        if len(text) < 40 or any(n in text.lower() for n in _PAGE_NOISE):
            continue
        for s in _sentences(text, 6):
            if len(s) < 35:
                continue
            low = s.lower()
            score = sum(k in low for k in ("definition", "example", "solution", "means", "called", "set is",
                                           "venn", "union", "intersection", "subset", "element", "note",
                                           "form", "empty", "finite", "infinite", "equal"))
            score += 1 if len(s) > 70 else 0
            cands.append({"text": s, "bbox": bl["bbox"], "score": score})
    if not cands:  # older indexes without blocks: no location -> no fake highlight
        return []
    cands.sort(key=lambda c: -c["score"])
    chosen = cands[:limit]
    chosen.sort(key=lambda c: (c["bbox"][1], c["bbox"][0]))  # read top-to-bottom
    return chosen


def _windows(segments):
    """Spoken-narration windows for ordered segments: [(start, end), ...]
    as fractions of total narration characters."""
    total = max(1, sum(len(s) + 1 for s in segments))
    out, acc = [], 0.0
    for s in segments:
        w = (len(s) + 1) / total
        out.append((acc, min(1.0, acc + w)))
        acc += w
    return out


def _textbook_examples(index, pages, limit=3):
    """Worked examples printed in the textbook itself (never invented)."""
    out = []
    for pg in pages:
        text = re.sub(r"\s+", " ", index.page_text(pg) or "")
        for m in re.finditer(r"Example\s+(\d+)\s+", text):
            chunk = text[m.start():m.start() + 700]
            sents = [s for s in _sentences(chunk, 6) if len(s) > 18]
            if len(sents) >= 2:
                out.append({"page": pg, "number": m.group(1), "sentences": sents[:5]})
            if len(out) >= limit:
                return out
    return out


def _exercise_questions(index, pages, limit=4):
    """Exercise questions printed in the textbook (prompts only)."""
    out = []
    for pg in pages:
        text = index.page_text(pg) or ""
        m = re.search(r"EXERCISE\s*[\d.]*", text, re.I)
        if not m:
            continue
        tail = re.sub(r"\s+", " ", text[m.start():m.start() + 2200])
        body = re.sub(r"^EXERCISE\s*[\d.]*\s*", "", tail, flags=re.I)
        qs = []
        expect = 1
        for qm in re.finditer(r"(\d+)\.\s+(.{25,300}?)(?=\s\d+\.\s+|\s\(ii\)|$)", body):
            if int(qm.group(1)) != expect:  # only the real sequence 1,2,3,...
                continue
            q = re.sub(r"\s*\(i\).*$", "", qm.group(2)).strip()  # first sub-part only
            if len(q) >= 25 and "Reprint" not in q:
                qs.append(f"{qm.group(1)}. {q}")
                expect += 1
        for q in qs[:limit]:
            out.append({"page": pg, "text": q})
        if out:
            break
    return out[:limit]


def build_plan(session_id: str, question: str, mode: str, content: LessonContent,
               index: PdfIndex, asset_ids_for_page: dict, language="en-IN", grade=None,
               width=1280, height=720, fps=30, theme="auto", panel_position="top_right",
               include_page_reading: bool = False, page_range=None,
               part_label: str = "", next_part_label: str = "") -> VideoPlan:
    video_id = "video_" + uuid.uuid4().hex[:10]
    try:
        mode_enum = Mode(mode)
    except ValueError:
        mode_enum = Mode.detailed
    pages = index.find_relevant_pages(question + " " + content.title, top=2)
    main_page = pages[0] if pages else 1
    refs = [TextbookRef(page=p) for p in pages]

    scenes, n = [], [0]

    def add(kind, title, narration, elements, basis="textbook", scene_refs=None):
        if not narration or not narration.strip():
            return
        n[0] += 1
        board = SCENE_BOARDS.get(kind, "green_board") if theme == "auto" else theme
        scenes.append(Scene(scene_id=f"scene_{n[0]:03d}", title=title, kind=kind, board_theme=board,
                            narration=narration.strip(), board_elements=elements,
                            textbook_references=scene_refs if scene_refs is not None else refs,
                            source_basis=basis))

    title = content.title or question
    intro_prefix = f"Welcome. In this lesson we will learn about {title}. "
    intro_w = _windows([intro_prefix, content.concept or ""])
    add("intro", "Introduction",
        (intro_prefix + (content.concept or "")).strip(),
        [BoardElement(type="heading", text=title, animation="fade_in", sync_start=0.0, sync_end=max(0.05, intro_w[0][1])),
         BoardElement(type="paragraph", text=content.concept, animation="reveal",
                      sync_start=intro_w[1][0], sync_end=1.0)])
    obj_items = ["Understand the core concept", "Connect it with the textbook", "Apply it to daily life", "Check your understanding"]
    add("objectives", "What we will learn",
        "By the end of this lesson, you will be able to explain the main idea, connect it with the textbook diagram, and answer questions on it.",
        [BoardElement(type="heading", text="What we will learn", animation="fade_in", sync_start=0.0, sync_end=0.10),
         BoardElement(type="bullet_list", items=obj_items, animation="reveal", sync_start=0.10, sync_end=1.0)])

    if content.simple_explanation:
        add("concept", "In simple words", content.simple_explanation,
            [BoardElement(type="heading", text="In simple words", animation="fade_in", sync_start=0.0, sync_end=0.08),
             BoardElement(type="definition", text=content.simple_explanation, animation="reveal", sync_start=0.08, sync_end=1.0)])

    # Detailed explanation, taught point-by-point: smaller chunks, FULL
    # sentences on the board (never truncated), each bullet written exactly
    # while its own sentence is spoken.
    detailed_chunks = _chunks(content.detailed_explanation or content.simple_explanation, size=430)
    for i, chunk in enumerate(detailed_chunks if mode_enum != Mode.quick else detailed_chunks[:2]):
        sents = _sentences(chunk, 5)
        wins = _windows(sents)
        els = [BoardElement(type="heading", text="Detailed explanation", animation="fade_in", sync_start=0.0, sync_end=0.06)]
        for (s, (ws_, we_)) in zip(sents, wins):
            els.append(BoardElement(type="bullet_list", items=[s], animation="reveal",
                                    sync_start=0.06 + ws_ * 0.94, sync_end=0.06 + we_ * 0.94))
        add("explanation", f"Explanation {i + 1}" if len(detailed_chunks) > 1 else "Detailed explanation", chunk, els)

    # Image scenes: show EVERY useful textbook figure (up to the mode limit)
    # and EXPLAIN it with sentences taken from that figure's own page (§9, §10).
    _candidates = list(pages) + [p for p in sorted(asset_ids_for_page) if p not in pages]
    image_pages = [p for p in _candidates if asset_ids_for_page.get(p)]
    max_images = 1 if mode_enum == Mode.quick else 2
    if image_pages:
        for diagram_page in image_pages[:max_images]:
            asset_id = asset_ids_for_page[diagram_page][0]
            page_sents = [s for s in _sentences(index.page_text(diagram_page), 10)
                          if len(s) > 35 and not s.lower().startswith("chapter")]
            explain = " ".join(page_sents[:3])[:560]
            narration = (f"Now look at this figure from page {diagram_page} of your textbook. "
                         f"Let me explain it. {explain} Connect each label in the figure with this explanation.")
            dwins = _windows([f"Now look at this figure from page {diagram_page} of your textbook. Let me explain it."] + page_sents[:3])
            dels = [BoardElement(type="heading", text=f"From your textbook (page {diagram_page})", animation="fade_in",
                                 sync_start=0.0, sync_end=max(0.04, dwins[0][1])),
                    BoardElement(type="textbook_image", asset_id=asset_id, animation="zoom_region",
                                 sync_start=dwins[0][1], sync_end=dwins[-1][1])]
            for (s, (ws_, we_)) in zip(page_sents[:3], dwins[1:]):
                dels.append(BoardElement(type="bullet_list", items=[s], animation="reveal", sync_start=ws_, sync_end=we_))
            add("diagram", f"Textbook figure — page {diagram_page}", narration, dels,
                scene_refs=[TextbookRef(page=diagram_page, image_id=asset_id)])
    else:
        steps = [s[:42] for s in _sentences(content.detailed_explanation, 3)] or [title[:42]]
        add("diagram", "Understand the process",
            "Let us understand this as a step-by-step process. Follow each step as it appears on the board.",
            [BoardElement(type="heading", text="Step by step", animation="fade_in"),
             BoardElement(type="diagram", diagram=[DiagramOp(op="process_flow", steps=steps)], animation="draw_line")],
            basis="explanation")

    # ── Page-by-page reading: the actual textbook page is shown large,
    # the passage being read is TRULY highlighted (its real rectangle in
    # the PDF) and magnified, each passage is explained, notes follow ──
    if include_page_reading and page_range:
        note_points = []
        for pg in page_range:
            passages = _page_passages(index, pg, limit=4 if mode_enum != Mode.quick else 2)
            if not passages:
                continue
            intro = f"Now open page {pg} in your textbook. Read this page with me, line by line. "
            body = [p["text"] for p in passages]
            outro = (f"Look at the highlighted part on page {pg}. Read it once more in your book "
                     f"and underline the important words. ")
            segments = [intro] + body + [outro]
            wins = _windows(segments)
            note_points.append(f"Page {pg}: {body[0][:110]}")
            narration = " ".join(segments)
            add("reading", f"Textbook page {pg} — read with me", narration,
                [BoardElement(type="heading", text=f"Textbook page {pg} — read with me", animation="fade_in",
                              sync_start=0.0, sync_end=max(0.04, wins[0][1])),
                 BoardElement(type="textbook_page", asset_id=f"page_render_{pg}", animation="highlight",
                              sync_start=wins[0][1], sync_end=wins[-2][1],
                              regions=[p["bbox"] for p in passages],
                              region_windows=[[w[0], w[1]] for w in wins[1:-1]])],
                scene_refs=[TextbookRef(page=pg)])
            # per-page notes: written right after reading that page
            pts = [f"Page {pg}: {t[:130]}" for t in body[:3]]
            nintro = f"Let us write the important points from page {pg}. Copy them slowly in your notebook. "
            nwins = _windows([nintro] + pts)
            nels = [BoardElement(type="heading", text=f"Notes — page {pg}", animation="fade_in",
                                 sync_start=0.0, sync_end=max(0.04, nwins[0][1]))]
            for (t, (ws_, we_)) in zip(pts, nwins[1:]):
                nels.append(BoardElement(type="bullet_list", items=[t], animation="reveal",
                                         sync_start=ws_, sync_end=we_))
            add("notes", f"Notes — page {pg}", nintro + " ".join(pts), nels, basis="explanation",
                scene_refs=[TextbookRef(page=pg)])
        # worked examples printed in these very pages, solved step-by-step
        for ex in _textbook_examples(index, page_range, limit=0 if mode_enum == Mode.quick else 3):
            sents = ex["sentences"]
            wins = _windows(sents)
            els = [BoardElement(type="heading", text=f"Textbook example {ex['number']} — page {ex['page']}",
                                animation="fade_in", sync_start=0.0, sync_end=0.05)]
            for (s, (ws_, we_)) in zip(sents, wins):
                els.append(BoardElement(type="step_list", items=[s], animation="reveal",
                                        sync_start=0.05 + ws_ * 0.95, sync_end=0.05 + we_ * 0.95))
            add("worked_example", f"Textbook example {ex['number']} (page {ex['page']})",
                f"Now let us solve Example {ex['number']} from page {ex['page']} of your textbook, step by step. "
                + " ".join(sents) + " Follow every step on the board and write the method, not only the answer.",
                els, scene_refs=[TextbookRef(page=ex["page"])])
        # exercise questions from the textbook — students try, then check
        exqs = _exercise_questions(index, page_range)
        if exqs and mode_enum != Mode.quick:
            qtext = " ".join(f"Question {i + 1}. {q['text']}" for i, q in enumerate(exqs))
            add("quiz", "From your textbook exercise",
                f"Now try these questions from the exercise on page {exqs[0]['page']}. Pause the video and write your answers first. "
                + qtext + " After trying, check your answers in the textbook and correct your mistakes.",
                [BoardElement(type="heading", text="From your textbook exercise", animation="fade_in",
                              sync_start=0.0, sync_end=0.08),
                 BoardElement(type="bullet_list", items=[q["text"] for q in exqs], animation="reveal",
                              sync_start=0.08, sync_end=1.0)],
                basis="explanation", scene_refs=[TextbookRef(page=exqs[0]["page"])])

    if mode_enum != Mode.quick:
        for ex in (content.real_life_examples or [])[:3]:
            add("example", "Real-life example", ex,
                [BoardElement(type="heading", text="Real-life example", animation="fade_in", sync_start=0.0, sync_end=0.08),
                 BoardElement(type="paragraph", text=ex, animation="reveal", sync_start=0.08, sync_end=1.0)],
                basis="real_life_example")

    if content.worked_example:
        wsents = _sentences(content.worked_example, 5)
        wins = _windows(wsents)
        els = [BoardElement(type="heading", text="Worked example", animation="fade_in", sync_start=0.0, sync_end=0.06)]
        for (s, (ws_, we_)) in zip(wsents, wins):
            els.append(BoardElement(type="step_list", items=[s], animation="reveal",
                                    sync_start=0.06 + ws_ * 0.94, sync_end=0.06 + we_ * 0.94))
        add("worked_example", "Worked example", content.worked_example, els)

    if mode_enum == Mode.mastery:
        for mk in (content.common_mistakes or [])[:3]:
            add("mistakes", "Common mistake", f"Be careful. A common mistake is: {mk}",
                [BoardElement(type="heading", text="Common mistake", animation="pulse", sync_start=0.0, sync_end=0.10),
                 BoardElement(type="paragraph", text=mk, animation="reveal", sync_start=0.10, sync_end=1.0)],
                basis="explanation")

    sum_sents = _sentences(content.summary or content.simple_explanation, 5)
    wins = _windows(sum_sents or [""])
    els = [BoardElement(type="heading", text="Summary", animation="fade_in", sync_start=0.0, sync_end=0.06)]
    for (s, (ws_, we_)) in zip(sum_sents, wins):
        els.append(BoardElement(type="bullet_list", items=[s], animation="reveal",
                                sync_start=0.06 + ws_ * 0.94, sync_end=0.06 + we_ * 0.94))
    add("summary", "Summary", content.summary or content.simple_explanation, els)

    quiz_items = content.quiz or []
    if mode_enum != Mode.quick or quiz_items:
        qtext = " ".join([f"Question {i + 1}. {q['question']}" for i, q in enumerate(quiz_items[:3])]) or \
            f"Now check yourself. What is the main idea of {title}? Where is it explained in your textbook?"
        add("quiz", "Check your understanding", qtext + " Pause the video, answer, then continue.",
            [BoardElement(type="heading", text="Check your understanding", animation="fade_in", sync_start=0.0, sync_end=0.08),
             BoardElement(type="bullet_list", items=[q["question"] for q in quiz_items[:3]] or [f"What is {title}?"], animation="reveal",
                          sync_start=0.08, sync_end=1.0)],
            basis="explanation")

    if next_part_label:
        add("revision", "Next part unlocked",
            f"Well done. You completed {part_label or 'this part'}. Revise your notes and answer the questions "
            f"before moving on. The next video is now unlocked: {next_part_label}. We will continue page by page in that video.",
            [BoardElement(type="heading", text="Next part unlocked", animation="fade_in"),
             BoardElement(type="bullet_list", items=[f"Completed: {part_label or 'this part'}",
                                                     f"Next: {next_part_label}",
                                                     "Revise your notes before you continue"], animation="reveal")],
            basis="explanation")

    plan = VideoPlan(
        session_id=session_id, video_id=video_id,
        lesson=Lesson(title=title, subject="Textbook Lesson", language=language, grade=grade, mode=mode_enum),
        video=VideoSettings(width=width, height=height, fps=fps),
        layout=Layout(textbook_panel_enabled=True, textbook_panel_position=panel_position, board_theme=theme),
        scenes=scenes,
        quiz=[{"question": q["question"], "answer": q["answer"]} for q in quiz_items],
        asset_ids=[a for assets in asset_ids_for_page.values() for a in assets]
                  + ([f"page_render_{p}" for p in page_range] if include_page_reading and page_range else []),
    )
    return plan
