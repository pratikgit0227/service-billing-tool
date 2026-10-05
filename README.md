# Service Billing Tool

Client billing, invoice, pricing and payment-tracking tool. Static web app (`index.html`) backed by
Supabase (Postgres + Auth + private file storage), so the same data shows up on every device.

## One-time setup (~5 minutes)

1. Create a free project at https://supabase.com (region: Mumbai / ap-south-1 is closest).
2. **SQL Editor** -> New query -> paste `supabase/schema.sql` -> Run.
3. **Authentication -> Sign In / Providers -> Email**: turn **off** "Allow new users to sign up".
4. **Authentication -> Users -> Add user**: create your login (email + password, tick auto-confirm).
   Add more users the same way if others need access; everyone sees the same data.
5. **Project Settings -> API**: copy the Project URL and the `anon` / publishable key into `config.js`.
6. Open `index.html` (or deploy, below) and sign in.

## Deploy (so it opens from any device)

Any static host works. Easiest: Cloudflare Pages, Netlify or Vercel, connected to this GitHub repo
(works with a private repo, no build command, output directory = repo root). The repo and site may be
public: data is protected by login and row-level security, not by hiding the page.

## Data

- Clients, pricing, invoices and payments: Postgres tables (`clients`, `pricing`, `invoices`, `meta`).
- Payment proofs: private Storage bucket `proofs`, opened via short-lived signed links.
- Enable daily backups in Supabase (paid plan) or use **Export data** regularly (exports records; proof files stay in Storage).
- **Import data** accepts exports from this version and the old local-only version (proofs are uploaded to Storage).

## Google Calendar sync

To-do tasks sync to your primary Google Calendar from the browser (Google OAuth, token model).
Set `googleClientId` in `config.js` (Google Cloud -> Credentials -> OAuth client ID, type Web application,
authorized JavaScript origin = the site URL). Then To-do -> "Connect Google Calendar".
