# Architecture (v0.24.0)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter UI — Android + Windows                                        │
│  Home · Lesson player · Reader · Exams · Vault · Theme Studio         │
└───────────────┬──────────────────────────────────────────────────────┘
                │
      ┌─────────▼─────────┐
      │ AiService         │  picks the mode from AiConfig
      ├───────────────────┼──────────────────────────────────────────┐
      │ AiMode.webview    │ AiMode.api                               │
      │ WebAiEngine       │ AiClient (OpenAI/Gemini/Claude/custom)   │
      │ drives the public │ PDF as a file, JSON mode, retries        │
      │ site in a WebView │                                          │
      └─────────┬─────────┴───────────────┬──────────────────────────┘
                │                         │
                └──────────┬──────────────┘
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
6. **Two doors, one pipeline.** `AiService` is the only way AI is reached:
   the free WebView automation or the teacher's key. No endpoint, key or model
   name is hardcoded anywhere else.
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

## Providers

| Provider | Endpoint | PDF payload |
|---|---|---|
| OpenAI | `POST /v1/responses` | `input_file` with base64 `file_data` |
| Gemini | `POST /v1beta/models/{model}:generateContent` | `inline_data` (`application/pdf`) |
| Anthropic | `POST /v1/messages` | `document` block, base64 |
| Custom | `POST /v1/chat/completions` | not supported (text only) |

18 MB upload cap, one retry on 429/5xx, friendly errors for 401/402/403/404/413.
