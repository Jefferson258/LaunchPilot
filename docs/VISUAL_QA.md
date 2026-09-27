# Visual QA — LaunchPilot

How screenshot QA works across Corvim / Juicd / Velour Closet (apps + sites), and how
to keep it deep and consistent.

## Command

```bash
./bin/pilot qa <product>          # run product qa_cmd + enforce depth fields
./bin/pilot run <product> "…"     # same QA step inside the pipeline
```

Env:

| Variable | Meaning |
|----------|---------|
| `QA_DEPTH=deep\|smoke` | App wrappers default to `deep` |
| `QA_SIM_NAME` | Force simulator device name |
| `PILOT_QA_STRICT` | Legacy compatibility setting; `pilot run` always fails closed on QA failure |
| `PILOT_QA_KIT` / `PILOT_QA_WEB` | Override path to shared kit helpers |

## Shared kit (`kits/qa/`)

- **`ios-uitest-capture.sh`** — pick sim → boot → run N UITests → count PNGs  
  Used by Corvim + Juicd `scripts/capture-qa-screenshots.sh`.
- **`web-capture.mjs`** — Playwright desktop + mobile heroes, scroll slices,
  full-page, multi-route (skips HTTP ≥400). Used by all three marketing sites.
- Product-specific chrome (FakeSocial, `-QATab`, friend-code cloud test) stays
  in each repo’s UITests / launch args.

See [kits/qa/README.md](../kits/qa/README.md).

## Depth matrix (this workspace)

| Product | Capture surface | Required / min |
|---------|-----------------|----------------|
| `corvim-app` | Home, Workout, Progress, Social, Groups (FakeSocial) | 5 PNGs + named required |
| `juicd-app` | Play, Tourney, Dashboard, Friends, Profile + **cloud friend code** (`05-friends-cloud.png` in deep) | ≥5 required tab shots |
| `velour-app` | Home, Closet (+ filters + item editor in deep), Today, Calendar | ≥6 required |
| `*-site` | `/`, `/privacy`, `/terms` (+ Juicd `/contest-rules`) × desktop + mobile + scrolls | `qa_min_pngs` 8–10 |

## `products.json` fields

```json
{
  "qa_cmd": "./scripts/capture-qa-screenshots.sh",
  "qa_out": "qa-screenshots",
  "qa_min_pngs": 5,
  "qa_required": "01-home.png,02-workout.png",
  "qa_strict": true
}
```

After each run, Pilot writes `qa-screenshots/qa-manifest.json` (file list +
timestamp) and copies PNGs into `jobs/<product>-<stamp>/screenshots/` when
invoked from `pilot run`.

## Adding a new product

1. Apps: add UITest(s) that write PNGs under `qa-screenshots/`, wrap with
   `kits/qa/ios-uitest-capture.sh` (copy Juicd’s script).
2. Sites: thin `scripts/capture-qa-screenshots.mjs` that calls
   `web-capture.mjs` with your routes (copy Corvim-Website’s script).
3. Register `qa_*` fields in `config/products.json`.
4. Smoke: `./bin/pilot qa <product>`.

## Pipeline behavior

- Default `pilot run`: required QA failure **stops before release**. A missing
  `qa_cmd`, missing output directory, failed capture, or unmet depth check is
  a failure. `qa_strict: false` does not relax this (the flag is documentary).
- Prefer fixing flaky sims over lowering `qa_min_pngs`.
