# Supabase + Vercel: what's left for you (and how long)

Everything is scripted. The only thing I can't do is log into your accounts.
Each unblock below is a **token paste**, then I run one command.

---

## Vercel (websites) — ~2 min on your end

All three marketing sites build cleanly and are deploy-ready
(`Corvim-Website`, `juicd-website`, `VelourClosetWebsite`).

**You do (once):**
1. Go to <https://vercel.com/account/tokens>, create a token, copy it.
2. Tell me the token (or run it yourself):
   ```bash
   export VERCEL_TOKEN=xxxxx
   ~/Desktop/scripts/deploy-websites.sh
   ```

**Then I do:** deploy all three to live `*.vercel.app` URLs. Custom domain
`corvim.app` is already owned and attached. `juicd.app` and `velourcloset.app`
get added after you buy them.

> Time on your end: **~2 min** (make token). Deploy itself is automated.

---

## Supabase (backends)

### Velour Closet — nothing to do ✅
Velour Closet v1 is fully on-device (SwiftData). No backend, not a blocker.

### Corvim — project already exists, ~1–5 min
Corvim already has a live Supabase project wired into the app
(`ptqrkpiiflihuhcfkutd.supabase.co`, anon key in Info.plist). It responds to
API calls. What I can't verify without access is whether the **schema/migrations
are applied**.

**You do (once):**
1. Create a Supabase access token: <https://supabase.com/dashboard/account/tokens>
   ```bash
   export SUPABASE_ACCESS_TOKEN=sbp_xxxxx
   ```
2. Tell me the token + confirm the project is the Corvim one.

**Then I do:** check the schema and, if the DB is empty, apply the bootstrap
(`supabase/NEW_PROJECT_FULL_SETUP.sql`) + deploy the edge functions
(`claude-progress-advice`, `send-push-apns`). Corvim's migrations are paste-style
SQL, so if it's already set up this is a no-op.

> Time on your end: **~1 min** (make token). If the project's already migrated, **0**.

### Juicd — needs a project created, ~3–5 min
Juicd's app reads `SUPABASE_URL` / `SUPABASE_ANON_KEY` from its build settings,
but no project is wired in yet. It has timestamped migrations + 2 edge functions
ready to deploy.

**You do (once):**
1. Same access token as above works.
2. Create a blank Supabase project in the dashboard (pick a name + DB password,
   ~2 min) and copy its **project ref** (the `<ref>` in `<ref>.supabase.co`).
3. Give me the ref + token.

**Then I do:**
```bash
export SUPABASE_ACCESS_TOKEN=sbp_xxxxx
~/Desktop/scripts/deploy-juicd-backend.sh <project-ref>
```
This links the project, pushes migrations, deploys `play-board` +
`resolve-play-slip`, then I wire `SUPABASE_URL`/`SUPABASE_ANON_KEY` into Juicd's
Xcode build settings and re-upload to TestFlight.

> Time on your end: **~3–5 min** (token + create project). Rest is automated.

---

## Fastest path

1. Make **one Supabase access token** + **one Vercel token** (~4 min total).
2. Create **one blank Supabase project for Juicd** (~2 min).
3. Hand me both tokens + the Juicd project ref.

That's **~6 minutes of your time** and I deploy all three websites and both
backends. Velour Closet needs nothing.
