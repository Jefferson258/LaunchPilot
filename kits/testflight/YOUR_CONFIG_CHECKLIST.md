# TestFlight config — checklist (~10 minutes)

The kit needs two local, gitignored files. Until they exist, scripts stop with
a clear error.

| File | Template | Holds |
|---|---|---|
| `config.local.sh` (or `config.sh`) | `config.example.sh` | Team ID + ASC API key |
| `apps.local.sh` (or `apps.sh`) | `apps.example.sh` | Xcode projects, bundle IDs, ASC app IDs, optional external groups |

## Step 1 — Copy the templates

```bash
cd kits/testflight
cp config.example.sh config.local.sh
cp apps.example.sh apps.local.sh
```

## Step 2 — Fill the credentials

| Variable | Where to get it |
|----------|-----------------|
| `TEAM_ID` | [developer.apple.com/account](https://developer.apple.com/account) → Membership → **Team ID** |
| `ASC_KEY_ID` | App Store Connect → Users and Access → **Integrations** → Keys → create key with **App Manager** role |
| `ASC_ISSUER_ID` | Same Integrations page (top of Keys section) |
| `ASC_KEY_PATH` | Path to the `.p8` file you download **once** when creating the key |

### Safe storage for the `.p8` file

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

## Step 3 — Add your apps

One `case` per app in `apps.local.sh`, and list the keys in `TF_APP_KEYS`.
The key must match `tf_key` in `config/products.json`.

## Step 4 — Verify

```bash
./kits/testflight/verify-key.sh                      # key works, lists apps
./kits/testflight/archive-and-upload.sh <app-key> --dry-run   # config resolves
./kits/testflight/build-check.sh all                 # every app compiles
```

## Step 5 — Upload

```bash
./kits/testflight/archive-and-upload.sh <app-key>
```

Requires an App Store Connect **app record** for each bundle ID.

## Security

- Local config files are gitignored — never commit them or paste `.p8` contents anywhere.
- Revoke old ASC keys if compromised.
