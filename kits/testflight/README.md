# TestFlight kit (bundled in LaunchPilot)

Archive, bump build numbers, and upload iOS apps to TestFlight.

All per-app and per-account values live in **local, gitignored** files that the
scripts read (first match wins; override with `TF_APPS_FILE` / `TF_CONFIG_FILE`):

| What | Local file | Template |
|---|---|---|
| App registry (Xcode project, scheme, bundle ID, profile, ASC app ID, groups) | `apps.local.sh` → `apps.sh` | `apps.example.sh` |
| Apple credentials (Team ID, ASC key id / issuer / `.p8` path) | `config.local.sh` → `config.sh` | `config.example.sh` |

The `.p8` key stays outside the repo, e.g. `~/.appstoreconnect/private_keys/`.

```bash
cp config.example.sh config.local.sh
cp apps.example.sh apps.local.sh
# edit both — see YOUR_CONFIG_CHECKLIST.md and ../../docs/SETUP.md
```

## Commands (from LaunchPilot root)

```bash
./kits/testflight/build-check.sh <app-key>|all
./kits/testflight/bump-build.sh <app-key> [build]
./kits/testflight/archive-and-upload.sh <app-key> [--dry-run]
./kits/testflight/post-upload.sh <app-key> [build] [--dry-run]
./kits/testflight/verify-key.sh
./kits/testflight/make-signing-assets.sh

# or via pilot (preferred)
./bin/pilot build <product>
./bin/pilot testflight <product> --confirm
```

`--dry-run` (or `TF_DRY_RUN=1`) resolves the registry and credentials, prints
the plan with IDs masked, and exits without archiving, uploading, or calling
App Store Connect.

`<app-key>` must match a case in the registry and the `tf_key` field in
`config/products.json`.

## After every upload: tester groups

Every successful upload runs `post-upload.sh`, which waits for the build to
become VALID, checks export-compliance metadata, attaches the build to **every
internal tester group**, and tries to set `hasAccessToAllBuilds` on internal
groups so later builds show up without a manual click.

**External groups are opt-in.** By default nothing is attached to external
groups (that can trigger Beta App Review and reach outside testers). To opt in:

```bash
# per app, in apps.local.sh
EXTERNAL_BETA_GROUP_IDS="<group-id> [<group-id> …]"
# or for every app, in config.local.sh
export TF_EXTERNAL_BETA_GROUP_IDS="<group-id>"
# legacy single BETA_GROUP_ID is only used with TF_ATTACH_EXTERNAL=1
```

Workspace for product repos: `PILOT_WORKSPACE` or the parent folder of
LaunchPilot.

More: [YOUR_CONFIG_CHECKLIST.md](YOUR_CONFIG_CHECKLIST.md), [DEVICE_TESTING.md](DEVICE_TESTING.md),
[docs/SETUP.md](../../docs/SETUP.md).
