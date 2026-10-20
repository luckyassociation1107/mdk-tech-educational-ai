# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| “Add your AI key first” when adding a book | Settings → AI & Prompts: paste a key and press **Test connection**. |
| “The AI key was rejected (401)” | Wrong/expired key, or the key belongs to a different provider than the one selected. |
| “Model not found (404)” | The model name is wrong for that provider (or your account has no access). |
| “Rate limit or no credit left (429)” | The provider account is out of quota/credit; wait or top up. |
| “This PDF is 24 MB. The AI upload limit is 18 MB” | Compress the PDF, split the chapter, or use a provider with a larger upload limit. |
| “The AI could not read any page” | The PDF may be a scan; use a vision model (Gemini / GPT-4.1 / Claude). |
| “The AI answered pages 13–24 with something that is not JSON” | Another prompt broke the JSON contract — press the reset icon in AI & Prompts, or ask for JSON only at the start of your prompt. |
| Lessons have no figures | Either the book has no figures, or the extraction prompt's `figures` rule was changed. Re-add the book after resetting prompts. |
| “Page not rendered” in the reader | Rendering is unavailable or the page is still rendering; open the class once, or on Windows run `dart run pdfx:install_windows` and rebuild. |
| No voice on Windows | Install a system voice (Settings → Time & Language → Speech), then reopen the lesson. |
| Lesson generated but text-only | The AI script call failed (quota/offline) — the on-device builder made the lesson instead; the toast still opens it. |
| Emoji vault restore fails | The code carries its own key; check for missing emojis/line breaks, or use the local vault backup. |
