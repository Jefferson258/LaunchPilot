#!/usr/bin/env python3
"""Create (or refresh) one Metabase health dashboard per product.

Products come from gitignored dashboards.local.json (template:
dashboards.example.json). Secrets (Metabase admin login) stay in gitignored
supabase-connections.env. Idempotent by card/dashboard name.

Each product needs an events table (event_name, created_at) and an errors
table (severity, message, screen, created_at) — the shape kits/analytics
writes. Usage:

  python3 create_health_dashboards.py
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from pathlib import Path

DIR = Path(__file__).resolve().parent
ENV_PATH = DIR / "supabase-connections.env"
CONFIG_PATH = Path(os.environ.get("METABASE_DASHBOARDS_FILE") or DIR / "dashboards.local.json")
IDS_PATH = DIR / "metabase-db-ids.json"


def load_cfg() -> dict:
    cfg = {}
    for line in ENV_PATH.read_text().splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        cfg[k.strip()] = v.strip()
    return cfg


def load_products() -> tuple[dict, list[dict]]:
    if not CONFIG_PATH.is_file():
        raise SystemExit(
            f"Missing {CONFIG_PATH}. Copy dashboards.example.json to dashboards.local.json and edit."
        )
    data = json.loads(CONFIG_PATH.read_text())
    return data, data.get("products") or []


BASE = os.environ.get("METABASE_URL", "http://localhost:3000")


def api(method: str, path: str, token: str | None = None, payload=None, allow_error: bool = False):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["X-Metabase-Session"] = token
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read().decode()
            return r.status, json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        err = e.read().decode()
        if allow_error:
            return e.code, err
        raise SystemExit(f"{method} {path} -> {e.code}: {err[:1200]}") from e


def login(cfg: dict) -> str:
    _, body = api(
        "POST",
        "/api/session",
        payload={
            "username": cfg["METABASE_ADMIN_EMAIL"],
            "password": cfg["METABASE_ADMIN_PASSWORD"],
        },
    )
    return body["id"]


def native_card(db: int, name: str, sql: str, display: str, viz: dict) -> dict:
    return {
        "name": name,
        "display": display,
        "collection_id": None,
        "dataset_query": {
            "database": db,
            "type": "native",
            "native": {"query": sql.strip()},
        },
        "visualization_settings": viz,
        "description": None,
    }


def find_named(items: list, name: str):
    for item in items:
        if item.get("name") == name and not item.get("archived"):
            return item
    return None


def upsert_card(token: str, collection_id: int, spec: dict) -> int:
    spec = dict(spec)
    spec["collection_id"] = collection_id
    _, cards = api("GET", "/api/card", token)
    existing = find_named(cards, spec["name"])
    if existing:
        _, body = api("PUT", f"/api/card/{existing['id']}", token, spec)
        return body["id"]
    _, body = api("POST", "/api/card", token, spec)
    return body["id"]


def upsert_collection(token: str, name: str) -> int | None:
    _, cols = api("GET", "/api/collection", token)
    existing = find_named(cols, name)
    if existing:
        return existing["id"]
    status, body = api(
        "POST",
        "/api/collection",
        token,
        {"name": name, "color": "blue", "parent_id": None},
        allow_error=True,
    )
    if status == 200 and isinstance(body, dict) and body.get("id"):
        return body["id"]
    personal = next(
        (c for c in cols if "Personal Collection" in (c.get("name") or "")),
        None,
    )
    return personal["id"] if personal else None


def upsert_dashboard(token: str, name: str, description: str, collection_id: int) -> int:
    _, dashes = api("GET", "/api/dashboard", token)
    existing = find_named(dashes, name)
    if existing:
        api(
            "PUT",
            f"/api/dashboard/{existing['id']}",
            token,
            {"name": name, "description": description, "collection_id": collection_id},
        )
        return existing["id"]
    _, body = api(
        "POST",
        "/api/dashboard",
        token,
        {"name": name, "description": description, "collection_id": collection_id},
    )
    return body["id"]


def text_card(dash_id: int, text: str, row: int, col: int, size_x: int, size_y: int, nid: int):
    return {
        "id": nid,
        "card_id": None,
        "dashboard_id": dash_id,
        "row": row,
        "col": col,
        "size_x": size_x,
        "size_y": size_y,
        "series": [],
        "parameter_mappings": [],
        "visualization_settings": {
            "virtual_card": {
                "name": None,
                "display": "text",
                "visualization_settings": {},
                "dataset_query": {},
                "archived": False,
            },
            "text": text,
        },
    }


def place(dash_id: int, card_id: int, row: int, col: int, size_x: int, size_y: int, nid: int):
    return {
        "id": nid,
        "card_id": card_id,
        "dashboard_id": dash_id,
        "row": row,
        "col": col,
        "size_x": size_x,
        "size_y": size_y,
        "series": [],
        "parameter_mappings": [],
        "visualization_settings": {},
    }


SCALAR = {
    "scalar.switch_positive_negative": False,
    "scalar.compact_primary_number": True,
}
BAR = lambda dim, metric, x, y: {
    "graph.dimensions": [dim],
    "graph.metrics": [metric],
    "graph.x_axis.title_text": x,
    "graph.y_axis.title_text": y,
    "graph.show_values": True,
}
LINE = lambda dim, metrics, x, y: {
    "graph.dimensions": [dim],
    "graph.metrics": metrics if isinstance(metrics, list) else [metrics],
    "graph.x_axis.title_text": x,
    "graph.y_axis.title_text": y,
    "graph.x_axis.scale": "timeseries",
}



def product_cards(p: dict, tz: str) -> list[dict]:
    db = int(p["metabase_db_id"])
    label = p["label"]
    ev = p.get("events_table", "analytics_events")
    er = p.get("errors_table", "app_errors")
    today = f"(timezone('{tz}', now()))::date"
    series14 = f"""
            generate_series(
                ({today} - 13)::timestamp,
                {today}::timestamp,
                interval '1 day'
            ) as gs"""
    return [
        native_card(db, f"{label} · Events today", f"""
            select count(*)::int as "Events today" from {ev}
            where (timezone('{tz}', created_at))::date = {today}
            """, "scalar", SCALAR),
        native_card(db, f"{label} · Errors last 24 hours", f"""
            select count(*)::int as "Errors last 24 hours" from {er}
            where created_at > now() - interval '24 hours'
            """, "scalar", SCALAR),
        native_card(db, f"{label} · Errors last 7 days", f"""
            select count(*)::int as "Errors last 7 days" from {er}
            where created_at > now() - interval '7 days'
            """, "scalar", SCALAR),
        native_card(db, f"{label} · Events last 7 days", f"""
            select count(*)::int as "Events last 7 days" from {ev}
            where created_at > now() - interval '7 days'
            """, "scalar", SCALAR),
        native_card(db, f"{label} · Events per day (14 days)", f"""
            select gs::date as "Day", coalesce(count(e.*), 0)::int as "Events"
            from {series14}
            left join {ev} e on (timezone('{tz}', e.created_at))::date = gs::date
            group by 1 order by 1
            """, "line", LINE("Day", "Events", "Day", "Events")),
        native_card(db, f"{label} · What people did (7 days)", f"""
            select event_name as "Event", count(*)::int as "Count" from {ev}
            where created_at > now() - interval '7 days'
            group by 1 order by 2 desc limit 15
            """, "bar", BAR("Event", "Count", "Event", "Count")),
        native_card(db, f"{label} · Errors per day (14 days)", f"""
            select gs::date as "Day", coalesce(count(e.*), 0)::int as "Errors"
            from {series14}
            left join {er} e on (timezone('{tz}', e.created_at))::date = gs::date
            group by 1 order by 1
            """, "line", LINE("Day", "Errors", "Day", "Errors")),
        native_card(db, f"{label} · Errors by screen (7 days)", f"""
            select coalesce(nullif(screen, ''), '(unknown)') as "Screen", count(*)::int as "Errors"
            from {er} where created_at > now() - interval '7 days'
            group by 1 order by 2 desc limit 15
            """, "bar", BAR("Screen", "Errors", "Screen", "Errors")),
        native_card(db, f"{label} · Errors by severity (7 days)", f"""
            select severity as "Severity", count(*)::int as "Errors"
            from {er} where created_at > now() - interval '7 days'
            group by 1 order by 2 desc
            """, "table", {"table.pivot": False}),
        native_card(db, f"{label} · Latest errors", f"""
            select created_at as "When", severity as "Severity",
                   coalesce(nullif(screen, ''), '(unknown)') as "Screen",
                   left(message, 180) as "Message"
            from {er} order by created_at desc limit 25
            """, "table", {"table.pivot": False}),
    ]


def layout_health(dash_id: int, ids: dict, intro: str):
    """4 KPIs, 4 charts, 2 tables. Grid is 24 wide."""
    order = [
        "events_today",
        "errors_24h",
        "third",
        "fourth",
        "events_day",
        "event_mix",
        "left_chart",
        "right_chart",
        "snapshot",
        "latest_errors",
    ]
    n = -1

    def nid():
        nonlocal n
        n -= 1
        return n

    cards = [
        text_card(dash_id, intro, 0, 0, 24, 2, nid()),
        place(dash_id, ids["events_today"], 2, 0, 6, 3, nid()),
        place(dash_id, ids["errors_24h"], 2, 6, 6, 3, nid()),
        place(dash_id, ids["third"], 2, 12, 6, 3, nid()),
        place(dash_id, ids["fourth"], 2, 18, 6, 3, nid()),
        place(dash_id, ids["events_day"], 5, 0, 12, 7, nid()),
        place(dash_id, ids["event_mix"], 5, 12, 12, 7, nid()),
        place(dash_id, ids["left_chart"], 12, 0, 12, 7, nid()),
        place(dash_id, ids["right_chart"], 12, 12, 12, 7, nid()),
        place(dash_id, ids["snapshot"], 19, 0, 10, 8, nid()),
        place(dash_id, ids["latest_errors"], 19, 10, 14, 8, nid()),
    ]
    return cards


def save_dashboard(token: str, dash_id: int, name: str, description: str, collection_id: int, dashcards: list):
    payload = {
        "name": name,
        "description": description,
        "collection_id": collection_id,
        "dashcards": dashcards,
        "tabs": [],
        "parameters": [],
        "auto_apply_filters": True,
    }
    api("PUT", f"/api/dashboard/{dash_id}", token, payload)


def main() -> None:
    data, products = load_products()
    tz = data.get("timezone", "UTC")
    cfg = load_cfg()
    token = login(cfg)
    ids_file = json.loads(IDS_PATH.read_text()) if IDS_PATH.exists() else {}
    collection_id = upsert_collection(token, data.get("collection", "App health"))
    keys = ["events_today", "errors_24h", "third", "fourth", "events_day",
            "event_mix", "left_chart", "right_chart", "snapshot", "latest_errors"]
    for p in products:
        if ids_file.get(p.get("env_prefix", "")):
            p["metabase_db_id"] = ids_file[p["env_prefix"]]
        specs = product_cards(p, tz)
        ids = [upsert_card(token, collection_id, spec) for spec in specs]
        name = f"{p['label']} health"
        desc = f"One-screen {p['label']} health. Errors last 24 hours should stay at 0."
        dash = upsert_dashboard(token, name, desc, collection_id)
        intro = (
            f"## {p['label']} health\n"
            "**Errors last 24 hours** is the first thing to check — it should stay at **0**. "
            "Event charts stay flat until people use the app."
        )
        save_dashboard(token, dash, name, desc, collection_id, layout_health(dash, dict(zip(keys, ids)), intro))
        print(f"{name}  {BASE}/dashboard/{dash}")


if __name__ == "__main__":
    main()
