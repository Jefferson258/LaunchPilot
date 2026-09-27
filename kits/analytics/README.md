# kits/analytics

Shared analytics kit for LaunchPilot products. See
[`docs/ANALYTICS.md`](../../docs/ANALYTICS.md) for the architecture decision
and privacy checklist first — this file is the practical "how do I actually
roll this out" companion.

## What's in here

```text
kits/analytics/
  Package.swift, Sources/AnalyticsCore/, Tests/AnalyticsCoreTests/
    ── the tested reference implementation (swift test, no simulator/network)
  templates/ios/
    AnalyticsConfig.swift.template        # env/plist-driven config (copy + rename)
    AnalyticsFacade.swift.template         # the <Product>Analytics singleton (copy + rename)
    TelemetryDeckProvider.swift.template   # #if canImport(TelemetryDeck) — safe to add today
    AnalyticsDebugOverlay.swift.template   # optional SwiftUI QA overlay
  templates/web/
    beacon.js, beacon.test.mjs, package.json  # first-party pageview/event beacon
```

## Status per product

| Product | Status | Files |
|---|---|---|
| Corvim | **Implemented** — facade, debug sink, unit tests in `CorvimTests`, wired at app open / tab change / sign-in | `Corvim/Corvim/Services/Analytics/` |
| Juicd | **Implemented** — `AnalyticsService` facade, debug sink (ring buffer + `os.Logger`), verified via `xcodebuild build` + `JuicdUITests/JuicdAnalyticsLogicTests.swift` | `juicd/Services/Analytics/` |
| Velour | Not started — see "Rollout: Velour" below | — |
| Corvim-Website / juicd-website / VelourClosetWebsite | Not started — `templates/web/beacon.js` is ready and tested, not yet dropped into a site | — |

## Verify the core logic (do this first — fast, no Xcode)

```bash
cd LaunchPilot/kits/analytics
swift test                                    # 13 tests, ~1s
node --test templates/web/beacon.test.mjs     # 6 tests, ~0.1s
```

## Rollout to a new iOS app (the pattern used for Corvim/Juicd)

1. Copy these files, unmodified, from `Sources/AnalyticsCore/` into the app's
   `Services/Analytics/` folder: `AnalyticsEvent.swift`, `AnalyticsNaming.swift`,
   `AnalyticsPrivacy.swift`, `AnalyticsProvider.swift`, `AnalyticsDebugSink.swift`,
   `AnalyticsClient.swift`.
2. Copy `templates/ios/AnalyticsConfig.swift.template` →
   `Services/Analytics/AnalyticsConfig.swift`, replacing `{{App}}`/`{{APP}}`
   with the product name (e.g. `Corvim`/`CORVIM`).
3. Copy `templates/ios/AnalyticsFacade.swift.template` →
   `Services/Analytics/<Product>Analytics.swift`, same replacement. Add/adjust
   the convenience methods for that app's actual screens.
4. Copy `templates/ios/TelemetryDeckProvider.swift.template` →
   `Services/Analytics/TelemetryDeckProvider.swift` as-is (no placeholders).
5. Add the 8 new file references to `<Product>.xcodeproj/project.pbxproj` (or
   drag them into Xcode, which does this for you). If editing by hand: find
   an existing file in the same group (e.g. `SupabaseConfig.swift`) and copy
   its 4 pbxproj entries (`PBXBuildFile`, `PBXFileReference`, group child,
   Sources build phase child) once per new file, with fresh unique IDs.
6. Call `<Product>Analytics.logAppOpen()` near app launch, `.logTabView(_:)`
   on tab change, `.logSignIn(method:)` after a successful sign-in. Pick a few
   more real screens — don't instrument everything on day one.
7. (Optional) copy `AnalyticsDebugOverlay.swift.template` into `Support/` and
   drop `AnalyticsDebugOverlay()` into the root view's `ZStack` for on-device
   QA (`-showAnalyticsDebugOverlay` launch arg to make it visible; it's always
   present-but-transparent so UITests can read it either way).
8. Add `analytics_provider` / `analytics_debug` / `analytics_app_id_env` /
   `analytics_enabled` / `analytics_debug_file` to that product's entry in
   `LaunchPilot/config/products.json` and `products.example.json`.

**Verify without a paid account:** run the app (simulator or device), tap
around, then either read `Documents/analytics-debug-events.jsonl` from the
app's container (Xcode → Window → Devices and Simulators → select app →
Download Container), or check Xcode's console for `[Analytics][debug] ...`
lines (DEBUG builds only), or (if you added the overlay) read the
`analytics-debug-count` / `analytics-debug-last-event` accessibility elements
from a UITest — see `CorvimTests/AnalyticsClientTests.swift` and
`JuicdUITests/JuicdUITests.swift` for real examples.

## Rollout: Velour (client-side only, no Supabase)

Velour is on-device SwiftData with no backend — this is actually the
*simplest* case: follow the iOS steps above, but permanently keep
`provider = "debug"` (or eventually TelemetryDeck) since there's no
first-party server to add a Supabase-table option for. No changes needed
to this kit; it was designed for exactly this "no backend" case first.

## Rollout: a marketing site (Corvim-Website / juicd-website / VelourClosetWebsite)

1. Copy `templates/web/beacon.js` into the site's `public/` folder.
2. Add `<script type="module" src="/beacon.js"></script>` to the HTML
   `<head>` (or import it from the app entry point if the framework bundles
   `public/` assets differently — check each site's existing build).
3. Call `window.analytics.track("cta_click", { label: "hero_get_started" })`
   from click handlers on a couple of key CTAs. A pageview (`page_view`) is
   sent automatically on script load.
4. Verify in the browser console (default `logToConsole: true`) or by reading
   `window.__analyticsBeacon.events` in devtools — no backend required.
5. Only if/when the owner wants real numbers: either (a) turn on **Vercel
   Analytics** in the Vercel dashboard (free tier exists, zero code — these
   sites already deploy via Vercel), or (b) point `data-endpoint` at a small
   serverless function that inserts into Supabase (additive table only, same
   pattern as `kits/analytics/Sources` events). Neither is implemented yet —
   deliberately, to avoid overbuilding before there's a live site + traffic.

## Rollout: first-party Supabase event table (Juicd/Corvim, optional, not yet added)

Only do this if the owner wants raw event rows to query with SQL in addition
to (or instead of) the debug sink. Sketch (additive, RLS-safe, **not applied**
by this kit — write it as a normal migration in the product's own `supabase/`
folder when wanted):

```sql
create table if not exists public.analytics_events (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  params jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.analytics_events enable row level security;
-- Insert-only from the client, scoped to the caller's own uid (or null for anonymous).
create policy if not exists "insert own analytics events"
  on public.analytics_events for insert
  with check (user_id is null or user_id = auth.uid());
-- No select policy for regular users — this table is write-only from the client by design.
```

Then add an `AnalyticsProvider` conformance in the app that inserts into this
table (same shape as `PostReportAnalytics.swift` / `RepDetectionAnalytics.swift`
in Corvim — fire-and-forget, swallow errors, never block UI).
