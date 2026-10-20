# AI Textbook Classroom

**Turn a school textbook PDF into a teacher that teaches it — on the device.**

You add a textbook. The app reads it, plans a lesson, and plays that lesson like a
live class: a board that writes itself, a voice that speaks every line, figures cut
straight out of your book, quick questions, exams and a report card. Works on
**Android and Windows**, offline once a book has been read.

> **v0.24.0 — AI reads the PDF, and it is free by default.**
> The on-device parser (Syncfusion) is gone. The PDF is read by the AI with two
> editable prompts: one extracts the page text and says **where** each figure
> sits, the other designs the **lesson script**. Free mode drives the public
> PDF-teacher website inside the app's own WebView — no key, no account, no
> cost. Your own API key (OpenAI / Gemini / Claude) is an optional upgrade.
> Pages and figures are still rendered and cut **on this device**, so the video
> is produced locally.

---

## What it does

| | |
|---|---|
| 📚 **Add a textbook** | Pick any PDF. It is uploaded once to your AI, read page by page, and cached so the book works offline afterwards. |
| 🆓 **Free AI (default)** | The public PDF-teacher site is automated in the app's WebView: the PDF is uploaded through the page's own file input, prompts are typed into its chat, answers are read back. No key, no cost. |
| 🧠 **AI extraction** | Custom prompt → `{title, subject, pages[{page, text, figures[{caption, where}]}]}`. Batched for big books (12 pages per call, 40 for very large ones). |
| ✂️ **Figures: AI says where, the app measures** | The model can describe a figure and say it is at the top/middle/bottom of a page. The app renders that page and finds the exact box from the pixels (`FigureFinder`), then crops it out of the PDF with PDFium. No vision model, no invented coordinates. |
| 🎬 **AI-designed lessons** | A second custom prompt asks the AI how the video should run: scene order, narration, board text and which figure to show. The result is validated scene by scene. |
| 📺 **On-device video** | The lesson is *rendered on the device*: Flutter paints the board, the system voice narrates with word-level highlighting (Android), figures and pages are local files. |
| 🗣️ **Speech on both platforms** | Android keeps the native bridge (real word ranges); Windows uses `flutter_tts`. |
| 🧪 **Exams, flashcards, revision** | Question bank, listening exam, daily challenge, SRS flashcards, report card and a completion certificate. |
| 🔐 **Child profiles** | PIN-protected profiles in an encrypted, emoji-encoded vault, with an optional free Nostr-relay backup. |
| 🎨 **Themes** | Six built-in themes plus a custom theme studio with export/import. |

## How a lesson is made

```
 PDF ──upload──▶  AI  (free website in WebView  ·  or your own API key)
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

## Choose the AI (once)

`Settings → AI & Prompts → How to reach the AI`

| | **Free — automate the website** *(default)* | **My own API key** |
|---|---|---|
| Cost | nothing | per book, on your account |
| Setup | none | paste a key |
| Platforms | Android (WebView) | Android **+ Windows** |
| Can see page images | no — hence the local figure finder | yes (Gemini / GPT-4.1 / Claude) |

Both use the same prompts and the same on-device lesson pipeline; only the AI
behind them changes.

### API mode

| Provider | Default model | PDF support |
|---|---|---|
| Google Gemini | `gemini-2.5-flash` | ✅ PDF uploaded inline |
| OpenAI | `gpt-4.1-mini` | ✅ PDF uploaded via the Responses API |
| Anthropic | `claude-sonnet-4-5` | ✅ PDF as a document block |
| Custom (OpenAI-compatible) | `gpt-4o-mini` | text only |

The key is stored in the platform keystore (`flutter_secure_storage`), never in
the repo and never in a log. **Test connection** works in both modes: it asks
for the single word `READY`.

### Prompts (both modes)

The three prompts (extraction, video script, doubt answering) are editable and
can be reset to defaults. Placeholders are filled by the app, so a teacher can
change the teaching style without touching code.

> **How free mode works:** the WebView opens the public PDF-teacher site, feeds
> the PDF to its file input through a `DataTransfer` (no native picker), types
> the prompt into its "Ask PDF" box, clicks send and reads the streamed answer
> out of the page. A small panel shows the live page while it works. The site's
> layout can change at any time — if it does, the app says so and you can switch
> to an API key.

## Build & run

```bash
git clone https://github.com/luckyassociation1107/mdk-tech-educational-ai
cd mdk-tech-educational-ai/app
flutter pub get
flutter analyze        # 0 errors
flutter test           # 56 tests
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

`flutter test` runs 56 tests: 24 for the AI pipeline (request bodies for all
four providers, response parsing, JSON repair, bbox normalisation, batched
extraction, script validation, crop fallbacks) and 8 for the local figure
finder (synthetic pages with text lines, coloured figures and line drawings).
`flutter analyze` reports **0 errors**.

## Honest limits

- **Free mode depends on somebody else's website.** It is free because the
  public PDF-teacher site pays for the model. It can change or disappear, and it
  works on Android only (WebView). API mode is the durable path.
- **Free mode cannot see the pages**, so figure boxes come from the local
  pixel finder — accurate for charts, photos and boxed diagrams, weaker for a
  small sketch in a corner. API mode with a vision model can return exact boxes.
- **Scanned PDFs** need a vision-capable model in API mode.
- **API cost** is on your own account, per book (~9 extraction calls for 100
  pages, plus one call per lesson part).
- Windows needs `dart run pdfx:install_windows` once before building.
- Public Nostr relays may prune old events — the encrypted emoji code is the
  durable backup.

## License

No license file is included yet; all rights reserved by the author.
Third-party notices: **pdfx** (MIT), **flutter_tts** (MIT), Syncfusion is no
longer used.
