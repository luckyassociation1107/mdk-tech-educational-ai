# Setup

## 1. Choose the AI

**Free (default)** — nothing to configure. The app drives the public
PDF-teacher website inside its own WebView; the PDF is uploaded there and the
prompts are typed into its chat. Android only.

**Your own key** — needed on Windows, and better for scans (a vision model can
see the page images). Reading a textbook then requires a model that accepts a
PDF file.

| Provider | Where to get a key | Suggested model |
|---|---|---|
| Google Gemini | aistudio.google.com → API key | `gemini-2.5-flash` |
| OpenAI | platform.openai.com → API keys | `gpt-4.1-mini` |
| Anthropic | console.anthropic.com | `claude-sonnet-4-5` |
| Custom | your own OpenAI-compatible server | any text model (no PDF upload) |

In the app: **Settings → AI & Prompts → How to reach the AI → My own API key →
paste key → Test connection → Save.** In free mode just press **Test
connection** — it should answer `READY`.

## 2. Run on Android

```bash
cd app
flutter pub get
flutter run            # phone or emulator (Android 8.0+, minSdk 26)
```

## 3. Run on Windows

```bash
cd app
flutter config --enable-windows-desktop
flutter create --platforms=windows --org com.mdk --project-name textbook_video_classroom .
dart run pdfx:install_windows      # required once: pins the PDFium build
flutter pub get
flutter build windows
```

`pdfx:install_windows` edits the generated `windows/CMakeLists.txt` so the
bundled PDFium matches the plugin. Without it, page rendering fails on Windows
(the app still works; pages show "Page not rendered").

## 4. Tests

```bash
cd app
flutter analyze      # 0 errors
flutter test         # 59 tests
```

The AI tests use a fake transport — no key or network is needed.

## 5. Prompts

All three prompts are editable in the app and stored with the rest of the AI
settings (key: keystore, prompts: preferences).

| Prompt | Placeholders |
|---|---|
| extract | `{start}` `{end}` `{total}` |
| script | `{title}` `{subject}` `{language}` `{grade}` `{part}` `{pages}` `{teacher_note}` `{content}` `{figures}` |
| ask | `{title}` `{pages}` `{content}` `{question}` `{language}` |

The extraction prompt **must** return
`{"title", "subject", "pages":[{"page","text","figures":[{"caption","bbox"}]}]}`.
The script prompt **must** return `{"scenes":[…]}`, where a scene is one of
`title | board | figure | quick | daily | summary`. Unknown extras are ignored;
invalid scenes are dropped (and the on-device builder takes over below 4 scenes).
