# TestFlight kit (bundled in LaunchPilot)

Archive, bump build numbers, and upload iOS apps to TestFlight.

Product Xcode paths and ASC app IDs live in **gitignored** `apps.sh`.
Apple credentials live in **gitignored** `config.sh`. The `.p8` key stays under
`~/.appstoreconnect/`.

```bash
cp config.example.sh config.sh
cp apps.example.sh apps.sh
# edit both — see ../../docs/SETUP.md
```

## Commands (from LaunchPilot root)

```bash
./kits/testflight/build-check.sh <tf_key>
./kits/testflight/bump-build.sh <tf_key>
./kits/testflight/archive-and-upload.sh <tf_key>
./kits/testflight/verify-key.sh
./kits/testflight/make-signing-assets.sh

# or via pilot (preferred)
./bin/pilot build <product>
./bin/pilot testflight <product> --confirm
```

`tf_key` must match a case in `apps.sh` and the `tf_key` field in
`config/products.json`.

Every successful upload runs `post-upload.sh`, which waits for the build to
become VALID, attaches it to **Internal Testers** (every internal group) plus
the configured external group, and tries to set `hasAccessToAllBuilds` on
internal groups so later builds show up on the phone without a manual ASC click.

Workspace for product repos: `PILOT_WORKSPACE` or the parent folder of
LaunchPilot.

More: [YOUR_CONFIG_CHECKLIST.md](YOUR_CONFIG_CHECKLIST.md), [DEVICE_TESTING.md](DEVICE_TESTING.md),
[docs/SETUP.md](../../docs/SETUP.md).
