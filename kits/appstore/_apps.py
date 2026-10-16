"""Shared config loading for the App Store kit.

Per-app values live in a gitignored local file, never in code:

  kits/appstore/apps.local.json   (template: apps.example.json)
  override path with APPSTORE_APPS_FILE

ASC credentials come from the TestFlight kit's local config
(kits/testflight/config.local.sh or config.sh). If an app entry has no
"asc_app_id", it is read from the TestFlight app registry (ASC_APP_ID).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent  # kits/appstore
TF_KIT = ROOT.parent / "testflight"
APPS_FILE = Path(os.environ.get("APPSTORE_APPS_FILE") or ROOT / "apps.local.json")
EXAMPLE_FILE = ROOT / "apps.example.json"


def _bash_tf(snippet: str) -> list[str]:
    cmd = f"source '{TF_KIT / 'lib.sh'}' >/dev/null && {snippet}"
    out = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or f"bash exited {out.returncode}")
    return out.stdout.strip().splitlines()


def tf_asc_app_id(key: str) -> str:
    try:
        lines = _bash_tf(f"resolve_app '{key}' >/dev/null && printf '%s\\n' \"${{ASC_APP_ID:-}}\"")
    except RuntimeError:
        return ""
    return lines[-1] if lines else ""


def load_raw() -> dict[str, Any]:
    if not APPS_FILE.is_file():
        sys.exit(
            f"Missing {APPS_FILE}.\n"
            f"Copy {EXAMPLE_FILE.name} to {APPS_FILE.name} and fill in your apps (see kits/appstore/README.md)."
        )
    return json.loads(APPS_FILE.read_text())


def load_apps() -> dict[str, dict[str, Any]]:
    """Return {app_key: cfg}. Keys match tf_key in config/products.json."""
    raw = load_raw()
    defaults = raw.get("defaults", {})
    apps: dict[str, dict[str, Any]] = {}
    for key, entry in (raw.get("apps") or {}).items():
        cfg = {**defaults, **entry}
        d = Path(cfg.get("dir") or (ROOT / "products" / key))
        cfg["dir"] = d if d.is_absolute() else (ROOT / d)
        cfg.setdefault("platform", "IOS")
        if not cfg.get("asc_app_id"):
            cfg["asc_app_id"] = tf_asc_app_id(key)
        apps[key] = cfg
    if not apps:
        sys.exit(f"{APPS_FILE} has no entries under \"apps\".")
    return apps


def require_asc_app_id(key: str, cfg: dict[str, Any]) -> str:
    app_id = str(cfg.get("asc_app_id") or "")
    if not app_id:
        sys.exit(
            f"No ASC app id for '{key}': set asc_app_id in {APPS_FILE.name} "
            "or ASC_APP_ID in the TestFlight app registry."
        )
    return app_id


def load_asc_config() -> tuple[str, str, str]:
    try:
        out = _bash_tf(
            "load_config >/dev/null && printf '%s\\n' \"$ASC_KEY_ID\" \"$ASC_ISSUER_ID\" \"$ASC_KEY_PATH\""
        )
    except RuntimeError as e:
        sys.exit(f"Could not read ASC config from kits/testflight local config: {e}")
    if len(out) < 3:
        sys.exit("Could not read ASC config from kits/testflight local config")
    key_id, issuer_id, key_path = out[-3:]
    if not Path(key_path).is_file():
        sys.exit(f"ASC key not found: {key_path}")
    return key_id, issuer_id, key_path
