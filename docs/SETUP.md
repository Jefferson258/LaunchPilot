# Setup — secrets & first run

LaunchPilot is **one repo**. Kits for TestFlight upload and App Store Connect
metadata / optional submit live under `kits/`. Secrets stay in **gitignored**
local files (or outside the repo entirely). Nothing below should ever be
committed.

## Quick start (no Apple / no Cursor)

```bash
git clone https://github.com/Jefferson258/LaunchPilot.git
cd LaunchPilot
./bin/pilot demo          # bundled site build + QA screenshots
./bin/pilot preflight     # readiness report
```

## Where secrets go

| What | Where (local only) | Template (committed) |
|------|--------------------|----------------------|
| Cursor / Vercel / workspace | `config/pilot.env` | `config/pilot.env.example` |
| Your product list | `config/products.json` | `config/products.example.json` |
| Apple Team + ASC API key | `kits/testflight/config.sh` | `kits/testflight/config.example.sh` |
| Your Xcode apps (paths, bundle IDs, ASC app IDs) | `kits/testflight/apps.sh` | `kits/testflight/apps.example.sh` |
| ASC `.p8` private key | `~/.appstoreconnect/private_keys/AuthKey_….p8` | — (never in git) |
| ASC listing copy + screenshots | `kits/appstore/products/<app>/` | see `kits/appstore/README.md` |

Screenshots under `kits/appstore/products/*/screenshots/` are gitignored (large /
marketing-specific). Metadata markdown can be committed if you want, or kept local.

```bash
cp config/pilot.env.example config/pilot.env
cp config/products.example.json config/products.json
cp kits/testflight/config.example.sh kits/testflight/config.sh
cp kits/testflight/apps.example.sh kits/testflight/apps.sh
# edit the four local files; put your .p8 under ~/.appstoreconnect/…
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
      onboarding/                  ← Notion / Mac setup notes
  MyApp/                           ← your product repos
  MySite/
```

## iOS / TestFlight

1. Fill `kits/testflight/config.sh` (Team ID, ASC key id/issuer, path to `.p8`).
2. Fill `kits/testflight/apps.sh` — one case per app; `tf_key` in `products.json`
   must match the case name (`juicd`, `velour`, …).
3. Signing: Distribution cert + App Store profiles (see
   `kits/testflight/make-signing-assets.sh` and `YOUR_CONFIG_CHECKLIST.md`).
4. Smoke:

```bash
./bin/pilot preflight
./bin/pilot build my-app
./bin/pilot testflight my-app --confirm   # gated upload
```

## App Store Connect metadata / screenshots

```bash
# optional promotional frames
python3 kits/appstore/overlay-screenshots.py

# push listing + screenshots (positional app key — not --app)
python3 kits/appstore/push-metadata.py juicd
```

See `kits/appstore/README.md`.

## Optional: App Store Submit for Review

Wired for **future** use. Safe by default; not part of `--ship`.

```bash
# Read-only plan (version state, whether submittable) — preferred
./bin/pilot appstore-submit juicd-app --dry-run

# Real submit (creates reviewSubmission + items, sets submitted=true)
./bin/pilot appstore-submit juicd-app --confirm

# Pipeline opt-in (never implied by --ship)
./bin/pilot run juicd-app "…" --ship-appstore
```

Requires ASC API key with permission to submit. Prefer owner smoke + ASC UI for
first launches; keep automation for later.

## Visual QA

```bash
./bin/pilot qa juicd-app
./bin/pilot qa juicd-site
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
- Never commit `pilot.env`, `products.json`, `config.sh`, `apps.sh`, or `.p8` files.
- Details: [SECURITY.md](../SECURITY.md) · [policy.json](../config/policy.json).
