# Setup — secrets & first run

LaunchPilot is **one repo**. Kits for TestFlight upload and App Store Connect
metadata / optional submit live under `kits/`. Secrets stay in **gitignored**
local files (or outside the repo entirely). Nothing below should ever be
committed.

## Quick start (no Apple / no Cursor)

```bash
git clone https://github.com/<your-account>/LaunchPilot.git   # your fork or copy
cd LaunchPilot
./bin/pilot demo          # bundled site build + QA screenshots
./bin/pilot preflight     # readiness report
```

## Where secrets go

| What | Where (local only) | Template (committed) |
|------|--------------------|----------------------|
| Cursor / Vercel / workspace | `config/pilot.env` | `config/pilot.env.example` |
| Your product list | `config/products.json` | `config/products.example.json` |
| Apple Team + ASC API key | `kits/testflight/config.local.sh` (or `config.sh`) | `kits/testflight/config.example.sh` |
| Your Xcode apps (paths, bundle IDs, ASC app IDs, TestFlight groups) | `kits/testflight/apps.local.sh` (or `apps.sh`) | `kits/testflight/apps.example.sh` |
| ASC `.p8` private key | `~/.appstoreconnect/private_keys/AuthKey_….p8` | — (never in git) |
| ASC per-app settings + review contact | `kits/appstore/apps.local.json` | `kits/appstore/apps.example.json` |
| ASC listing copy + screenshots | `kits/appstore/products/<app>/` | `kits/appstore/products/example/` |
| Error-spike products (Supabase refs, tables) | `kits/ops/products.local.json` | `kits/ops/products.example.json` |
| Dashboards (products, tables) + read-only DB creds | `kits/metabase/dashboards.local.json`, `supabase-connections.env` | `dashboards.example.json`, `supabase-connections.env.example` |
| Private notes / runbooks | `local/` | — |

Everything matching `*.local`, `*.local.*`, `.env.local`, `local/`, and
`kits/appstore/products/*` (except `example/`) is gitignored.

```bash
cp config/pilot.env.example config/pilot.env
cp config/products.example.json config/products.json
cp kits/testflight/config.example.sh kits/testflight/config.local.sh
cp kits/testflight/apps.example.sh kits/testflight/apps.local.sh
# edit the local files; put your .p8 under ~/.appstoreconnect/…
# optional kits:
cp kits/appstore/apps.example.json kits/appstore/apps.local.json
cp kits/ops/products.example.json kits/ops/products.local.json
```

## Layout after clone

```text
workspace/                         ← PILOT_WORKSPACE (default: parent of LaunchPilot)
  LaunchPilot/
    config/
      pilot.env.example            ← commit
      pilot.env                    ← YOU create (gitignore)
      products.example.json        ← commit
      products.json                ← YOU create (gitignore)
      policy.json                  ← gate list (commit)
    kits/
      testflight/                  ← archive, bump, upload, signing helpers
      appstore/                    ← push-metadata, overlay, submit-for-review
      qa/                          ← shared visual QA (iOS UITest + Playwright)
    docs/
      SETUP.md                     ← this file
      VISUAL_QA.md                 ← screenshot depth + products.json qa_* fields
      PHONE.md                     ← phone → wake → remote-run
      onboarding/                  ← optional Notion board setup
  MyApp/                           ← your product repos
  MySite/
```

## iOS / TestFlight

1. Fill `kits/testflight/config.local.sh` (Team ID, ASC key id/issuer, path to `.p8`).
2. Fill `kits/testflight/apps.local.sh` — one case per app, keys listed in `TF_APP_KEYS`; `tf_key` in `products.json`
   must match the case name (`example`, …).
3. Signing: Distribution cert + App Store profiles (see
   `kits/testflight/make-signing-assets.sh` and `YOUR_CONFIG_CHECKLIST.md`).
4. Smoke:

```bash
./bin/pilot preflight
./bin/pilot build my-app
./kits/testflight/archive-and-upload.sh example --dry-run   # config resolves, no upload
./bin/pilot testflight my-app --confirm   # gated upload
```

## App Store Connect metadata / screenshots

```bash
# optional promotional frames
python3 kits/appstore/overlay-screenshots.py

# push listing + screenshots (positional app key — not --app)
python3 kits/appstore/push-metadata.py example
```

See `kits/appstore/README.md`.

## Optional: App Store Submit for Review

Wired for **future** use. Safe by default; not part of `--ship`.

```bash
# Read-only plan (version state, whether submittable) — preferred
./bin/pilot appstore-submit my-app --dry-run

# Real submit (creates reviewSubmission + items, sets submitted=true)
./bin/pilot appstore-submit my-app --confirm

# Pipeline opt-in (never implied by --ship)
./bin/pilot run my-app "…" --ship-appstore
```

Requires ASC API key with permission to submit. Prefer owner smoke + ASC UI for
first launches; keep automation for later.

## Visual QA

```bash
./bin/pilot qa my-app
./bin/pilot qa my-site
```

Shared helpers live in `kits/qa/`. Depth fields (`qa_min_pngs`, `qa_required`,
`qa_strict`) live in `products.json`. `qa_strict: false` does not relax
`pilot run` (it always fails closed). Full guide: [VISUAL_QA.md](VISUAL_QA.md).
Staged App Store / Vercel rollouts: [ROLLOUT.md](ROLLOUT.md).

## Phone / remote Mac

Sleep → wake → full pipeline → sleep: `docs/PHONE.md` and
`./bin/pilot remote-check` / `remote-run`.

Do **not** put `--ship-appstore` in an iPhone Shortcut unless you intentionally
want a real ASC submit from your phone.

## Optional: Cursor coding step

Put `CURSOR_API_KEY` in `config/pilot.env`, then:

```bash
npm --prefix agent install
./bin/pilot run demo-site "Shorten the hero headline"
```

## Safety

- Default `pilot run` stops at PR.
- Production deploy / TestFlight need an explicit `--ship*` / `--confirm`.
- App Store submit needs `--ship-appstore` or `appstore-submit --confirm`
  (not covered by `--ship`).
- Never commit `pilot.env`, `products.json`, `config*.sh` / `apps*.sh` (except the `.example` templates), `*.local.*`, or `.p8` files.
- Details: [SECURITY.md](../SECURITY.md) · [policy.json](../config/policy.json).
