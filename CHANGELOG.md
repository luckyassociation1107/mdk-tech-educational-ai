# Changelog

Everything below is the project's own running log, newest first.
The current architecture is described in README.md.

## v0.24.0 — free website AI by default, local figure finding, APK/EXE verified

**The app now reads PDFs for free.** The public PDF-teacher website is driven
inside the app's own WebView: the PDF goes into the page's file input through a
`DataTransfer` (no native picker, no root, no automation service), the prompts
are typed into its "Ask PDF" box, and the answers are read back as text. No API
key, no account, no cost.

- **Two modes**, same prompts, same pipeline: *Free — automate the website*
  (default, Android) and *My own API key* (OpenAI / Gemini / Claude, also on
  Windows, can see page images).
- **Figures without a vision model.** The model can only say *what* a figure is
  and roughly *where* (top / middle / bottom). The new `FigureFinder` renders
  the page with PDFium, finds the large coloured/dense blobs (charts, photos,
  boxed diagrams) on a coarse grid, picks the one in the requested band and
  hands the exact box to the cropper. Verified against the live site: the model
  returned the JSON contract, page text and figure captions for a real PDF.
- **Live progress panel** (`WebAiHost`) shows the site working, so nothing
  happens invisibly; one session is reused for the extraction and every lesson
  script, and prompts are uploaded in chunks so a 20 MB book cannot blow up the
  WebView.
- **Scene parser hardened** for what the free model actually returns (mangled
  keys, missing `kind`, prose around JSON, trailing commas).
- Tests: **59** (26 AI pipeline + 9 figure finder + vault + UI), `flutter
  analyze` **0 errors**; Android APK and Windows EXE built green in CI.

### What v0.24.0 also removed

The Syncfusion parser and the Android-only Kotlin `PdfRenderer` are gone. The
PDF is read by the AI, pages and figures are rendered with PDFium on both
platforms, and narration falls back to `flutter_tts` where the native bridge is
not available.

## v0.23.0 — The AI brain works natively (no WebView scraping)

The brain was never removed: the in-app WebView automation is still there. But while
checking it against the live site I found something much better, and used it.

**What the website really does.** Its WebView flow uploads the PDF, reads the text in the
browser, and then simply POSTs JSON to a free chat endpoint and streams the answer back.
So the app now does the same thing natively:

| Step | Before (v0.22.1) | Now (v0.23.0) |
| --- | --- | --- |
| Upload the PDF | WebView file-chooser + hidden input | not needed — the app already has the text |
| Get a summary | scrape the page after clicking a button | `POST` JSON → SSE stream read directly |
| Ask a question | type into the page's textarea, click, scrape | `POST` JSON with the question → SSE stream |
| Platforms | Android only (WebView) | **Android + Windows** |
| Failure mode | page changes a button → automation breaks | one JSON contract |

**New code**
- `lib/brain/ai_brain.dart` — the client: request bodies (same prompts as the site), SSE
  parsing, streaming callback, cancel, timeout, friendly errors, 45 000-character clip.
- `lib/screens/brain_screen.dart` — *AI Brain*: Brief/Medium/Detailed, live streaming text,
  stop button, saved summary, ask box, saved Q&A, copy, clear.
- Home has an **AI Brain** card; the textbook app-bar button opens it; **Ask PDF chat now
  answers with AI first** and falls back to the book's own sentences when offline.
- The WebView automation is still reachable as *website mode* (Android).

**Proof (run for real, today)**
- Captured the live site's own request: `POST https://productivity-tools-server-qgvsu...`
  `{"messages":[…],"model":"gpt-4o-mini","stream":true}` → `text/event-stream` chunks.
- Same flow with `playwright` on the live site: PDF uploaded → summary in ~7 s → question
  answered in ~2 s.
- Same flow from **pure Dart** (`dart run`): summary **4.7 s / 2 193 chars / 480 streamed
  chunks**, answer **3.2 s / 1 609 chars**. No key, no account, no payment.
- 11 new automated tests (SSE parsing of real chunks, request bodies, clipping, offline
  UI state); whole suite **32 tests green**, `flutter analyze` **0 errors**.

**Honest limits.** The endpoint belongs to that public website — it is free but not ours,
so it can change or be busy (the app then shows a clear message and the book still works
offline). It needs internet. Text, not images, is sent.

## v0.22.1 — stability pass: 21 automated tests, three real UI bugs fixed

Everything below was run for real (Flutter 3.24.5 in a clean sandbox), not assumed.

**Static check.** `flutter analyze` over the whole app: **0 errors** (113 infos/warnings).

**21 automated tests** (`app/test/`), all green:
- unit: emoji codec round-trip, seal/open, wrong-key and tamper rejection, PBKDF2 salt
  uniqueness, signup → wrong PIN → right PIN, data surviving logout, PIN change keeping
  data, PIN validation, JSON→tables→JSON, emoji packet round-trip, Nostr event signature
  and tamper rejection.
- UI on a 360×640 canvas: gate renders, full sign-up flow (name → avatar → PIN typed
  twice → profile listed), wrong PIN refused, profile screen + tablet-free layout, cloud
  vault screen fits, emoji code export → wipe → import restores both profiles.

**Three real bugs the tests caught and we fixed**
1. `vault_sync_screen`: the "Copy emoji / Paste emoji" row **overflowed by ~10 px** on a
   360 dp phone → text now flexes with ellipsis.
2. `child_gate_screen` (sign-up): "Create my profile" sat **below the fold** on a 640 dp
   tall phone → the button is now pinned to the bottom of the screen (always visible).
3. Sign-up validation text ("Please type your name.") was rendered **inside the scroll
   area**, so a child tapping Create could see nothing happen → the message now appears
   directly above the pinned button.

**CI now runs the tests** on every push, for both the Android and Windows builds, so a
future feature cannot silently break the gate, the vault or the relay backup.

## v0.22.0 — Emoji cloud vault: tables → encrypted emojis → free Nostr relays

**What you asked for.** An encryption/decryption path where the vault JSON is kept as a
table database, encrypted, written as emojis, stored on **free Nostr relays**, and on the
way back the emojis are turned into tables again.

**The pipeline (both directions)**

| Step | Forward (backup) | Reverse (restore) |
| --- | --- | --- |
| 1 | vault JSON + progress keys | emoji string from relay / clipboard |
| 2 | split into **tables** (profiles, sealed cells, settings, progress, activity) | base64 |
| 3 | `gzip` | decrypt (HMAC-SHA256 keystream + tag) |
| 4 | seal with PBKDF2/`HMAC-SHA256` key from the device secret | `gunzip` |
| 5 | base64 → **64-emoji alphabet** | JSON → **tables** |
| 6 | signed **NIP-01** event `kind 30078`, d-tag `emoji-vault` | tables → vault JSON + progress rows |

**Free cloud database.** No account, no API key, no paid plan: public relays keep the signed
event. The same `d`-tag is re-published on every backup, so a relay always holds exactly one
row per child device. Six relays are used by default (damus, nos.lol, nostr.mom, primal,
snort, wellorder) — a backup is confirmed as soon as three of them store it (~1.5 s in
testing) and a restore returns the first relay that answers (~0.8 s).

**Crypto.** The payload is encrypted *before* it is signed, so a relay only ever sees
emojis. Key = PBKDF2-HMAC-SHA256(device secret, 30 000 rounds) → 32 bytes; each save uses a
fresh 16-byte nonce, an HMAC-SHA256 counter keystream and a truncated HMAC tag, so a wrong
key or one flipped emoji fails the tag check.

**Schnorr signatures, pure Dart.** Nostr needs BIP-340 signatures; the app now has a
self-contained secp256k1 implementation. It is checked against the official BIP-340 test
vectors 0 and 1 (public key, signature, verification) and corrupt signatures are rejected.

**In the app.** *My space → Emoji cloud vault*: backup now, restore, copy/paste the emoji
code, edit the relay list, auto-backup after every finished class/test, per-relay status
lines, and a **decrypted table view** (rows × columns) of exactly what the emojis contain.

**Verified live, end to end:** fake vault + progress → backup (6/6 relays, 2 564 emoji
chars) → fetch → decrypt → tables `profiles(1×8) sealed(1×4) settings(2) progress(3)
activity(0)` → progress restored (XP 250) and profiles restored (`Kiran`).

**Honest limits (stated in the UI too).** Public relays are free, so they may prune old
events — therefore: several relays, a local vault, and the emoji code backup. Anyone can
read the emojis, but only this device key can decrypt them; the emoji code carries that key,
so treat it like a password.

## v0.21.0 — emoji vault: encrypted child accounts, PIN login and activity logs

**What it is.** A fully on-device, encrypted "database" for children's accounts, written
as an **emoji code**. Free, unlimited (phone storage), stable and 100% offline. It is not
a cloud service — copying it to another phone means sharing the emoji code — and that
limit is stated plainly in the UI.

**How it protects data**

- Each child profile: name, an avatar emoji, and a **4–6 digit PIN**.
- The PIN is never stored. A **PBKDF2-HMAC-SHA256** (120 000 rounds) key is derived from
  the PIN + a random per-child salt; only a 60 000-round verifier hash is kept for the
  fast PIN check.
- The child's data (marks, activity log, profile info) is sealed with a **SHA-256 HMAC
  keystream + HMAC tag**: a wrong PIN fails the tag check, and any edited byte in the
  ciphertext is rejected. Salt and verifier live outside the payload.
- The whole vault (all profiles + sealed payloads) is base64-encoded and mapped onto a
  **64-emoji alphabet** — the "emoji database". The code starts with 🎒 so it is easy to
  recognise, and can be copied or saved as a backup and restored on any phone.

**In the app**

- **Child gate at launch**: pick a profile → numeric PIN pad (long-press the dots to peek
  at the digits) → home. New children sign up with a name, an emoji avatar and a PIN typed
  twice. "Continue without a profile" keeps the old single-learner mode.
- **Per-child scoping**: exam results, XP, completed parts, streaks, daily-goal counters and
  activity logs are namespaced per profile, so two children on one phone never mix data.
- **My space** (avatar button on Home): change name, change avatar, change PIN (old PIN
  required, data is re-sealed with the new key), switch child, sign out.
- **Activity log** (encrypted): sign-up, sign-in, sign-out, PIN change, profile edits,
  every finished class and every finished test.
- **Emoji vault code**: copy the code / import a code to restore all profiles.

**Verified offline (plain Dart test, `--enable-asserts`)** — emoji round-trip of UTF-8 bytes,
seal/open with the right PIN, rejection with a wrong PIN, tamper rejection, PIN-hash
uniqueness, and 64 unique emojis in the alphabet.

## v0.20.0 — animated diagrams, listening exam, daily challenge, bookmarks, word bank, certificate

**Animated diagrams inside the class.** One diagram per part is drawn live while the
teacher speaks — a **cycle** (science idea chains), a **timeline** (social studies years),
a **process flow** (vocational/lab steps) or a **number line** (maths values). Nodes are
short phrases taken from the textbook itself; they appear one by one driven by the voice
progress, with arrows, highlights and labels.

**Listening exam.** The teacher reads each question and its options aloud; the student
answers by tapping. Show-text toggle, replay counter, instant spoken correction, and a
score screen — real exam-condition practice and a true accessibility mode.

**Daily challenge.** Five mixed questions from every textbook on the phone, the same set
for the whole day (seed = date), on Home. +60 / +30 / +10 XP with a celebration at 80%+.

**Reader bookmarks.** Bookmark any page, see a list of all bookmarks, jump straight to a
page, and see bookmark badges on pages you saved.

**My Words (personal dictionary).** Every word tapped in Word help is saved with the
textbook sentence it came from, its page number and its translation. Search, listen,
delete, clear — a growing vocabulary bank built from real reading.

**Certificate of completion.** A shareable A4-landscape PNG certificate (parts completed,
average, level, date, "verified on device") rendered on the phone and saved to
`classroom/certificates/`. Reached from Study tools in any textbook.

## v0.19.0 — Theme engine: 6 themes + custom themes with export/import

**Every colour in the app is now theme-driven.** `AppColors` became palette getters
backed by `ThemeManager`, so a theme switch repaints the entire app instantly
(Home, classes, quizzes, tools, reader, settings). 261 `const` usages were rewritten
so dynamic colours are legal everywhere.

**6 built-in themes — 3 dark + 3 light**
- Dark: **Midnight Indigo** (original premium navy), **Neon Graphite** (black + cyan/lime),
  **Royal Aurora** (deep violet + pink + amber)
- Light: **Daylight Paper** (clean white + indigo), **Warm Sand** (cream + terracotta),
  **Mint Studio** (pale mint + emerald)

**Theme Studio** (Home palette button, or Settings → Appearance):
- Every theme card shows a gradient preview, a LIGHT/DARK badge and its six colours.
- **Create tab**: name + six colour pickers (background, card, text, primary, secondary,
  accent) with a compact HSV picker (hue strip, saturation, brightness, hex entry and
  swatch rows). Light/dark is detected from the background, and muted/stroke/border
  tones are generated so text always stays readable. Live preview card updates as you
  pick; Save & apply stores it, Edit and Delete manage saved themes.
- **Export / Import tab**: export the current theme or all custom themes as JSON
  (copied to the clipboard and saved to `classroom/themes/*.json`), import by pasting
  JSON, or open a saved theme file. Imported themes appear in the list immediately.
- The aurora background, glass cards, glow icons and gradients all follow the palette;
  light themes get softer auroras and light-appropriate shadows.

## v0.18.0 — install-over updates (no uninstall) + premium UI

**Updates now install straight over the old app.** From v0.18.0 every release APK is
signed with the permanent release key (same certificate for every future build), so
Android treats each new version as an *update* of the installed app: marks, streaks,
flashcards, downloaded textbooks and settings all stay. `tools/release_sign_apk.sh`
documents the zipalign + apksigner (v1/v2/v3) flow used for the release asset; the
keystore itself never enters the repo. The Windows installer already upgrades in place
(same Inno AppId). One honest note: builds up to v0.17.0 were debug-signed by CI, so the
install of v0.18.0 is the last one that needs a fresh install; everything after it updates
over the top.

**In-app update banner.** Home asks GitHub for the newest release once per launch; when
a newer version exists it shows an amber card with an Update button that opens the APK
link directly (native `openUrl`), saying plainly that nothing is deleted.

**Premium UI layer (pure Flutter, no packages).**
- `AuroraBackground` — animated three-blob aurora behind Home, Settings and the splash.
- `GlassCard` — frosted glass surfaces with soft shadows replacing flat fills.
- `GlowIcon` — gradient icon chips with coloured glow.
- `GradientText` — shader-masked gradient headlines.
- `RiseIn` — staggered fade-and-rise entrances for list content.
- `AnimatedCount`, animated progress fills, Zoom page transitions app-wide.
- **Celebrations**: confetti + sparkle burst dialog when a badge unlocks (once per badge).
- New splash: glowing logo, gradient wordmark, aurora, smooth hand-off to Home.
- New Home: greeting by time of day, **Continue learning** card (animated progress +
  one-tap resume), update banner, glass stat card, achievements strip.

## v0.17.0 — voice studio, streaks & badges, flashcards, reader, revision hub

**Voice Studio (Settings → Voice, or the "Voice" key inside a class).** Lists the real
voices installed on the phone, with quality / "needs internet" labels; speed 50–150%
and pitch 0.7–1.3 with instant preview, saved and used everywhere (class, podcast,
quiz, reader). Native `listVoices` + per-utterance voice/pitch on Android.

**Streak & badges on Home.** Consecutive-day streak, last-7-days strip, daily scene goal
ring (6/12/20/30, choose in Settings), total study minutes, XP level (250 XP per level,
Starter → Legend) and 10 achievements that unlock from real activity only.

**Flashcards (spaced repetition).** Cards are built from the part's own key points
(cloze: one word blanked) and, for language books, glossary words. Leitner boxes
0–5 with 1/2/4/8/16-day intervals; wrong cards return the same day; flip animation,
one-tap pronunciation, XP for every review, "all caught up" scheduling.

**Textbook Reader.** Page-by-page reading with deep pinch-zoom, whole-book search
(every hit shows its page + snippet and jumps there), "read this page to me" using the
chosen voice, and a PART PAGE marker.

**Revision hub.** Reads the student's own test history; every part under 60% becomes
a card with Re-watch and Flashcards actions — the plan is derived, never invented.

**Class upgrades.** Theatre mode (full-screen class), Repeat, Slow replay (0.62×) of the
whole scene, and **Word help**: tap any hard word from the board to hear it slowly, see
the exact textbook sentence containing it, and get its translation in the chosen
explanation language.

**Backup.** Settings → Progress backup → Export writes a JSON of all progress (marks,
XP, streaks, completed parts, flashcard schedule, settings) to the phone; Restore lists
the newest backups and imports them.

## v0.16.0 — live Zoom-style class, translator, podcast, quiz, mind map, key-points book

**The class:** a live-classroom screen with a pulsing LIVE badge, teacher avatar,
viewer count, XP counter, animated scene transitions, board writing that follows the
voice character-by-character and textbook-page highlighting that can never drift
out of sync (native `ttsRange`).

**Translator (explanation only).** The student picks an explanation language from
**49 languages** (all major Indian languages first: Telugu, Hindi, Tamil, Kannada,
Malayalam, Marathi, Bengali, Gujarati, Punjabi, Odia, Assamese, Urdu, Nepali,
Sinhala, Sanskrit, Sindhi — then Spanish, French, German, Portuguese, Italian,
Dutch, Russian, Ukrainian, Polish, Czech, Romanian, Hungarian, Greek, Swedish,
Danish, Norwegian, Finnish, Turkish, Arabic, Persian, Hebrew, Swahili, Amharic,
Chinese Simplified/Traditional, Japanese, Korean, Vietnamese, Thai, Indonesian,
Malay, Filipino).

- **Only the explanation is translated.** Textbook points always stay in the book's
  own language and main/technical words stay in English, so notes stay easy to
  prepare from the class.
- Textbook lines are spoken in the **book's own language** (auto-detected script).
- Engines need **no API key** (Google gtx endpoint → MyMemory → Lingva fallback
  chain). Results are **cached on the phone**, so a class translated once replays
  offline. If the first run is offline the app says so honestly and plays English.

**Podcast class.** The same teaching as audio: artwork with animated equalizer,
part selector, scene scrubber, 75/100/120% speed, transcript with tap-to-jump, and
the same explanation-language option.

**Quiz with answers.** 8 instant-feedback questions (MCQ + fill) built only from
that part's own key points. Correct answer + the textbook line appear immediately,
with streak counter, XP (+5 correct, +25 on pass) and a full answer key at the end.

**Mind map.** Radial map of the part with every key point as a branch; tap a node to
read/hear the full textbook line, pinch to zoom.

**Key Points Book.** Every part's key points (plus the website-brain summary when
present) in one searchable booklet, read aloud with one tap and saved as a `.txt`
file on the phone.

**Exams & eligibility (unchanged, still enforced).** Part tests stay MCQ + fill +
short + optional timing and negative marking; **40% passes the part and unlocks the
next class**. Report card keeps marks, grades, XP levels and rank bands.

## v0.15.0 — labs & labelled figures
Physics/chemistry/biology experiments are taught as full labs:
aim -> materials -> numbered steps -> observation -> result, with
safety callouts; board colours change by phase. Figure scenes now
show the textbook's figure label and nearby diagram labels as chips
while zooming onto the labelled region.

## v0.14.0 — subject-wise teaching engine
The subject of any uploaded textbook is auto-detected (Maths,
Science, Social, Language, Vocational, any language book) and classes
teach in that style: step-by-step solving for maths/trades (+safety),
daily-life connects for science/social, timelines for history dates,
grammar rules + vocabulary cards + fill-in practice for language —
every point referenced to real textbook pages/passages.

## v0.13.0 — voice-true sync + Zoom-style classes
The lesson player is rebuilt: Android TTS reports the exact spoken
character range, and board writing, captions and the page highlighter
move from those ranges — no more timer-estimate drift. Figure/diagram
areas of each page get Zoom-style focus scenes, and boards/fonts adapt
to the matter (formulas → graph board + mono type, definitions → green
board, examples → white board, long matter → ruled notebook).

## v0.12.0 — student-only
Founder/principal/teacher/staff roles are removed. One learner adds a
textbook PDF and learns: PDF-based interactive lessons ("video
classes"), Ask-PDF chat, optional per-device website brain, tests,
report card — everything on the student's own device.

## v0.7.0 — auto Gofile + cloud link catalog

When a teacher/principal adds a textbook PDF it is now **automatically
uploaded to Gofile** and its link is registered in a **shared cloud
catalog** (Google Form → Google Sheet, entries stored encoded, nothing
readable on any public page). Student devices read the catalog, so new
links appear everywhere. One-time setup: see `CATALOG-SETUP.md`.

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
