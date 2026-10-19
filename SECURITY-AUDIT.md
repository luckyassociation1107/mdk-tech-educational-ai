# Security audit — AI Textbook Classroom (v0.9.0)

Checked the actual code on 2026-10-19. Ordered by severity.

## 🔴 High

1. **User passwords are weakly hashed** (`auth_models.dart`)
   `sha256(salt + "::" + password)`, one round, and the salt is only
   32-bit. All accounts sit in plain SharedPreferences JSON. Anyone who
   gets the app's data file (rooted phone, stolen backup) can crack
   every password offline in minutes.
   **Fix:** key-derivation function like PBKDF2 (≥100k rounds,
   pointycastle already ships it) + 128-bit salt + secure storage.

2. **No login lockout** (`login_screen.dart` / `auth_store.dart`)
   Unlimited password guesses on the login screen. Local-only, but a
   lost phone = free brute force against weak passwords.
   **Fix:** attempt counter with growing delay / temporary lock.

3. **All long-lived secrets are in plain SharedPreferences** (`store.dart`, `gofile_service.dart`)
   - catalog **nsec** (publish-as-school key)
   - catalog **secret** (decrypts the whole catalog)
   - per-teacher **Gofile guest token** (can delete that teacher's files)
   **Fix:** `flutter_secure_storage` (Android Keystore / Windows DPAPI).

4. **Android backup is not disabled** (`AndroidManifest.xml`)
   No `allowBackup`/backup-rules, so app data (accounts, hashes, keys,
   tokens) can leave via ADB/Google backup.
   **Fix:** `android:allowBackup="false"` (or rules excluding prefs).

5. **APK release is debug-signed** (`app/android/app/build.gradle`)
   `signingConfig signingConfigs.debug`. The debug key is identical for
   everyone — tampered "updates" can be produced trivially, and Play
   Protect treats it as untrusted.
   **Fix:** real release keystore (kept outside the repo), CI secret.

6. **Catalog ciphertext is publicly harvestable, protection = human phrase**
   (`catalog_codec.dart`, `nostr_service.dart`)
   Entries are published with a public `t=mdk-textbook-catalog` tag, so
   ANYONE can enumerate every school's catalog ciphertext from public
   relays. The AES key is one plain SHA-256 of the school's secret
   phrase — a weak phrase ("school123") falls to offline dictionary
   attack; relays keep the ciphertext forever.
   **Fix:** drop the discoverable topic tag (readers query by npub
   anyway) + PBKDF2-HMAC-SHA256 (≥200k iterations) for key derivation +
   encourage long secrets.

## 🟠 Medium

7. **Relay events are trusted without signature verification** (`nostr_service.dart`)
   Fetch filters by `pubkey` but never calls the existing
   `verifyBip340`. A rogue/buggy relay could inject entries claiming
   our npub. AES-secret entries resist (they won't decrypt), encoded
   legacy entries do not.
   **Fix:** verify every event signature before decoding.

8. **Students open catalog URLs unchecked** (`student_home.dart`)
   `launchUrl(pdf.downloadPage)` accepts any host/scheme. A poisoned
   entry (leaked nsec) could send students to phishing sites.
   **Fix:** allow only `https://gofile.io/d/…` before launching.

9. **Online-brain traffic may be plaintext + arbitrary endpoint** (`settings_screen.dart`, `engine_gateway.dart`)
   The brain server URL is free text and `http://` is the hinted form —
   textbook PDFs can flow over cleartext to any server a device is
   pointed at.
   **Fix:** require HTTPS (explicit warning override for LAN), show
   where the PDF is being sent.

10. **One shared nsec = one point of total compromise** (by design)
    A single leaked staff phone can publish forever; `by` is
    self-claimed, so entries can impersonate the principal. Revocation
    means rotating the key on every device.
    **Fix (later):** per-teacher keys + an npub allow-list the founder signs.

11. **Marks/exams integrity is purely local** (`auth_store.dart`)
    Report cards/ranks live in editable on-device JSON — a technical
    student can inflate marks. Acceptable for classroom use today;
    don't use ranks for high-stakes decisions.

## 🟡 Low / notes

- **Unsigned Windows Setup.exe** — SmartScreen warnings; anyone can
  repackage the installer. Code-signing certificate fixes it (paid).
- **Gofile links are bearer links** — any student can forward a
  decrypted link outside school; the 10-day inactivity retirement is
  the only leash (by design).
- **GitHub repo is public** — intentional, but it documents the
  protocol; combined with #6 it tells attackers exactly where to
  harvest. Security must never depend on the code being hidden.

## ✅ Already solid

- BIP-340 signing verified against the official test vector.
- Per-entry AES-GCM random IV; wrong-secret decryption fails closed.
- Students are genuinely read-only in UI + publication scoping by
  school/class in the store.
- PDFs only to Gofile; videos never uploaded (Playwright engine only).
- No hardcoded secrets anywhere in the repo; GitHub tokens never stored.

---
## Fix status (v0.10.0, 2026-10-19)
- ✅ #1 PBKDF2-HMAC-SHA256 (100k) + 128-bit salt; legacy hashes migrate at login
- ✅ #2 Login lockout: 5 fails → 30s, escalating to 1h
- ✅ #3 nsec / catalog secret / Gofile tokens in flutter_secure_storage (+ auto-migration)
- ✅ #4 allowBackup=false
- ✅ #5 Real PKCS12 signing via CI secrets (keystore generated; founder adds GitHub secrets)
- ✅ #6 Topic tag removed; catalog key now PBKDF2 200k (MDKENC2; ENC1 still readable)
- ✅ #7 Every relay event: id recomputed + BIP-340 signature verified client-side
- ✅ #8 Students only launch https://gofile.io links
- ✅ #9 HTTPS enforced for non-LAN brain URLs
- ✅ #10 Per-teacher keys: own nsec per device + npub approval list (Settings, one per line)
- ✅ #11 Exam results sealed (HMAC) with secure-storage device key; tamper → discarded
- ⏳ #12 Windows code-signing certificate (paid/external — SmartScreen only)
- ℹ️ Gofile bearer links & public repo: by design; protection = encryption keys, never obscurity
