# App Store Connect kit (inside LaunchPilot)

Push listing copy and screenshots to ASC. Optional gated **Submit for Review**.
Auth comes from the TestFlight kit's local credentials
(`kits/testflight/config.local.sh` or `config.sh`) — same ASC API key.

## Configure (local, gitignored)

```bash
cp kits/appstore/apps.example.json kits/appstore/apps.local.json
cp -R kits/appstore/products/example kits/appstore/products/<app-key>
```

`apps.local.json` holds, per app key (must match `tf_key` in
`config/products.json`): `asc_app_id` (optional if `ASC_APP_ID` is set in the
TestFlight registry), `screenshot_type`, categories, the listing folder, and an
optional `overlay` block (headline copy, colors, canvas size) for
`overlay-screenshots.py`. A top-level `review_contact` supplies the App Review
contact; if it is missing, the scripts skip creating one. Override the path
with `APPSTORE_APPS_FILE`.

Only `products/example/` is tracked; your own `products/<app-key>/` folders
are gitignored.

## Layout

```text
kits/appstore/
  _apps.py                 # shared config loader
  apps.example.json        # template → apps.local.json (gitignored)
  push-metadata.py
  overlay-screenshots.py
  submit-for-review.py     # optional ASC reviewSubmissions flow
  products/
    example/metadata.md    # template listing
    <app-key>/             # yours, gitignored
      metadata.md          # title, subtitle, description, keywords, …
      screenshots/         # PNGs for ASC
        raw/               # optional originals before overlay
```

## Commands

```bash
# From LaunchPilot root
python3 kits/appstore/overlay-screenshots.py [app-key]   # optional marketing frames
python3 kits/appstore/push-metadata.py example           # positional app key

# Submit for Review — dry-run (safe) vs execute; default = regular release
python3 kits/appstore/submit-for-review.py example --dry-run
python3 kits/appstore/submit-for-review.py example --dry-run --phased
# Prefer the Pilot wrapper (sets env gate for --execute):
./bin/pilot appstore-submit my-app --dry-run
./bin/pilot appstore-submit my-app --confirm --phased   # real submit + phased
```

`--phased` / `--no-phased` choose Apple's Phased Release vs regular (default).
Pause / Release to All stay in ASC UI. See [docs/ROLLOUT.md](../../docs/ROLLOUT.md).

Requires: `pip3 install pyjwt cryptography` (and Pillow for overlays).

**Gates:** `--ship` never submits. Use `--ship-appstore` or
`appstore-submit --confirm` only when you mean it. See [docs/SETUP.md](../../docs/SETUP.md)
and [config/policy.json](../../config/policy.json).
