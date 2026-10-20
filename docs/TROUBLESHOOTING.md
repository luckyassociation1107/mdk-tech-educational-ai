# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| “did not load” / “did not accept the PDF” | The public website is down or changed. Retry once; if it persists, try again later. |
| Works on the phone but not on Windows | Reading a book needs an Android WebView. Windows plays books that were already read. |
| The answer never arrives | The site is busy. The app waits up to 4 minutes per call; retry. |
| A lesson has no figure | The page had no detectable figure, or the crop failed — the board teaches it instead. Check the caption in the extraction prompt. |
| “The free website changed its layout” | Its buttons or box moved. Wait for an app update — the app tells you instead of hanging. |
| “The AI is not set up yet” | Settings → AI & Prompts → **Test the free AI**. It checks that the website is reachable. |
| “The free AI needs Android” | Reading a book needs an Android WebView; Windows only plays books that were already read. |
| “The free website did not accept the PDF” | The book is very large or the site is refusing uploads. Try a smaller PDF (split the chapter) or retry later. |
| “The AI could not read any page” | The free AI reads text only, so a scanned book (photos of pages) cannot be read. |
| “The AI answered pages 13–24 with something that is not JSON” | Another prompt broke the JSON contract — press the reset icon in AI & Prompts, or ask for JSON only at the start of your prompt. |
| Lessons have no figures | Either the book has no figures, or the extraction prompt's `figures` rule was changed. Re-add the book after resetting prompts. |
| “Page not rendered” in the reader | Rendering is unavailable or the page is still rendering; open the class once, or on Windows run `dart run pdfx:install_windows` and rebuild. |
| No voice on Windows | Install a system voice (Settings → Time & Language → Speech), then reopen the lesson. |
| Lesson generated but text-only | The AI script call failed (offline / site busy) — the on-device builder made the lesson instead; the toast still opens it. |
| Emoji vault restore fails | The code carries its own key; check for missing emojis/line breaks, or use the local vault backup. |
