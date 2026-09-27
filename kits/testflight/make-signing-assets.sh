#!/usr/bin/env bash
# Create an Apple **Distribution** certificate + App Store provisioning profiles
# via the App Store Connect API, and install them locally so command-line
# TestFlight uploads work WITHOUT Xcode cloud-managed signing.
#
# Why this exists:
#   This Apple account's API key has the "App Manager" role. Apple FORBIDS
#   App Manager keys from using *cloud-managed* distribution certificates
#   ("You haven't been given access to cloud-managed distribution
#   certificates"). But App Manager CAN create a regular distribution
#   certificate from a CSR and create profiles. So we do manual signing.
#
# Run once per Mac (or when the cert expires / is revoked):
#   ./make-signing-assets.sh
#
# Then archive-and-upload.sh uses signingStyle=manual with these assets.
#
# Requirements: config.sh filled in; python3 with pyjwt + cryptography
#   pip3 install pyjwt cryptography

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_config

WORK="$HOME/.appstoreconnect"
KEYDIR="$WORK/private_keys"
CSR="$WORK/dist.csr"
PRIVKEY="$WORK/dist_key.pem"
CERT_PEM="$WORK/dist.pem"
CERT_DER="$WORK/dist.cer"
P12="$WORK/dist.p12"
mkdir -p "$KEYDIR"

log "Generating local private key + CSR…"
[[ -f "$PRIVKEY" ]] || openssl genrsa -out "$PRIVKEY" 2048 2>/dev/null
openssl req -new -key "$PRIVKEY" -out "$CSR" \
  -subj "/CN=Distribution/O=Developer/C=US" 2>/dev/null

log "Creating Apple Distribution certificate via App Store Connect API…"
PROFILE_NAMES="Velour AppStore:com.velour.VelourCloset Juicd AppStore:com.jefferson258.juicd Corvim AppStore:com.corvim.Corvim"
python3 - "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$ASC_KEY_PATH" "$CSR" "$CERT_DER" "$TEAM_ID" "$PROFILE_NAMES" <<'PY'
import sys, time, json, http.client, base64, os
import jwt
key_id, issuer_id, key_path, csr_path, cer_out, team_id, profmap = sys.argv[1:8]
def tok():
    return jwt.encode({"iss":issuer_id,"iat":int(time.time()),"exp":int(time.time())+1200,"aud":"appstoreconnect-v1"},
                      open(key_path).read(), algorithm="ES256", headers={"kid":key_id,"typ":"JWT"})
def api(method,path,body=None):
    c=http.client.HTTPSConnection("api.appstoreconnect.apple.com")
    h={"Authorization":f"Bearer {tok()}","Content-Type":"application/json"}
    c.request(method,path,body=json.dumps(body) if body else None,headers=h)
    r=c.getresponse(); return r.status, r.read().decode()

# Reuse an existing DISTRIBUTION cert if present, else create one.
st,b=api("GET","/v1/certificates?limit=200")
cert_id=None
for c in json.loads(b).get("data",[]):
    if c["attributes"].get("certificateType")=="DISTRIBUTION":
        cert_id=c["id"]; break
if cert_id:
    print("Reusing distribution cert", cert_id)
    st,b=api("GET",f"/v1/certificates/{cert_id}")
    content=json.loads(b)["data"]["attributes"]["certificateContent"]
else:
    csr=open(csr_path).read()
    payload={"data":{"type":"certificates","attributes":{"certificateType":"IOS_DISTRIBUTION","csrContent":csr}}}
    st,b=api("POST","/v1/certificates",payload)
    if st not in (200,201): sys.exit(f"cert create failed {st}: {b[:400]}")
    d=json.loads(b)["data"]; cert_id=d["id"]; content=d["attributes"]["certificateContent"]
    print("Created distribution cert", cert_id)
open(cer_out,"wb").write(base64.b64decode(content))

# Map bundle identifiers -> portal bundleId resource IDs
st,b=api("GET","/v1/bundleIds?limit=200")
bundles={x["attributes"]["identifier"]:x["id"] for x in json.loads(b)["data"]}
profdir=os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
os.makedirs(profdir,exist_ok=True)
for pair in profmap.split():
    name,ident = pair.split(":")
    name=name.replace("_"," ")
    bid=bundles.get(ident)
    if not bid:
        print("  ! missing bundleId in portal:",ident); continue
    # delete existing profile with same name to avoid duplicates
    st,b=api("GET","/v1/profiles?limit=200")
    for p in json.loads(b).get("data",[]):
        if p["attributes"]["name"]==name:
            api("DELETE",f"/v1/profiles/{p['id']}")
    payload={"data":{"type":"profiles","attributes":{"name":name,"profileType":"IOS_APP_STORE"},
      "relationships":{"bundleId":{"data":{"type":"bundleIds","id":bid}},
      "certificates":{"data":[{"type":"certificates","id":cert_id}]}}}}
    st,b=api("POST","/v1/profiles",payload)
    if st not in (200,201): print("  ! profile failed",ident,st,b[:200]); continue
    d=json.loads(b)["data"]; uuid=d["attributes"]["uuid"]
    open(os.path.join(profdir,f"{uuid}.mobileprovision"),"wb").write(base64.b64decode(d["attributes"]["profileContent"]))
    print(f"  installed profile '{name}' ({uuid}) for {ident}")
PY

log "Converting + importing distribution certificate into login keychain…"
openssl x509 -inform DER -in "$CERT_DER" -out "$CERT_PEM" 2>/dev/null
# -legacy so macOS Security can read the PKCS#12 (OpenSSL 3 default is unreadable)
openssl pkcs12 -export -legacy -inkey "$PRIVKEY" -in "$CERT_PEM" -out "$P12" \
  -passout pass:assetpass -name "Apple Distribution" 2>/dev/null
security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P "assetpass" -T /usr/bin/codesign -T /usr/bin/xcodebuild 2>&1 | tail -2 || true

log "Signing assets ready. Identities:"
security find-identity -v -p codesigning | grep -i distribution || true
echo
echo "Now run: ./archive-and-upload.sh <velour|juicd|corvim>"
