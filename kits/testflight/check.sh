#!/usr/bin/env bash
# Syntax-check the TestFlight kit and exercise lib.sh without App Store Connect.
#
#   ./kits/testflight/check.sh
#
# lib.sh is sourced, not executed. Callers and the functions they use:
#   archive-and-upload.sh   resolve_app tf_app_keys load_config tf_apps_file
#                           tf_config_file mask log
#   build-check.sh          resolve_app tf_app_keys log warn
#   bump-build.sh           resolve_app log
#   make-signing-assets.sh  resolve_app tf_app_keys load_config log err
#   post-upload.sh          resolve_app tf_app_keys load_config mask log
#   verify-key.sh           load_config log
#   kits/appstore/_apps.py  resolve_app load_config (bash -c 'source lib.sh')
# ok/err/warn/log are the shared logging helpers.
#
# This script never calls the App Store Connect API. Real uploads stay in
# post-upload.sh and only run when --dry-run is absent.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_PYTHON="$(command -v python3)"
TMP="$(mktemp -d)"
GUARD_LOG="$TMP/guard.log"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }

assert_has() {
  local hay="$1" needle="$2" label="$3"
  [[ "$hay" == *"$needle"* ]] || fail "$label: missing '$needle'"
}

assert_lacks() {
  local hay="$1" needle="$2" label="$3"
  [[ "$hay" != *"$needle"* ]] || fail "$label: unexpectedly contained '$needle'"
}

echo "== bash -n =="
shopt -s nullglob
found=0
for f in "$KIT_DIR"/*.sh; do
  bash -n "$f"
  printf '  %s\n' "$(basename "$f")"
  found=1
done
[[ "$found" == 1 ]] || fail "no shell scripts in $KIT_DIR"
[[ -f "$KIT_DIR/lib.sh" ]] || fail "kits/testflight/lib.sh is missing"

echo "== embedded python syntax =="
"$REAL_PYTHON" - "$KIT_DIR" <<'PY'
import ast, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
found = 0
for path in sorted(root.glob("*.sh")):
    blocks = re.findall(r"<<'PY'\n(.*)\nPY\n", path.read_text(), re.S)
    for i, block in enumerate(blocks, 1):
        ast.parse(block)
        print(f"  {path.name} python block {i}")
        found += 1
if found == 0:
    sys.exit("no embedded python blocks found")
PY

echo "== lib.sh function contract =="
# shellcheck disable=SC2016
bash --noprofile --norc -c '
set -euo pipefail
source "$1"
required="resolve_app tf_app_keys tf_apps_file tf_config_file load_config mask log ok warn err"
for fn in $required; do
  declare -F "$fn" >/dev/null || { echo "missing function: $fn" >&2; exit 1; }
  printf "  %s\n" "$fn"
done
' _ "$KIT_DIR/lib.sh"

# Fake credentials only. Not a real key, team, or app id.
printf '%s\n' "not-a-real-key" > "$TMP/fake.p8"
cat > "$TMP/config.sh" <<EOF
export TEAM_ID="TEAMID1234"
export ASC_KEY_ID="KEYID12345"
export ASC_ISSUER_ID="00000000-0000-0000-0000-000000000000"
export ASC_KEY_PATH="$TMP/fake.p8"
EOF
cp "$KIT_DIR/apps.example.sh" "$TMP/apps.sh"

mkdir -p "$TMP/bin"
for cmd in python3 python xcodebuild curl; do
  cat > "$TMP/bin/$cmd" <<EOF
#!/bin/sh
echo "BLOCKED $cmd \$*" >> "$GUARD_LOG"
exit 99
EOF
  chmod +x "$TMP/bin/$cmd"
done

run_kit() {
  PATH="$TMP/bin:$PATH" \
  TF_APPS_FILE="$TMP/apps.sh" \
  TF_CONFIG_FILE="$TMP/config.sh" \
  PILOT_WORKSPACE="$TMP/workspace" \
  "$@"
}

echo "== post-upload --dry-run =="
post_out="$(run_kit "$KIT_DIR/post-upload.sh" example 42 --dry-run)"
printf '%s\n' "$post_out"
assert_has "$post_out" "DRY RUN — post-upload plan for Example App (example)" "post-upload dry-run"
assert_has "$post_out" "build      : 42" "post-upload build"
assert_has "$post_out" "internal groups only" "post-upload default groups"
assert_has "$post_out" "set (10 chars)" "post-upload masked app id"
for secret in TEAMID1234 KEYID12345 00000000-0000-0000-0000-000000000000 0000000000 not-a-real-key; do
  assert_lacks "$post_out" "$secret" "post-upload dry-run"
done

echo "== TF_DRY_RUN=1 =="
env_out="$(TF_DRY_RUN=1 run_kit "$KIT_DIR/post-upload.sh" example)"
assert_has "$env_out" "DRY RUN" "TF_DRY_RUN"
assert_has "$env_out" "build      : latest" "TF_DRY_RUN latest build"

echo "== external group list =="
ext_out="$(TF_EXTERNAL_BETA_GROUP_IDS="g-one,g-two" run_kit "$KIT_DIR/post-upload.sh" example 9 --dry-run)"
assert_has "$ext_out" "internal groups + 2 configured external group(s)" "comma-separated external groups"
assert_lacks "$ext_out" "g-one" "external group ids stay out of the plan"
assert_lacks "$ext_out" "g-two" "external group ids stay out of the plan"

echo "== legacy BETA_GROUP_ID stays off unless opted in =="
cat > "$TMP/legacy-apps.sh" <<'EOF'
TF_APP_KEYS="example"
tf_resolve_app() {
  case "${1:-}" in
    example)
      APP_KEY="example"
      APP_DISPLAY="Example App"
      PROJECT="$DESKTOP/ExampleApp/ExampleApp.xcodeproj"
      SCHEME="ExampleApp"
      BUNDLE_ID="com.example.app"
      PROFILE_NAME="Example App AppStore"
      ASC_APP_ID="0000000000"
      BETA_GROUP_ID="legacy-group"
      EXTERNAL_BETA_GROUP_IDS=""
      SIM_DEST="generic/platform=iOS Simulator"
      ;;
    *)
      echo "ERROR: unknown app '${1:-}'" >&2
      return 1
      ;;
  esac
}
EOF
legacy_off="$(PATH="$TMP/bin:$PATH" TF_APPS_FILE="$TMP/legacy-apps.sh" TF_CONFIG_FILE="$TMP/config.sh" PILOT_WORKSPACE="$TMP/workspace" \
  "$KIT_DIR/post-upload.sh" example --dry-run)"
assert_has "$legacy_off" "internal groups only" "legacy group ignored by default"
legacy_on="$(PATH="$TMP/bin:$PATH" TF_APPS_FILE="$TMP/legacy-apps.sh" TF_CONFIG_FILE="$TMP/config.sh" PILOT_WORKSPACE="$TMP/workspace" TF_ATTACH_EXTERNAL=1 \
  "$KIT_DIR/post-upload.sh" example --dry-run)"
assert_has "$legacy_on" "internal groups + 1 configured external group(s)" "legacy group when opted in"
assert_lacks "$legacy_on" "legacy-group" "legacy group id not printed"

echo "== archive-and-upload --dry-run =="
arch_out="$(run_kit "$KIT_DIR/archive-and-upload.sh" example --dry-run)"
printf '%s\n' "$arch_out"
assert_has "$arch_out" "nothing will be archived or uploaded" "archive dry-run"
assert_has "$arch_out" "scheme     : ExampleApp" "archive scheme"
assert_has "$arch_out" ".p8 present" "archive key present"
for secret in TEAMID1234 KEYID12345 00000000-0000-0000-0000-000000000000 0000000000 not-a-real-key; do
  assert_lacks "$arch_out" "$secret" "archive dry-run"
done

echo "== resolve_app and load_config =="
# shellcheck disable=SC2016
bash --noprofile --norc -c '
set -euo pipefail
source "$1"
export TF_APPS_FILE="$2" TF_CONFIG_FILE="$3" PILOT_WORKSPACE="$4"
resolve_app example >/dev/null
test "$APP_KEY" = "example"
test "$APP_DISPLAY" = "Example App"
test "$SCHEME" = "ExampleApp"
test "$ASC_APP_ID" = "0000000000"
test "$PBXPROJ" = "$PROJECT/project.pbxproj"
test "$(tf_app_keys)" = "example"
load_config >/dev/null
test "$TEAM_ID" = "TEAMID1234"
test "$ASC_KEY_ID" = "KEYID12345"
test -f "$ASC_KEY_PATH"
' _ "$KIT_DIR/lib.sh" "$TMP/apps.sh" "$TMP/config.sh" "$TMP/workspace"

echo "== error paths =="
set +e
unknown="$(PATH="$TMP/bin:$PATH" TF_APPS_FILE="$TMP/apps.sh" TF_CONFIG_FILE="$TMP/config.sh" \
  "$KIT_DIR/post-upload.sh" not-an-app --dry-run 2>&1)"
unknown_rc=$?
set -e
[[ "$unknown_rc" -ne 0 ]] || fail "unknown app key should fail"
assert_has "$unknown" "unknown app" "unknown app error"

printf '%s\n' 'export TEAM_ID=TEAMID1234' 'export ASC_KEY_ID=KEYID12345' \
  'export ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000' \
  "export ASC_KEY_PATH=$TMP/missing.p8" > "$TMP/bad-config.sh"
set +e
badkey="$(PATH="$TMP/bin:$PATH" TF_APPS_FILE="$TMP/apps.sh" TF_CONFIG_FILE="$TMP/bad-config.sh" \
  "$KIT_DIR/post-upload.sh" example --dry-run 2>&1)"
badkey_rc=$?
set -e
[[ "$badkey_rc" -ne 0 ]] || fail "missing API key file should fail"
assert_has "$badkey" "API key file not found" "missing key error"
assert_lacks "$badkey" "not-a-real-key" "missing key error"

if [[ -f "$KIT_DIR/apps.local.sh" || -f "$KIT_DIR/apps.sh" ]]; then
  echo "  skip missing-registry case (local apps file present)"
else
  set +e
  noreg="$(PATH="$TMP/bin:$PATH" TF_APPS_FILE="$TMP/does-not-exist.sh" TF_CONFIG_FILE="$TMP/config.sh" \
    "$KIT_DIR/bump-build.sh" example 2>&1)"
  noreg_rc=$?
  set -e
  [[ "$noreg_rc" -ne 0 ]] || fail "missing app registry should fail"
  assert_has "$noreg" "no app registry found" "missing registry error"
fi

if [[ -s "$GUARD_LOG" ]]; then
  echo "blocked commands were invoked:" >&2
  cat "$GUARD_LOG" >&2
  fail "dry-run invoked python, curl, or xcodebuild"
fi

echo "OK  TestFlight lib.sh syntax and dry-run checks passed"
