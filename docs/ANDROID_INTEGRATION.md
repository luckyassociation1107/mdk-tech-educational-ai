# Android integration strategy

## Verified core (runs anywhere Python runs)
The whole pipeline — PDF indexing, lesson planning, schema validation,
board rendering, FFmpeg composition, session cleanup — is pure Python in
`engine/textbook_video/` and is tested on desktop. This is the code that
must behave identically on the phone.

## On-device layout (app/)
```
Flutter UI (lib/main.dart, lib/engine_gateway.dart)
   │ MethodChannel com.mdk.textbook_video/engine
Kotlin MainActivity
   ├─ Chaquopy → android_bridge.py → textbook_video engine (synced by tools/sync_engine_to_android.sh)
   ├─ Android TextToSpeech → narration; te-IN used only when the device
   │   reports the voice available (Settings screen checks this honestly)
   └─ PDFBox-Android → fallback PDF extraction producing PdfIndex JSON
```

## Compatibility notes (checked, not assumed)
- **PyMuPDF**: excellent on desktop; it does **not** ship a reliable
  Android wheel for Chaquopy. Strategy: on Android, Kotlin/PDFBox-Android
  extracts per-page text + image info into the same `PdfIndex` JSON
  schema (`PdfIndex.from_dict`), and the planner/renderer — which never
  needed PyMuPDF — works unchanged. Page rendering/cropping on device
  uses PDFBox's PDFRenderer equivalents; asset files are written into
  the session workspace and registered by ID exactly like desktop.
- **Pillow / pydantic**: pure wheels available via Chaquopy pip (pinned in
  `app/android/app/build.gradle`).
- **FFmpeg**: desktop uses system FFmpeg or the `imageio-ffmpeg` binary.
  On Android, bundle an FFmpeg binary for arm64 (e.g. an ffmpeg-kit /
  mobile-ffmpeg successor build) and point `EngineConfig.ffmpeg` at it;
  the engine only ever invokes the configured binary path.
- **Chaquopy** plugin 16.x with Python 3.11, minSdk 26, arm64-v8a —
  configured in Gradle. Storage stays in the app-private directory, so
  no broad storage permissions are needed; exports go to the app exports
  folder and are shared through the system share sheet.

## Why a MethodChannel and not a server
The spec forbids silently adding a remote rendering server. Rendering
stays on-device. The only network step is the brain: the Playwright
automation website is itself a cloud service, reached over HTTPS; the
UI discloses that the PDF is sent there for understanding.

## Build (where Android Studio / Flutter SDK exists)
```bash
cd app
flutter pub get
../tools/sync_engine_to_android.sh
flutter build apk --debug      # or: flutter run
```
The sandbox used to develop this project has Java but no Flutter or
Android SDK, so the APK itself has not been compiled here — the Flutter
and Kotlin sources are written to the standard project layout so this
build is the intended next step, and anything unbuilt is labelled as such.
