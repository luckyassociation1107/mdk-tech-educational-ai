# Architecture (v0.26.0 — free only)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter UI — Android + Windows                                        │
│  Home · Lesson player · Reader · Exams · Vault · Theme Studio         │
└───────────────┬──────────────────────────────────────────────────────┘
                │
                      ┌───────────────────────┐
                      │ AiService (free only) │
                      │ WebAiEngine: drives   │
                      │ the public PDF-teacher│
                      │ site in the app's own │
                      │ Android WebView       │
                      └───────────┬───────────┘
                                  ▼
             ┌───────────────────────────┐   ┌────────────────────────┐
             │ TextbookExtractor         │   │ PdfRaster (PDFium)     │
             │ page text + caption/where │   │ page PNG, box → crop   │
             └──────────┬────────────────┘   │ Android ✓ Windows ✓    │
                        │                    └───────────┬────────────┘
             ┌──────────▼────────────────┐               │
             │ ScriptDesigner            │               │
             │ scenes (validated)        │               │
             └──────────┬────────────────┘               │
                        │                                │
                        ▼                                ▼
                 scenes (per part, cached)      pages/*.png  figures/*.png
                        │                                ▲
                        └───────────────┬────────────────┘
                                        ▼
                        Lesson player (on-device): board · voice ·
                        highlights · figures · diagrams · quick checks
                                        ▲
                        FigureFinder: page pixels → exact figure box
```

## Invariants

1. **No PDF text parser on the device.** Page text comes from the AI. The
   device only rasterises pages, measures figure boxes and crops rectangles.
2. **AI designs, the device renders.** The model returns text + coordinates,
   never media. Video, audio and animation are produced locally.
3. **Prompts are data.** Extraction, scripting and doubt-answering are stored in
   `AiConfig`, editable in Settings and covered by placeholders; the code never
   hardcodes a prompt body.
4. **Coordinates are measured, not invented.** A text-only model may say *what*
   a figure is and roughly *where*; `FigureFinder` then finds the exact box in
   the rendered page. Any box the model does return is clamped, ordered,
   size-checked, and a figure scene whose crop fails is dropped.
5. **Everything is cached per session.** `book.pdf`, `index.json`,
   `scenes[part]`, `pages/*.png`, `figures/*.png` — a generated lesson replays
   offline, byte for byte.
6. **One door, one free engine.** `AiService` is the only way AI is reached,
   and behind it there is exactly one engine: the free WebView automation. No
   endpoint, key, provider or model name exists anywhere in the codebase.
7. **Failures degrade, never block.** No AI script → the on-device scene builder
   composes a lesson from the AI-extracted text. No crop → the board explains
   the figure instead. No TTS → captions.

## Session folder

```
<documents>/classroom/<session_id>/
  book.pdf            original upload
  index.json          AI extraction: title, subject, pages[text, figures[bbox]]
  scenes (in meta)    AI script per part
  pages/page_N.png     rendered on demand (PDFium)
  figures/f_<hash>.png cropped by measured coordinates
  brain.json          summary + saved Q&A
```

Session metadata lives in `classroom/sessions.json` (single index file).

## The free engine

| Step | What happens |
|---|---|
| open | `WebViewController` loads the public PDF-teacher site once per app run |
| upload | the PDF is built into a `File` and pushed into `input[type=file]` with a `DataTransfer` + `change` event — no native picker |
| transfer | base64 in 900 KB chunks into `window.__mdkPdf`; prompts over 120 KB in 120 KB chunks — a 20 MB book cannot blow up `evaluateJavascript` |
| ask | the prompt goes into `textarea[placeholder="Ask PDF"]` through the native value setter, then the send button is clicked (retried while React enables it) |
| read | the answer is the last `.prose-sm/.prose-neutral` block; it is considered finished after two stable polls (~2 s) |
| recovery | `<dialog class="modal">` popups are closed before every step; a different book reloads the site; 4-minute timeout per call |

There is no API, no endpoint and no model name in the app — only this page.
