# Platform notes — Android & Windows

Everything the classroom needs is either Dart or a plugin that supports both
platforms. No Chaquopy, no Python, no Kotlin PDF code.

| Job | Android | Windows |
|---|---|---|
| Read the PDF | free AI — the website, driven in the app's WebView | not available (books already read still play) |
| Render pages / crop figures | `pdfx` (PDFium) | `pdfx` + `dart run pdfx:install_windows` |
| Speak | native bridge `com.mdk.textbook_video/engine` (word ranges) | `flutter_tts` (SAPI) |
| Pick a PDF | `file_picker` | `file_picker` |
| Save files | app documents dir | app documents dir |
| Open update link | MethodChannel → Intent | (no-op: open the Releases page manually) |
| Vault / exam seals | EncryptedSharedPreferences via `flutter_secure_storage` | DPAPI via `flutter_secure_storage` |

## Android specifics

`MainActivity.kt` keeps only the TTS bridge: `speak`, `stopTts`, `checkTts`,
and the `ttsRange` / `ttsDone` callbacks that drive word-level highlighting.

## What is not platform-parity

- **Reading a new textbook is Android-only** — it needs a WebView to drive the
  free AI. On Windows, a book that was already read (index, figures, lessons in
  the session folder) opens and plays normally.

- Word-level highlighting is Android-only (Windows speech has no range callbacks).
- The in-app "open update" button is Android-only.
- `flutter_tts` on Windows needs a system voice installed (SAPI).
