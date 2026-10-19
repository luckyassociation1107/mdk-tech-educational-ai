# AI Textbook-to-Video Classroom Designer

Upload a textbook PDF → ask educational questions → get a real teaching
video for every question. **The cloud AI only plans the lesson; the local
Python engine renders the actual MP4.** No image-generation AI, no
video-generation AI, no API key.

## The "brain" is Playwright (as requested)

Instead of an AI API key, the brain is the PDF Summarizer website we
already automated (`pdf-summarizer-automation/`). Our automation:

1. Uploads the textbook PDF (one live session per textbook = session isolation)
2. Reads the website's summary as the document analysis
3. Asks each student question in that site's **Ask PDF** chat with a
   strict section prompt (`TITLE / CONCEPT / DETAILED EXPLANATION / …`)
4. Returns the text; **our local code** turns it into a validated JSON
   scene plan. Textbook page numbers are found by searching the PDF
   locally — they are never taken from the AI, so they can't be invented.

An offline deterministic brain is included for tests and for when the
site is unreachable.

```
Flutter Android app ──MethodChannel──► Kotlin (Chaquopy + Android TTS)
        │                                   │
        │                            Python engine (on device)
        │                            plan → board → FFmpeg → MP4
        └── PDF/question ─► Playwright brain website (cloud AI, over HTTPS)
```

## Quick start (desktop prototype — verified in this workspace)

```bash
cd engine
pip install -r requirements.txt
python -m textbook_video.cli demo --brain offline        # no network at all
python -m textbook_video.cli demo --brain playwright     # uses the website brain*
pytest -q                                                # 6 tests
```

\* Playwright brain needs the sibling project running once:
`cd ../../pdf-summarizer-automation && npm install && npx playwright install --with-deps chromium && node server.js`
(the Python client auto-starts it when it can find it).

## What is verified (actually run, not claimed)

- ✅ Playwright-brain end-to-end with **real human-like audio**: website
  summary → "Understanding Photosynthesis" → **11 scenes → 199.7s 720p MP4**,
  narration by **Edge TTS (en-IN-NeerjaNeural)** — measured mean volume
  −22 dB (not silent) → disconnect cleanup completed, export preserved
- ✅ **Green chalkboard** theme (green board, chalk-yellow headings),
  textbook figure scenes that **show the PDF's own diagram AND explain it**
  with sentences from that page
- ✅ **Chat session + video session in one textbook session**: chat question
  answered in-session, videos listed per session, exports preserved
- ✅ Offline end-to-end: sample textbook → 8 scenes → 88.9s 720p MP4 + SRT
- ✅ **9 automated tests**: PDF indexing/images, schema rejecting unknown
  animations & path assets, green-board + image-explanation plans, chat
  sessions, session isolation, idempotent cleanup, quick vs detailed modes

## What is NOT done / honest limits

- 📱 **APK was not built in this workspace** — there is no Flutter/Android
  SDK here. The complete Flutter + Kotlin + Chaquopy project is in `app/`;
  build it where the Android toolchain exists (see `docs/SETUP.md`).
- 🔊 Narration uses **Edge TTS** (human-like, en-IN/te-IN voices, no API
  key) → falls back to espeak → then captions mode. Voice is selectable
  with `TTS_VOICE` / `TTS_MODE`. On Android the app additionally can use
  the **device TextToSpeech**; a Telugu voice is used only if the device
  actually has te-IN installed — otherwise the app says so and keeps captions.
- 🧾 Scanned-PDF OCR and the Kotlin PDFBox extraction path are designed
  and interfaced (`PdfIndex.from_dict`) but not executed in this workspace.

## Layout

| Path | What |
|---|---|
| `engine/textbook_video/` | Python engine: PDF, brains, planner, board, TTS, FFmpeg, sessions, cleanup |
| `engine/tests/` | pytest suite |
| `app/` | Flutter Android project + Kotlin/Chaquopy bridge |
| `docs/` | Architecture, Android integration, setup, config, troubleshooting |
| `data/`, `data-pw/` | Demo outputs (exports preserved, sessions cleaned) |
| `tools/` | Engine→Android sync script |

## Human-teacher feel (boards)

Default board mode is **auto**: the teacher moves between boards by scene —
green chalkboard (intro/summary), black chalkboard (explanations),
whiteboard (objectives/examples/quiz), ruled notebook (definitions,
mistakes) and graph board (diagrams/worked examples). Text is written in
a real handwriting font, letter-by-letter, with a chalk/marker/pen nib
following the writing, hand-drawn underlines and gradual reveals —
synced with the human-like narration. Force one board any time with
`--theme green_board|black_board|white_board|ruled_board|graph_board`.

## Voice-synchronised writing + page-by-page chapter series

**Fix 1 — writing now matches the voice.** The TTS layer requests exact
word timings (`WordBoundary`) from the voice service while the audio is
generated. The board renderer budgets its handwriting from *spoken words*
(`BoardRenderer.spoken_ratio`): a word forms on the board when it is
spoken, instead of the old behaviour where a whole board's text formed
across a fixed time window and visibly lagged the voice. Providers without
timings fall back to measured-audio pacing.

**Fix 2 — chapters are taught page by page, as a series.** New scene kinds
`reading`/`notes`: the real textbook page is shown large, a highlight band
moves over the passage being read, key sentences (extracted locally from
that exact page — ads/headers removed) are explained and noted. The whole
chapter is divided by `chapter_series(session, pages_per_part=6)` into
Parts (e.g. Sets: pages 1–6, 7–12, 13–18, 19–23). Part 1 starts unlocked;
finishing a part (`complete_part`) unlocks the next video's part. Each part
ends with checkpoint questions and a "Next part unlocked" scene. CLI:
`series --session ...` and `ask ... --page-reading --pages 1,2,3,4,5,6
--part-label "..." --next-part-label "..."`.

## Teacher-sync, true highlighting & detailed classes (V3)

**Writing locked to the voice.** Each board element now carries a
planner-computed *sync window* — the exact fraction of the scene's spoken
narration during which that element is written. Bullets keep their FULL
sentences (no truncation, which used to make board text drift away from
the narration), bullets reveal by character share, words count partially
while being uttered, and writing uses a 0.3s lead so the hand is never
behind the voice. The voice itself is slowed to teaching pace
(Edge `rate=-20%`, espeak 140wpm; override with `TTS_RATE`).

**True highlighting.** The PDF indexer now stores per-page text blocks
with normalised coordinates. Reading scenes locate the actual passage
rectangles being read (`BoardElement.regions` + `region_windows`), draw
the live red highlight box on the page overview, and show a MAGNIFIED
crop of the passage being read so the words are actually readable —
previously the "highlight" was a timer-driven band over a tiny page.

**More detailed classes.** The brain prompt demands full-period teaching
(12+ sentence detailed explanations, terms defined, reasons given) and
auto-expands a thin answer once. Plans add per-page notes right after
each page is read, worked examples extracted from the textbook's own
Example sections solved step-by-step, and real Exercise questions from
the book. TTS output is validated (duration vs word timings/text length)
with one retry, so a truncated voice stream can never silently ship.

Sets Part 1 (pages 1–6) with all of this: **1361s / 31 scenes**
(`data-sets/exports/session_a61122dbb820/Sets_Part1_TeacherSync_Final.mp4`).

## Premium Flutter App + APK (V4)

The Flutter app was rebuilt as a full premium classroom product
(`app/lib/`, ~2,300 lines): splash → textbook library with per-book
progress rings → chapter-series screen (parts with lock/unlock badges,
key points, generate/watch per part) → generation sheet (depth, page-by-page
reading toggle, honest on-device/online-brain notice) → video player
(synced captions from the word-timed SRT, resume position, 0.5x–1.5x
speed with 1.0x marked as teacher pace, "complete part & unlock next")
→ Ask PDF chat → notes (key points + class captions, downloadable .txt)
→ settings (language English/Telugu, pages-per-part, 480p/720p, board
style, offline vs online brain + server URL, device-voice check).
Local progress (completed parts, watch positions) persists via
SharedPreferences and mirrors the engine's unlock state.

**APK built in this environment**: `AI_Textbook_Classroom.apk` (44MB,
arm64-v8a, minSdk 26, targetSdk 35, debug-signed) with Flutter 3.24.5 +
JDK 17 + Gradle 8.7. The Chaquopy Python 3.11 runtime and the synced
`textbook_video` engine are packaged inside (`assets/chaquopy/`).
The engine schema layer is now pydantic-free (dataclasses) because
pydantic-core has no Android wheel; desktop tests still pass (13/13).

Rebuild: install Flutter 3.24.5 + JDK 17 + Android SDK 34/35, then
`tools/sync_engine_to_android.sh` and
`cd app/android && ./gradlew assembleRelease -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart -Pbase-application-name=android.app.Application -Pdart-obfuscation=false -Ptrack-widget-creation=true -Ptree-shake-icons=true`
(Lint tasks are disabled in `android/build.gradle` for low-RAM builds.)

**Honest limitations**: (1) The APK could not be run on a device/emulator
in this sandbox (no KVM), so on-device behaviour is not device-tested.
(2) PyMuPDF has no Android wheel — on-device PDF text/page rendering
still needs the Kotlin PDFBox/PDFRenderer layer described in
`docs/ANDROID_INTEGRATION.md`; without it, phone-side session creation
reports a clear engine error in the UI instead of crashing. The online
brain mode additionally needs a reachable brain-server URL (Settings).
(3) The release APK is debug-signed; use your own keystore for Play.

## Academics: tests, doubts, marks & ranks (v0.2)

- **Exams & Tests hub** (Home -> Academics): pick any textbook + part and
  start an auto-graded test. Question types: MCQ, fill-in-the-blank and
  short answers; optional timed exam (auto-submit) and -0.25 negative
  marking for wrong MCQs. Questions are generated on-device from the
  part's own key points (real textbook content, works fully offline).
- **Part unlocking by merit**: scoring 40%+ in a part test marks the part
  complete and unlocks the next class, same as finishing the video.
- **Doubt clearing**: every textbook card links straight into Ask PDF chat.
- **Report Card**: per-textbook marks table (tests, average, best, grade),
  recent attempts, XP levels, rank bands (Rank 1 Gold Scholar down to
  Rank 6 Learner, computed from the student's own averages on this
  device - openly labelled in-app) and a weak-parts revision list that
  jumps back into the textbook. All history is stored on the phone only.

## Institution mode: Admin, Principal, Teachers, Students (v0.3)

The app now works like an institutional application with role logins
(all accounts stored on-device; no server needed):

- **Admin = founder/creator.** First launch creates the founder account.
  The admin creates schools and appoints exactly one Principal per school
  (appointing a new one deactivates the old), can deactivate schools and
  reset principal passwords.
- **Principal (one per school).** Controls the whole staff of their
  school: adds/deactivates teachers and students, resets passwords, sees
  school test counts and averages per student, and can also open the
  teaching tools to upload/publish.
- **Teachers.** Upload textbooks, generate classes, create tests and
  **publish** a textbook to the whole school or one class
  (Textbook -> Publish to students).
- **Students (read-only).** See only published textbooks for their
  school/class: read, watch, Ask PDF doubts and take tests. There is no
  upload or generate control in the student experience, and exam history
  is stored per student account, so marks stay private per login.

## PDF sharing via Gofile (v0.4 — PDFs only)

- Teachers/principals: **Home -> Share PDFs with students** uploads a PDF
  to a per-device Gofile guest account and publishes the link to the
  whole school or one class. Videos are never uploaded anywhere — they
  are generated by the Playwright-automation teaching engine.
- Students: **PDFs shared by your teachers** lists the files; one tap
  opens the download page and the PDF stays in the student's phone.
- Honest lifetime handling: free Gofile links live on real downloads
  (~10 days of inactivity may retire them). The teacher sees a countdown
  and a one-tap refresh (a genuine re-upload) — the app never fabricates
  downloads to game the clock.

## Fixed: "No module named pymupdf" on Android (v0.5)

Device report: adding a textbook failed with
`ModuleNotFoundError: No module named 'pymupdf'` — PyMuPDF has no Android
wheel. The engine now falls back automatically:

- `index_pdf` uses pypdf (pure Python, shipped via Chaquopy) for page
  count, title and text on Android; PyMuPDF is still used on desktop.
- Kotlin (PdfRenderer) renders page pictures when a session is created;
  `render_page_crop` crops them with Pillow on-device, so page-reading
  and highlight scenes keep working. Estimated block bands (from
  paragraph order) are used for highlighting until exact boxes exist.
- Verified in a simulated no-PyMuPDF environment and by the engine
  suite: 13/13 tests still pass.

## Flutter-only rewrite (v0.6.0) — Python removed from the app

Per direction, the application no longer ships Python/Chaquopy at all.
The former Python engine was re-implemented in Dart:

- PDF text/structure: Syncfusion Dart PDF parser (exact page text and
  line bounds for highlighting); page pictures: Android PdfRenderer via
  one small platform method.
- Chapter series, part unlocking and doubt clearing run in Dart over the
  extracted textbook (offline, extractive, real page references only).
- Lessons are an interactive Flutter player: board themes (green/black/
  white/ruled/graph) with voice-synced writing (device TTS), textbook
  page reading with passage highlighting and captions — instead of an
  MP4 rendered by a Python pipeline. Tests/report-card stay as before.
- The old Python engine remains available in git history (pre-v0.6
  commits) for reference; the app APK is now smaller and starts faster.

Note: Syncfusion's PDF package may ask for a (free) Community license
key in release builds; if a license prompt ever appears, register a
free key at syncfusion.com and add `SyncfusionLicense.registerLicense`
in main() — no code structure changes needed. The app itself has no
other third-party runtime services.
