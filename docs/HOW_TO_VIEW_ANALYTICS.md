# How to view analytics & errors

Free tiers only. Nothing paid is required. Table names below are the defaults
written by `kits/analytics` (`analytics_events`, `app_errors`); use whatever
your product actually uses.

## The map (what lives where)

| Place | What you see | Who uses it |
|-------|----------------|-------------|
| **Supabase SQL Editor** (Supabase-backed apps) | Custom events, app errors, product metrics via tables + views | You (owner) — primary for bugs + product funnels |
| **Apple App Analytics** (App Store Connect) | Sessions, active devices, sources/campaigns, crashes (aggregated) | You — marketing + high-level health |
| **Xcode / Simulator debug sink** | Live event stream + optional HUD while developing | Agent / you during QA |
| **TelemetryDeck** (optional) | Privacy-friendly dashboards | You — after free account + app IDs |
| **Vercel Analytics** (marketing sites, optional) | Pageviews / visitors | You — turn on in Vercel |
| **Metabase / lite dashboard** (`kits/metabase`) | One-screen health per product | You — local, read-only |
| **Error spikes** (`pilot watch-spikes`) | GitHub issue + `jobs/alerts/` + optional ntfy | Configured in `kits/ops/products.local.json` |
| **Release ledger** | GitHub Releases + `CHANGELOG.md` | Auto on TF / web `--prod` |

---

## Supabase-backed app

**Supabase project:** `YOUR_SUPABASE_PROJECT_REF` → Dashboard → SQL Editor.

Suggested tables:

- `analytics_events` — `event_name`, `params` (jsonb), `session_id`, `app_version`, `build`, `user_id`, `created_at`
- `app_errors` — `severity`, `message`, `screen`, `extra` (jsonb), `app_version`, `build`, `user_id`, `created_at`

### Useful SQL (paste in SQL Editor)

```sql
-- Recent errors (bugs)
select created_at, severity, screen, message, app_version, build
from app_errors
order by created_at desc
limit 50;

-- Events last 7 days by name
select event_name, count(*)
from analytics_events
where created_at > now() - interval '7 days'
group by 1
order by 2 desc;

-- Sign-ins per day
select date_trunc('day', created_at) as day, count(*)
from analytics_events
where event_name = 'sign_in'
group by 1 order by 1 desc;
```

### Apple App Analytics (marketing + crashes)

App Store Connect → **your app** → **Analytics**:

- Acquisition / sources (campaigns, App Store browse)
- Usage (sessions, active devices)
- Metrics → Crashes (OS-level; not custom breadcrumbs)

### Local debug (dev)

- Console filter: `[Analytics]`
- Launch arg `-showAnalyticsDebugOverlay`
- File: app Documents → `analytics-debug-events.jsonl`

---

## On-device app (no backend)

Use the local debug sink for QA and Apple App Analytics for store metrics.

---

## Marketing sites

| Site | View |
|------|------|
| Your websites | **Vercel** → Project → **Analytics** |
| First-party beacon | Browser console `window.__analyticsBeacon` when `beacon.js` is installed |

Track: `page_view`, `cta_click` (hero, download, privacy).

---

## Bug-tracking workflow (recommended)

1. **Reproduce / triage:** `app_errors` (last 24h by severity).
2. **Breadcrumbs:** matching `analytics_events` for that `user_id` / time window.
3. **Crash-only:** Apple App Analytics → Crashes.
4. **Fix → ship TF** via LaunchPilot / TestFlight kit.

---

## Owner one-time setup checklist

- [ ] Apply your analytics/errors migration in each Supabase project
- [ ] Confirm apps use a provider that includes Supabase (see each app's AnalyticsConfig)
- [ ] App Store Connect → enable App Analytics for each app
- [ ] Optional: Vercel Web Analytics on your sites
- [ ] Optional: TelemetryDeck free app IDs (no secrets in git)

Privacy: event params must stay non-PII (no emails, names, tokens). See `docs/ANALYTICS.md`.
