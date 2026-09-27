# Metabase / lite dashboard status — Aug 31, 2026

## What the original issue was

It was **RAM, not disk**. This Mac is still **8 GB**. In July, the Metabase JVM started, then launchd KeepAlive crash-looped under memory pressure. Disk today has ~12 GB free (94% full) — enough for the already-downloaded `metabase.jar` (~630 MB). Extra storage does not fix a 768 MB–1.5 GB Java heap on an 8 GB machine that is already swapping (~1.7 GB swap in use).

## Rechecked Aug 31, 2026

- OpenJDK 21 still installed; `metabase.jar` still present.
- Read-only `metabase_ro` pooler connections still work for **Juicd** and **Corvim**.
- **Lite dashboard** (`python3 lite_dashboard.py` → http://127.0.0.1:3050) is the reliable charts UI on this Mac.
- **Full Metabase** came up this session with `JAVA_TOOL_OPTIONS=-Xmx512m -Xms128m` at http://localhost:3000 (`/api/health` ok). Juicd (id 2) and Corvim (id 3) Postgres were added as on-demand, not full-sync. Login: `METABASE_ADMIN_*` in gitignored `supabase-connections.env`.
- KeepAlive plist is **still not loaded**. A background start with nohup died immediately (empty log); a foreground JVM with a 512 MB cap did initialize. Do not re-enable KeepAlive — it will crash-loop when Cursor/Safari/Simulator are open.
- No SMTP is configured; Metabase will not send mail from this box.

## When you want full Metabase

1. Quit heavy apps if the JVM dies on start.
2. `cd ~/Desktop/LaunchPilot/kits/metabase && JAVA_TOOL_OPTIONS='-Xmx512m -Xms128m' ./start.sh`
3. Open http://localhost:3000 (Safari on the other monitor).
4. If it dies, use the lite dashboard instead.

## Files

- `start.sh` / `stop.sh` — Metabase jar
- `lite_dashboard.py` — light charts
- `supabase-connections.env` — secrets (gitignored)
- `com.launchpilot.metabase.plist` — optional KeepAlive (leave unloaded)
