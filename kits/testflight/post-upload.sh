#!/usr/bin/env bash
# After a TestFlight upload: wait for processing, verify export compliance metadata,
# attach the build to Internal Testers (every internal group) plus the configured
# external group, and turn on hasAccessToAllBuilds so later uploads show up too.
#
#   ./post-upload.sh velour [build-number]
#
# Requires ASC_APP_ID + BETA_GROUP_ID in lib.sh resolve_app().

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
resolve_app "${1:?Usage: ./post-upload.sh <juicd|velour|corvim> [build-number]}"
EXPECTED_BUILD="${2:-}"
load_config

log "Post-upload: $APP_DISPLAY (internal testers + beta group, verify compliance metadata)"
if [[ -n "$EXPECTED_BUILD" ]]; then
  log "Waiting for build $EXPECTED_BUILD to finish processing"
fi

python3 - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH" "$ASC_APP_ID" "$BETA_GROUP_ID" "$APP_DISPLAY" "$EXPECTED_BUILD" <<'PY'
import sys, time, json, http.client
try:
    import jwt
except ImportError:
    sys.exit("PyJWT required: pip3 install pyjwt cryptography")

key_id, issuer_id, key_path, app_id, group_id, name, expected_build = sys.argv[1:8]
expected_build = expected_build or None
with open(key_path) as f:
    private_key = f.read()

def token():
    return jwt.encode(
        {"iss": issuer_id, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )

def request(method, path, body=None):
    conn = http.client.HTTPSConnection("api.appstoreconnect.apple.com")
    headers = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}
    conn.request(method, path, body=body, headers=headers)
    resp = conn.getresponse()
    raw = resp.read().decode()
    if resp.status >= 400:
        raise RuntimeError(f"{method} {path} failed ({resp.status}): {raw}")
    return json.loads(raw) if raw else {}

def latest_build():
    data = request("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=10")
    builds = data.get("data", [])
    if not builds:
        raise RuntimeError("No builds found for app")
    if expected_build:
        for b in builds:
            if b["attributes"].get("version") == expected_build:
                return b
        # New upload may not be indexed yet — fall back to highest version.
    builds.sort(key=lambda b: int(b["attributes"].get("version", "0")), reverse=True)
    return builds[0]

# Poll until the target build finishes processing (up to ~20 min).
build = None
for attempt in range(40):
    build = latest_build()
    state = build["attributes"].get("processingState", "")
    ver = build["attributes"].get("version")
    enc = build["attributes"].get("usesNonExemptEncryption")
    print(f"  build {ver} processingState={state} usesNonExemptEncryption={enc}")
    if state == "VALID":
        if expected_build and ver != expected_build:
            print(f"  still waiting for build {expected_build} (latest indexed: {ver})")
            time.sleep(30)
            continue
        break
    if state == "FAILED":
        raise RuntimeError("Build processing failed on Apple's side")
    time.sleep(30)
else:
    raise RuntimeError("Timed out waiting for build to become VALID")

if build["attributes"].get("usesNonExemptEncryption") is not False:
    print("WARNING: usesNonExemptEncryption is not false — check Info.plist ITSAppUsesNonExemptEncryption")

# Internal Testers is a separate group from the public-link "Beta Testers"
# group. Attach this build to every internal group, and try to turn on
# hasAccessToAllBuilds so future uploads appear without another attach.
bid = build["id"]
payload = json.dumps({"data": [{"type": "builds", "id": bid}]})
group_ids = []
group_names = {}
if group_id:
    group_ids.append(group_id)
groups = request("GET", f"/v1/apps/{app_id}/betaGroups?limit=200")
for g in groups.get("data", []):
    gid = g.get("id")
    attrs = g.get("attributes") or {}
    gname = attrs.get("name") or gid
    internal = bool(attrs.get("isInternalGroup"))
    all_builds = attrs.get("hasAccessToAllBuilds")
    print(f"  group {gname!r} id={gid} internal={internal} hasAccessToAllBuilds={all_builds}")
    if not gid:
        continue
    group_names[gid] = gname
    # Groups with hasAccessToAllBuilds already see every upload; Apple 422s
    # if we try to assign a build to them. Juicd's Internal Testers does not
    # allow flipping that flag, so those still need a per-build attach.
    if internal and all_builds is True:
        print(f"  {gname!r} already receives every build")
    elif gid not in group_ids:
        group_ids.append(gid)
    if internal and all_builds is not True:
        patch = json.dumps({
            "data": {
                "type": "betaGroups",
                "id": gid,
                "attributes": {"hasAccessToAllBuilds": True},
            }
        })
        try:
            request("PATCH", f"/v1/betaGroups/{gid}", patch)
            print(f"  enabled hasAccessToAllBuilds on {gname!r}")
        except RuntimeError as e:
            print(f"  could not enable hasAccessToAllBuilds on {gname!r} (will still attach this build): {e}")

for gid in group_ids:
    label = group_names.get(gid, gid)
    try:
        request("POST", f"/v1/betaGroups/{gid}/relationships/builds", payload)
        print(f"Added {name} build {build['attributes'].get('version')} to {label} ({gid})")
    except RuntimeError as e:
        if (
            "409" in str(e)
            or "already" in str(e).lower()
            or "Cannot add internal group to a build" in str(e)
        ):
            print(f"Build already in {label} ({gid}) (ok)")
        else:
            raise

detail = request("GET", f"/v1/builds/{bid}/buildBetaDetail")
attrs = detail.get("data", {}).get("attributes", {})
print(f"  internalBuildState={attrs.get('internalBuildState')}")
print(f"  externalBuildState={attrs.get('externalBuildState')}")
PY

log "$APP_DISPLAY post-upload complete"
