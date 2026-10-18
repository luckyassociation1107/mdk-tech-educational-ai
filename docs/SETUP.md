# Setup

## 1. Python engine (desktop prototype)
```bash
cd engine
pip install -r requirements.txt     # PyMuPDF, Pillow, pydantic, imageio-ffmpeg, pytest
python -m textbook_video.cli demo --brain offline
pytest -q
```

## 2. Playwright brain (the AI — no API key)
```bash
cd ../../pdf-summarizer-automation
npm install
npx playwright install --with-deps chromium
node server.js                       # serves http://127.0.0.1:3000
```
Then in `engine/`: `python -m textbook_video.cli demo --brain playwright`
Environment (optional): `BRAIN_MODE`, `PDF_SUMMARIZER_SERVER`,
`PDF_SUMMARIZER_PROJECT`, `TEXTBOOK_VIDEO_DATA`, `TTS_MODE` (`auto|espeak|captions`).

No credentials exist anywhere in this codebase: the brain website needs
no key, and nothing is hardcoded (§3, §23 of the spec).

## 3. Android app
Requires Flutter SDK + Android Studio (not present in the dev sandbox):
```bash
cd app
flutter pub get
../tools/sync_engine_to_android.sh
flutter run          # device/emulator with internet for the brain step
```

## 4. Make your own textbook video (CLI)
```bash
python -m textbook_video.cli create --pdf MyBook.pdf --brain playwright
python -m textbook_video.cli ask --session session_xxx --question "Explain photosynthesis with daily-life examples" --mode detailed_teaching
python -m textbook_video.cli disconnect --session session_xxx   # deletes temp files, keeps exports/
```
Modes: `quick_explanation`, `detailed_teaching`, `complete_concept_mastery`.
