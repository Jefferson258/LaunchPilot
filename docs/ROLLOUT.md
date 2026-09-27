# Staged rollouts (region vs percentage)

There is no free, per-version “ship this build only to Texas / 5% of all users”
switch that covers both App Store apps and Vercel sites. Use TestFlight and
preview URLs to test; use the free controls below when a version is live.

## iOS / iPadOS (App Store)

**Percentage (automatic updates only).** App Store Connect **Phased Release**
rolls a *version update* over 7 days to a random sample of users who have
automatic updates on: 1% → 2% → 5% → 10% → 20% → 50% → 100%. You can pause
(up to 30 cumulative days) or release to everyone. You cannot pick a custom
percentage or a country for that canary.

Anyone who taps **Update** in the App Store, or who **installs for the first
time**, gets the new version immediately. Phased Release is not a true canary
for 100% of traffic.

Docs: [Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases).

**Region.** App Store **availability** is the whole app (countries you sell
in), not a single version. You cannot leave v1.0 live in the US and ship v1.1
only in Canada. TestFlight groups are the right place to limit testers before
submit.

**This workspace.** Do not submit without an explicit owner ask plus the
org + bank gate. When that happens, prefer Phased Release on the first public
update.

## Websites (Vercel)

**Hobby (current plan): production is 100%.** A `--prod` deploy becomes the
live alias for everyone. There is no percentage split on Hobby.

**Percentage canary** is [Vercel Rolling Releases](https://vercel.com/docs/rolling-releases)
(Pro/Enterprise). Do **not** upgrade plans. Free path:

1. `deploy-web.sh <product>` — preview URL, HTTP smoke (`GET /`).
2. Owner checks the preview.
3. `deploy-web.sh <product> --prod` — smoke again; previous production URL is
   recorded under `jobs/web-rollbacks/<product>.json` (gitignored).
4. If smoke fails, **manual** Instant Rollback to the previous URL. Never auto.

**Region.** Vercel Function region settings choose where compute runs, not
which visitors see a new version. All production visitors still get the live
deployment.

## What to tell an agent

- Apps: TestFlight first; Phased Release after a real App Store version exists.
- Sites: preview → smoke → prod; rollback is Instant Rollback / `vercel rollback`
  to the **previous** URL, never to the new one.
- Do not buy Vercel Pro for Rolling Releases.
