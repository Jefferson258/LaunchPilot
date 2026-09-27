# Metabase (local) for Juicd + Corvim

Free, self-hosted dashboards against Supabase Postgres.

## Use this now (lite — works on 8GB Mac)

```bash
cd ~/Desktop/LaunchPilot/kits/metabase
python3 lite_dashboard.py
# http://127.0.0.1:3050
```

Charts for Juicd/Corvim events, errors, and product views via read-only `metabase_ro` roles.

## Full Metabase (heavier — 8 GB RAM; use a 512 MB heap)

The original failure was **RAM**, not disk. KeepAlive is not loaded.

```bash
JAVA_TOOL_OPTIONS='-Xmx512m -Xms128m' ./start.sh
# then open http://localhost:3000 on the other monitor:
~/Desktop/scripts/open-on-other-monitor.sh "Safari"
open http://localhost:3000
```

Login: see `METABASE_ADMIN_*` in gitignored `supabase-connections.env`.

Health dashboards (one screen per app):

```bash
python3 create_health_dashboards.py   # idempotent refresh
open http://localhost:3000/dashboard/2   # Juicd health
open http://localhost:3000/dashboard/3   # Corvim health
```

**Errors last 24 hours** should stay at 0. Charts stay flat until TestFlight traffic lands. Velour has no backend analytics — use App Store Connect.

## Connect databases (Metabase UI)

Use Session pooler settings from `supabase-connections.README.md` (passwords in local `supabase-connections.env`, never git). SSL required.

Suggested questions / dashboards:
- Juicd: `v_juicd_analytics_daily`, `v_juicd_app_errors_daily`, `v_juicd_slip_events_daily`, `v_juicd_product_counts`
- Corvim: `v_analytics_daily`, `v_app_errors_daily`, `v_social_stats` (if present)

## Stop

```bash
./stop.sh
pkill -f lite_dashboard.py
```

See `STATUS.md` for what was verified Jul 23.
