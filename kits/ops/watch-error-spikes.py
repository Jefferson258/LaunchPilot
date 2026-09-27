#!/usr/bin/env python3
"""Detect error spikes in Juicd/Corvim Supabase app_errors tables and alert.

Alerts (in order, each optional):
  1. Write markdown under LaunchPilot/jobs/alerts/
  2. Create a GitHub issue on the product repo (phone-visible)
  3. POST to ntfy.sh topic if PILOT_NTFY_TOPIC is set (phone push, free)
  4. Print a Notion-ready card body for the agent / Shortcuts

No auto-deploy. No secrets committed — uses `supabase` CLI login role.

Usage:
  python3 watch-error-spikes.py [--dry-run] [--window-min 15] [--product juicd|corvim|all]
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import hashlib
import tempfile
from datetime import datetime, timezone
from pathlib import Path

LP_DIR = Path(__file__).resolve().parents[2]
ALERTS_DIR = LP_DIR / "jobs" / "alerts"
STATE_PATH = ALERTS_DIR / "spike-state.json"

PRODUCTS = {
    "juicd": {
        "ref": "hwyxtklbffqwcbtuetit",
        "repo": "juicd",
        "table": "juicd_app_errors",
        "gh_repo": "Jefferson258/juicd",
        "label": "Juicd",
        "pilot_product": "juicd-app",
    },
    "corvim": {
        "ref": "ptqrkpiiflihuhcfkutd",
        "repo": "Corvim",
        "table": "app_errors",
        "gh_repo": "Jefferson258/Corvim",
        "label": "Corvim",
        "pilot_product": "corvim-app",
    },
}

def product_workdir(cfg: dict) -> Path:
    workspace = Path(
        os.environ.get("PILOT_WORKSPACE", str(Path.home() / "Desktop"))
    ).expanduser()
    return workspace / cfg["repo"]


def verify_linked_project(workdir: Path, expected_ref: str) -> None:
    ref_file = workdir / "supabase" / ".temp" / "project-ref"
    if not ref_file.is_file():
        raise RuntimeError(f"Supabase project is not linked (missing {ref_file})")
    actual_ref = ref_file.read_text().strip()
    if actual_ref != expected_ref:
        raise RuntimeError(
            f"Supabase project ref mismatch: expected {expected_ref}, got {actual_ref or '(empty)'}"
        )


def run(cmd: list[str], cwd: Path | None = None, timeout: int = 90) -> subprocess.CompletedProcess:
    env = os.environ.copy()
    env.setdefault("DO_NOT_TRACK", "1")
    env.setdefault("SUPABASE_INTERNAL_DISABLE_TELEMETRY", "1")
    # Prefer CLI token from Keychain when unset (macOS).
    if "SUPABASE_ACCESS_TOKEN" not in env:
        try:
            tok = subprocess.check_output(
                ["security", "find-generic-password", "-s", "Supabase CLI", "-w"],
                text=True,
                timeout=5,
            ).strip()
            if tok:
                env["SUPABASE_ACCESS_TOKEN"] = tok
        except Exception:
            pass
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)


def db_query(workdir: Path, sql: str) -> list[dict]:
    proc = run(
        ["supabase", "db", "query", "--linked", "--output-format", "json", sql],
        cwd=workdir,
        timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"supabase db query failed in {workdir}: {proc.stderr or proc.stdout}")
    # CLI may print banners before/after the JSON object. Decode one complete
    # object instead of assuming JSON occupies the rest of stdout.
    text = proc.stdout.strip()
    decoder = json.JSONDecoder()
    for start, char in enumerate(text):
        if char != "{":
            continue
        try:
            payload, _ = decoder.raw_decode(text[start:])
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict) and "rows" in payload:
            return payload.get("rows") or []
    raise RuntimeError(f"no JSON query result in output: {text[:300]}")


def spike_sql(table: str, window_min: int) -> str:
    # Absolute floor avoids noise on empty projects; 3× baseline catches relative spikes.
    return f"""
with win as (
  select
    coalesce(nullif(screen, ''), '(unknown)') as screen,
    severity,
    count(*)::int as n
  from public.{table}
  where created_at > now() - interval '{window_min} minutes'
  group by 1, 2
),
base as (
  select
    coalesce(nullif(screen, ''), '(unknown)') as screen,
    severity,
    (count(*)::float / greatest(1, (7 * 24 * 60 / {window_min}))) as avg_per_window
  from public.{table}
  where created_at > now() - interval '7 days'
    and created_at <= now() - interval '{window_min} minutes'
  group by 1, 2
),
totals as (
  select
    (select count(*)::int from public.{table}
      where created_at > now() - interval '{window_min} minutes') as window_total,
    (select count(*)::int from public.{table}
      where created_at > now() - interval '7 days') as week_total
)
select
  w.screen,
  w.severity,
  w.n as window_count,
  round(coalesce(b.avg_per_window, 0)::numeric, 3) as baseline_avg,
  t.window_total,
  t.week_total,
  case
    when w.n >= greatest(5, ceil(3 * coalesce(b.avg_per_window, 0))) then true
    when t.window_total >= 10 and w.n >= 5 then true
    else false
  end as is_spike
from win w
cross join totals t
left join base b on b.screen = w.screen and b.severity = w.severity
order by w.n desc;
"""


def load_state() -> dict:
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text())
        except Exception:
            return {}
    return {}


def save_state(state: dict) -> None:
    ALERTS_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", dir=ALERTS_DIR, prefix=".spike-state.", delete=False
    ) as tmp:
        json.dump(state, tmp, indent=2)
        tmp.write("\n")
        tmp_path = Path(tmp.name)
    tmp_path.replace(STATE_PATH)


def fingerprint(product: str, rows: list[dict]) -> str:
    key = "|".join(
        f"{r['screen']}:{r['severity']}:{r['window_count']}"
        for r in rows
        if r.get("is_spike") in (True, "t", "true", 1)
    )
    return hashlib.sha256(f"{product}:{key}".encode()).hexdigest()[:16]


def write_alert_md(product: str, label: str, rows: list[dict], window_min: int) -> Path:
    ALERTS_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    path = ALERTS_DIR / f"{product}-spike-{stamp}.md"
    spikes = [r for r in rows if r.get("is_spike") in (True, "t", "true", 1)]
    lines = [
        f"# Error spike — {label}",
        "",
        f"- Detected (UTC): {datetime.now(timezone.utc).isoformat()}",
        f"- Window: last {window_min} minutes",
        f"- Product: {product}",
        "",
        "## Spikes",
        "",
        "| screen | severity | window | baseline/window |",
        "|--------|----------|--------|-----------------|",
    ]
    for r in spikes:
        lines.append(
            f"| {r['screen']} | {r['severity']} | {r['window_count']} | {r['baseline_avg']} |"
        )
    lines += [
        "",
        "## Suggested Notion card",
        "",
        f"**Task:** {label} error spike ({spikes[0]['screen'] if spikes else 'unknown'})",
        "**Status:** To Do Next",
        "**Priority:** P0 - Do first",
        "**Owner:** Agent",
        f"**Next Action:** Investigate `{spikes[0]['screen'] if spikes else '?'}` errors; pull last 50 from `{PRODUCTS[product]['table']}`; fix + tests; PR only (no auto-ship).",
        "",
        "## SQL to paste",
        "",
        "```sql",
        f"select created_at, severity, screen, message, app_version, build",
        f"from public.{PRODUCTS[product]['table']}",
        f"where created_at > now() - interval '{window_min} minutes'",
        "order by created_at desc limit 50;",
        "```",
        "",
    ]
    path.write_text("\n".join(lines))
    return path


def create_github_issue(repo: str, title: str, body: str, dry_run: bool) -> str | None:
    if dry_run:
        print(f"[dry-run] would open GitHub issue on {repo}: {title}")
        return None
    proc = run(
        [
            "gh",
            "issue",
            "create",
            "--repo",
            repo,
            "--title",
            title,
            "--body",
            body,
            "--label",
            "bug",
        ],
        timeout=60,
    )
    if proc.returncode != 0:
        # label may not exist — retry without
        proc = run(
            ["gh", "issue", "create", "--repo", repo, "--title", title, "--body", body],
            timeout=60,
        )
    if proc.returncode != 0:
        print(f"GitHub issue failed: {proc.stderr or proc.stdout}", file=sys.stderr)
        return None
    url = (proc.stdout or "").strip()
    print(f"GitHub issue: {url}")
    return url or None


def append_intake_job(pilot_product: str, prompt: str, dry_run: bool) -> Path:
    inbox = LP_DIR / "intake" / "inbox.md"
    if not inbox.exists():
        example = LP_DIR / "intake" / "inbox.example.md"
        inbox.write_text(example.read_text() if example.exists() else "# LaunchPilot intake inbox\n\n")
    line = f"{pilot_product} | {prompt}\n"
    if dry_run:
        print(f"[dry-run] would append to {inbox}: {line.strip()}")
        return inbox
    with inbox.open("a") as f:
        f.write(line)
    print(f"appended intake job: {line.strip()}")
    return inbox


def maybe_auto_dispatch(dry_run: bool) -> None:
    if os.environ.get("PILOT_SPIKE_AUTO_DISPATCH", "").strip() not in ("1", "true", "yes"):
        print("PILOT_SPIKE_AUTO_DISPATCH not set — intake job queued; run `pilot dispatch`")
        return
    if dry_run:
        print("[dry-run] would run intake/dispatch.sh (PR-only pipeline)")
        return
    proc = run(["bash", str(LP_DIR / "intake" / "dispatch.sh")], cwd=LP_DIR, timeout=7200)
    if proc.returncode != 0:
        print(f"auto-dispatch failed: {proc.stderr or proc.stdout}", file=sys.stderr)
    else:
        print("auto-dispatch finished")


def ntfy_push(topic: str, title: str, message: str, dry_run: bool) -> None:
    if dry_run:
        print(f"[dry-run] would ntfy {topic}: {title}")
        return
    try:
        import urllib.request

        req = urllib.request.Request(
            f"https://ntfy.sh/{topic}",
            data=message.encode(),
            method="POST",
            headers={"Title": title, "Priority": "high", "Tags": "warning,skull"},
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            print(f"ntfy status {resp.status}")
    except Exception as e:
        print(f"ntfy failed: {e}", file=sys.stderr)


def check_product(product: str, window_min: int, dry_run: bool) -> int:
    cfg = PRODUCTS[product]
    workdir = product_workdir(cfg)
    if not workdir.is_dir():
        print(f"query failed for {product}: missing repository {workdir}", file=sys.stderr)
        return 1
    print(f"==> checking {cfg['label']} ({cfg['table']})")
    try:
        verify_linked_project(workdir, cfg["ref"])
        rows = db_query(workdir, spike_sql(cfg["table"], window_min))
    except Exception as e:
        print(f"query failed for {product}: {e}", file=sys.stderr)
        return 1

    spikes = [r for r in rows if r.get("is_spike") in (True, "t", "true", 1)]
    if not spikes:
        print(f"no spike ({len(rows)} screen/severity buckets in window)")
        return 0

    fp = fingerprint(product, rows)
    state = load_state()
    last = (state.get(product) or {}).get("fingerprint")
    if last == fp:
        print(f"spike already alerted (fingerprint {fp}) — skipping duplicate")
        return 0

    path = write_alert_md(product, cfg["label"], rows, window_min)
    print(f"wrote {path}")
    body = path.read_text()
    title = f"[error-spike] {cfg['label']}: {spikes[0]['screen']} ×{spikes[0]['window_count']} ({spikes[0]['severity']})"
    issue_url = create_github_issue(cfg["gh_repo"], title, body, dry_run)

    topic = os.environ.get("PILOT_NTFY_TOPIC", "").strip()
    if topic:
        ntfy_push(topic, title, f"{cfg['label']} error spike. See {issue_url or path}", dry_run)

    top = spikes[0]
    fix_prompt = (
        f"Error spike on {top['screen']} ({top['severity']}): "
        f"{top['window_count']} in last {window_min}m. "
        f"Investigate {cfg['table']}, fix root cause, add regression coverage if practical. "
        f"PR only — no auto-ship. Alert: {path.name}"
    )
    append_intake_job(cfg["pilot_product"], fix_prompt, dry_run)
    maybe_auto_dispatch(dry_run)

    print("\n--- Notion card (create via MCP / phone Shortcuts) ---")
    print(f"Task: {title}")
    print("Status: To Do Next | Priority: P0 - Do first | Owner: Agent | App:", cfg["label"] if cfg["label"] in ("Juicd", "Corvim") else "Business")
    print(f"Notes: alert file {path}" + (f" issue {issue_url}" if issue_url else ""))

    if not dry_run:
        state[product] = {
            "fingerprint": fp,
            "at": datetime.now(timezone.utc).isoformat(),
            "alert": str(path),
            "issue": issue_url,
        }
        save_state(state)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--window-min", type=int, default=15)
    ap.add_argument("--product", choices=["juicd", "corvim", "all"], default="all")
    args = ap.parse_args()
    if not 1 <= args.window_min <= 7 * 24 * 60:
        ap.error("--window-min must be between 1 and 10080 minutes")

    # Optional pilot.env
    env_path = LP_DIR / "config" / "pilot.env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            key = k.strip()
            if key.startswith("export "):
                key = key[7:].strip()
            os.environ.setdefault(key, v.strip().strip('"').strip("'"))

    products = ["juicd", "corvim"] if args.product == "all" else [args.product]
    rc = 0
    for p in products:
        rc |= check_product(p, args.window_min, args.dry_run)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
