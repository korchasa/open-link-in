---
date: 2026-06-16
status: in progress
implements:
  - FR-DIST
  - FR-DIST.MAS
tags: [distribution, licensing, app-store, open-source]
---
# Open source + paid Mac App Store build

## Goal

Ship the project as open source (GPL-3.0-or-later) while selling the official,
notarized, sandboxed build on the Mac App Store for a small price (~$3 / €3) as a
convenience + funding channel. The author is the sole copyright holder, so the
owner-exception lets the paid App Store build coexist with the GPL source.

## Overview

### Context

- Source: public repo under **GPL-3.0-or-later** (`LICENSE`, `CONTRIBUTING.md` CLA
  grants the maintainer the extra right to ship contributions in the proprietary
  App Store build).
- Two build configs in `build.sh`:
  - `prod` → Developer ID + Hardened Runtime, **no sandbox** (DMG/zip outside MAS).
  - `appstore` → **App Sandbox** enabled (`Resources/SmartLinksOpener.appstore.entitlements`).
- Feasibility verified locally: the sandboxed build launches, a sandbox container
  is created at `~/Library/Containers/dev.korchasa.SmartLinksOpener`, browser
  enumeration + picker work under the sandbox. Precedent: Velja (a browser picker)
  ships sandboxed on the Mac App Store.

### Current State

- Bundle ID: `dev.korchasa.SmartLinksOpener` (`Resources/Info.plist`).
- Sandbox entitlements ready; ad-hoc sandbox build proven to run.
- Needs a paid **Apple Developer Program** membership ($99/yr) — available.

### Constraints

- GPL is incompatible with Apple's MAS terms → only the copyright holder may
  upload; third-party forks cannot use MAS (fine, by design).
- App Sandbox is mandatory for MAS. Do not request entitlements the app does not
  use (currently only `com.apple.security.app-sandbox`).
- Each upload needs a unique, increasing `CFBundleVersion`.

## Definition of Done

- [x] FR-DIST: GPL `LICENSE` + open-source repo scaffolding present.
  - Evidence: `test -f LICENSE && head -1 LICENSE | grep -q 'GNU GENERAL PUBLIC LICENSE'`
- [x] FR-DIST.MAS: sandboxed build produces a running app under App Sandbox.
  - Evidence: `./build.sh appstore && codesign -d --entitlements - SmartLinksOpener-AppStore.app 2>&1 | grep -q app-sandbox`
- [ ] FR-DIST.MAS: app uploaded to App Store Connect and priced at the ~$3 tier.
  - Evidence: `manual — maintainer — build visible in App Store Connect, price tier set`

## Solution — submission playbook (maintainer, requires Apple account)

### 1. Apple Developer setup (developer.apple.com)
1. Ensure Apple Developer Program membership is active.
2. Certificates → create **Apple Distribution** and **Mac Installer Distribution**
   certs (Xcode can auto-manage these).
3. Identifiers → register an App ID matching `dev.korchasa.SmartLinksOpener`
   (explicit, not wildcard). No special capabilities needed.
4. Profiles → create a **Mac App Store** provisioning profile for that App ID;
   download as `SmartLinksOpener_MAS.provisionprofile`.

### 2. App Store Connect record (appstoreconnect.apple.com)
1. My Apps → **+** → New App → macOS → pick the bundle ID, name "Smart Links
   Opener", primary language, category **Utilities**.
2. Pricing and Availability → set price to the ~$3 tier (US $2.99 ≈ €3.49;
   exact EUR per Apple's current price matrix). Pick territories.
3. App Privacy → **Data Not Collected** (the app collects/transmits nothing).
4. App Review notes: explain it is a default-browser router that opens links in
   the user-chosen browser (precedent: Velja). Provide a demo rule + test link.
5. Add screenshots (rules window + picker) and a description.

### 3. Build, package, upload
```bash
# bump CFBundleVersion in Resources/Info.plist before each upload
MAS_APP_IDENTITY="Apple Distribution: <NAME> (<TEAMID>)" \
MAS_PROVISION_PROFILE=./SmartLinksOpener_MAS.provisionprofile \
  ./build.sh appstore

productbuild --component SmartLinksOpener-AppStore.app /Applications \
    --sign "3rd Party Mac Developer Installer: <NAME> (<TEAMID>)" \
    SmartLinksOpener.pkg

# upload (App Store Connect API key, or use Transporter.app GUI)
xcrun altool --upload-app -f SmartLinksOpener.pkg -t macos \
    --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```
> If `altool`/`productbuild` signing is fiddly, the most reliable path is to wrap
> the SPM target in a thin Xcode project and use Xcode → Product → Archive →
> Distribute App → App Store Connect, which manages signing/profiles automatically.

### 4. Submit for review
1. In App Store Connect, attach the uploaded build to the version.
2. Submit for review; respond to any reviewer questions using the notes above.
3. On approval, release. Price (~$3) is already set in step 2.

### Notes / risks
- Sandbox edge case to confirm during review/testing: opening a URL in a *specific*
  browser via `NSWorkspace.open(_:withApplicationAt:)` under sandbox. Enumeration +
  picker are verified; the open call relies on LaunchServices and matches Velja's
  approach, but test on the real signed build.
- The sandboxed build stores rules in its container, separate from the open-source
  Developer ID build — expected.
