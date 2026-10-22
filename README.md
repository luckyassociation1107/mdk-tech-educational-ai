# AI Textbook Classroom

**Turn a school textbook PDF into a teacher that teaches it — on the device.**

You add a textbook. The app reads it, plans a lesson, and plays that lesson like a
live class: a board that writes itself, a voice that speaks every line, figures cut
straight out of your book, quick questions, exams and a report card. Works on
**Android and Windows**, offline once a book has been read.

> **v0.28.0 — no sign-up, no login, no key, no cloud.** The app opens straight
> into the classroom: one learner lives on the device, and progress is backed
> up as an emoji code. There is no paid option anywhere in the app — reading a
> book is free.
> The PDF is read by the AI with two editable prompts: one extracts the page
> text and says **where** each figure sits, the other designs the **lesson
> script**. The AI is the public PDF-teacher website, driven inside the app's
> own WebView — no key, no account, no subscription, no cost. Pages and figures
> are still rendered and cut **on this device**, so the video is produced
> locally. (Reading a book needs Android; Windows plays books already read.)

---

## What it does

| | |
|---|---|
| 📚 **Add a textbook** | Pick any PDF. It is uploaded once to the free AI, read page by page, and cached so the book works offline afterwards. |
| 🆓 **Free AI — the only mode** | The public PDF-teacher site is automated in the app's WebView: the PDF is uploaded through the page's own file input, the prompts are typed into its chat, the answers are read back. One plugin, both platforms — `flutter_inappwebview` (Android WebView / Edge WebView2). No key, no account, no cost. |
| 🧠 **AI extraction** | Custom prompt → `{title, subject, pages[{page, text, figures[{caption, where}]}]}`. Batched for big books (12 pages per call, 40 for very large ones). |
| ✂️ **Figures: AI says where, the app measures** | The model can describe a figure and say it is at the top/middle/bottom of a page. The app renders that page and finds the exact box from the pixels (`FigureFinder`), then crops it out of the PDF with PDFium. No vision model, no invented coordinates. |
| 🎬 **AI-designed lessons** | A second custom prompt asks the AI how the class should run: three acts (hook → journey → payoff), scene order, narration, board text and which figure to show. The result is validated scene by scene. |
| 📺 **On-device video** | The lesson is *rendered on the device*: Flutter paints the board, the voice narrates, figures and pages are local files. The page is drawn at its true aspect ratio — never stretched to fill the card. |
| 🗣️ **Neural voice, male or female** | A real neural reader speaks every scene in 45 languages (Telugu, Hindi, Tamil, Kannada, Malayalam, Marathi, Bengali, Gujarati, Urdu, Nepali, Sinhala and the world languages), with a male and a female voice each. No key, no account, no cost. It falls back to the free Google voice and then to the device voice, so a class never goes silent. Clips are cached per scene. |
| 🌐 **Translation that lands** | Explanations are translated into 50 languages by a chain of free engines with two tries each; a reply that comes back unchanged is rejected instead of shown. |
| 🧪 **Exams, flashcards, revision** | Question bank, listening exam, daily challenge, SRS flashcards, report card and a completion certificate. |
| 🔐 **No sign-up, no login** | The app opens straight to the classroom. Progress is sealed on the device and can be backed up as an emoji code (copy, file, or paste on a new phone). |
| 🎨 **Themes** | Six built-in themes plus a custom theme studio with export/import. |

## How a lesson is made

```
 PDF ──upload──▶  free AI  (the PDF-teacher website, driven in the app's WebView)
                   │
                   │  ① extraction prompt
                   ▼
     { pages: [ {page, text, figures:[{caption, bbox}]} ] }   ── cached in the session
                   │
                   │  ② script prompt (+ teacher's own note for this part)
                   ▼
     { scenes: [ title, board, daily, steps, timeline, compare,
                 vocab, formula, quote, figure(page,bbox), quick, summary ] }
                   │
                   ▼
   ON THIS DEVICE:  PDFium renders pages → bbox crops the figures →
                    Flutter paints the board → neural voice narrates →
                    word-synced highlighting, diagrams, XP
```

Nothing about the lesson is streamed or rendered elsewhere: the AI returns **text
and coordinates**, never video, and the app builds the class itself.

## The AI (free, and only free)

`Settings → AI & Prompts` — there is no key field, no provider and no model to
choose, because nothing is billed:

| | |
|---|---|
| Cost | **nothing** — no key, no account, no subscription |
| Setup | **none** — install and add a book |
| Platforms | **Android 8+ and Windows 10/11** — reading a book needs a WebView, and Windows has Edge WebView2 |
| Sees page images | no — which is why the figure box is measured on the device |

**How it works:** the WebView opens the public PDF-teacher site, feeds the PDF to
its file input through a `DataTransfer` (no native picker), types the prompt into
its "Ask PDF" box, clicks send and reads the streamed answer out of the page. A
small panel shows the live page while it works. The site's layout can change at
any time — if it does, the app says so plainly instead of hanging.

### Prompts

The three prompts (extraction, video script, doubt answering) are editable and
can be reset to defaults. Placeholders are filled by the app, so a teacher can
change the teaching style without touching code.

## Build & run

```bash
git clone https://github.com/luckyassociation1107/mdk-tech-educational-ai
cd mdk-tech-educational-ai/app
flutter pub get
flutter analyze        # 0 errors
flutter test           # 51 tests
flutter run            # Android phone / emulator
```

**Windows**

```bash
flutter config --enable-windows-desktop
flutter create --platforms=windows --org com.mdk --project-name textbook_video_classroom .
dart run pdfx:install_windows     # points PDFium at the Windows build
flutter build windows
```

Prebuilt binaries: **Actions → Build Android APK / Build Windows EXE** (or the
Releases page — APK + Inno Setup installer, install-over updates).

## Project layout

```
app/lib/
  ai/            ai_service + web_ai_engine (the free AI), ai_config (prompts),
                 prompts (VISTA-style lesson prompt), extractor, script
                 designer (12 scene kinds + T01-T60 look hints), brain,
                 JSON repair
  pdf/           pdf_raster — pages + figure crops (PDFium, Android & Windows)
  speech/        neural_tts — the free neural reader (WebSocket, MP3)
               online_voice — neural → Google voice → device voice, cached
               speech_channel — Android bridge / flutter_tts everywhere else
  engine         dart_engine, engine_gateway, subject_engine, lesson_content
  screens/       30 screens (home, lesson player, reader, exams, backup, …)
  vault/         PBKDF2 + HMAC sealing, emoji codec
app/test/        51 tests: AI pipeline, figure finder, vault, brain/clip, UI smoke
docs/            architecture, setup, platforms, troubleshooting
```

## Testing

`flutter test` runs 51 tests: 18 for the AI pipeline (JSON repair, bbox
normalisation, batched extraction through a stubbed free transport, script
validation, board and option normalisation, crop fallbacks), 9 for the local
figure finder (synthetic pages with text lines, coloured figures, line drawings,
and a text column that must lose to a coloured figure) and 24 for the vault,
brain and UI. `flutter analyze` reports **0 errors**.

## Honest limits

- **The app depends on somebody else's website.** It is free because the public
  PDF-teacher site pays for the model. It can change or disappear, and it is
  driven through `flutter_inappwebview` — Android WebView, or Edge WebView2
  on Windows.
- **It cannot see the pages**, so figure boxes come from the local pixel finder —
  accurate for charts, photos and boxed diagrams, weaker for a small sketch in a
  corner.
- **Scanned PDFs cannot be read.** The free AI reads text only, so a book that is
  just photos of pages will not work.
- **Reading a book needs Android.** Windows can open and play books that were
  already read (the index, figures and lessons are cached on the device).
- Windows needs `dart run pdfx:install_windows` once before building, and
  `nuget` on PATH for the WebView2 plugin (CI does both).
- Backup is manual: copy the emoji code (or the file) somewhere safe. There is
  no cloud sync — nothing leaves the phone on its own.

## License

No license file is included yet; all rights reserved by the author.
Third-party notices: **pdfx** (MIT), **flutter_tts** (MIT), **audioplayers** (MIT), Syncfusion is no
longer used.
