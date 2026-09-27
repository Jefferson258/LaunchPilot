# Agent setup — read this on a new Mac or after a workflow reset

**Purpose:** One document so you can tell Cursor: *“Read `LaunchCommandCenter/AGENT_SETUP.md` and restore launch workflow access.”*

**Last verified:** June 28, 2026 · GitHub account `Jefferson258`

---

## What this workflow is

Three iOS apps + three marketing sites + LLC/legal launch, coordinated via:

- **Repos** on `~/Desktop` (and GitHub)
- **Notion** Launch Command Center (task board)
- **TestFlight kit** at `~/Desktop/TestFlight`
- **Cursor** agent on the Mac (optional Cloud Agent if Mac is offline)

---

## Folder map (Desktop)

| Path | GitHub remote | Role |
|------|---------------|------|
| `Corvim/` | `Jefferson258/Corvim` | iOS app + Supabase |
| `Corvim-Website/` | `Jefferson258/Corvim-website` | Marketing site |
| `juicd/` | `Jefferson258/juicd` | iOS app + Supabase |
| `juicd-website/` | `Jefferson258/Juicd-website` | Marketing site |
| `VelourCloset/` | `Jefferson258/VelourCloset` | iPad app (SwiftData) |
| `VelourClosetWebsite/` | `Jefferson258/VelourClosetWebsite` | Marketing site |
| `LaunchPilot/` | *(local git repo — push to GitHub when ready)* | Orchestration CLI for agent-driven pipelines |
| `TestFlight/` | *(local only — not a repo)* | Build/upload scripts |
| `LaunchCommandCenter/` | *(local only)* | Notion CSV, this doc, phone workflow |
| `LegalDocuments/` | *(local only)* | Terms/privacy drafts, counsel brief |

---

## Access checklist (give the agent / restore on new Mac)

### 1. Mac prerequisites

- [ ] **Xcode** installed (App Store) — ships universal `xcodebuild` (no Rosetta needed)
- [ ] **Node.js** for websites — use **arm64** build (`node -p process.arch` → `arm64`)
- [ ] **GitHub CLI:** `brew install gh` from **Apple Silicon Homebrew** (`/opt/homebrew`)
- [ ] **Git:** `brew install git` (avoid Intel-only `/usr/local/bin/git`)
- [ ] **Cursor** with Desktop workspace open

#### Apple silicon / Rosetta (read before macOS 28)

Apple [plans to limit Rosetta](https://support.apple.com/en-us/102527) after macOS 27.
Intel-only CLI tools (`Application (Intel)` in Finder → Get Info) will stop working.

```bash
~/Desktop/scripts/check-native-tools.sh   # should pass with no warnings
```

If `git` or `gh` show as Intel/Rosetta:

```bash
brew install git gh
# In ~/.zshrc, put Apple Silicon Homebrew first:
export PATH="/opt/homebrew/bin:/usr/bin:$PATH"
```

LaunchPilot already prefers `/opt/homebrew/bin` when running pipeline steps.

### 2. GitHub (`gh auth login`) — **DONE on current Mac**

```bash
cd ~/Desktop
gh auth login
# GitHub.com → HTTPS → login with browser → authorize git credentials
gh auth status   # should show Jefferson258, scopes include repo
```

**Clone repos on a new Mac:**

```bash
mkdir -p ~/Desktop && cd ~/Desktop
gh repo clone Jefferson258/Corvim
gh repo clone Jefferson258/Corvim-website Corvim-Website
gh repo clone Jefferson258/juicd
gh repo clone Jefferson258/Juicd-website juicd-website
gh repo clone Jefferson258/VelourCloset
gh repo clone Jefferson258/VelourClosetWebsite
```

Copy `TestFlight/` and `LaunchCommandCenter/` from backup or old Mac (not on GitHub).

**Security:** Corvim remote must **not** embed a PAT in the URL. Use:

```bash
cd ~/Desktop/Corvim
git remote set-url origin https://github.com/Jefferson258/Corvim.git
```

Revoke any old exposed `ghp_` tokens in GitHub → Settings → Developer settings → Personal access tokens.

### 3. Notion MCP (Cursor)

**Config file:** `~/.cursor/mcp.json` (or `Desktop/.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "notion": {
      "url": "https://mcp.notion.com/mcp"
    }
  }
}
```

**First use:** Agent calls Notion MCP auth; you complete OAuth in browser.  
**Board URL:** [Launch Command Center](https://app.notion.com/p/ce12da3033f84861a49353acdf19d520)

**Key views:** `Fastest Unblocks`, `Phone Priority Queue`, `Priority Board`

If the board is missing on a fresh Notion account, re-import `LaunchCommandCenter/notion-import.csv` per `NOTION_SETUP.md`.

### 4. Apple / TestFlight (you — identity bound)

| Item | Location / action |
|------|-------------------|
| Apple Developer | [developer.apple.com](https://developer.apple.com/account) |
| App Store Connect | [appstoreconnect.apple.com](https://appstoreconnect.apple.com) |
| Team ID | Membership details (e.g. `8H2437SV33`) |
| ASC API key (`.p8`) | ASC → Users and Access → Integrations → Keys |
| Local config | `~/Desktop/TestFlight/config.sh` (copy from `config.example.sh`, gitignored) |
| Checklist | `TestFlight/YOUR_CONFIG_CHECKLIST.md` |

**Agent can run after `config.sh` + ASC app records exist:**

```bash
~/Desktop/TestFlight/build-check.sh all      # juicd, velour, corvim
~/Desktop/TestFlight/archive-and-upload.sh juicd
~/Desktop/TestFlight/archive-and-upload.sh velour
```

### 5. Vercel (websites) — **still needed**

- Import each `*-Website` repo at [vercel.com](https://vercel.com)
- Framework: **Vite** · Build: `npm run build` · Output: `dist`
- Invite agent or store deploy token in 1Password

### 6. Supabase (Corvim + Juicd) — **still needed**

- Create two projects (or one per app)
- Invite agent email to project
- Agent runs migrations under `supabase/migrations/` and deploys Juicd edge functions (`play-board`, `resolve-play-slip`)
- Store `SUPABASE_URL`, `SUPABASE_ANON_KEY`, service role in 1Password — **never commit**

### 7. 1Password vault “Launch” (recommended)

Store (never paste in chat):

- Apple Team ID, ASC Key ID, Issuer ID, path to `.p8`
- Supabase URLs and keys
- Vercel token (if used)
- Domain registrar login hint / DNS notes
- LLC legal name once formed

### 8. Cursor workspace rules (optional)

`Desktop/.cursor/rules/open-apps-on-other-monitor.mdc` — opens GUI apps on second monitor via:

```bash
~/Desktop/scripts/open-on-other-monitor.sh "Safari"
```

### 9. Domains (you — payment)

| App | Domain |
|-----|--------|
| Corvim | `corvim.app` — **owned and live** (`https://corvim.app`) |
| Juicd | `juicd.app` (not purchased) |
| Velour Closet | `velourcloset.app` (not purchased) |

Point DNS to Vercel after deploy for remaining domains (`juicd.app`, `velourcloset.app`). `corvim.app` is already attached. Privacy/terms routes already exist in each website repo.

---

## What the agent can do with each access level

| Access | ~% of launch automation |
|--------|-------------------------|
| Repos only (local) | 35% — drafts, builds, metadata docs |
| + `gh auth login` | 50% — push docs/code to GitHub |
| + Mac / Xcode | 60% — compile-check all apps, screenshots |
| + Vercel | 70% — live website previews |
| + Supabase invites | 80% — backends for Corvim/Juicd |
| + ASC key + app records + `config.sh` | 90% — TestFlight upload loop |
| + domains + legal sign-off | 95% — you still click Submit in ASC |

---

## Current access status (update when things change)

| System | Status |
|--------|--------|
| GitHub `gh` | ✅ Logged in as Jefferson258 |
| Notion MCP | ✅ OAuth connected; board live |
| Mac + Xcode | ✅ All 3 apps compile; all 3 sites build |
| Vercel | ❌ Not connected |
| Supabase | ❌ Projects not handed to agent |
| TestFlight `config.sh` | ❌ Not created yet |
| ASC app records | ❌ You |
| Domains | ❌ You |
| LLC / counsel (Juicd) | ❌ You |

---

## Agent-prepared artifacts (no extra access needed)

| App | App Store listing | Privacy questionnaire | Review notes |
|-----|-------------------|----------------------|--------------|
| Corvim | `Corvim/docs/APP_STORE_LISTING.md` | `Corvim/docs/APP_PRIVACY_QUESTIONNAIRE.md` | `Corvim/docs/APP_REVIEW_NOTES.md` |
| Velour Closet | `VelourCloset/docs/APP_STORE_LISTING.md` | `VelourCloset/docs/APP_PRIVACY_QUESTIONNAIRE.md` | in listing doc |
| Juicd | `juicd/docs/APP_STORE_LISTING.md` | `juicd/docs/APP_PRIVACY_QUESTIONNAIRE.md` | in listing doc |

Per-app deep dives: `*/MAX_ACCESS_SETUP_SPLIT.md`, `*/YOUR_LAUNCH_CHECKLIST.md`, `*/LAUNCH_OUT_OF_CODE.md`

---

## Phone workflow

See `LaunchCommandCenter/PHONE_AGENT_WORKFLOW.md` — use Notion **Phone Priority Queue** view.

---

## Restore prompt (copy-paste to a new Cursor chat)

```
Read ~/Desktop/LaunchCommandCenter/AGENT_SETUP.md and restore launch workflow.
Check gh auth, Notion MCP, and what's still blocked.
Continue from the Notion "Fastest Unblocks" queue.
```

---

## Security reminders

1. Never commit `.env`, `config.sh`, `.p8`, or API keys.
2. Rotate any PAT ever embedded in a git remote URL.
3. Juicd: keep `odds_mode = simulated` until counsel + Odds API are intentional.
4. Do not submit Juicd to App Store until counsel approves contest/gambling posture.
