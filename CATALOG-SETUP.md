# Cloud link catalog — Nostr setup (founder, once, ~2 minutes)

**What this gives you:** when a teacher/principal adds a textbook PDF in the
app, it is **automatically uploaded to Gofile**, and the download link is
automatically published to the school's **catalog on public Nostr relays**.
Every device with the catalog public key sees all links — anybody with the
key setup can add, there is no company storage and no practical entry
limit, and entries travel encoded (`MDKCAT1.…`) so no readable link ever
sits on a public page.

## Steps

1. **Founder/principal phone:** Settings → **Cloud link catalog** → tap
   **Create new catalog key**. This creates the school's catalog keypair.
2. Tap **Save settings**.
3. **Choose a catalog secret** (any school-only phrase) and enter it on
   EVERY device. With it, each entry is AES-256-GCM encrypted on the
   phone before publishing: outside the app the catalog is unreadable
   ciphertext on public relays; only your school's devices decrypt and
   display titles/links.
4. **Teacher/principal devices:** also enter the **private key (nsec)**
   (the public key fills itself). These devices can publish new links.
5. **Student devices:** enter only the **public key (npub)** + the catalog
   secret. Students can read the whole catalog but cannot publish.
5. On any device tap **Test catalog read** to verify.

That is all — no account, no form, no sheet, nothing to host.

## Notes & honest limits

- Anyone holding the **nsec** can publish to (and spam) the catalog —
  share it only with your staff. Anyone holding the **npub** can read
  encoded entries. If a key leaks: create a new key, give everyone the new
  public key, and re-share important PDFs.
- Entries are obfuscated (gzip+base64), not encrypted; treat the npub like
  a school read key. Gofile free links still retire after ~10 days without
  downloads; the in-app Refresh re-uploads genuinely.
- The app asks several independent relays in parallel, so one relay being
  down does not break the catalog. Without any key setup, the app simply
  uses its on-device catalog as before.
- Optional legacy fallback: a Google Form → Sheet pair can also be
  configured in the same Settings section; the app merges both sources.
