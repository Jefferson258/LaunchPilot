# Directing the agent from your phone (no Mac for a week)

Use this when you're away from your Mac but still want launch work to move. Your **Launch Command Center** in Notion is the hub.

**Master setup (new Mac / reset):** [AGENT_SETUP.md](AGENT_SETUP.md)

---

## What works well from phone

| You do on phone | Agent can do on Mac |
|-----------------|---------------------|
| Texas SOS LLC filing (Safari) | Compile apps, draft docs, wire code |
| App Store Connect app (iOS app) | Website builds, metadata files |
| Buy domains (registrar app) | Push repos after you `gh auth login` once |
| 1Password: store ASC key, Supabase keys | Fill `TestFlight/config.sh` from vault |
| Notion: move cards, add notes | Update same Notion board via MCP |
| Email counsel (Juicd) | Wait for your "approved" note |
| GitHub mobile: revoke bad token | Fix code, open PRs |

---

## Best setup before you leave the Mac (15–30 min)

1. **Keep Mac awake / plugged in** with Cursor open (or enable Cursor Cloud Agent on your repos).
2. **`gh auth login`** in Terminal — ✅ done on current Mac (`Jefferson258`); agent can push repos.
3. **Invite agent access:** GitHub repos, Vercel (3 sites), Supabase (Corvim + Juicd).
4. **1Password vault "Launch"** with Team ID, ASC Key ID, Issuer ID, `.p8` path, Supabase keys.
5. **Pin Launch Command Center** in Notion on your phone.

---

## How to message the agent from phone

**Cursor mobile / web chat** — send bounded prompts:

- "Mark 'Buy juicd.app' done in Notion — I bought it on Namecheap."
- "Deploy Corvim-Website to Vercel; keys are in 1Password."
- "Juicd counsel approved — deploy juicd-website."
- "Run TestFlight upload for Velour Closet; config.sh is filled."

**Notion as task queue:** move cards left → right as they progress. When you finish a phone task, drag it to **Done**. When you drop credentials in 1Password, move the card from **Waiting on Access** to **Backlog** or **To Do Next** (agent picks up from `AGENTS.md` / chat — there is no separate agent column).

---

## What does not work from phone alone

- Downloading ASC `.p8` (needs Mac for file placement)
- Xcode archive
- First `gh auth login` interactive flow
- Writing `config.sh` on disk unless Mac is reachable

---

## Priority if you only have phone time

1. LLC formed + EIN obtained (Aug 31, 2026) — next: operating agreement + LLC bank
2. Apple agreements + three ASC app records
3. ASC API key (Mac once) → 1Password
4. Domains: **corvim.app owned and live**; still buy juicd.app and velourcloset.app if you want custom URLs
5. Supabase projects + invite agent
6. Counsel email for Juicd
7. Rotate exposed GitHub token

---

## "10x" unlocks (ranked)

| Unlock | Your effort | Agent gain |
|--------|-------------|------------|
| Mac on + Cursor agent | Plug in, disable sleep | Continuous builds |
| `gh auth login` | ✅ Done | Push all repos |
| Vercel invite | 2 min | Live preview URLs |
| Supabase invites ×2 | 10 min | Migrations + edge functions |
| `TestFlight/config.sh` + ASC records | 15 min | TestFlight automation |
| 1Password shared vault | 10 min | No secrets in chat |
| Domain DNS → Vercel | 5 min/remaining domain | `corvim.app` already live; Juicd/Velour still need custom domains |
| Counsel Juicd sign-off | Email | Ship juicd site + submit |
| Cursor Cloud Agent | Settings | Runs when laptop closed |

---

## LaunchPilot from the phone (sleep-wake / M4 cold-boot)

Full recipes live in LaunchPilot:

- `LaunchPilot/docs/PHONE.md` — Path A (sleep → wake → pipeline → sleep) for this M2 mini; Path B (Always + smart plug → shutdown) for an M4+ mini
- `LaunchPilot/docs/shortcuts-iphone.md` — iPhone Shortcuts SSH scripts

```bash
# On the Mac once:
./bin/pilot remote-check

# From iPhone Shortcuts → Run Script Over SSH (Mac left asleep, not Off):
./bin/pilot remote-run demo-site "Phone smoke" --sleep
```

Do **not** put `--ship-prod` / `--ship-testflight` in a Shortcut unless you intentionally want real-user shipping. App Store Submit stays manual.

---

## Still blocked by you

Apple agreements, LLC, domain payment, final legal approval, App Store Submit button, counsel on Juicd, any 2FA on Apple/GitHub/bank.

---

## Agent-prepared files (paste into ASC from phone)

| App | Listing | Privacy labels | Review notes |
|-----|---------|----------------|--------------|
| Corvim | `Corvim/docs/APP_STORE_LISTING.md` | `Corvim/docs/APP_PRIVACY_QUESTIONNAIRE.md` | `Corvim/docs/APP_REVIEW_NOTES.md` |
| Velour Closet | `VelourCloset/docs/APP_STORE_LISTING.md` | `VelourCloset/docs/APP_PRIVACY_QUESTIONNAIRE.md` | in listing doc |
| Juicd | `juicd/docs/APP_STORE_LISTING.md` | `juicd/docs/APP_PRIVACY_QUESTIONNAIRE.md` | in listing doc |

TestFlight: `TestFlight/YOUR_CONFIG_CHECKLIST.md`
