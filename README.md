# AI Textbook Classroom

**Turn a school textbook PDF into a teacher that teaches it — on the device.**

You add a textbook. The app reads it, plans a lesson, and plays that lesson like a
live class: a board that writes itself, a voice that speaks every line, figures cut
straight out of your book, quick questions, exams and a report card. Works on
**Android and Windows**, offline once a book has been read.

> **v0.24.0 — the AI now reads the PDF, not the device.**
> The old on-device parser (Syncfusion) is gone. The PDF is uploaded to the
> teacher's **own** AI account with a custom prompt; the model returns the page
> text and the bounding box of every figure. The AI also designs the lesson
> script from a second, editable prompt. Pages and figures are then rendered and
> cropped locally, so the video is still produced on this device.

---

## What it does

| | |
|---|---|
| 📚 **Add a textbook** | Pick any PDF. It is uploaded once to your AI, read page by page, and cached so the book works offline afterwards. |
| 🧠 **AI extraction** | Custom prompt → `{title, subject, pages[{page, text, figures[{caption, bbox}]}]}`. Batched for big books (12 pages per call, 40 for very large ones). |
| ✂️ **Figures by coordinates** | Every figure carries a normalised box `[x0,y0,x1,y1]`; the app cuts that exact rectangle out of the PDF with PDFium. No figures → no figure scenes. |
| 🎬 **AI-designed lessons** | A second custom prompt asks the AI how the video should run: scene order, narration, board text and which figure to show. The result is validated scene by scene. |
| 📺 **On-device video** | The lesson is *rendered on the device*: Flutter paints the board, the system voice narrates with word-level highlighting (Android), figures and pages are local files. |
| 🗣️ **Speech on both platforms** | Android keeps the native bridge (real word ranges); Windows uses `flutter_tts`. |
| 🧪 **Exams, flashcards, revision** | Question bank, listening exam, daily challenge, SRS flashcards, report card and a completion certificate. |
| 🔐 **Child profiles** | PIN-protected profiles in an encrypted, emoji-encoded vault, with an optional free Nostr-relay backup. |
| 🎨 **Themes** | Six built-in themes plus a custom theme studio with export/import. |

## How a lesson is made

```
 PDF ──upload──▶  YOUR AI  (provider + key + prompts, set once in Settings)
                   │
                   │  ① extraction prompt
                   ▼
     { pages: [ {page, text, figures:[{caption, bbox}]} ] }   ── cached in the session
                   │
                   │  ② script prompt (+ teacher's own note for this part)
                   ▼
     { scenes: [ title, board, figure(page,bbox), quick, daily, summary ] }
                   │
                   ▼
   ON THIS DEVICE:  PDFium renders pages → bbox crops the figures →
                    Flutter paints the board → system TTS narrates →
                    word-synced highlighting, diagrams, XP
```

Nothing about the lesson is streamed or rendered elsewhere: the AI returns **text
and coordinates**, never video, and the app builds the class itself.

## Add your AI key (one time)

`Settings → AI & Prompts`

| Provider | Default model | PDF support |
|---|---|---|
| Google Gemini | `gemini-2.5-flash` | ✅ PDF uploaded inline |
| OpenAI | `gpt-4.1-mini` | ✅ PDF uploaded via the Responses API |
| Anthropic | `claude-sonnet-4-5` | ✅ PDF as a document block |
| Custom (OpenAI-compatible) | `gpt-4o-mini` | text only |

The key is stored in the platform keystore (`flutter_secure_storage`), never in
the repo and never in a log. **Test connection** does a one-line round-trip.
The three prompts (extraction, video script, doubt answering) are editable and
can be reset to defaults.

## Build & run

```bash
git clone https://github.com/luckyassociation1107/mdk-tech-educational-ai
cd mdk-tech-educational-ai/app
flutter pub get
flutter analyze        # 0 errors
flutter test           # 48 tests
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
  ai/            ai_config, ai_client (4 providers), prompts, extractor,
                 script designer, brain (summary & Q&A), JSON repair
  pdf/           pdf_raster — pages + figure crops (PDFium, Android & Windows)
  speech/        speech_channel — Android bridge / flutter_tts everywhere else
  engine         dart_engine, engine_gateway, subject_engine, lesson_content
  screens/       31 screens (home, lesson player, reader, exams, vault, …)
  vault/         PBKDF2 + HMAC sealing, emoji codec, secp256k1, Nostr sync
app/test/        48 tests: AI pipeline, vault, brain/clip, UI smoke
docs/            architecture, setup, platforms, troubleshooting
```

## Testing

`flutter test` runs 48 tests, including 24 for the AI pipeline with a fake
transport: request bodies for all four providers, response parsing, JSON repair,
bbox normalisation, batched extraction, script validation and figure cropping
fallbacks. `flutter analyze` reports **0 errors**.

## Honest limits

- **You need your own API key.** Reading a book without one is not possible any
  more — that is the point of the change.
- **Scanned PDFs** need a vision-capable model; the PDF is sent as a file, so
  Gemini / GPT-4.1 / Claude can see the pages.
- **Cost** is on your account, per book. A 100-page book is ~9 extraction calls
  plus one call per lesson part.
- Windows needs `dart run pdfx:install_windows` once before building.
- Public Nostr relays may prune old events — the encrypted emoji code is the
  durable backup.

## License

No license file is included yet; all rights reserved by the author.
Third-party notices: **pdfx** (MIT), **flutter_tts** (MIT), Syncfusion is no
longer used.
