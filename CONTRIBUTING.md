# Contributing

Thanks for looking at LaunchPilot. Keep changes small, reversible, and honest
about what is (and is not) implemented.

## Setup

```bash
cd LaunchPilot
./bin/pilot demo                         # bundled site: build + screenshots, no keys
cp config/pilot.env.example config/pilot.env
cp config/products.example.json config/products.json   # if demo didn't already create it
# edit products.json — keep demo-site; add sibling repos under your workspace
cd agent && npm install && cd ..          # only for pilot code / run
./bin/pilot preflight
```

Workspace root defaults to the parent of `LaunchPilot/`. Override with
`PILOT_WORKSPACE` (shell env or `config/pilot.env`) if your product repos live
elsewhere. Optional sibling tooling (`TestFlight/`, helper scripts) is expected
under that same workspace root when you use those steps. Paths under
`examples/` resolve inside the LaunchPilot checkout (used by the bundled demo).

## How to add a product

1. Put the product repo under your workspace root (or set `PILOT_WORKSPACE`),
   unless it lives under `examples/` inside LaunchPilot.
2. Add an entry to **local** `config/products.json` (never commit this file):

```json
{
  "my-site": {
    "name": "My Site",
    "type": "web",
    "repo": "MySite",
    "web_build": "npm run build",
    "qa_cmd": "npm run qa:screenshots",
    "qa_out": "qa-screenshots",
    "vercel_project": "my-site"
  }
}
```

| Field | Required | Notes |
|-------|----------|-------|
| `name` | yes | Display name |
| `type` | yes | `app` or `web` |
| `repo` | yes | Workspace sibling, `examples/…`, or absolute path |
| `tf_key` | apps | Must match a key in sibling `TestFlight/` resolve logic |
| `vercel_project` | sites | Vercel project slug for deploys |
| `web_build` | sites | Build command (default often `npm run build`) |
| `qa_cmd` / `qa_out` | optional | Visual QA command and output dir |

3. Keep real product names and slugs out of `products.example.json` — that file
   is the public template (`demo-site`, `my-app`, `my-site` only).
4. Verify with `./bin/pilot products` and `./bin/pilot build <key>`.
5. Run `./bin/pilot demo` after changing path resolution or the bundled example.

## Safety gates

`config/policy.json` is the source of truth. Do not weaken gates in PRs without
an explicit discussion.

- **Auto-allowed:** code, build, QA, commit, push to `pilot/*`, open PR, web
  preview deploy.
- **Needs an explicit CLI flag:** production web deploy (`--prod`), TestFlight
  upload (`--confirm`).
- **Needs owner approval:** App Store submit, DB migrations, secret changes,
  domain changes, going live / spending money.
- **Never without per-action approval:** force push, history rewrite, destructive
  SQL, mass delete, secret rotation.

When adding a new pipeline step that touches production or users, default it to
gated and document the flag in the README command table.

## No secrets in git

- Do not commit `config/pilot.env` or `config/products.json`.
- Do not add real API keys, `.p8` contents, or team-specific product registries
  to examples, tests, or docs.
- Prefer empty strings in `pilot.env.example`.
- See [SECURITY.md](SECURITY.md).

## Pull requests

- Match existing bash / README tone: direct, no invented features.
- Prefer additive changes over rewrites of working scripts.
- Run `./bin/pilot preflight` after touching path resolution or config loading.
- Do not commit or push from contributor docs as an instruction to agents —
  humans decide when to publish.
