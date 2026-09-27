# Agent instructions — LaunchPilot

LaunchPilot is the **orchestration layer** that drives a Cursor agent through a
change pipeline for products registered in `config/products.json`. It is tooling,
not a product.

## Operating principles

1. **Be open and honest.** Report what ran, what failed, what's unverified.
2. **Never spend money.** Free tiers only. Stop and ask if a step costs money.
3. **No destructive/sweeping changes without explicit per-action approval:** no
   `git push --force`, history rewrites, mass deletion, destructive SQL, secret
   rotation.
4. **Secrets never go in git.** Use `config/pilot.env` (gitignored) or a vault.
5. **Respect the gates.** `config/policy.json` is authoritative. Production web
   deploy, TestFlight upload, App Store submit, DB migrations, and going live are
   approval-gated — require an explicit flag and, for real-user impact, owner OK.

## What is safe to do unattended

- `code`, `build`, `qa`, `commit`, `push` to a `pilot/*` branch, and open a PR.
- Deploy a **preview** (non-production) website build.

## What needs an explicit flag / approval

- `pilot deploy <product> --prod`
- `pilot testflight <product> --confirm`
- `pilot appstore-submit <product> --confirm` (or `run … --ship-appstore`)
- `pilot run … --ship-prod` / `--ship-testflight` / `--ship-appstore` / `--ship`
  (ship steps after the PR portion of the pipeline)
- Any DB migration, secret change, domain change, or going live / real-money
  mode flip.

Do **not** pass `--ship*` for owner products unless the owner asked for that run.
**`--ship` never means App Store submit** — that requires `--ship-appstore` alone.
Prefer `appstore-submit --dry-run` unless the owner explicitly wants a real ASC
submit. Do not put `--ship-appstore` in phone Shortcuts by default.

## Visual QA

- Shared kit: `kits/qa/` · guide: `docs/VISUAL_QA.md`
- Enforce required QA and depth via `qa_min_pngs` / `qa_required` in `products.json`
- `pilot run` fails closed before release when QA is missing or fails
- Default `QA_DEPTH=deep` for app/site capture wrappers

## Notes

- The deterministic pipeline is bash; the coding step is `agent/run-agent.mjs`
  via the Cursor SDK and needs `CURSOR_API_KEY`.
- Reuses bundled `kits/testflight`, `kits/appstore`, and `kits/qa`. Secrets stay
  in gitignored `config.sh` / `apps.sh` / `pilot.env` — see `docs/SETUP.md`.
- Product registry lives in gitignored `config/products.json` (copy from
  `products.example.json`). Bundled smoke test: `./bin/pilot demo`.
- `repo` values under `examples/` resolve inside the LaunchPilot checkout.
- Phone remote: `pilot remote-check` / `pilot remote-run` — see `docs/PHONE.md`.
  This workspace’s M2 mini uses **sleep → wake → pipeline → sleep** (Path A).
  M4+ **Always** + smart plug is Path B. Prefer `--sleep` over `--shutdown`
  unless passwordless sudo for `/sbin/shutdown` is configured. Never put
  `--ship*` in a phone Shortcut unless the owner asked for that run.
