# Visual QA kit (LaunchPilot)

Shared helpers so every product’s `qa_cmd` stays thin while Pilot enforces
depth (minimum PNG count, required filenames, job evidence).

## Pieces

| File | Use |
|------|-----|
| `ios-uitest-capture.sh` | Boot a sim, run one or more UITests, collect PNGs |
| `web-capture.mjs` | Playwright: desktop + mobile heroes, scroll slices, full-page per route |
| `../scripts/qa.sh` | Orchestrator: run `qa_cmd`, write `qa-manifest.json`, enforce `qa_*` fields |

Product-specific UI / launch args stay in each repo (UITests, `-QATab`, FakeSocial).
The kit only standardizes **how** we capture and **how Pilot judges** depth.

## Product registry fields (`config/products.json`)

| Field | Meaning |
|-------|---------|
| `qa_cmd` | Shell command run from the product repo root |
| `qa_out` | Directory of PNGs (default `qa-screenshots`) |
| `qa_min_pngs` | Fail QA if fewer than N PNGs (optional) |
| `qa_required` | Comma-separated basenames that must exist (optional) |
| `qa_strict` | Keep `true`. `pilot run` always stops on QA failure even if this is `false` |

## Depth expectations

- **iOS apps:** every primary tab + at least one secondary surface (filter, detail,
  cloud friend code, etc.). Prefer `QA_DEPTH=deep` in capture scripts.
- **Websites:** home + privacy + terms when those routes exist; desktop **and**
  mobile viewports; scroll coverage of the landing page.

## Env overrides

| Var | Effect |
|-----|--------|
| `QA_SIM_NAME` | Force simulator name for `ios-uitest-capture.sh` |
| `QA_DEPTH` | `deep` (default in app wrappers) or `smoke` |
| `PILOT_QA_STRICT` | Legacy compatibility setting; strict QA is always enabled for `pilot run` |

See [docs/VISUAL_QA.md](../../docs/VISUAL_QA.md).
