# Launch Command Center → Notion

Optional: a Notion board as a phone-friendly status cockpit for launch
blockers and owner decisions. LaunchPilot works without it
(`PILOT_NOTION_ENABLED=0` by default).

Build the board by hand or import a CSV with the columns listed in Step 2.

---

## Step 1 — Install Notion (free)

- **iPhone/iPad:** App Store → search **Notion**
- **Mac:** [notion.so/desktop](https://www.notion.so/desktop) or Mac App Store

Sign in with Apple or email.

---

## Step 2 — Import the board

1. Open Notion → **New page** → name it **Launch Command Center**
2. Type `/table` → choose **Table – Full page** (or **Board** after import)
3. Click **⋯** (top right of the database) → **Merge with CSV** / **Import** → **CSV**
4. Select your CSV (columns: Task, App, Owner, Status, Phone OK?, Notes)
5. Map columns if prompted:
   - **Task** → Title
   - **App** → Select
   - **Owner** → Select
   - **Status** → Select
   - **Phone OK?** → Select
   - **Notes** → Text

---

## Step 3 — Turn it into a Kanban board

1. Click **+ Add a view** (top left of the database)
2. Choose **Board**
3. Group by **Status**
4. Optional: add a **Table** view filtered by **Owner = You** for your phone checklist

### Recommended Status values (left → right on **Flow** / **Pipeline** board)

1. **Backlog** — not started; ideas and later work
2. **To Do Next** — your turn (phone-friendly owner tasks)
3. **Waiting on Access** — blocked on credentials, login, or a Mac-only step you haven’t done yet
4. **Waiting on Counsel** — legal review
5. **Done** — finished; drag here when complete

**No “Agent Ready” column.** Routine agent work (builds, deploys, docs) lives in each repo’s `AGENTS.md` and `LaunchPilot/README.md`. Notion is only for **blockers and owner decisions** — not a dump of everything the agent could do.

Use the **Flow** view for the kanban; column order follows the list above.

---

## Step 4 — Pin on your phone

1. Open the page in Notion iOS
2. Tap **⋯** → **Add to Home Screen** (optional)
3. Favorite the page in Notion sidebar

---

## Optional filters (views)

| View name | Filter |
|-----------|--------|
| **My tasks** | Owner = You, Status ≠ Done |
| **Blocked on you** | Owner = You, Status = To Do Next |
| **Legal review** | App = Example App, Owner = Counsel |
| **Phone tonight** | Phone OK? = Yes, Owner = You, Status ≠ Done |
| **One app first** | App = Example App |

---

## Keep in sync with repos

Repo checklists (source of truth for *how* to do each task):

- `<YourApp>/YOUR_LAUNCH_CHECKLIST.md` (one per product repo)

Notion = **status cockpit**. Repos = **step-by-step instructions**.

When you complete a card, move it to **Done** in Notion and tell the agent what's unblocked.
