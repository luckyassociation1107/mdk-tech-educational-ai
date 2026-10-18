# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `BrainUnavailableError: Playwright brain server not found` | Start `node server.js` in `pdf-summarizer-automation/`, or set `PDF_SUMMARIZER_PROJECT`. |
| `browserType.launch … libnspr4.so` | Browser system libs missing: `npx playwright install --with-deps chromium` in the automation project. |
| `password_protected_pdf` | The PDF needs a password (§22). Use an unlocked copy; the app never guesses passwords. |
| Video has captions but no voice | No TTS voice on this machine/device. Engine falls back to captions mode and says so in the result (`tts_provider: captions`). On Android, install/enable a te-IN or en-IN voice in system TTS settings. |
| `Session is not attached in this process` | The app/CLI restarted; provider files are never assumed immortal (§4). Create a new session to re-attach the PDF. |
| Plan validation failed | The brain's reply could not be parsed into the strict schema after section parsing. Retry; if it persists, inspect `workspace/plans/` and the brain's raw answer. Nothing invalid is ever rendered. |
| Slow rendering | Lower `--width/--height/--fps`, or use `quick_explanation`. Frames are streamed to FFmpeg, so memory stays bounded; CPU is the limit. |
| Storage full | Disconnect old sessions (deletes temp files, keeps exports), or lower resolution. The original PDF is never deleted. |
| Telugu captions show boxes in desktop renders | DejaVu lacks Telugu glyphs; device renders should use a Noto Telugu font. Narration language ≠ caption font — check both. |
