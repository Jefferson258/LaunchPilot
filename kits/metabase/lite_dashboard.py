#!/usr/bin/env python3
"""Lightweight analytics dashboard (stdlib + psycopg2) for Juicd + Corvim.

Metabase is preferred when this Mac has spare RAM; this kit stays free/local
and queries the same metabase_ro roles via Supabase pooler.

Usage:
  python3 lite_dashboard.py
  open http://127.0.0.1:3050
"""

from __future__ import annotations

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
HOST, PORT = "127.0.0.1", 3050


def load_cfg() -> dict:
    cfg = {}
    for line in ENV_PATH.read_text().splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        cfg[k.strip()] = v.strip()
    return cfg


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


def _sum_n(rows) -> int:
    return sum(int(r.get("n") or 0) for r in (rows or []))


def metrics(cfg: dict) -> dict:
    out = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "juicd": {},
        "corvim": {},
        "errors": [],
    }
    try:
        out["juicd"]["events_7d"] = q(
            cfg,
            "JUICD",
            """
            select event_name, count(*)::int as n
            from juicd_analytics_events
            where created_at > now() - interval '7 days'
            group by 1 order by 2 desc limit 20
            """,
        )
        out["juicd"]["errors_7d"] = q(
            cfg,
            "JUICD",
            """
            select coalesce(nullif(screen,''),'(unknown)') as screen,
                   severity, count(*)::int as n
            from juicd_app_errors
            where created_at > now() - interval '7 days'
            group by 1,2 order by 3 desc limit 20
            """,
        )
        out["juicd"]["errors_24h"] = q(
            cfg,
            "JUICD",
            """
            select count(*)::int as n
            from juicd_app_errors
            where created_at > now() - interval '24 hours'
            """,
        )
        out["juicd"]["product"] = q(cfg, "JUICD", "select * from v_juicd_product_counts")
        out["juicd"]["slips_daily"] = q(
            cfg,
            "JUICD",
            "select * from v_juicd_slip_events_daily limit 14",
        )
        out["juicd"]["summary"] = {
            "events_7d": _sum_n(out["juicd"]["events_7d"]),
            "errors_7d": _sum_n(out["juicd"]["errors_7d"]),
            "errors_24h": int((out["juicd"]["errors_24h"] or [{}])[0].get("n") or 0),
            "top_event": (out["juicd"]["events_7d"] or [{}])[0].get("event_name") or "—",
        }
    except Exception as e:
        out["errors"].append(f"juicd: {e}")

    try:
        out["corvim"]["events_7d"] = q(
            cfg,
            "CORVIM",
            """
            select event_name, count(*)::int as n
            from analytics_events
            where created_at > now() - interval '7 days'
            group by 1 order by 2 desc limit 20
            """,
        )
        out["corvim"]["errors_7d"] = q(
            cfg,
            "CORVIM",
            """
            select coalesce(nullif(screen,''),'(unknown)') as screen,
                   severity, count(*)::int as n
            from app_errors
            where created_at > now() - interval '7 days'
            group by 1,2 order by 3 desc limit 20
            """,
        )
        out["corvim"]["errors_24h"] = q(
            cfg,
            "CORVIM",
            """
            select count(*)::int as n
            from app_errors
            where created_at > now() - interval '24 hours'
            """,
        )
        out["corvim"]["summary"] = {
            "events_7d": _sum_n(out["corvim"]["events_7d"]),
            "errors_7d": _sum_n(out["corvim"]["errors_7d"]),
            "errors_24h": int((out["corvim"]["errors_24h"] or [{}])[0].get("n") or 0),
            "top_event": (out["corvim"]["events_7d"] or [{}])[0].get("event_name") or "—",
        }
    except Exception as e:
        out["errors"].append(f"corvim: {e}")
    return out


HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Launch Analytics</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js"></script>
<style>
  :root {
    --bg: #0c1117;
    --bg-elev: #121a24;
    --card: #16202b;
    --card-border: #243141;
    --text: #e8eef6;
    --muted: #8fa3b8;
    --faint: #5d7288;
    --juicd: #3dd6c6;
    --juicd-dim: rgba(61, 214, 198, 0.14);
    --corvim: #7eb6ff;
    --corvim-dim: rgba(126, 182, 255, 0.14);
    --warn: #f0b429;
    --bad: #ff7b7b;
    --ok: #6dcca8;
    --radius: 14px;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    font: 14px/1.45 "IBM Plex Sans", "Segoe UI", system-ui, sans-serif;
    color: var(--text);
    background:
      radial-gradient(900px 420px at 8% -10%, rgba(61,214,198,0.08), transparent 55%),
      radial-gradient(700px 380px at 92% 0%, rgba(126,182,255,0.08), transparent 50%),
      var(--bg);
  }
  header {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    justify-content: space-between;
    gap: 12px 24px;
    padding: 22px 28px 18px;
    border-bottom: 1px solid var(--card-border);
    background: rgba(12, 17, 23, 0.72);
    backdrop-filter: blur(10px);
    position: sticky;
    top: 0;
    z-index: 5;
  }
  .brand h1 {
    margin: 0;
    font-size: 22px;
    font-weight: 650;
    letter-spacing: -0.02em;
  }
  .brand .sub { color: var(--muted); margin-top: 4px; font-size: 13px; }
  .meta {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 10px;
    border-radius: 999px;
    background: var(--bg-elev);
    border: 1px solid var(--card-border);
    color: var(--muted);
    font-size: 12px;
  }
  .pill strong { color: var(--text); font-weight: 600; }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--ok); }
  .dot.warn { background: var(--warn); }
  .dot.bad { background: var(--bad); }
  button.refresh {
    appearance: none;
    border: 1px solid var(--card-border);
    background: var(--card);
    color: var(--text);
    border-radius: 10px;
    padding: 8px 12px;
    font: inherit;
    cursor: pointer;
  }
  button.refresh:hover { border-color: var(--muted); }
  main { padding: 20px 28px 48px; max-width: 1280px; margin: 0 auto; }
  .alerts { margin-bottom: 16px; }
  .alert {
    background: rgba(255,123,123,0.1);
    border: 1px solid rgba(255,123,123,0.35);
    color: #ffc9c9;
    padding: 10px 12px;
    border-radius: 10px;
    margin-bottom: 8px;
    font-size: 13px;
  }
  .kpi-row {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
    margin-bottom: 18px;
  }
  .kpi {
    background: var(--card);
    border: 1px solid var(--card-border);
    border-radius: var(--radius);
    padding: 14px 16px;
    min-height: 92px;
  }
  .kpi .label {
    color: var(--muted);
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin-bottom: 8px;
  }
  .kpi .value {
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.03em;
    line-height: 1.1;
  }
  .kpi .hint { color: var(--faint); font-size: 12px; margin-top: 6px; }
  .kpi.juicd { box-shadow: inset 3px 0 0 var(--juicd); }
  .kpi.corvim { box-shadow: inset 3px 0 0 var(--corvim); }
  .kpi.warn .value { color: var(--warn); }
  .kpi.bad .value { color: var(--bad); }
  .apps {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 16px;
  }
  .app-panel {
    background: var(--card);
    border: 1px solid var(--card-border);
    border-radius: var(--radius);
    overflow: hidden;
  }
  .app-panel > header {
    position: static;
    backdrop-filter: none;
    background: transparent;
    border-bottom: 1px solid var(--card-border);
    padding: 14px 16px;
  }
  .app-panel h2 {
    margin: 0;
    font-size: 16px;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .badge {
    font-size: 11px;
    font-weight: 600;
    padding: 3px 8px;
    border-radius: 999px;
  }
  .badge.juicd { background: var(--juicd-dim); color: var(--juicd); }
  .badge.corvim { background: var(--corvim-dim); color: var(--corvim); }
  .panel-body { padding: 14px 16px 16px; display: grid; gap: 14px; }
  .block h3 {
    margin: 0 0 8px;
    font-size: 13px;
    color: var(--muted);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .chart-wrap {
    position: relative;
    height: 220px;
    background: var(--bg-elev);
    border-radius: 10px;
    padding: 8px;
    border: 1px solid rgba(36,49,65,0.8);
  }
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }
  th, td {
    text-align: left;
    padding: 7px 6px;
    border-bottom: 1px solid rgba(36,49,65,0.9);
  }
  th { color: var(--faint); font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.03em; }
  td.num { text-align: right; font-variant-numeric: tabular-nums; color: var(--text); }
  .sev {
    display: inline-block;
    padding: 2px 7px;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
  }
  .sev-error, .sev-fatal { background: rgba(255,123,123,0.15); color: var(--bad); }
  .sev-warning, .sev-warn { background: rgba(240,180,41,0.15); color: var(--warn); }
  .sev-info { background: rgba(126,182,255,0.15); color: var(--corvim); }
  .empty { color: var(--faint); font-size: 13px; padding: 8px 0; }
  .wide { margin-top: 16px; }
  .wide .app-panel { }
  .scroll { max-height: 240px; overflow: auto; }
  .loading {
    color: var(--muted);
    padding: 48px 0;
    text-align: center;
  }
  @media (max-width: 980px) {
    .kpi-row { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .apps { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>
<header>
  <div class="brand">
    <h1>Launch Analytics</h1>
    <div class="sub">Lite dashboard · Juicd + Corvim via Supabase read-only · auto-refresh 60s</div>
  </div>
  <div class="meta">
    <span class="pill"><span class="dot" id="statusDot"></span> <span id="statusText">Connecting…</span></span>
    <span class="pill">Updated <strong id="updatedAt">—</strong></span>
    <button class="refresh" type="button" onclick="load(true)">Refresh</button>
  </div>
</header>
<main id="root"><div class="loading">Loading metrics…</div></main>
<script>
const charts = {};

function esc(s){
  return String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function fmtTime(iso){
  if(!iso) return '—';
  try {
    const d = new Date(iso);
    return d.toLocaleString(undefined, { month:'short', day:'numeric', hour:'numeric', minute:'2-digit' });
  } catch { return iso; }
}

function sumN(rows){ return (rows||[]).reduce((a,r)=>a+(r.n||0),0); }

function kpiClass(n, warnAt, badAt){
  if(n >= badAt) return 'bad';
  if(n >= warnAt) return 'warn';
  return '';
}

function tableEvents(rows){
  if(!rows || !rows.length) return '<div class="empty">No events in the last 7 days</div>';
  const max = Math.max(...rows.map(r=>r.n||0), 1);
  return `<div class="scroll"><table>
    <thead><tr><th>Event</th><th style="text-align:right">Count</th></tr></thead>
    <tbody>${rows.map(r=>`<tr>
      <td>${esc(r.event_name)}</td>
      <td class="num">${esc(r.n)} <span style="color:var(--faint);font-size:11px">(${Math.round(100*(r.n||0)/max)}%)</span></td>
    </tr>`).join('')}</tbody>
  </table></div>`;
}

function tableErrors(rows){
  if(!rows || !rows.length) return '<div class="empty">No errors in the last 7 days</div>';
  return `<div class="scroll"><table>
    <thead><tr><th>Screen</th><th>Severity</th><th style="text-align:right">Count</th></tr></thead>
    <tbody>${rows.map(r=>{
      const sev = String(r.severity||'info').toLowerCase();
      return `<tr>
        <td>${esc(r.screen)}</td>
        <td><span class="sev sev-${esc(sev)}">${esc(r.severity||'info')}</span></td>
        <td class="num">${esc(r.n)}</td>
      </tr>`;
    }).join('')}</tbody>
  </table></div>`;
}

function tableGeneric(rows){
  if(!rows || !rows.length) return '<div class="empty">No rows yet</div>';
  const cols = Object.keys(rows[0]);
  return `<div class="scroll"><table>
    <thead><tr>${cols.map(c=>`<th>${esc(c)}</th>`).join('')}</tr></thead>
    <tbody>${rows.map(r=>`<tr>${cols.map(c=>{
      const v = r[c];
      const num = typeof v === 'number';
      return `<td class="${num?'num':''}">${esc(v)}</td>`;
    }).join('')}</tr>`).join('')}</tbody>
  </table></div>`;
}

function destroyChart(id){
  if(charts[id]){ charts[id].destroy(); delete charts[id]; }
}

function barChart(id, rows, color){
  const el = document.getElementById(id);
  if(!el || !window.Chart) return;
  destroyChart(id);
  const labels = (rows||[]).slice(0,12).map(r=>r.event_name);
  const data = (rows||[]).slice(0,12).map(r=>r.n);
  charts[id] = new Chart(el, {
    type: 'bar',
    data: {
      labels,
      datasets: [{
        data,
        backgroundColor: color,
        borderRadius: 6,
        maxBarThickness: 28,
      }]
    },
    options: {
      indexAxis: 'y',
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { display: false }, tooltip: { callbacks: {
        title: (items) => items[0]?.label || '',
      }}},
      scales: {
        x: {
          grid: { color: 'rgba(36,49,65,0.8)' },
          ticks: { color: '#8fa3b8', precision: 0 },
          border: { display: false },
        },
        y: {
          grid: { display: false },
          ticks: { color: '#c5d3e0', font: { size: 11 } },
          border: { display: false },
        }
      }
    }
  });
}

function lineChart(id, rows){
  const el = document.getElementById(id);
  if(!el || !window.Chart || !rows || !rows.length) return;
  destroyChart(id);
  // Prefer day + count-like columns
  const keys = Object.keys(rows[0]);
  const dayKey = keys.find(k => /day|date|created/i.test(k)) || keys[0];
  const numKeys = keys.filter(k => k !== dayKey && rows.some(r => typeof r[k] === 'number'));
  const palette = ['#3dd6c6', '#7eb6ff', '#f0b429', '#c4a7ff'];
  charts[id] = new Chart(el, {
    type: 'line',
    data: {
      labels: rows.map(r => {
        const v = r[dayKey];
        try { return new Date(v).toLocaleDateString(undefined, { month:'short', day:'numeric' }); }
        catch { return String(v); }
      }).reverse(),
      datasets: numKeys.slice(0,4).map((k,i)=>({
        label: k,
        data: rows.map(r=>r[k]??0).reverse(),
        borderColor: palette[i%palette.length],
        backgroundColor: palette[i%palette.length] + '33',
        tension: 0.35,
        fill: false,
        pointRadius: 2,
        borderWidth: 2,
      }))
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { labels: { color: '#8fa3b8', boxWidth: 12 } } },
      scales: {
        x: { ticks: { color: '#8fa3b8', maxRotation: 0 }, grid: { display: false }, border: { display: false } },
        y: { ticks: { color: '#8fa3b8', precision: 0 }, grid: { color: 'rgba(36,49,65,0.8)' }, border: { display: false } }
      }
    }
  });
}

async function load(manual){
  const root = document.getElementById('root');
  const statusText = document.getElementById('statusText');
  const statusDot = document.getElementById('statusDot');
  if(manual) statusText.textContent = 'Refreshing…';
  try {
    const res = await fetch('/api/metrics');
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const data = await res.json();
    const j = data.juicd || {};
    const c = data.corvim || {};
    const js = j.summary || {};
    const cs = c.summary || {};
    const jErr24 = js.errors_24h || 0;
    const cErr24 = cs.errors_24h || 0;
    const alerts = (data.errors||[]).map(e=>`<div class="alert">${esc(e)}</div>`).join('');

    document.getElementById('updatedAt').textContent = fmtTime(data.generated_at);
    statusText.textContent = data.errors?.length ? 'Partial data' : 'Live';
    statusDot.className = 'dot' + (data.errors?.length ? ' warn' : '');

    root.innerHTML = `
      <div class="alerts">${alerts}</div>
      <div class="kpi-row">
        <div class="kpi juicd">
          <div class="label">Juicd events · 7d</div>
          <div class="value">${esc(js.events_7d ?? sumN(j.events_7d))}</div>
          <div class="hint">Top: ${esc(js.top_event || '—')}</div>
        </div>
        <div class="kpi juicd ${kpiClass(jErr24, 1, 10)}">
          <div class="label">Juicd errors · 24h</div>
          <div class="value">${esc(jErr24)}</div>
          <div class="hint">${esc(js.errors_7d ?? sumN(j.errors_7d))} in last 7 days</div>
        </div>
        <div class="kpi corvim">
          <div class="label">Corvim events · 7d</div>
          <div class="value">${esc(cs.events_7d ?? sumN(c.events_7d))}</div>
          <div class="hint">Top: ${esc(cs.top_event || '—')}</div>
        </div>
        <div class="kpi corvim ${kpiClass(cErr24, 1, 10)}">
          <div class="label">Corvim errors · 24h</div>
          <div class="value">${esc(cErr24)}</div>
          <div class="hint">${esc(cs.errors_7d ?? sumN(c.errors_7d))} in last 7 days</div>
        </div>
      </div>

      <div class="apps">
        <section class="app-panel">
          <header>
            <h2>Juicd <span class="badge juicd">Play / social</span></h2>
            <div class="sub">Event mix and error hotspots</div>
          </header>
          <div class="panel-body">
            <div class="block">
              <h3>Top events (7d)</h3>
              <div class="chart-wrap"><canvas id="je"></canvas></div>
            </div>
            <div class="block">
              <h3>Event breakdown</h3>
              ${tableEvents(j.events_7d)}
            </div>
            <div class="block">
              <h3>Errors by screen</h3>
              ${tableErrors(j.errors_7d)}
            </div>
          </div>
        </section>

        <section class="app-panel">
          <header>
            <h2>Corvim <span class="badge corvim">Social / workouts</span></h2>
            <div class="sub">Event mix and error hotspots</div>
          </header>
          <div class="panel-body">
            <div class="block">
              <h3>Top events (7d)</h3>
              <div class="chart-wrap"><canvas id="ce"></canvas></div>
            </div>
            <div class="block">
              <h3>Event breakdown</h3>
              ${tableEvents(c.events_7d)}
            </div>
            <div class="block">
              <h3>Errors by screen</h3>
              ${tableErrors(c.errors_7d)}
            </div>
          </div>
        </section>
      </div>

      <div class="wide">
        <section class="app-panel">
          <header>
            <h2>Juicd product snapshot</h2>
            <div class="sub">Counts + slip activity (last ~14 days)</div>
          </header>
          <div class="panel-body" style="grid-template-columns:1fr 1.2fr; display:grid;">
            <div class="block">
              <h3>Product counts</h3>
              ${tableGeneric(j.product)}
            </div>
            <div class="block">
              <h3>Slips daily</h3>
              <div class="chart-wrap"><canvas id="slips"></canvas></div>
              ${tableGeneric(j.slips_daily)}
            </div>
          </div>
        </section>
      </div>
    `;

    barChart('je', j.events_7d || [], '#3dd6c6');
    barChart('ce', c.events_7d || [], '#7eb6ff');
    if ((j.slips_daily || []).length) lineChart('slips', j.slips_daily);
  } catch (e) {
    statusText.textContent = 'Offline';
    statusDot.className = 'dot bad';
    root.innerHTML = `<div class="alert">Failed to load metrics: ${esc(e.message || e)}</div>`;
  }
}
load();
setInterval(() => load(false), 60000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("[%s] %s" % (self.log_date_time_string(), fmt % args))

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/", "/index.html"):
            body = HTML.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/api/metrics":
            cfg = load_cfg()
            payload = json.dumps(metrics(cfg), default=str).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self.send_error(404)


def main():
    if not ENV_PATH.exists():
        raise SystemExit(f"Missing {ENV_PATH}")
    cfg = load_cfg()
    for key in ("JUICD", "CORVIM"):
        conn = connect(cfg, key)
        conn.close()
        print(f"connected {key}")
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"Open http://{HOST}:{PORT}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
