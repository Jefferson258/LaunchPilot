# Phone → Mac → LaunchPilot → sleep/shutdown

Two supported paths. **This workspace’s Mac mini (M2, 2023) uses Path A.**
Path B needs a **2024+ Mac mini (M4)** (or eligible Studio/iMac) plus a smart plug.

Also see Cursor Cloud / Remote Control notes at the bottom.

---

## Path A — Sleep → wake → pipeline → sleep/shutdown  
*(works on current M2 Mac mini)*

You **cannot** cold-boot this Mac from the phone. Leave it **asleep** (not Off).

### One-time Mac setup

1. **System Settings → Energy**
   - Turn on **Wake for network access**
   - Prefer Ethernet over Wi‑Fi when away
2. **System Settings → General → Sharing → Remote Login** (SSH) — on  
   Allow your user (or “Administrators”)
3. Optional: HomePod / Apple TV on the same LAN (Bonjour Sleep Proxy helps wake)
4. Verify:

```bash
cd ~/Desktop/LaunchPilot
./bin/pilot remote-check
```

5. Optional passwordless shutdown (only if you want `--shutdown` from Shortcuts):

```bash
# Careful: limits sudo without password to shutdown only
sudo visudo -f /etc/sudoers.d/pilot-shutdown
# Add one line (replace USER):
# USER ALL=(ALL) NOPASSWD: /sbin/shutdown
```

Prefer **`--sleep`** so you can wake again without a power button.

### iPhone Shortcut (Path A)

1. Shortcuts → **New Shortcut** → name it `LaunchPilot remote`
2. Add **Run Script Over SSH**:
   - Host: Mac LAN IP (from `pilot remote-check`) or Tailscale IP
   - User: your Mac username
   - Authentication: SSH Key (recommended) or password
   - Script:

```bash
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
cd "$HOME/Desktop/LaunchPilot" || cd /Users/tjkade/Desktop/LaunchPilot
./bin/pilot remote-run demo-site "Phone smoke: tweak nothing, just prove remote-run" --sleep
```

3. For a real product later (still no auto-ship unless you add a flag):

```bash
./bin/pilot remote-run velour-app "Describe the change" --sleep
# intentional TestFlight:
# ./bin/pilot remote-run velour-app "…" --ship-testflight --sleep
```

4. Run the Shortcut from the Home Screen / Control Center.

**What happens:** SSH reaches the sleeping Mac (wake-for-network) → `caffeinate` holds it awake → `pilot run` → Mac sleeps again.

If SSH fails while asleep: open the Shortcut once more after a few seconds, or use a HomePod on the LAN; Apple silicon wake can be flaky without a sleep proxy.

Full Shortcut field notes: [shortcuts-iphone.md](shortcuts-iphone.md).

### CLI (on the Mac, or already SSH’d in)

```bash
./bin/pilot remote-run <product> "<prompt>" [--ship…] [--sleep|--shutdown|--stay-awake]
./bin/pilot remote-check
```

---

## Path B — Fully off → smart plug → Always boot → pipeline → shutdown  
*(M4 Mac mini / eligible desktops only)*

Apple docs: [Turn on a Mac without pressing the power button](https://support.apple.com/en-us/125517)

**Requirements**

- macOS **26.5+**
- **Mac mini 2024+**, **Mac Studio 2025+**, or **iMac 2024+**
- HomeKit/Matter **smart plug** controllable from iPhone
- Same SSH + LaunchPilot setup as Path A
- Energy → **Start up when power is connected → Always**

Your current **M2 mini (Mac14,3) does not get this setting.**

### One-time setup (on the new Mac)

1. Energy → **Start up when power is connected → Always**
2. Plug Mac power brick into a smart plug (not a dumb strip you can’t cut)
3. Remote Login + `pilot remote-check`
4. Passwordless `shutdown` sudoers entry (Path B usually wants `--shutdown`)
5. FileVault: after cold boot you may land at login screen — use **auto-login** for a dedicated build user **or** SSH as a user that can unlock (plan this before relying on unattended runs)

### iPhone Shortcut (Path B)

Create a Shortcut that runs **in order**:

1. **Control Home** → smart plug **Off**
2. **Wait** 35 seconds (PSU discharge; Apple suggests ~30s)
3. **Control Home** → smart plug **On** (Mac should auto-boot)
4. **Wait** 60–90 seconds (boot + network)
5. **Run Script Over SSH**:

```bash
export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
cd "$HOME/Desktop/LaunchPilot"
# Retry SSH-side readiness briefly
for i in 1 2 3 4 5 6; do
  ./bin/pilot remote-check >/tmp/pilot-remote-check.txt 2>&1 && break
  sleep 10
done
./bin/pilot remote-run demo-site "Cold-boot remote smoke" --shutdown
```

6. Optional: smart plug **Off** after another wait (saves power; next run power-cycles again)

### Safety

- Hard power-cut via smart plug is fine for “off,” but don’t yank power mid-Xcode archive — let `remote-run` finish and `--shutdown` cleanly.
- Never put `--ship-prod` / `--ship-testflight` in a phone Shortcut until you intentionally want real-user shipping.

---

## Cursor iOS (related, not the same)

| Mode | Mac needed? | Runs LaunchPilot locally? |
|------|-------------|---------------------------|
| Cloud Agent | No | No (no local Xcode/TF kit) |
| Remote Control / My Machines | Yes (awake) | Yes — can call `pilot remote-run` |
| Path A/B Shortcuts SSH | Sleep or cold-boot as above | Yes |

---

## Recommended for this workspace today

1. Use **Path A** on the M2 mini: sleep + SSH Shortcut + `remote-run … --sleep`
2. Keep App Store Submit manual; ship flags only when you mean them
3. If you later buy an **M4 mini**, enable Path B and keep Path A as fallback
