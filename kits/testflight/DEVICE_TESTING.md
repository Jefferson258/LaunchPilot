# Getting Juicd & Velour Closet onto a real iPhone (like Corvim)

Both apps are now uploaded to **TestFlight**, so you have two ways to test on a
physical device. TestFlight is the easy one (no cable, installs over the air).

---

## Option A — TestFlight (recommended, wireless)

Status right now:
- **Juicd** — build 2 uploaded, processing in App Store Connect.
- **Velour Closet** — build 2 uploaded, processing in App Store Connect.
- **Corvim** — already on your device; can also be pushed to TestFlight with
  `./archive-and-upload.sh corvim` (note: it needs the Supabase backend live to
  actually function).

Processing takes ~5–30 min. Once a build shows up under **TestFlight** in App
Store Connect, do this **once per app** (all doable from your phone):

1. App Store Connect → your app → **TestFlight** tab.
2. If prompted for **export compliance**, answer the encryption question
   (these apps use only standard HTTPS → "No" / exempt). You can avoid the
   prompt permanently by adding `ITSAppUsesNonExemptEncryption = NO` to each
   app's Info.plist — say the word and I'll add it.
3. Under **Internal Testing**, create a group (e.g. "Me") and add yourself as a
   tester (your Apple ID email). Internal testers don't need Beta App Review.
4. Install **TestFlight** from the App Store on your iPhone, sign in with the
   same Apple ID, and the app appears there to install.

That's it — same experience you'd give beta users later.

## To push a fresh build later

```bash
cd ~/Desktop
./TestFlight/bump-build.sh juicd     # or velour / corvim
./TestFlight/archive-and-upload.sh juicd
```

The build number must increase each upload (the bump script handles it).

---

## Option B — Direct install over USB (fastest for *your* device)

This sideloads a debug build straight from Xcode — no TestFlight, no processing
wait. Good for rapid iteration on your own iPhone.

1. Plug the iPhone into the Mac, unlock it, tap **Trust**.
2. Open the project in Xcode (`Juicd.xcodeproj` / `VelourCloset.xcodeproj`).
3. Top bar: pick your iPhone as the run destination (instead of a simulator).
4. Press **Run** (⌘R). First run: on the phone go to
   **Settings → General → VPN & Device Management** and trust your developer
   cert.

Free/dev-signed installs expire after 7 days and must be re-run; TestFlight
builds last 90 days. For "set it and check it over a week," prefer TestFlight.

---

## How signing works now (why uploads stopped failing)

Your App Store Connect API key has the **App Manager** role. Apple forbids that
role from using Xcode's *cloud-managed* distribution certificate, which is why
the first upload failed with `FORBIDDEN_ERROR`. Workaround now in place:

- An **Apple Distribution certificate** + **App Store provisioning profiles**
  (Velour / Juicd / Corvim) were created through the App Store Connect API and
  installed locally.
- `archive-and-upload.sh` now uses **manual signing** with those assets.
- To rebuild them on a new Mac (or when the cert expires in ~1 year):
  `./TestFlight/make-signing-assets.sh`

No action needed from you for this — it's done.
