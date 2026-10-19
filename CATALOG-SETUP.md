# Cloud link catalog — one-time setup (founder/principal, ~5 minutes)

**What this gives you:** when a teacher/principal adds a textbook PDF in the
app, it is **automatically uploaded to Gofile**, and the download link is
automatically registered in **one shared catalog**. Every student/teacher
device that has the catalog configured sees the new link — no manual link
copying, and the links never appear on any public web page.

How it works:

- **Write:** the app submits one *encoded* string to a Google Form
  (anonymous submission — the Form acts as the report/intake function).
- **Store:** the Form's responses land in a Google Sheet (your private
  catalog database). Entries look like `MDKCAT1.…` — not readable links.
- **Read:** apps fetch the Sheet as JSON and decode entries back to links.

## Steps

1. **Create the Form** at <https://forms.google.com>:
   - Name it e.g. `MDK Textbook Link Catalog`.
   - Add ONE question: **Short answer**, title it `entry`.
   - Settings → Responses: turn **OFF** "Collect email addresses" and
     "Limit to 1 response" (submissions must be anonymous).
2. **Link the Sheet:** in the Form's **Responses** tab, click the green
   Sheets icon → create the response spreadsheet.
3. **Share the Sheet for reading:** open the Sheet → **Share** →
   "Anyone with the link" → **Viewer**. Copy the Sheet link.
   (Reading is public-by-link, but cells only contain encoded strings.)
4. **Get the entry id:** Form → ⋮ → **Get pre-filled link** → type
   anything in the `entry` box → **Get link** → copy it. In that link find
   `entry.123456789` — that is the entry id.
5. **In the app** (every device): Settings → **Cloud link catalog**:
   - *Catalog Form link:* paste the Form's normal link
     (`…/viewform`) — the app converts it automatically.
   - *Form entry id:* `entry.123456789` from step 4.
   - *Catalog Sheet link:* the Sheet link from step 3.
   - Save, then tap **Test catalog read**.

Student devices only need the **Sheet link** to read; teacher devices need
all three to publish.

## Notes & honest limits

- Encoding is obfuscation, not encryption — treat the Sheet link like a
  read key for your school. Gofile free links themselves retire after
  ~10 days without downloads; the in-app Refresh re-uploads genuinely.
- The on-device catalog always works without this setup; the cloud catalog
  simply adds cross-device links on top.
- Google Forms/Sheets free quotas are generous for school use; nothing here
  costs money and no server or bot is involved.
