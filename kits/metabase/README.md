# Metabase (local) + lite dashboard

Free, self-hosted dashboards against your products' Supabase Postgres, using
read-only roles. Works with the event/error tables written by `kits/analytics`
(`event_name`, `created_at` / `severity`, `message`, `screen`, `created_at`).

## Configure (local, gitignored)

```bash
cd kits/metabase
cp dashboards.example.json dashboards.local.json           # products + table names
cp supabase-connections.env.example supabase-connections.env  # read-only creds
```

See [supabase-connections.README.md](supabase-connections.README.md) for the
connection settings.

## Lite dashboard (light on RAM)

```bash
python3 lite_dashboard.py
# http://127.0.0.1:3050
```

## Full Metabase (heavier; cap the heap on small machines)

```bash
# put metabase.jar in this folder first (gitignored)
JAVA_TOOL_OPTIONS='-Xmx512m -Xms128m' ./start.sh
open http://localhost:3000
```

Admin login: `METABASE_ADMIN_*` in `supabase-connections.env`. Add each
product's Postgres in the Metabase UI, then put the Metabase database id in
`dashboards.local.json` (`metabase_db_id`).

Health dashboards (one screen per product, idempotent refresh):

```bash
python3 create_health_dashboards.py
```

**Errors last 24 hours** should stay at 0. Charts stay flat until real traffic lands.

Optional launchd KeepAlive: copy `com.launchpilot.metabase.plist.example`, replace
`/path/to/LaunchPilot`, and load it only if the machine has RAM to spare.

## Customizing

Product-specific cards (custom views, business metrics) are best kept in a
private `*.local.py` copy of these scripts — `*.local.*` is gitignored.

## Stop

```bash
./stop.sh
pkill -f lite_dashboard.py
```
