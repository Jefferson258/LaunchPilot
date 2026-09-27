# Website CI boundary

## What the bundled workflow checks

`.github/workflows/website-ci.yml` runs on changes to LaunchPilot and checks
only `examples/demo-site`. It uses `contents: read`, installs dependencies
with `npm ci`, builds, optionally typechecks, installs the Playwright Chromium
browser, and runs visual QA. It has no secrets, uploads, or deployment steps.

## Why it cannot check the three real sites from this repository

The real sites are private sibling repositories:

- `Corvim-Website` (`corvim-site`)
- `juicd-website` (`juicd-site`)
- `VelourClosetWebsite` (`velour-site`)

The workflow runs in the private LaunchPilot repository. Its default
`GITHUB_TOKEN` is scoped to LaunchPilot and cannot check out those other
private repositories. Checking them out would require a PAT, GitHub App
credential, or another cross-repository secret, which is outside the
secret-free CI policy and should not be added to this workflow.

Also, a push or pull request in a sibling repository does not trigger a
workflow defined in LaunchPilot. The sites' current screenshot scripts resolve
the shared QA helper from a neighboring local `LaunchPilot` checkout, which is
available on this Mac but is not present in a clean product-repository runner.

Therefore, this workflow is intentionally not expanded with external checkout
jobs, scheduled polling, `repository_dispatch`, or production deployment
logic.

## Safe local checks today

From the LaunchPilot checkout, run the existing registry-driven checks against
the local sibling repositories:

```bash
./bin/pilot build corvim-site
./bin/pilot qa corvim-site

./bin/pilot build juicd-site
./bin/pilot qa juicd-site

./bin/pilot build velour-site
./bin/pilot qa velour-site
```

These commands use the configured local workspace, build only, and capture
visual QA. They do not commit, push, deploy, or submit anything. Missing
dependencies may cause the build step to run `npm install`; prefer `npm ci`
in a clean checkout when reproducing CI locally.

## Safest future workflow shape

Each website repository should own its own pull-request workflow. That keeps
the workflow trigger and `GITHUB_TOKEN` in the repository whose code is being
tested and requires no cross-repository secret. The safe steps are:

1. Check out that repository with `actions/checkout@v4`.
2. Set up Node 20 with `actions/setup-node@v4` and its own lockfile.
3. Run `npm ci`, `npm run build`, and `npm run typecheck --if-present`.
4. Install only the Playwright Chromium browser and run visual QA.
5. Keep `permissions: contents: read`; do not add Vercel credentials, deploy
   commands, artifact publication, or production steps.

Before enabling step 4 in a clean product-repository runner, make the
repository's `qa:screenshots` script self-contained by checking in the shared
QA helper or otherwise making it available without accessing a private
LaunchPilot checkout. That product-repository change is intentionally outside
this task. Until then, use the local commands above for build plus visual QA.
