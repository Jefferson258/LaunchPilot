# Release notes kit

Every TestFlight / production web ship should leave a **GitHub Release** (and `CHANGELOG.md` entry) listing commits since the previous tag so you can revert/fix quickly.

## Commands

```bash
# Preview notes for a repo
./kits/release-notes/generate.sh --repo ~/Desktop/exampleapp | less

# Publish tag + GitHub Release + prepend CHANGELOG.md (commit that file only)
./kits/release-notes/publish.sh --repo ~/Desktop/exampleapp --tag exampleapp-ios-1.0.0+8 --title "Example App iOS 1.0.0 (8)" --commit
```

LaunchPilot wires this automatically:

- `pilot testflight <product> --confirm` → after upload, publishes `\<tf_key\>-ios-\<version\>+\<build\>`
- `pilot deploy <product> --prod` → publishes `\<product\>-web-\<YYYYMMDD\>-\<shortsha\>`

## Where to look when something breaks

1. GitHub → repo → **Releases** — what went out in that build
2. Root `CHANGELOG.md` — same notes in-repo
3. Apple / Vercel deploy timestamps ↔ release tag date

## Convention

| Product | Tag example |
|---------|-------------|
| Example App iOS | `exampleapp-ios-1.0.0+7` |
| Sample App iOS | `sampleapp-ios-1.0.0+39` |
| DemoApp iOS | `demoapp-ios-1.0.0+12` |
| Sites | `exampleapp-site-web-20260721-a1b2c3d` |
