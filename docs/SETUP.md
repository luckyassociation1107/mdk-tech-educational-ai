# Setup

## 1. Nothing to configure

There is **no key, no account and no payment** anywhere in this app. Reading a
textbook is done by the public PDF-teacher website, driven inside the app's own
WebView: the PDF is uploaded there and the prompts are typed into its chat.

Open **Settings → AI & Prompts → Test the free AI**. It should say the site is
up and waiting for a PDF. Everything on that screen is free.

Reading a book needs **Android** (a WebView). Windows can open and play books
that were already read on the phone/emulator — index, figures and lessons are
cached on the device.

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
flutter test         # 51 tests
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
