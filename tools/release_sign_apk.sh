#!/usr/bin/env bash
# Signs a CI-built APK with the permanent release key so that every future
# version installs OVER the previous one (no uninstall, no data loss).
#
# Requires: Java (11+), Android build-tools (zipalign + apksigner).
# The keystore and its password are NEVER stored in this repo.
#
#   KEYSTORE=/path/AI_Textbook_Classroom_java.p12 #   STOREPASS_FILE=/path/keystore-password.txt #   ./tools/release_sign_apk.sh in.apk out.apk
set -euo pipefail
BT="${BUILD_TOOLS:-$HOME/android-build-tools}"
IN="$1"
OUT="$2"
PASS="$(cat "${STOREPASS_FILE:?set STOREPASS_FILE}")"
ALIAS="${KEY_ALIAS:-mdkclassroom}"
"$BT/zipalign" -f 4 "$IN" "$OUT.aligned.apk"
"$BT/apksigner" sign \
  --ks "${KEYSTORE:?set KEYSTORE}" --ks-type PKCS12 \
  --ks-pass pass:"$PASS" --ks-key-alias "$ALIAS" --key-pass pass:"$PASS" \
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true \
  --out "$OUT" "$OUT.aligned.apk"
rm -f "$OUT.aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT"
