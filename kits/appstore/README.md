# App Store Connect kit (inside LaunchPilot)

Push listing copy and screenshots to ASC. Optional gated **Submit for Review**.
Auth comes from `kits/testflight/config.sh` (same ASC API key as TestFlight).

## Layout

```text
kits/appstore/
  push-metadata.py
  overlay-screenshots.py
  submit-for-review.py     # optional ASC reviewSubmissions flow
  products/
    <app>/
      metadata.md          # title, subtitle, description, keywords, …
      screenshots/         # gitignored — PNGs for ASC
        raw/               # optional originals before overlay
```

Create a folder per app key (must match keys in `push-metadata.py` / 
`submit-for-review.py` `APPS`, or edit those dicts for your own ASC app IDs).

## Commands

```bash
# From LaunchPilot root
python3 kits/appstore/overlay-screenshots.py       # optional marketing frames
python3 kits/appstore/push-metadata.py juicd       # positional app key

# Submit for Review — dry-run (safe) vs execute
python3 kits/appstore/submit-for-review.py juicd --dry-run
# Prefer the Pilot wrapper (sets env gate for --execute):
../../bin/pilot appstore-submit juicd-app --dry-run
../../bin/pilot appstore-submit juicd-app --confirm   # real submit
```

Requires: `pip3 install pyjwt cryptography` (and Pillow for overlays).

**Gates:** `--ship` never submits. Use `--ship-appstore` or
`appstore-submit --confirm` only when you mean it. See [docs/SETUP.md](../../docs/SETUP.md)
and [config/policy.json](../../config/policy.json).
