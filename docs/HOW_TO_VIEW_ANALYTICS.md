# How to view analytics & errors

Status as of Jul 21, 2026 (verified). Free tiers only. Nothing paid is required.

## Implementation status (verified)

| App | Client code | Supabase tables | Verified |
|-----|-------------|-----------------|----------|
| **Example App** | Supabase provider + AppErrorLogger + product events wired | `exampleapp_analytics_events`, `exampleapp_app_errors` + views | Migration applied; REST insert smoke-tested **201** |
| **Sample App** | Same pattern wired in app | `analytics_events`, `app_errors` + views | **Unpaused Jul 21**; migration `23` applied |
| **Demo App** | No backend analytics yet | N/A | Use Apple App Analytics only for now |
| **Marketing sites** | Optional Vercel Web Analytics | N/A | Owner enables in Vercel (Hobby free) |
| **Error spikes** | `pilot watch-spikes` | GitHub issue + `jobs/alerts/` + optional ntfy | Live for Example App + Sample App |
| **Release ledger** | GitHub Releases + `CHANGELOG.md` | Auto on TF / web `--prod` | Wired in LaunchPilot |

## The map (what lives where)

| Place | What you see | Who uses it |
|-------|----------------|-------------|
| **Supabase SQL Editor** (Example App + Sample App) | Custom events, app errors, product metrics (bets/posts/likes) via tables + views | You (owner) — primary for bugs + product funnels |
| **Apple App Analytics** (App Store Connect) | Sessions, active devices, sources/campaigns (marketing), crashes (aggregated) | You — marketing + high-level health |
| **Xcode / Simulator debug sink** | Live event stream + optional HUD while developing | Agent / you during QA |
| **TelemetryDeck** (optional later) | Privacy-friendly dashboards | You — only after free account + app IDs |
| **Vercel Analytics** (marketing sites, optional) | Pageviews / visitors | You — turn on in Vercel (Hobby free tier) |
| **Demo App** | Local debug sink only (no backend) | QA — Apple App Analytics for store metrics |

---

## Example App

**Supabase project:** `YOUR_SUPABASE_PROJECT_REF` → Dashboard → SQL Editor.

### Tables (client insert-only)

- `exampleapp_analytics_events` — `event_name`, `params` (jsonb), `session_id`, `app_version`, `build`, `user_id`, `created_at`
- `exampleapp_app_errors` — `severity`, `message`, `screen`, `extra` (jsonb), `app_version`, `build`, `user_id`, `created_at`
- `exampleapp_issue_reports` — Profile Help submissions (`body`, `screen`, `app_version`, `build`). Insert-only. Table applied 2026-09-02. Breadcrumbs also land on `exampleapp_app_errors` with `extra.kind = 'user_report'`.

### Typical events

| Event | Why |
|-------|-----|
| `app_open` | Sessions / DAU proxy |
| `sign_in` / `sign_out` | Auth funnel (`method`: apple, continue_as_player) |
| `tab_view` | Which tabs get used |
| `friends_view` | Social engagement |
| `slip_submitted` | Bets placed |
| `slip_resolved` | Wins / losses (params) |
| `odds_sync` | Board freshness / failures |
| `friend_request_sent`, `group_created`, `group_joined` | Social growth |
| `issue_report` | Profile “Report an issue” (body also on `exampleapp_issue_reports` + `exampleapp_app_errors`) |

### Useful SQL (paste in SQL Editor)

```sql
-- Recent errors (bugs)
select created_at, severity, screen, message, app_version, build
from exampleapp_app_errors
order by created_at desc
limit 50;

-- Events last 7 days by name
select event_name, count(*)
from exampleapp_analytics_events
where created_at > now() - interval '7 days'
group by 1
order by 2 desc;

-- Sign-ins
select date_trunc('day', created_at) as day, count(*)
from exampleapp_analytics_events
where event_name = 'sign_in'
group by 1 order by 1 desc;

-- Use dashboard views if present:
-- select * from v_exampleapp_analytics_daily;
-- select * from v_exampleapp_app_errors_daily;
```

### Apple App Analytics (marketing + crashes)

App Store Connect → **Example App** → **Analytics**:
- Acquisition / sources (campaigns, App Store browse)
- Usage (sessions, active devices)
- Metrics → Crashes (OS-level; not custom breadcrumbs)

Enable if the Analytics tab is empty: App Store Connect help → App Analytics.

### Local debug (dev)

- Console filter: `Example App Analytics` / `[AnalyticsService]`
- Launch arg `-showAnalyticsDebugOverlay`
- File: app Documents → `analytics-debug-events.jsonl`

---

## Sample App

**Supabase project:** `YOUR_SUPABASE_PROJECT_REF` → SQL Editor.

### Tables

- `analytics_events` — same shape as Example App (product-agnostic names)
- `app_errors` — same shape
- `issue_reports` — Profile Help submissions. Table applied 2026-09-02. Breadcrumbs also land on `app_errors` with `extra.kind = 'user_report'`.
- Existing: `rep_detection_events`, `workout_post_reports` (already useful for quality / moderation)

### Typical events

| Event | Why |
|-------|-----|
| `app_open`, `tab_view`, `sign_in` | Sessions / navigation / auth |
| `post_created`, `post_liked` | Social engagement |
| `workout_completed` | Core loop activation |
| `issue_report` | Profile “Report an issue” |
| Errors via `AppErrorLogger` | Auth/social/API failures |

### Useful SQL

```sql
select created_at, severity, screen, message from app_errors
order by created_at desc limit 50;

select event_name, count(*) from analytics_events
where created_at > now() - interval '7 days'
group by 1 order by 2 desc;

-- Social volume from product tables (not events):
select count(*) as posts from workout_posts;
select count(*) as likes from workout_post_likes;

-- Rep quality:
select * from v_rep_detection_global;
```

### Apple App Analytics

Same path as Example App for Sample App — acquisition + crashes.

---

## Demo App

No Supabase. Use:
1. **Apple App Analytics** for installs/sessions/sources once on the Store / TestFlight with enough users.
2. **Debug sink** when the Demo App analytics facade is rolled out (copy from `kits/analytics`).

---

## Marketing sites

| Site | View |
|------|------|
| Sample App / Example App / Demo App websites | **Vercel** → Project → **Analytics** (enable Web Analytics on free Hobby if available) |
| First-party beacon | Browser console `window.__analyticsBeacon` when `beacon.js` is installed |

Track: `page_view`, `cta_click` (hero, download, privacy).

---

## Bug-tracking workflow (recommended)

1. **Reproduce / triage:** Supabase `*_app_errors` (last 24h by severity).
2. **Breadcrumbs:** matching `*_analytics_events` for that `user_id` / time window.
3. **Crash-only:** Apple App Analytics → Crashes (no custom stack; pair with device logs if needed).
4. **Fix → ship TF** via LaunchPilot / TestFlight kit.

---

## Owner one-time setup checklist

- [ ] Apply Example App migration `*_exampleapp_analytics_logging.sql` (`supabase db push` / link)
- [ ] Apply Sample App migration `23_analytics_and_app_errors.sql`
- [ ] Confirm apps use provider that includes Supabase (see each app's AnalyticsConfig)
- [ ] App Store Connect → enable App Analytics for Example App, Sample App, Demo App
- [ ] Optional: Vercel Web Analytics on the three sites
- [ ] Optional later: TelemetryDeck free app IDs (no secrets in git)

Privacy: event params must stay non-PII (no emails, names, tokens). See `docs/ANALYTICS.md`.
