# app — AI Textbook Classroom (Flutter)

The whole application. See the [project README](../README.md) for what it does
and [docs/SETUP.md](../docs/SETUP.md) for building on Android and Windows.

```bash
flutter pub get
flutter run                 # Android
flutter test                # 48 tests
```

Key folders:

| Path | Purpose |
|---|---|
| `lib/ai/` | provider client, prompts, PDF extraction, script designer, brain |
| `lib/pdf/` | PDFium page rendering + figure crops (Android + Windows) |
| `lib/speech/` | native Android TTS bridge / `flutter_tts` fallback |
| `lib/screens/` | 31 screens |
| `lib/vault/` | encrypted child profiles, emoji codec, Nostr backup |
| `test/` | AI pipeline, vault crypto, brain/clip, UI smoke |
