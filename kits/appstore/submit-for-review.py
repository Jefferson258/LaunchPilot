#!/usr/bin/env python3
"""Optional App Store Connect 'Submit for Review' via the reviewSubmissions API.

Gated for future use. Default mode is --dry-run (read-only ASC GETs + plan).
Real submit requires --execute (and LaunchPilot's bash wrapper also requires
--confirm). Never implied by `pilot run … --ship`.

Phased vs regular release (version *updates* only — not the first public version):
  --phased      Create appStoreVersionPhasedRelease (Apple's fixed 7-day ramp).
  --no-phased   Regular/immediate release (default). Deletes a planned
                (INACTIVE) phased release if one exists; does not touch an
                already-started ramp. Pause / Release to All stay in ASC UI.

Flow (Apple's current API):
  1. Optionally create/delete appStoreVersionPhasedRelease on the version
  2. POST /v1/reviewSubmissions  (app + platform)
  3. POST /v1/reviewSubmissionItems  (appStoreVersion)
  4. PATCH /v1/reviewSubmissions/{id}  submitted=true

Usage (from LaunchPilot root):
  python3 kits/appstore/submit-for-review.py juicd --dry-run
  python3 kits/appstore/submit-for-review.py juicd --dry-run --phased
  python3 kits/appstore/submit-for-review.py juicd --execute --phased
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any
from urllib import request as urlrequest

try:
    import jwt
except ImportError:
    sys.exit("PyJWT required: pip3 install pyjwt cryptography")

ROOT = Path(__file__).resolve().parent
KIT_DIR = ROOT.parent / "testflight"
API = "https://api.appstoreconnect.apple.com"

APPS = {
    "velour": {"asc_app_id": "6785327329", "platform": "IOS"},
    "corvim": {"asc_app_id": "6760210188", "platform": "IOS"},
    "juicd": {"asc_app_id": "6785327494", "platform": "IOS"},
}

SUBMITTABLE = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
}

# Idempotent "already set" states when --phased is requested.
PHASED_OK_STATES = {"INACTIVE", "ACTIVE"}


class PhasedReleaseError(RuntimeError):
    """Raised when Apple rejects phased release (e.g. first public version)."""


def load_asc_config() -> tuple[str, str, str]:
    config = KIT_DIR / "config.sh"
    if not config.is_file():
        sys.exit(f"Missing {config}")
    out = subprocess.check_output(
        [
            "bash",
            "-lc",
            f"source '{config}' && printf '%s\\n' \"$ASC_KEY_ID\" \"$ASC_ISSUER_ID\" \"$ASC_KEY_PATH\"",
        ],
        text=True,
    ).strip().splitlines()
    if len(out) != 3:
        sys.exit("Could not read ASC config from kits/testflight/config.sh")
    key_id, issuer_id, key_path = out
    if not Path(key_path).is_file():
        sys.exit(f"ASC key not found: {key_path}")
    return key_id, issuer_id, key_path


class ASCClient:
    def __init__(self, key_id: str, issuer_id: str, key_path: str) -> None:
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = Path(key_path).read_text()

    def token(self) -> str:
        return jwt.encode(
            {
                "iss": self.issuer_id,
                "iat": int(time.time()),
                "exp": int(time.time()) + 1200,
                "aud": "appstoreconnect-v1",
            },
            self.private_key,
            algorithm="ES256",
            headers={"kid": self.key_id, "typ": "JWT"},
        )

    def request(
        self,
        method: str,
        path: str,
        body: dict | None = None,
        *,
        allow_not_found: bool = False,
    ) -> dict | None:
        url = f"{API}{path}"
        data = json.dumps(body).encode() if body is not None else None
        req = urlrequest.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token()}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urlrequest.urlopen(req) as resp:
                raw = resp.read().decode()
        except urlrequest.HTTPError as e:
            raw = e.read().decode()
            if allow_not_found and e.code == 404:
                return None
            raise RuntimeError(f"{method} {path} failed ({e.code}): {raw}") from e
        return json.loads(raw) if raw else {}


def get_editable_version(client: ASCClient, app_id: str) -> dict:
    data = client.request(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20",
    )
    versions = data.get("data", [])
    preferred = [
        v
        for v in versions
        if v["attributes"].get("appStoreState") in SUBMITTABLE
    ]
    if preferred:
        return preferred[0]
    if versions:
        return versions[0]
    raise RuntimeError(f"No app store version found for app {app_id}")


def find_open_submission(client: ASCClient, app_id: str) -> dict | None:
    data = client.request(
        "GET",
        f"/v1/reviewSubmissions?filter[app]={app_id}&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES&limit=5",
    )
    items = data.get("data") or []
    return items[0] if items else None


def get_phased_release(client: ASCClient, version_id: str) -> dict | None:
    """Return the version's appStoreVersionPhasedRelease resource, or None."""
    data = client.request(
        "GET",
        f"/v1/appStoreVersions/{version_id}/appStoreVersionPhasedRelease",
        allow_not_found=True,
    )
    if not data or not data.get("data"):
        return None
    return data["data"]


def plan_phased_release(
    want_phased: bool, current: dict | None
) -> dict[str, Any]:
    """Build dry-run / execute plan for phased vs regular release."""
    state = (current or {}).get("attributes", {}).get("phasedReleaseState")
    rid = (current or {}).get("id")
    mode = "phased" if want_phased else "regular"

    if want_phased:
        if current is None:
            return {
                "mode": mode,
                "action": "create",
                "current_state": None,
                "current_id": None,
                "note": (
                    "Will create appStoreVersionPhasedRelease (INACTIVE until "
                    "the update goes live; Apple's fixed 7-day 1→100% ramp). "
                    "Only valid for version updates, not the first public version."
                ),
            }
        if state in PHASED_OK_STATES:
            return {
                "mode": mode,
                "action": "noop",
                "current_state": state,
                "current_id": rid,
                "note": f"Phased release already {state} — leave as-is (idempotent).",
            }
        return {
            "mode": mode,
            "action": "noop",
            "current_state": state,
            "current_id": rid,
            "note": (
                f"Phased release already exists (state={state}). "
                "Pause / resume / Release to All stay in ASC UI — not automated."
            ),
        }

    # Regular / --no-phased (default)
    if current is None:
        return {
            "mode": mode,
            "action": "none",
            "current_state": None,
            "current_id": None,
            "note": "Regular (immediate) release — no phased release resource.",
        }
    if state == "INACTIVE":
        return {
            "mode": mode,
            "action": "delete",
            "current_state": state,
            "current_id": rid,
            "note": (
                "Will DELETE planned (INACTIVE) phased release so this update "
                "ships as a regular/immediate release."
            ),
        }
    return {
        "mode": mode,
        "action": "noop",
        "current_state": state,
        "current_id": rid,
        "note": (
            f"Phased release already started (state={state}); not deleting. "
            "Pause or Release to All in App Store Connect UI."
        ),
    }


def apply_phased_release(
    client: ASCClient, version_id: str, phased_plan: dict[str, Any]
) -> dict[str, Any]:
    """Create or delete phased release per plan. Pause/complete are ASC UI only."""
    action = phased_plan["action"]
    if action in ("none", "noop"):
        return {"applied": action, "id": phased_plan.get("current_id"), "state": phased_plan.get("current_state")}

    if action == "create":
        try:
            created = client.request(
                "POST",
                "/v1/appStoreVersionPhasedReleases",
                {
                    "data": {
                        "type": "appStoreVersionPhasedReleases",
                        "relationships": {
                            "appStoreVersion": {
                                "data": {
                                    "type": "appStoreVersions",
                                    "id": version_id,
                                }
                            }
                        },
                    }
                },
            )
        except RuntimeError as e:
            msg = str(e)
            raise PhasedReleaseError(
                "Apple refused creating a phased release. Phased Release applies "
                "only to version *updates* (not the first public version). "
                "Use a regular release (omit --phased / pass --no-phased), or "
                f"fix in ASC. Underlying error: {msg}"
            ) from e
        data = created.get("data") or {}
        return {
            "applied": "create",
            "id": data.get("id"),
            "state": (data.get("attributes") or {}).get("phasedReleaseState"),
        }

    if action == "delete":
        rid = phased_plan.get("current_id")
        if not rid:
            raise PhasedReleaseError("Plan says delete but no phased release id")
        if phased_plan.get("current_state") != "INACTIVE":
            raise PhasedReleaseError(
                f"Refusing to delete phased release in state "
                f"{phased_plan.get('current_state')} (only INACTIVE is safe)"
            )
        client.request("DELETE", f"/v1/appStoreVersionPhasedReleases/{rid}")
        return {"applied": "delete", "id": rid, "state": None}

    raise PhasedReleaseError(f"Unknown phased_release action: {action}")


def plan(app_key: str, client: ASCClient, want_phased: bool) -> dict[str, Any]:
    meta = APPS[app_key]
    app_id = meta["asc_app_id"]
    version = get_editable_version(client, app_id)
    attrs = version.get("attributes", {})
    open_sub = find_open_submission(client, app_id)
    current_phased = get_phased_release(client, version["id"])
    return {
        "app_key": app_key,
        "asc_app_id": app_id,
        "platform": meta["platform"],
        "version_id": version["id"],
        "version_string": attrs.get("versionString"),
        "app_store_state": attrs.get("appStoreState"),
        "submittable": attrs.get("appStoreState") in SUBMITTABLE,
        "open_submission_id": (open_sub or {}).get("id"),
        "open_submission_state": (open_sub or {}).get("attributes", {}).get("state"),
        "phased_release": plan_phased_release(want_phased, current_phased),
    }


def execute_submit(client: ASCClient, info: dict[str, Any]) -> dict[str, Any]:
    if not info["submittable"]:
        raise RuntimeError(
            f"Version {info['version_string']} is {info['app_store_state']} — "
            f"expected one of {sorted(SUBMITTABLE)}"
        )
    if info.get("open_submission_id"):
        raise RuntimeError(
            f"Open reviewSubmission already exists ({info['open_submission_id']} "
            f"state={info.get('open_submission_state')}). Resolve/cancel in ASC first."
        )

    # Phased create/delete while the version is still editable, before submit.
    phased_result = apply_phased_release(
        client, info["version_id"], info["phased_release"]
    )

    created = client.request(
        "POST",
        "/v1/reviewSubmissions",
        {
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": info["platform"]},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": info["asc_app_id"]}},
                },
            }
        },
    )
    submission_id = created["data"]["id"]

    client.request(
        "POST",
        "/v1/reviewSubmissionItems",
        {
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {"type": "reviewSubmissions", "id": submission_id}
                    },
                    "appStoreVersion": {
                        "data": {
                            "type": "appStoreVersions",
                            "id": info["version_id"],
                        }
                    },
                },
            }
        },
    )

    submitted = client.request(
        "PATCH",
        f"/v1/reviewSubmissions/{submission_id}",
        {
            "data": {
                "type": "reviewSubmissions",
                "id": submission_id,
                "attributes": {"submitted": True},
            }
        },
    )
    return {
        "submission_id": submission_id,
        "state": submitted.get("data", {}).get("attributes", {}).get("state"),
        "phased_release": phased_result,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Optional ASC Submit for Review (dry-run by default)."
    )
    parser.add_argument(
        "app",
        choices=sorted(APPS),
        help="App key (velour|corvim|juicd)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Read ASC state and print the plan (default if --execute omitted)",
    )
    mode.add_argument(
        "--execute",
        action="store_true",
        help="Create reviewSubmission + items and set submitted=true",
    )
    phased = parser.add_mutually_exclusive_group()
    phased.add_argument(
        "--phased",
        action="store_true",
        help=(
            "Phased Release for Automatic Updates (ASC appStoreVersionPhasedReleases; "
            "version updates only)"
        ),
    )
    phased.add_argument(
        "--no-phased",
        action="store_true",
        help="Regular/immediate release (default). Cancel planned INACTIVE phased release if present",
    )
    args = parser.parse_args()
    dry = not args.execute
    want_phased = bool(args.phased)  # default regular when neither flag set

    key_id, issuer_id, key_path = load_asc_config()
    client = ASCClient(key_id, issuer_id, key_path)
    info = plan(args.app, client, want_phased)
    print(json.dumps({"mode": "dry-run" if dry else "execute", "plan": info}, indent=2))

    if dry:
        print(
            "\nDry-run only — no submission created. "
            "Re-run with --execute (via `pilot appstore-submit … --confirm`) to submit.",
            file=sys.stderr,
        )
        return 0

    # Extra belt: require env confirmation for execute path.
    if os.environ.get("PILOT_ALLOW_APPSTORE_SUBMIT") != "1":
        sys.exit(
            "Refusing --execute: set PILOT_ALLOW_APPSTORE_SUBMIT=1 in the environment "
            "(LaunchPilot bash wrapper sets this only after --confirm)."
        )

    try:
        result = execute_submit(client, info)
    except PhasedReleaseError as e:
        print(json.dumps({"error": "phased_release", "detail": str(e)}, indent=2))
        print(f"\nPhasedReleaseError: {e}", file=sys.stderr)
        return 1
    print(json.dumps({"submitted": result}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
