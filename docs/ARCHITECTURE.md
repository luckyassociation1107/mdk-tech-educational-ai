# Architecture (v0.24.0)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Flutter UI — Android + Windows                                        │
│  Home · Lesson player · Reader · Exams · Vault · Theme Studio         │
└───────────────┬──────────────────────────────────────────────────────┘
                │
    ┌───────────▼────────────┐      ┌──────────────────────────────────┐
    │ AiConfig               │      │ PdfRaster (pdfx / PDFium)        │
    │ provider · key · model │      │ page → PNG, bbox → cropped PNG   │
    │ 3 editable prompts     │      │ Android ✓  Windows ✓             │
    └───────────┬────────────┘      └──────────────┬───────────────────┘
                │                                  │
    ┌───────────▼────────────┐                     │
    │ AiClient               │                     │
    │ OpenAI · Gemini ·      │                     │
    │ Claude · custom        │                     │
    │ PDF as file, JSON mode │                     │
    └───────┬────────┬───────┘                     │
            │        │                             │
   ┌────────▼──┐  ┌──▼──────────────┐              │
   │ Textbook  │  │ ScriptDesigner  │              │
   │ Extractor │  │ scenes + bboxes │              │
   │ batches   │  └──┬──────────────┘              │
   └────┬──────┘     │                             │
        │            │                             │
        ▼            ▼                             ▼
   index.json    scenes.json                 pages/*.png
   (AI text +    (per part, cached)          figures/*.png
    figures)          │
                      ▼
              Lesson player (on-device)
              board · voice · highlights · diagrams · quick checks
```

## Invariants

1. **No PDF text parser on the device.** Page text and figure boxes come from
   the AI. The device only rasterises pages and crops rectangles.
2. **AI designs, the device renders.** The model returns text + coordinates,
   never media. Video, audio and animation are produced locally.
3. **Prompts are data.** Extraction, scripting and doubt-answering are stored in
   `AiConfig`, editable in Settings and covered by placeholders; the code never
   hardcodes a prompt body.
4. **Coordinates are validated.** Boxes are clamped to the page, corners are
   ordered, tiny boxes are dropped, and a figure scene whose crop fails is
   removed rather than shown empty.
5. **Everything is cached per session.** `book.pdf`, `index.json`,
   `scenes[part]`, `pages/*.png`, `figures/*.png` — a generated lesson replays
   offline, byte for byte.
6. **One key, one account.** All AI traffic goes to the teacher's provider; there
   is no shared or borrowed endpoint in the codebase.
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
  figures/f_<hash>.png cropped by AI coordinates
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
