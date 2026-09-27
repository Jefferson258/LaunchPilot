#!/usr/bin/env python3
"""Push AppStoreSubmission metadata (+ screenshots) to App Store Connect."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
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

ROOT = Path(__file__).resolve().parent  # kits/appstore
KIT_DIR = ROOT.parent / "testflight"  # kits/testflight (ASC JWT via config.sh)
API = "https://api.appstoreconnect.apple.com"

# Product listing assets live under kits/appstore/products/<key>/ (screenshots gitignored).
# Copy products.example layout or your own folders; see docs/SETUP.md.
APPS = {
    "velour": {
        "asc_app_id": "6785327329",
        "dir": ROOT / "products" / "velour",
        "screenshot_type": "APP_IPAD_PRO_3GEN_129",
        "primary_category": "LIFESTYLE",
        "secondary_category": "PHOTO_AND_VIDEO",
    },
    "corvim": {
        "asc_app_id": "6760210188",
        "dir": ROOT / "products" / "corvim",
        "screenshot_type": "APP_IPHONE_67",
        "primary_category": "HEALTH_AND_FITNESS",
        "secondary_category": "SOCIAL_NETWORKING",
    },
    "juicd": {
        "asc_app_id": "6785327494",
        "dir": ROOT / "products" / "juicd",
        "screenshot_type": "APP_IPHONE_67",
        "primary_category": "SPORTS",
        "secondary_category": "ENTERTAINMENT",
    },
}


def load_asc_config() -> tuple[str, str, str]:
    config = KIT_DIR / "config.sh"
    if not config.is_file():
        sys.exit(f"Missing {config}")
    env = os.environ.copy()
    out = subprocess.check_output(
        ["bash", "-lc", f"source '{config}' && printf '%s\\n' \"$ASC_KEY_ID\" \"$ASC_ISSUER_ID\" \"$ASC_KEY_PATH\""],
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

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
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
            raise RuntimeError(f"{method} {path} failed ({e.code}): {raw}") from e
        return json.loads(raw) if raw else {}

    def upload_bytes(self, upload_url: str, content: bytes, content_type: str) -> None:
        req = urlrequest.Request(
            upload_url,
            data=content,
            method="PUT",
            headers={"Content-Type": content_type},
        )
        try:
            with urlrequest.urlopen(req) as resp:
                if resp.status >= 400:
                    raise RuntimeError(f"Upload failed ({resp.status})")
        except urlrequest.HTTPError as e:
            raise RuntimeError(f"Upload failed ({e.code}): {e.read().decode()}") from e


def parse_metadata(md_path: Path) -> dict[str, str]:
    text = md_path.read_text()
    fields: dict[str, str] = {}

    def grab(label: str) -> str | None:
        m = re.search(
            rf"\|\s*\*\*{re.escape(label)}\*\*(?:\s*\([^)]*\))?\s*\|\s*([^|]+?)\s*\|",
            text,
        )
        return m.group(1).strip() if m else None

    for label, key in [
        ("Subtitle", "subtitle"),
        ("Support URL", "support_url"),
        ("Marketing URL", "marketing_url"),
        ("Privacy Policy URL", "privacy_policy_url"),
        ("Copyright", "copyright"),
    ]:
        val = grab(label)
        if val:
            fields[key] = val

    promo = re.search(r"## Promotional text.*?\n\n(.+?)\n\n---", text, re.S)
    if promo:
        fields["promotional_text"] = promo.group(1).strip()

    desc = re.search(r"## Description\n\n(.+?)\n\n---", text, re.S)
    if desc:
        fields["description"] = desc.group(1).strip()

    kw = re.search(r"## Keywords.*?\n\n```\n(.+?)\n```", text, re.S)
    if kw:
        fields["keywords"] = kw.group(1).strip()

    notes = re.search(r"## Notes for Review\n\n```\n(.+?)\n```", text, re.S)
    if notes:
        fields["review_notes"] = notes.group(1).strip()

    return fields


def first(data: dict, default: Any = None) -> Any:
    items = data.get("data", [])
    return items[0] if items else default


def get_editable_version(client: ASCClient, app_id: str) -> dict:
    data = client.request(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20",
    )
    versions = data.get("data", [])
    preferred = [
        v
        for v in versions
        if v["attributes"].get("appStoreState")
        in {
            "PREPARE_FOR_SUBMISSION",
            "DEVELOPER_REJECTED",
            "REJECTED",
            "METADATA_REJECTED",
            "WAITING_FOR_REVIEW",
            "IN_REVIEW",
        }
    ]
    if preferred:
        return preferred[0]
    editable = [v for v in versions if v["attributes"].get("appStoreState") != "READY_FOR_SALE"]
    if editable:
        return editable[0]
    if versions:
        return versions[0]
    raise RuntimeError(f"No app store version found for app {app_id}")


def get_localization(client: ASCClient, version_id: str, locale: str = "en-US") -> dict:
    data = client.request(
        "GET",
        f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?filter[locale]={locale}&limit=1",
    )
    loc = first(data)
    if not loc:
        raise RuntimeError(f"No {locale} localization for version {version_id}")
    return loc


def get_app_info_localization(client: ASCClient, app_id: str, locale: str = "en-US") -> tuple[dict, dict]:
    app_infos = client.request("GET", f"/v1/apps/{app_id}/appInfos?limit=1")
    app_info = first(app_infos)
    if not app_info:
        raise RuntimeError(f"No appInfo for app {app_id}")
    locs = client.request(
        "GET",
        f"/v1/appInfos/{app_info['id']}/appInfoLocalizations?filter[locale]={locale}&limit=1",
    )
    loc = first(locs)
    if not loc:
        raise RuntimeError(f"No appInfo localization for app {app_id}")
    return app_info, loc


def ensure_review_detail(client: ASCClient, version_id: str) -> dict | None:
    try:
        data = client.request("GET", f"/v1/appStoreVersions/{version_id}/appStoreReviewDetail")
    except RuntimeError as e:
        if "404" not in str(e):
            raise
        data = {"data": None}
    detail = data.get("data")
    if detail:
        return detail
    try:
        created = client.request(
            "POST",
            "/v1/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": {
                        "contactFirstName": "Thomas",
                        "contactLastName": "Kade",
                        "contactPhone": "+10000000000",
                    },
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            },
        )
        return created["data"]
    except RuntimeError:
        return None


def ensure_screenshot_set(client: ASCClient, loc_id: str, display_type: str) -> dict:
    data = client.request(
        "GET",
        f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?filter[screenshotDisplayType]={display_type}&limit=1",
    )
    ss = first(data)
    if ss:
        return ss
    created = client.request(
        "POST",
        "/v1/appScreenshotSets",
        {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                    }
                },
            }
        },
    )
    return created["data"]


def delete_existing_screenshots(client: ASCClient, set_id: str) -> None:
    data = client.request("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=20")
    for shot in data.get("data", []):
        client.request("DELETE", f"/v1/appScreenshots/{shot['id']}")


def screenshot_bytes(path: Path, display_type: str) -> tuple[bytes, str]:
    targets = {
        "APP_IPAD_PRO_3GEN_129": (2064, 2752),
        "APP_IPHONE_67": (1290, 2796),
    }
    target = targets.get(display_type)
    if not target:
        return path.read_bytes(), path.name

    try:
        from PIL import Image
    except ImportError:
        return path.read_bytes(), path.name

    with Image.open(path) as im:
        if im.size != target:
            im = im.resize(target, Image.Resampling.LANCZOS)
        from io import BytesIO

        buf = BytesIO()
        im.save(buf, format="PNG", optimize=True, compress_level=9)
        return buf.getvalue(), path.name


def upload_screenshot(client: ASCClient, set_id: str, path: Path, display_type: str) -> None:
    content, file_name = screenshot_bytes(path, display_type)
    size = len(content)
    content_type = mimetypes.guess_type(file_name)[0] or "image/png"
    reserved = client.request(
        "POST",
        "/v1/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {
                    "fileName": file_name,
                    "fileSize": size,
                },
                "relationships": {
                    "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                },
            }
        },
    )
    shot_id = reserved["data"]["id"]
    ops = reserved["data"]["attributes"].get("uploadOperations", [])
    if not ops:
        raise RuntimeError(f"No upload operations for {file_name}")
    op = ops[0]
    upload_type = content_type
    for header in op.get("requestHeaders", []):
        if header.get("name", "").lower() == "content-type":
            upload_type = header["value"]
    client.upload_bytes(op["url"], content, upload_type)
    for attempt in range(5):
        try:
            client.request(
                "PATCH",
                f"/v1/appScreenshots/{shot_id}",
                {
                    "data": {
                        "type": "appScreenshots",
                        "id": shot_id,
                        "attributes": {"uploaded": True},
                    }
                },
            )
            break
        except RuntimeError as e:
            if "500" not in str(e) or attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))
    for _ in range(60):
        detail = client.request("GET", f"/v1/appScreenshots/{shot_id}")
        state = detail["data"]["attributes"].get("assetDeliveryState", {}).get("state")
        if state == "COMPLETE":
            return
        if state == "FAILED":
            errors = detail["data"]["attributes"].get("assetDeliveryState", {}).get("errors", [])
            raise RuntimeError(f"Screenshot upload failed for {file_name}: {errors}")
        time.sleep(2)
    raise RuntimeError(f"Timed out waiting for screenshot upload: {file_name}")


def push_app(
    client: ASCClient,
    app_key: str,
    *,
    screenshots: bool,
    force_screenshots: bool = False,
) -> None:
    cfg = APPS[app_key]
    meta = parse_metadata(cfg["dir"] / "metadata.md")
    app_id = cfg["asc_app_id"]
    print(f"\n==> {app_key} (ASC {app_id})")

    version = get_editable_version(client, app_id)
    version_id = version["id"]
    state = version["attributes"].get("appStoreState")
    print(f"  version {version['attributes'].get('versionString')} state={state}")

    version_attrs: dict[str, str] = {}
    if meta.get("copyright"):
        version_attrs["copyright"] = meta["copyright"]
    if version_attrs:
        client.request(
            "PATCH",
            f"/v1/appStoreVersions/{version_id}",
            {"data": {"type": "appStoreVersions", "id": version_id, "attributes": version_attrs}},
        )

    app_info, app_info_loc = get_app_info_localization(client, app_id)
    info_loc_attrs = {}
    if meta.get("subtitle"):
        info_loc_attrs["subtitle"] = meta["subtitle"][:30]
    if meta.get("privacy_policy_url"):
        info_loc_attrs["privacyPolicyUrl"] = meta["privacy_policy_url"]
    if info_loc_attrs:
        client.request(
            "PATCH",
            f"/v1/appInfoLocalizations/{app_info_loc['id']}",
            {
                "data": {
                    "type": "appInfoLocalizations",
                    "id": app_info_loc["id"],
                    "attributes": info_loc_attrs,
                }
            },
        )

    loc = get_localization(client, version_id)
    loc_attrs: dict[str, str] = {}
    for src, dst in [
        ("description", "description"),
        ("keywords", "keywords"),
        ("promotional_text", "promotionalText"),
        ("support_url", "supportUrl"),
        ("marketing_url", "marketingUrl"),
    ]:
        if meta.get(src):
            loc_attrs[dst] = meta[src]
    if loc_attrs:
        client.request(
            "PATCH",
            f"/v1/appStoreVersionLocalizations/{loc['id']}",
            {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc["id"],
                    "attributes": loc_attrs,
                }
            },
        )

    if meta.get("review_notes"):
        detail = ensure_review_detail(client, version_id)
        if detail:
            client.request(
                "PATCH",
                f"/v1/appStoreReviewDetails/{detail['id']}",
                {
                    "data": {
                        "type": "appStoreReviewDetails",
                        "id": detail["id"],
                        "attributes": {"notes": meta["review_notes"]},
                    }
                },
            )
        else:
            print("  skipped review notes (no appStoreReviewDetail yet)")

    if screenshots:
        shots_dir = cfg["dir"] / "screenshots"
        files = sorted(shots_dir.glob("*.png"))
        if not files:
            print(f"  no screenshots in {shots_dir}")
        else:
            ss_set = ensure_screenshot_set(client, loc["id"], cfg["screenshot_type"])
            data = client.request("GET", f"/v1/appScreenshotSets/{ss_set['id']}/appScreenshots?limit=20")
            if force_screenshots:
                for shot in data.get("data", []):
                    print(f"  delete {shot['attributes'].get('fileName')}")
                    client.request("DELETE", f"/v1/appScreenshots/{shot['id']}")
                completed = set()
            else:
                completed = {
                    s["attributes"].get("fileName")
                    for s in data.get("data", [])
                    if s["attributes"].get("assetDeliveryState", {}).get("state") == "COMPLETE"
                }
                for shot in data.get("data", []):
                    state = shot["attributes"].get("assetDeliveryState", {}).get("state")
                    if state != "COMPLETE":
                        client.request("DELETE", f"/v1/appScreenshots/{shot['id']}")
            for path in files:
                if path.name in completed:
                    print(f"  skip {path.name} (already uploaded)")
                    continue
                print(f"  upload {path.name}")
                upload_screenshot(client, ss_set["id"], path, cfg["screenshot_type"])

    print(f"  done — preview in ASC Distribution for app {app_id}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Push AppStoreSubmission metadata to ASC")
    parser.add_argument("apps", nargs="*", choices=[*APPS, "all"], default=["all"])
    parser.add_argument("--no-screenshots", action="store_true")
    parser.add_argument(
        "--force-screenshots",
        action="store_true",
        help="Delete existing ASC screenshots and re-upload from disk",
    )
    args = parser.parse_args()
    apps = list(APPS) if "all" in args.apps or not args.apps else args.apps

    key_id, issuer_id, key_path = load_asc_config()
    client = ASCClient(key_id, issuer_id, key_path)

    for app_key in apps:
        push_app(
            client,
            app_key,
            screenshots=not args.no_screenshots,
            force_screenshots=args.force_screenshots,
        )


if __name__ == "__main__":
    main()
