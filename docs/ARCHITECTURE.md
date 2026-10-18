# Architecture

```
                ┌──────────────────────────────────────────────┐
                │ Flutter app (Android)                        │
                │ Home → Session → Question → Video → Settings │
                └───────────────┬──────────────────────────────┘
                        MethodChannel
                ┌───────────────▼──────────────────────────────┐
                │ Kotlin: Chaquopy host + Android TTS + PDFBox │
                └───────────────┬──────────────────────────────┘
                                │ JSON (validated VideoPlan)
                ┌───────────────▼──────────────────────────────┐
                │ Python engine (this repo, on-device)         │
                │ PDF index → planner → board/diagrams →       │
                │ narration timing → FFmpeg stream → MP4       │
                └───────────────▲──────────────────────────────┘
                                │ lesson text (sections)
                ┌───────────────┴──────────────────────────────┐
                │ Brain interface                              │
                │  • PlaywrightBrain — PDF Summarizer website  │
                │    via our existing automation, NO API key   │
                │  • OfflineBrain — deterministic, tests/local │
                └──────────────────────────────────────────────┘
```

Key invariants (from the project spec):
1. AI produces **content and a lesson structure only** — never code,
   never the video. Python renders the video.
2. **Page numbers are local truth**: found by searching extracted PDF
   text. The brain is explicitly told not to invent them.
3. **Assets are IDs** in a session registry; JSON contains no paths and
   no embedded image data. Unknown animations/ops are rejected.
4. **Scene duration = measured audio duration**, never an AI guess.
5. **Sessions are isolated directories**; disconnect deletes the whole
   temporary workspace and closes the brain session, while exports in
   `exports/<session_id>/` survive. Cleanup is idempotent.
6. Frames stream into FFmpeg — thousands of frame files never touch disk.
