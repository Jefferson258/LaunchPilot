# iPhone Shortcuts recipes (LaunchPilot)

Use with [PHONE.md](PHONE.md). Host/user/key are yours — do not commit secrets.

## Shared SSH action settings

| Field | Value |
|-------|--------|
| Host | LAN IP from `./bin/pilot remote-check`, or Tailscale IP if off-LAN |
| Port | `22` |
| User | Mac account that owns `~/Desktop/LaunchPilot` |
| Authentication | **SSH Key** (Shortcuts can generate; paste public key into Mac `~/.ssh/authorized_keys`) |
| Input | ignore |

First-time SSH key: in the Shortcuts SSH action, choose SSH Key → copy public key → on the Mac:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo 'PASTE_PUBLIC_KEY_HERE' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## Shortcut: `LP — sleep wake run` (Path A)

**Actions**

1. **Run Script Over SSH** — Script:

```bash
set -e
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
LP="${HOME}/Desktop/LaunchPilot"
cd "$LP"
./bin/pilot remote-run demo-site "Phone Path A smoke $(date -u +%Y-%m-%dT%H:%MZ)" --sleep
```

2. **Show Notification** — “LaunchPilot remote-run finished” (optional; may fire before sleep)

Replace `demo-site` / prompt when driving a real product. Add ship flags only deliberately:

```bash
./bin/pilot remote-run velour-app "Fix empty state" --sleep
# ./bin/pilot remote-run juicd-app "…" --ship-testflight --sleep
```

---

## Shortcut: `LP — M4 cold boot run` (Path B)

Requires eligible hardware + smart plug + Energy **Always**.

**Actions (order matters)**

1. **Control Home Device** → Mac’s smart plug → **Turn Off**
2. **Wait** → 35 seconds
3. **Control Home Device** → same plug → **Turn On**
4. **Wait** → 75 seconds
5. **Run Script Over SSH** — Script:

```bash
set -e
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
LP="${HOME}/Desktop/LaunchPilot"
cd "$LP"
# Boot can race DHCP; retry a few times
ok=0
for i in 1 2 3 4 5 6 7 8; do
  if ./bin/pilot remote-check >/tmp/lp-remote-check.txt 2>&1; then ok=1; break; fi
  sleep 15
done
test "$ok" = "1"
./bin/pilot remote-run demo-site "Phone Path B cold-boot smoke $(date -u +%Y-%m-%dT%H:%MZ)" --shutdown
```

6. **Wait** → 30 seconds (optional)
7. **Control Home Device** → plug **Turn Off** (optional power save)

If SSH fails at step 5, increase the wait after power-on (FileVault / Wi‑Fi join time).

---

## Shortcut: `LP — remote-check only`

```bash
export PATH="/opt/homebrew/bin:/usr/bin:/bin"
cd "$HOME/Desktop/LaunchPilot" && ./bin/pilot remote-check
```

Use this to verify wake/SSH before a long pipeline.
