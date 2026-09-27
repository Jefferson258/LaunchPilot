# Analytics — architecture & decisions

Status: **implemented and testable today** for Corvim and Juicd (debug sink,
no network). A real network provider (TelemetryDeck) is designed-for but
**owner-blocked** — see "What's owner-blocked" below. Nothing here spends
money or sends data anywhere by default.

## 1. What lives where

| Layer | Owns | Why |
|---|---|---|
| **LaunchPilot** (`kits/analytics/`) | Shared conventions, privacy checklist, event-naming rules, the tested reference implementation (`AnalyticsCore` Swift package), `products.json` registry fields, web beacon template | These are cross-product policy + a proven implementation to copy from — not product code, and not secrets. |
| **Each product repo** | SDK wiring (which provider, if any), the actual `<Product>Analytics` facade instance, concrete event call sites, provider API keys/app IDs (non-secret but product-specific), privacy-policy copy, consent UX | Every app has different screens, its own Supabase project (or none), and its own App Store privacy nutrition label. This can't be generalized without becoming vague. |

**Why copy the Swift source instead of a cross-repo SPM dependency:** Corvim,
Juicd, and Velour Closet all use classic (non-package) Xcode project files — adding a
local Swift package *dependency* to an existing `.xcodeproj` means hand-editing
`packageReferences` / `XCSwiftPackageProductDependency` entries in
`project.pbxproj`, which is fiddly and easy to corrupt. Adding a plain `.swift`
**file** to an existing group/target is a well-worn, low-risk 4-line edit (file
reference + build-file + group entry + sources-phase entry) that this codebase
already does by hand for other services. So: the logic is written **once**,
tested with `swift test` in `kits/analytics/`, and then the same ~5 small files
are copied into each app's `Services/Analytics/` and adapted with the product
name. If a product later adopts SPM-based project generation (e.g. Tuist,
`xcodegen`, or a from-scratch `.xcodeproj` with the newer file-system-synced
groups), switch to a real package dependency instead — the source is
line-for-line portable.

## 2. Provider comparison (free tier only)

| Provider | Free tier | Privacy posture | Setup cost | Verdict |
|---|---|---|---|---|
| **Debug sink (this repo)** | Free forever (no service) | Perfect — nothing leaves the device | Zero | **Default now.** Ships in every build; console + local JSONL file + in-memory buffer for QA/tests. |
| **Apple App Analytics** (App Store Connect) | Free, built-in | Apple-run, aggregated, opt-in-by-user at OS level | Zero code | Already available for every app with no work. Complements custom events; doesn't replace them (no custom event names, no funnel breakdowns). Turn it on in App Store Connect ("App Analytics" tab) if not already. |
| **TelemetryDeck** | Free tier: 1 app, ~100k signals/mo (check current limits before relying on them) | Privacy-first by design; anonymous, no IP storage, no cross-app tracking, App Store "Data Not Collected" friendly | Create account + app ID (owner), add SPM package in Xcode (owner or agent with Xcode GUI access), no backend to run | **Recommended next step** once the owner wants real dashboards. Best fit for "indie iOS, no server, privacy-safe, App Store nutrition label stays clean." |
| **PostHog** | Free cloud tier exists but has monthly event caps and the SDK/dependency footprint is heavier (session replay, feature flags, etc. bundled in); self-hosting free but is real infra to run/maintain | Good if self-hosted; cloud free tier still is a third-party processor | Higher (account + SDK + possibly infra) | Documented as an alternative, not implemented — more than these apps need right now. Revisit if the owner wants product analytics beyond events (funnels, replay) and is fine maintaining infra or accepting cloud limits. |
| **First-party Supabase event table** | Free (same project, same tier already in use) | Best possible — data never leaves the owner's own Supabase project | Low (one additive migration + insert calls) | Good complementary option for Juicd/Corvim specifically *if* the owner wants raw event rows to query with SQL. Not implemented yet (see "Rollout" doc) to avoid overbuilding; the debug sink already proves the client-side pattern, and adding the table is a 20-minute follow-up whenever wanted. |

**Decision:** ship the **debug sink as the permanent default provider** (it's
useful in every environment — TestFlight crash/support triage, QA, local dev)
and design the facade so a **second provider can be added later with a
one-line change** (`providers: [AnalyticsDebugSink(...), TelemetryDeckProvider(...)]`)
once the owner creates a TelemetryDeck app ID. Apple App Analytics needs no
code and should just be confirmed "on" in App Store Connect for each app.

## 3. Privacy checklist (App Store safe, "we don't sell data")

Applies to every event, every product:

- [ ] No email, full name, phone number, physical address, or exact
      GPS/location in any event or param.
- [ ] No free-text user content (post captions, chat messages, bios) as a
      param value — log that the action happened (`workout_posted`), not what
      was posted.
- [ ] User identifiers, if ever needed, are the app's own anonymous UUID
      (e.g. Supabase `auth.uid()`), never Apple ID / email / device
      fingerprinting.
- [ ] Param keys use the shared naming convention (§4) so a reviewer can scan
      the list and see nothing identifying by name alone.
- [ ] Nothing is sold or shared with third parties for advertising — this
      repo's clients only ever call `.track()` on providers the product
      explicitly configures, and free-tier analytics vendors here
      (TelemetryDeck) contractually don't resell data. PostHog/Supabase, if
      adopted, keep data first-party.
- [ ] Master kill switch: every `<Product>Analytics` facade has an
      `enabled` flag (env/plist-driven) so analytics can be turned off
      instantly without a code change, and a future "opt out" UI toggle has
      somewhere to plug into.
- [ ] `AnalyticsPrivacy.redactingLikelyPII` runs as defense-in-depth on every
      event before it reaches any provider (drops blocked keys like `email`;
      redacts obviously email/phone-shaped string values). This is a safety
      net, not a license to pass sensitive values on purpose.
- [ ] App Store privacy "nutrition label" (App Privacy Details in App Store
      Connect) is updated whenever a real network provider is turned on —
      TelemetryDeck's own docs list the correct answers for their SDK.

## 4. Event naming convention

- Event names: lowercase `snake_case`, 2–40 chars, e.g. `app_open`,
  `tab_view`, `sign_in`, `sign_out`, `screen_view`, `workout_posted`.
- Param keys: same charset. Param values are flat scalars (string/int/double/
  bool) — no nested objects, no arrays, no free text (see checklist).
- `AnalyticsClient.log(name:params:)` **enforces** this: invalid names/keys
  are dropped (never sent to a provider) and reported via `onInvalidEvent`,
  so a typo doesn't silently ship a bad taxonomy.
- Suggested baseline events for every app (not all required, pick what's
  meaningful): `app_open`, `tab_view` (param: `tab`), `sign_in` (param:
  `method`), `sign_out`, `screen_view` (param: `screen`).

## 5. `products.json` fields

Documentary-only fields (no secrets) added to every product entry in
`LaunchPilot/config/products.json` / `products.example.json`:

| Field | Meaning |
|---|---|
| `analytics_provider` | `"debug"` \| `"telemetrydeck"` \| `"none"`. What's actually wired today. Currently `"debug"` for iOS apps, `"none"`/undecided for sites. |
| `analytics_debug` | `true` when the debug sink is the active provider (or always-on alongside a network provider). Lets agents/QA know events are inspectable locally with no account. |
| `analytics_app_id_env` | The **name** of the env var / xcconfig key holding a provider app ID (e.g. `CORVIM_ANALYTICS_APP_ID`) — never the value. Empty string when no provider needs one (debug sink doesn't). |
| `analytics_enabled` | Documentary mirror of the in-app master kill switch default. |
| `analytics_debug_file` | Relative path convention for where the on-device JSONL debug log lands (e.g. `Documents/analytics-debug-events.jsonl`), so QA knows where to look via Xcode's device file browser / simulator container. |

These are read by humans/agents, not by `pilot` scripts today (no behavior
change to the CLI) — see `kits/analytics/README.md` for the practical
per-product rollout.

## 6. What's owner-blocked

- **TelemetryDeck app ID(s)** — free account + one app ID per product,
  created at telemetrydeck.com. Until this exists, `analytics_provider`
  stays `"debug"` and no network call is made.
- **Adding the TelemetryDeck SPM package to a product's `.xcodeproj`** — best
  done once, in Xcode's GUI ("Add Package Dependency…"), rather than by
  hand-editing `project.pbxproj`. The provider file
  (`TelemetryDeckProviderTemplate.swift`, guarded by
  `#if canImport(TelemetryDeck)`) is already written and compiles fine
  *without* the package present, so adding the package later is the only
  remaining step.
- **Turning on/confirming Apple App Analytics** in App Store Connect per app
  — zero cost, just needs the owner (or an agent with ASC access) to check
  it's enabled.
- **Website analytics** — no site repo was wired in this pass (Corvim-Website,
  juicd-website, VelourClosetWebsite); a first-party beacon template exists
  and is verified with `node --test`, but dropping it into a live site and
  deciding self-host vs. Vercel Analytics vs. nothing is an owner call — see
  `kits/analytics/README.md` "Rollout" section.

## 7. Testing

```bash
cd LaunchPilot/kits/analytics
swift test              # 13 unit tests, no simulator, no network, ~1s
node templates/web/beacon.test.mjs   # web beacon smoke test
```

Per-app verification is documented in each product's own analytics README
pointer (see `kits/analytics/README.md`).
