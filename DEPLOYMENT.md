# Vercel deployment preparation

Vercel supports the FastAPI `app` exported from the root `app.py`.
Import `muradmShah/AdmitCrew`, using the repository root and FastAPI preset.

The full application is not yet ready for a serverless deployment:

- Configure a Supabase project and apply the migrations in `supabase/setup.sql`
  for a fresh database. Local SQLite records are not migrated automatically.
- Configure SUPABASE_URL and SUPABASE_SECRET_KEY privately in Vercel.
- Configure a new private STAFF_PASSWORD and STAFF_EMAIL in Vercel.
- Replace the process-local session store with shared, expiring sessions so login
  works across function instances, and use Secure cookies on HTTPS.
- Use shared login rate limiting for the online application.
- Keep AUTO_REMINDERS disabled; a background thread is not a persistent scheduler
  on Vercel. Staff can run follow-ups manually until a scheduled endpoint is added.
- Verify registration, role isolation, document upload, approvals, and persistence
  against the deployed URL before treating the full application as available.

Never upload `.env`, the local `data/` directory, or actual student records.
`.vercelignore` excludes these from CLI uploads; `.gitignore` excludes them from Git.

A public-website-only preview is a separate option. It must clearly disable account
and messaging actions rather than present nonworking forms as available.

Reference: https://vercel.com/docs/frameworks/backend/fastapi
