# Service Billing Tool

Client billing, invoice, pricing, party-ledger and to-do tool. Static web app backed by Supabase
(Postgres + Auth + private file storage), installable as an app (PWA).

Files: `index.html` (page + styles), `app.js` (all logic), `early.js` (theme + anti-framing),
`config.js` (public settings), `sw.js` (offline shell), `vendor/supabase.js` (pinned library), `supabase/*.sql`.

## One-time setup

1. Create a free Supabase project. **SQL Editor** -> run `supabase/schema.sql`, then `supabase/hardening.sql`.
2. **Authentication**: turn **off** "Allow new users to sign up" and **off** "Allow anonymous sign-ins".
   Add your user (Users -> Add user, auto-confirm). Turn **on** CAPTCHA protection (Turnstile) if you use it.
3. Put the Project URL and anon key in `config.js`. The anon key is public by design (role `anon`).
   Also update the Supabase host in the `Content-Security-Policy` tag at the top of `index.html` if the URL changes.
4. Host the folder on any static host (GitHub Pages is configured).
5. In the app, open **Security** and turn on two-step verification (authenticator app).

## Security model (short)

- Data is protected by sign-in + row-level security. `hardening.sql` limits access to an allow-list of e-mails
  (`public.allowed_users`), blocks anonymous users, requires the 2-step code once it is enabled, records every change
  in `public.audit_log`, and limits uploads to 10 MB JPEG/PDF.
- The browser rebuilds all loaded data through a whitelist (`sanitizeState`) and escapes every value placed in HTML.
- Saving is version-checked: if another device changed the same record first, the save is refused and the latest data
  is reloaded (nothing is overwritten silently).
- A strict Content-Security-Policy is set in `index.html`; the Supabase library is vendored (v2.117.2, sha384
  `Rj26LVGvoeRVR6+mwQmFfcR3QOBEwT+ZmuCWpuiqeTzJpCs0ER4ITAWGb4Hiy3Ok`) instead of loaded from a CDN.
- Signed-in sessions end after 30 minutes without activity.
- Never commit exports, spreadsheets or keys (see `.gitignore`).

## Updating the vendored library

Download the exact version from two CDNs, confirm they are byte-identical, compare the sha384 above, replace
`vendor/supabase.js`, update the version/hash here and bump `CACHE` in `sw.js`.

## Data

- Clients, pricing, invoices and payments: Postgres tables `clients`, `pricing`, `invoices`, `meta`.
- Payment proofs and task attachments: private bucket `proofs`, opened through short-lived signed links.
- Free Supabase projects have no automatic backups: use **Export data** regularly (records only; proof files stay in Storage).

## Google Calendar sync

To-do tasks sync to your primary Google Calendar from the browser (Google OAuth token flow).
Set `googleClientId` in `config.js` (Google Cloud -> Credentials -> OAuth client ID, type Web application,
authorized JavaScript origin = the site URL). Then To-do -> "Connect Google Calendar".
A task can also invite another e-mail address; invoice/client details are never put in calendar events that have guests.
