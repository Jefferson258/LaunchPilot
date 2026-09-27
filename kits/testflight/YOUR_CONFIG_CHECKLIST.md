# TestFlight config — your checklist (~10 minutes)

The automation kit needs `config.sh` (gitignored). Until this exists, scripts like `archive-and-upload.sh` will stop with a clear error.

## Step 1 — Copy the template

On your Mac (or ask the agent after you paste values into 1Password):

```bash
cp ~/Desktop/TestFlight/config.example.sh ~/Desktop/TestFlight/config.sh
```

## Step 2 — Fill these four values

| Variable | Where to get it |
|----------|-----------------|
| `TEAM_ID` | [developer.apple.com/account](https://developer.apple.com/account) → Membership → **Team ID** (Juicd project already uses `8H2437SV33` if same account) |
| `ASC_KEY_ID` | App Store Connect → Users and Access → **Integrations** → Keys → create key with **App Manager** role |
| `ASC_ISSUER_ID` | Same Integrations page (top of Keys section) |
| `ASC_KEY_PATH` | Path to the `.p8` file you download **once** when creating the key |

### Safe storage for the `.p8` file

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

Update `ASC_KEY_PATH` in `config.sh` to match.

## Step 3 — Verify (Mac)

```bash
~/Desktop/TestFlight/verify-key.sh
~/Desktop/TestFlight/build-check.sh all    # Juicd + Velour + Corvim compile
```

Requires `gh auth login` on the Mac if pushing doc changes from agent workflows (see `LaunchCommandCenter/AGENT_SETUP.md`).

## Step 4 — What the agent can run after config exists

```bash
~/Desktop/TestFlight/archive-and-upload.sh juicd
~/Desktop/TestFlight/archive-and-upload.sh velour
```

Requires: App Store Connect **app records** already created for each bundle ID.

## Phone-friendly version

You can do Steps 2’s **Apple portal parts** on iPhone Safari:
- Accept agreements in developer.apple.com
- Create ASC API key (download `.p8` on Mac — **cannot** complete key setup on phone alone)

Store the four values in **1Password** and message the agent: “ASC key is in 1Password vault X” — never paste the `.p8` contents in chat.

## Security

- `config.sh` is gitignored — do not commit it
- Rotate the exposed GitHub token on Corvim remote (separate task on your board)
- Revoke old ASC keys if compromised
