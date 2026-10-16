#!/usr/bin/env python3
"""Lightweight analytics dashboard (stdlib + psycopg2) for your products.

Metabase is nicer when the machine has spare RAM; this stays free/local and
queries the same read-only roles via the Supabase pooler.

Products come from gitignored dashboards.local.json (template:
dashboards.example.json). Connection secrets come from gitignored
supabase-connections.env, using each product's env_prefix:
  <PREFIX>_HOST, <PREFIX>_PORT, <PREFIX>_DB, <PREFIX>_USER, <PREFIX>_PASSWORD

Usage:
  python3 lite_dashboard.py
  open http://127.0.0.1:3050
"""

from __future__ import annotations

import html
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

try:
    import psycopg2
    import psycopg2.extras
except ImportError as e:
    raise SystemExit("Install psycopg2-binary: python3 -m pip install --user psycopg2-binary") from e

DIR = Path(__file__).resolve().parent
ENV_PATH = DIR / "supabase-connections.env"
CONFIG_PATH = Path(os.environ.get("METABASE_DASHBOARDS_FILE") or DIR / "dashboards.local.json")
HOST, PORT = "127.0.0.1", int(os.environ.get("LITE_DASHBOARD_PORT", "3050"))


def load_cfg() -> dict:
    cfg = {}
    for line in ENV_PATH.read_text().splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        cfg[k.strip()] = v.strip()
    return cfg


def load_products() -> list[dict]:
    if not CONFIG_PATH.is_file():
        raise SystemExit(f"Missing {CONFIG_PATH}. Copy dashboards.example.json to dashboards.local.json.")
    return json.loads(CONFIG_PATH.read_text()).get("products") or []


def connect(cfg: dict, key: str):
    return psycopg2.connect(
        host=cfg[f"{key}_HOST"],
        port=int(cfg.get(f"{key}_PORT", "5432")),
        dbname=cfg.get(f"{key}_DB", "postgres"),
        user=cfg[f"{key}_USER"],
        password=cfg[f"{key}_PASSWORD"],
        sslmode="require",
        connect_timeout=15,
    )


def q(cfg: dict, key: str, sql: str):
    conn = connect(cfg, key)
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql)
            return list(cur.fetchall())
    finally:
        conn.close()


def product_metrics(cfg: dict, p: dict) -> dict:
    key = p["env_prefix"]
    ev = p.get("events_table", "analytics_events")
    er = p.get("errors_table", "app_errors")
    events = q(cfg, key, f"""
        select event_name, count(*)::int as n from {ev}
        where created_at > now() - interval '7 days'
        group by 1 order by 2 desc limit 20""")
    errors = q(cfg, key, f"""
        select coalesce(nullif(screen,''),'(unknown)') as screen, severity, count(*)::int as n
        from {er} where created_at > now() - interval '7 days'
        group by 1,2 order by 3 desc limit 20""")
    e24 = q(cfg, key, f"select count(*)::int as n from {er} where created_at > now() - interval '24 hours'")
    latest = q(cfg, key, f"""
        select created_at, severity, coalesce(nullif(screen,''),'(unknown)') as screen,
               left(message, 160) as message
        from {er} order by created_at desc limit 10""")
    return {
        "label": p["label"],
        "events_7d": events,
        "errors_7d": errors,
        "latest_errors": latest,
        "summary": {
            "events_7d": sum(r["n"] for r in events),
            "errors_7d": sum(r["n"] for r in errors),
            "errors_24h": int((e24 or [{}])[0].get("n") or 0),
            "top_event": (events or [{}])[0].get("event_name") or "—",
        },
    }


def metrics(cfg: dict) -> dict:
    out = {"generated_at": datetime.now(timezone.utc).isoformat(), "products": [], "errors": []}
    for p in load_products():
        try:
            out["products"].append(product_metrics(cfg, p))
        except Exception as e:  # keep the page up if one product fails
            out["errors"].append(f"{p.get('label', '?')}: {e}")
    return out


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Launch Analytics</title>
<style>
 body{font:14px -apple-system,system-ui,sans-serif;background:#0c1117;color:#e6edf3;margin:0;padding:24px}
 h1{font-size:20px;margin:0 0 4px} .sub{color:#8b98a5;margin-bottom:20px}
 .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:16px}
 .card{background:#16202b;border:1px solid #243141;border-radius:12px;padding:16px}
 .kpis{display:flex;gap:16px;flex-wrap:wrap;margin:8px 0 12px}
 .kpi .v{font-size:22px;font-weight:600} .kpi .l{color:#8b98a5;font-size:12px}
 .bad{color:#ff7b72} table{width:100%;border-collapse:collapse;font-size:12px}
 td,th{text-align:left;padding:4px 6px;border-top:1px solid #243141} .err{color:#ff7b72}
</style></head><body>
<h1>Launch Analytics</h1><div class="sub">Lite dashboard · read-only · auto-refresh 60s · <span id="ts"></span></div>
<div id="errs" class="err"></div><div class="grid" id="grid"></div>
<script>
function esc(s){return String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
function rows(list,cols){return '<table><tr>'+cols.map(c=>'<th>'+esc(c)+'</th>').join('')+'</tr>'+
  list.map(r=>'<tr>'+cols.map(c=>'<td>'+esc(r[c])+'</td>').join('')+'</tr>').join('')+'</table>'}
async function load(){
  const d=await (await fetch('/api/metrics')).json();
  document.getElementById('ts').textContent=d.generated_at;
  document.getElementById('errs').textContent=(d.errors||[]).join(' · ');
  document.getElementById('grid').innerHTML=d.products.map(p=>{const s=p.summary;return `
   <div class="card"><h2>${esc(p.label)}</h2><div class="kpis">
    <div class="kpi"><div class="v">${s.events_7d}</div><div class="l">events · 7d</div></div>
    <div class="kpi"><div class="v ${s.errors_24h>0?'bad':''}">${s.errors_24h}</div><div class="l">errors · 24h</div></div>
    <div class="kpi"><div class="v">${s.errors_7d}</div><div class="l">errors · 7d</div></div>
    <div class="kpi"><div class="v">${esc(s.top_event)}</div><div class="l">top event</div></div></div>
    <h3>Events (7d)</h3>${rows(p.events_7d,['event_name','n'])}
    <h3>Errors by screen (7d)</h3>${rows(p.errors_7d,['screen','severity','n'])}
    <h3>Latest errors</h3>${rows(p.latest_errors,['created_at','severity','screen','message'])}
   </div>`}).join('');
}
load(); setInterval(load,60000);
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code: int, ctype: str, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            return self._send(200, "text/html; charset=utf-8", PAGE.encode())
        if path == "/api/metrics":
            payload = json.dumps(metrics(load_cfg()), default=str).encode()
            return self._send(200, "application/json", payload)
        self.send_error(404)


def main():
    if not ENV_PATH.exists():
        raise SystemExit(f"Missing {ENV_PATH}")
    cfg = load_cfg()
    for p in load_products():
        connect(cfg, p["env_prefix"]).close()
        print(f"connected {html.escape(p['label'])}")
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Open http://{HOST}:{PORT}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
