# Ops kit — error spike watcher + (future) health checks

## Error spike → alert

Configure products first (local, gitignored):

```bash
cp kits/ops/products.example.json kits/ops/products.local.json
# fill in Supabase project ref, repo folder, errors table, gh_repo, pilot product
```

```bash
# one-shot (safe dry run)
./bin/pilot watch-spikes --dry-run

# live: writes jobs/alerts/*.md, opens GitHub issue, optional ntfy push
./bin/pilot watch-spikes
```

### What counts as a spike

Per product errors table (configured in `kits/ops/products.local.json`, e.g. `app_errors`), for each `(screen, severity)` in the last **15 minutes**:

- count ≥ **max(5, 3× 7-day baseline per window)**, or
- overall window ≥ 10 errors and this bucket ≥ 5

Duplicates with the same fingerprint are suppressed (`jobs/alerts/spike-state.json`).

### Alert channels

| Channel | How |
|---------|-----|
| Local file | `LaunchPilot/jobs/alerts/<product>-spike-*.md` |
| GitHub issue | Opens on the product's `gh_repo` with the markdown body (visible on phone) |
| Phone push | Set `PILOT_NTFY_TOPIC=your-secret-topic` in `config/pilot.env`, install [ntfy](https://ntfy.sh) app, subscribe to that topic |
| Notion | Script prints a ready card; agent/MCP creates it, or Shortcuts polls `jobs/alerts/` |

No auto-deploy / auto-fix.

### Schedule (macOS launchd example)

Copy `com.launchpilot.watch-spikes.plist.example` → `~/Library/LaunchAgents/`,
edit paths, then load it for the logged-in user:

```bash
mkdir -p /path/to/LaunchPilot/jobs/alerts
launchctl bootstrap "gui/$(id -u)" \
  ~/Library/LaunchAgents/com.launchpilot.watch-spikes.plist
```

Runs every 15 minutes while logged in.

Before bootstrapping, link each Supabase-backed repository so the watcher can
run its read-only `supabase db query --linked` checks:

```bash
cd "$PILOT_WORKSPACE/ExampleApp" && supabase link --project-ref <your-project-ref>
```

Verify each link with
`supabase db query --linked --output-format json 'select 1 as ok;'`, then
bootstrap the plist and run `./bin/pilot watch-status`. Do not bootstrap a
plist whose projects are not linked. The watcher also checks each linked
project ref against its configured `ref` in `products.local.json` before querying, so a
repository linked to the wrong project fails closed.

Verify installation and launchd state without changing anything:

```bash
./bin/pilot watch-status
./bin/pilot watch-status --require-running  # fail unless active right now
```

`loaded but idle` is healthy for a `StartInterval` job between runs. Check the
reported stdout/stderr timestamps for evidence of the last invocation. The
`watch-status` also fails when launchd reports a nonzero last exit code. If the
stderr log says macOS denied access to a checkout under a privacy-protected folder (e.g. `~/Desktop`), move the
checkout to a non-protected path (or grant the launchd Python process the
required privacy access) and bootstrap the plist again. The status command
does not print or inspect credentials.
