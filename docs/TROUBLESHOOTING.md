# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Free mode: “did not load” / “did not accept the PDF” | The public website is down or changed. Retry once; if it persists, switch to your own API key. |
| Free mode: works on the phone but not on Windows | The free mode needs an Android WebView. Use an API key on Windows. |
| Free mode: the answer never arrives | The site is busy. The app waits up to 4 minutes per call; retry, or switch to an API key. |
| A lesson has no figure | The page had no detectable figure, or the crop failed — the board teaches it instead. Check the caption in the extraction prompt. |
| “The free website changed its layout” | Its selectors moved. Use API mode until the app is updated. |
| “The AI is not set up yet” | Settings → AI & Prompts: pick a mode (free) or paste a key (API) and press **Test connection**. |
| “The AI key was rejected (401)” | Wrong/expired key, or the key belongs to a different provider than the one selected. |
| “Model not found (404)” | The model name is wrong for that provider (or your account has no access). |
| “Rate limit or no credit left (429)” | The provider account is out of quota/credit; wait or top up. |
| “This PDF is 24 MB. The AI upload limit is 18 MB” | Compress the PDF, split the chapter, or use a provider with a larger upload limit. |
| “The AI could not read any page” | Free mode reads text only, so a scan fails. Use API mode with a vision model (Gemini / GPT-4.1 / Claude). |
| “The AI answered pages 13–24 with something that is not JSON” | Another prompt broke the JSON contract — press the reset icon in AI & Prompts, or ask for JSON only at the start of your prompt. |
| Lessons have no figures | Either the book has no figures, or the extraction prompt's `figures` rule was changed. Re-add the book after resetting prompts. |
| “Page not rendered” in the reader | Rendering is unavailable or the page is still rendering; open the class once, or on Windows run `dart run pdfx:install_windows` and rebuild. |
| No voice on Windows | Install a system voice (Settings → Time & Language → Speech), then reopen the lesson. |
| Lesson generated but text-only | The AI script call failed (quota/offline) — the on-device builder made the lesson instead; the toast still opens it. |
| Emoji vault restore fails | The code carries its own key; check for missing emojis/line breaks, or use the local vault backup. |
