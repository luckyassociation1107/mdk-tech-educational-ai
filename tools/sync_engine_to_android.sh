#!/bin/sh
# Copy the pure-Python engine into the Android app (Chaquopy python sources).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/app/android/app/src/main/python/textbook_video"
mkdir -p "$DEST"
cp -r "$ROOT/engine/textbook_video/." "$DEST/"
echo "Engine synced to $DEST"
echo "NOTE: pdf_processing.py uses PyMuPDF on desktop. On Android the Kotlin"
echo "PDFBox layer must supply PdfIndex JSON (see docs/ANDROID_INTEGRATION.md)."
