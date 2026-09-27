# Security

## Secrets stay local

These files are **gitignored** and must never be committed:

| File | Why |
|------|-----|
| `config/pilot.env` | API keys (`CURSOR_API_KEY`, `VERCEL_TOKEN`, …) |
| `config/products.json` | Your real product registry |
| `kits/testflight/config.sh` | Apple Team ID + ASC API key id/issuer + path to `.p8` |
| `kits/testflight/apps.sh` | Your Xcode project paths / ASC app IDs |
| `kits/testflight/*.p8` | ASC private keys (prefer `~/.appstoreconnect/` instead) |
| `kits/appstore/products/*/screenshots/` | Large / marketing screenshots |

Copy from the committed templates:

```bash
cp config/pilot.env.example config/pilot.env
cp config/products.example.json config/products.json
cp kits/testflight/config.example.sh kits/testflight/config.sh
cp kits/testflight/apps.example.sh kits/testflight/apps.sh
```

Full map: [docs/SETUP.md](docs/SETUP.md).

Apple `.p8` keys and distribution certs live **outside** the repo (typically
`~/.appstoreconnect/private_keys/`). Do not paste private keys into chat,
rules files, or committed docs.

## What is safe to commit

- `*.example.*` templates (placeholders only)
- `config/policy.json` — gate definitions (no credentials)
- Kit scripts under `kits/testflight/` and `kits/appstore/`
- Docs, agent runner, demo site

## Reporting

If you find a security issue in LaunchPilot (e.g. a path that would commit
secrets, or a gate that can be bypassed unintentionally), open a private report
or an issue without including real credentials. Rotate any key that may have
been exposed.

## Going public

This repository is intended to be shareable. Before changing GitHub visibility to **Public**:

1. Confirm gitignored secret files were never committed (`config/pilot.env`, `config/products.json`, `kits/testflight/*.p8`, kit `config.sh` / `apps.sh`).
2. Search history for tokens and private keys (`git log -p --all -S 'BEGIN PRIVATE KEY'` and similar).
3. Keep real App Store / AdMob / bank identifiers in local gitignored config only.
4. Run `./bin/pilot demo` from a clean clone.

If you find a committed secret, rotate it immediately and purge it from history before opening the repo.
