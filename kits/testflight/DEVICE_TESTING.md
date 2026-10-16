# Getting your app onto a real iPhone

Two ways to test on a physical device. TestFlight is the easy one (no cable,
installs over the air).

---

## Option A — TestFlight (recommended, wireless)

```bash
./kits/testflight/bump-build.sh <app-key>
./kits/testflight/archive-and-upload.sh <app-key> --dry-run   # check config first
./kits/testflight/archive-and-upload.sh <app-key>
```

Processing takes ~5–30 min. Once a build shows up under **TestFlight** in App
Store Connect, do this **once per app**:

1. App Store Connect → your app → **TestFlight** tab.
2. If prompted for **export compliance**, answer the encryption question. Avoid
   the prompt permanently by adding `ITSAppUsesNonExemptEncryption = NO` to the
   app's Info.plist (only if that is true for your app).
3. Under **Internal Testing**, create a group and add yourself as a tester.
   Internal testers don't need Beta App Review.
4. Install **TestFlight** on your iPhone, sign in with the same Apple ID, and
   install the app.

`post-upload.sh` (run automatically after each upload) attaches new builds to
internal groups. External groups are attached only if you list them in
`EXTERNAL_BETA_GROUP_IDS` for that app — see [README.md](README.md).

The build number must increase each upload (`bump-build.sh` handles it).

---

## Option B — Direct install over USB (fastest for *your* device)

1. Plug the iPhone in, unlock it, tap **Trust**.
2. Open the project in Xcode (`ExampleApp.xcodeproj`).
3. Pick your iPhone as the run destination.
4. Press **Run** (⌘R). First run: on the phone go to
   **Settings → General → VPN & Device Management** and trust your developer cert.

Dev-signed installs from a free account expire after 7 days; TestFlight builds
last 90 days.

---

## Signing with an "App Manager" API key

Apple does not let an **App Manager** API key use Xcode's *cloud-managed*
distribution certificate (`FORBIDDEN_ERROR` on export). `make-signing-assets.sh`
works around this: it creates an **Apple Distribution certificate** and **App
Store provisioning profiles** for every app in your registry through the App
Store Connect API and installs them locally. `archive-and-upload.sh` then uses
**manual signing** with those assets. Re-run it on a new Mac or when the cert
expires.
