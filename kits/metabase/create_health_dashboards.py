#!/usr/bin/env python3
"""Create (or refresh) one Metabase health dashboard each for Juicd and Corvim.

Idempotent by card/dashboard name. Secrets stay in supabase-connections.env.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from pathlib import Path

DIR = Path(__file__).resolve().parent
ENV_PATH = DIR / "supabase-connections.env"
BASE = "http://localhost:3000"
IDS_PATH = DIR / "metabase-db-ids.json"

JUICD_DB = 2
CORVIM_DB = 3


def load_cfg() -> dict:
    cfg = {}
    for line in ENV_PATH.read_text().splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        cfg[k.strip()] = v.strip()
    return cfg


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


def juicd_cards():
    return [
        native_card(
            JUICD_DB,
            "Juicd · Events today",
            """
            select coalesce(sum(event_count), 0)::int as "Events today"
            from v_juicd_analytics_daily
            where day = (timezone('America/Chicago', now()))::date
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            JUICD_DB,
            "Juicd · Errors last 24 hours",
            """
            select count(*)::int as "Errors last 24 hours"
            from juicd_app_errors
            where created_at > now() - interval '24 hours'
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            JUICD_DB,
            "Juicd · Errors last 7 days",
            """
            select coalesce(sum(error_count), 0)::int as "Errors last 7 days"
            from v_juicd_app_errors_daily
            where day >= (timezone('America/Chicago', now()))::date - 6
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            JUICD_DB,
            "Juicd · Slips last 7 days",
            """
            select slips_last_7d as "Slips last 7 days"
            from v_juicd_product_counts
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            JUICD_DB,
            "Juicd · Events per day (14 days)",
            """
            select gs::date as day, coalesce(sum(v.event_count), 0)::int as events
            from generate_series(
                ((timezone('America/Chicago', now()))::date - 13)::timestamp,
                (timezone('America/Chicago', now()))::date::timestamp,
                interval '1 day'
            ) gs
            left join v_juicd_analytics_daily v on v.day = gs::date
            group by 1
            order by 1
            """,
            "line",
            LINE("day", "events", "Day", "Events"),
        ),
        native_card(
            JUICD_DB,
            "Juicd · What people did (7 days)",
            """
            select event_name as event, coalesce(sum(event_count), 0)::int as count
            from v_juicd_analytics_daily
            where day >= (timezone('America/Chicago', now()))::date - 6
            group by 1
            order by 2 desc
            """,
            "bar",
            BAR("event", "count", "Event", "Count"),
        ),
        native_card(
            JUICD_DB,
            "Juicd · Errors per day (14 days)",
            """
            select gs::date as day, coalesce(sum(v.error_count), 0)::int as errors
            from generate_series(
                ((timezone('America/Chicago', now()))::date - 13)::timestamp,
                (timezone('America/Chicago', now()))::date::timestamp,
                interval '1 day'
            ) gs
            left join v_juicd_app_errors_daily v on v.day = gs::date
            group by 1
            order by 1
            """,
            "line",
            LINE("day", "errors", "Day", "Errors"),
        ),
        native_card(
            JUICD_DB,
            "Juicd · Slips submitted vs settled (14 days)",
            """
            select gs::date as day,
                   coalesce(s.slips_submitted, 0)::int as submitted,
                   coalesce(s.slip_wins, 0)::int as wins,
                   coalesce(s.slip_losses, 0)::int as losses
            from generate_series(
                ((timezone('America/Chicago', now()))::date - 13)::timestamp,
                (timezone('America/Chicago', now()))::date::timestamp,
                interval '1 day'
            ) gs
            left join v_juicd_slip_events_daily s on s.day = gs::date
            order by 1
            """,
            "line",
            LINE("day", ["submitted", "wins", "losses"], "Day", "Slips"),
        ),
        native_card(
            JUICD_DB,
            "Juicd · Product snapshot",
            """
            select metric as "Metric", value as "Value"
            from (
              select 1 as ord, 'Total slips' as metric, total_slips::text as value from v_juicd_product_counts
              union all select 2, 'Slips last 7 days', slips_last_7d::text from v_juicd_product_counts
              union all select 3, 'Play outcomes', total_play_outcomes::text from v_juicd_product_counts
              union all select 4, 'Friendships', total_friendships::text from v_juicd_product_counts
              union all select 5, 'Pending friend requests', pending_friend_requests::text from v_juicd_product_counts
              union all select 6, 'Groups', total_groups::text from v_juicd_product_counts
              union all select 7, 'Group memberships', total_group_memberships::text from v_juicd_product_counts
            ) s
            order by ord
            """,
            "table",
            {"table.pivot": False},
        ),
        native_card(
            JUICD_DB,
            "Juicd · Latest errors",
            """
            select
              created_at as "When",
              severity as "Severity",
              coalesce(nullif(screen, ''), '(unknown)') as "Screen",
              left(message, 180) as "Message"
            from juicd_app_errors
            order by created_at desc
            limit 25
            """,
            "table",
            {"table.pivot": False},
        ),
    ]


def corvim_cards():
    return [
        native_card(
            CORVIM_DB,
            "Corvim · Events today",
            """
            select coalesce(sum(event_count), 0)::int as "Events today"
            from v_analytics_daily
            where day = (timezone('America/Chicago', now()))::date
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Errors last 24 hours",
            """
            select count(*)::int as "Errors last 24 hours"
            from app_errors
            where created_at > now() - interval '24 hours'
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Posts last 7 days",
            """
            select posts_last_7d as "Posts last 7 days"
            from v_product_social_counts
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Workout-post reports (7 days)",
            """
            select coalesce(sum(report_count), 0)::int as "Reports last 7 days"
            from v_workout_post_reports_daily
            where report_day_utc >= (timezone('America/Chicago', now()))::date - 6
            """,
            "scalar",
            SCALAR,
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Events per day (14 days)",
            """
            select gs::date as day, coalesce(sum(v.event_count), 0)::int as events
            from generate_series(
                ((timezone('America/Chicago', now()))::date - 13)::timestamp,
                (timezone('America/Chicago', now()))::date::timestamp,
                interval '1 day'
            ) gs
            left join v_analytics_daily v on v.day = gs::date
            group by 1
            order by 1
            """,
            "line",
            LINE("day", "events", "Day", "Events"),
        ),
        native_card(
            CORVIM_DB,
            "Corvim · What people did (7 days)",
            """
            select event_name as event, coalesce(sum(event_count), 0)::int as count
            from v_analytics_daily
            where day >= (timezone('America/Chicago', now()))::date - 6
            group by 1
            order by 2 desc
            """,
            "bar",
            BAR("event", "count", "Event", "Count"),
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Posts, likes, follows per day",
            """
            select gs::date as day,
                   coalesce(s.posts, 0)::int as posts,
                   coalesce(s.likes, 0)::int as likes,
                   coalesce(s.follows, 0)::int as follows
            from generate_series(
                ((timezone('America/Chicago', now()))::date - 13)::timestamp,
                (timezone('America/Chicago', now()))::date::timestamp,
                interval '1 day'
            ) gs
            left join v_product_social_daily s on s.day = gs::date
            order by 1
            """,
            "line",
            LINE("day", ["posts", "likes", "follows"], "Day", "Count"),
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Errors per day (14 days)",
            """
            select gs::date as day, coalesce(sum(v.error_count), 0)::int as errors
            from generate_series(
                ((timezone('America/Chicago', now()))::date - 13)::timestamp,
                (timezone('America/Chicago', now()))::date::timestamp,
                interval '1 day'
            ) gs
            left join v_app_errors_daily v on v.day = gs::date
            group by 1
            order by 1
            """,
            "line",
            LINE("day", "errors", "Day", "Errors"),
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Product snapshot",
            """
            select metric as "Metric", value as "Value"
            from (
              select 1 as ord, 'Total posts' as metric, total_posts::text as value from v_product_social_counts
              union all select 2, 'Posts last 7 days', posts_last_7d::text from v_product_social_counts
              union all select 3, 'Total likes', total_likes::text from v_product_social_counts
              union all select 4, 'Likes last 7 days', likes_last_7d::text from v_product_social_counts
              union all select 5, 'Total follows', total_follows::text from v_product_social_counts
              union all select 6, 'Follows last 7 days', follows_last_7d::text from v_product_social_counts
              union all select 7, 'Rep-detection sets', total_sets::text from v_rep_detection_global
              union all select 8, 'Rep-detection matches', match_count::text from v_rep_detection_global
            ) s
            order by ord
            """,
            "table",
            {"table.pivot": False},
        ),
        native_card(
            CORVIM_DB,
            "Corvim · Latest errors",
            """
            select
              created_at as "When",
              severity as "Severity",
              coalesce(nullif(screen, ''), '(unknown)') as "Screen",
              left(message, 180) as "Message"
            from app_errors
            order by created_at desc
            limit 25
            """,
            "table",
            {"table.pivot": False},
        ),
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
    cfg = load_cfg()
    token = login(cfg)
    ids_file = json.loads(IDS_PATH.read_text()) if IDS_PATH.exists() else {}
    global JUICD_DB, CORVIM_DB
    JUICD_DB = int(ids_file.get("JUICD") or JUICD_DB)
    CORVIM_DB = int(ids_file.get("CORVIM") or CORVIM_DB)

    collection_id = upsert_collection(token, "App health")

    juicd_specs = juicd_cards()
    juicd_ids = [upsert_card(token, collection_id, spec) for spec in juicd_specs]
    # events_today, errors_24h, errors_7d, slips_7d, events_day, event_mix, errors_day, slips_day, snapshot, latest
    jmap = {
        "events_today": juicd_ids[0],
        "errors_24h": juicd_ids[1],
        "third": juicd_ids[2],
        "fourth": juicd_ids[3],
        "events_day": juicd_ids[4],
        "event_mix": juicd_ids[5],
        "left_chart": juicd_ids[6],
        "right_chart": juicd_ids[7],
        "snapshot": juicd_ids[8],
        "latest_errors": juicd_ids[9],
    }
    jdesc = (
        "One-screen Juicd health. Errors last 24 hours should stay at 0. "
        "Zeros are expected until TestFlight traffic writes events."
    )
    jdash = upsert_dashboard(token, "Juicd health", jdesc, collection_id)
    save_dashboard(
        token,
        jdash,
        "Juicd health",
        jdesc,
        collection_id,
        layout_health(
            jdash,
            jmap,
            "## Juicd health\n"
            "**Errors last 24 hours** is the first thing to check — it should stay at **0**. "
            "Events, slips, and social counts stay at 0 until people use the app. "
            "If events are 0 but errors jump, something is wrong.",
        ),
    )

    corvim_specs = corvim_cards()
    corvim_ids = [upsert_card(token, collection_id, spec) for spec in corvim_specs]
    cmap = {
        "events_today": corvim_ids[0],
        "errors_24h": corvim_ids[1],
        "third": corvim_ids[2],
        "fourth": corvim_ids[3],
        "events_day": corvim_ids[4],
        "event_mix": corvim_ids[5],
        "left_chart": corvim_ids[6],
        "right_chart": corvim_ids[7],
        "snapshot": corvim_ids[8],
        "latest_errors": corvim_ids[9],
    }
    cdesc = (
        "One-screen Corvim health. Errors last 24 hours should stay at 0. "
        "Reports last 7 days is moderation. Workout posts/likes are product activity."
    )
    cdash = upsert_dashboard(token, "Corvim health", cdesc, collection_id)
    save_dashboard(
        token,
        cdash,
        "Corvim health",
        cdesc,
        collection_id,
        layout_health(
            cdash,
            cmap,
            "## Corvim health\n"
            "**Errors last 24 hours** should stay at **0**. "
            "**Reports last 7 days** is moderation. "
            "Events and social charts fill in as people open the app and post workouts.",
        ),
    )

    print(f"Juicd health  http://localhost:3000/dashboard/{jdash}")
    print(f"Corvim health http://localhost:3000/dashboard/{cdash}")


if __name__ == "__main__":
    main()
