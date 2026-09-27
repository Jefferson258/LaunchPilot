#!/usr/bin/env bash
# Quick sanity check that your App Store Connect API key works, WITHOUT
# building anything. Lists apps visible to the key. Run this right after you
# fill in config.sh to confirm the credentials are correct.
#
#   ./verify-key.sh

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_config

log "Validating API key by querying App Store Connect…"
# Generate a short-lived JWT and call the apps endpoint.
python3 - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH" <<'PY'
import sys, time, json, http.client
try:
    import jwt  # PyJWT
except ImportError:
    sys.exit("PyJWT not installed. Run: pip3 install pyjwt cryptography\n"
             "(Or just skip this check and run archive-and-upload.sh directly.)")

key_id, issuer_id, key_path = sys.argv[1:4]
with open(key_path) as f:
    private_key = f.read()

token = jwt.encode(
    {"iss": issuer_id, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
)

conn = http.client.HTTPSConnection("api.appstoreconnect.apple.com")
conn.request("GET", "/v1/apps?limit=200", headers={"Authorization": f"Bearer {token}"})
resp = conn.getresponse()
body = resp.read().decode()
if resp.status != 200:
    sys.exit(f"API call failed ({resp.status}): {body}")

data = json.loads(body)
apps = data.get("data", [])
print(f"\nKey works. {len(apps)} app(s) visible to this key:")
for a in apps:
    attr = a.get("attributes", {})
    print(f"  - {attr.get('name','?')}  [{attr.get('bundleId','?')}]")
print("\nIf Juicd / Velour are NOT listed, create their app records in")
print("App Store Connect first (see README.md, step 3).")
PY
