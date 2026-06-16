---
date: 2026-06-16
status: in progress
implements:
  - FR-DIST.MAS
tags: [ci-cd, app-store, signing, onboarding]
---
# App Store release via CI/CD — guided setup

## Goal

One-time setup so that pushing a `vX.Y.Z` tag builds the sandboxed app, signs it,
and uploads it to App Store Connect automatically (GitHub Actions). After this,
releasing = `git tag v1.0.1 && git push --tags`.

## What CI already does (in the repo)

- `.github/workflows/ci.yml` — runs `./build.sh check` on every push/PR.
- `.github/workflows/release.yml` — on a `v*` tag: imports certs → builds
  `./build.sh appstore` (sandboxed, `CFBundleVersion = run number`) → `productbuild`
  signed `.pkg` → uploads via `xcrun altool` with an App Store Connect API key.
- All signing material comes from **GitHub repository secrets** (below). Nothing
  secret is committed.

## Prerequisites (one-time, in YOUR Apple account)

Everything in this section can only be done by the account holder. Follow in order.
Replace `<NAME>` / `<TEAMID>` with your values; bundle ID is
`dev.korchasa.SmartLinksOpener`.

### A. App icon (App Store requires one)
The app currently has no icon; App Store validation needs a 1024×1024 icon. Add
`Resources/AppIcon.icns` (or an asset catalog) and reference it via
`CFBundleIconFile` before the first upload. (Tracked separately — not blocking the
pipeline wiring.)

### B. Apple Developer portal — https://developer.apple.com/account
1. **Identifiers → +** → App IDs → App → Description "Smart Links Opener",
   Bundle ID **explicit** `dev.korchasa.SmartLinksOpener`. No extra capabilities.
2. **Certificates → +**, create two (easiest from Xcode → Settings → Accounts →
   your team → Manage Certificates → + ):
   - **Apple Distribution** (signs the app)
   - **Mac Installer Distribution** (signs the `.pkg`)
3. **Profiles → +** → **Mac App Store** distribution → select the App ID and the
   Apple Distribution cert → download `SmartLinksOpener_MAS.provisionprofile`.

### C. Export the two certs as .p12 (from Keychain Access)
For each cert: find it in Keychain Access → login → My Certificates → right-click →
**Export** → `.p12` → set a password. You get `dist.p12` and `installer.p12`.

Find the exact identity strings (you'll need them as secrets):
```bash
security find-identity -v | grep -E "Apple Distribution|Mac Installer Distribution"
# e.g. "Apple Distribution: Your Name (TEAMID)"
#      "Mac Installer Distribution: Your Name (TEAMID)"
```

### D. App Store Connect — https://appstoreconnect.apple.com
1. **My Apps → + → New App** → macOS → bundle ID `dev.korchasa.SmartLinksOpener`,
   name "Smart Links Opener", category **Utilities**.
2. **Pricing and Availability** → price ≈ **$2.99 / €3.49** (closest tier to $3).
3. **App Privacy** → **Data Not Collected**.
4. **Users and Access → Integrations → App Store Connect API → +** → role
   **App Manager** → download `AuthKey_XXXXXX.p8` (**downloadable once!**). Note the
   **Key ID** and the **Issuer ID** (top of that page).

## Wire up GitHub secrets

From the repo root, with the GitHub CLI authenticated (`gh auth login`):

```bash
# certificates (base64-encoded .p12) + their export passwords
gh secret set DIST_CERT_P12_BASE64      < <(base64 -i dist.p12)
gh secret set DIST_CERT_PASSWORD        --body 'P12_PASSWORD'
gh secret set INSTALLER_CERT_P12_BASE64 < <(base64 -i installer.p12)
gh secret set INSTALLER_CERT_PASSWORD   --body 'P12_PASSWORD'

# provisioning profile (base64)
gh secret set PROVISION_PROFILE_BASE64  < <(base64 -i SmartLinksOpener_MAS.provisionprofile)

# signing identity names (exact strings from step C)
gh secret set MAS_APP_IDENTITY          --body 'Apple Distribution: <NAME> (<TEAMID>)'
gh secret set MAS_INSTALLER_IDENTITY    --body 'Mac Installer Distribution: <NAME> (<TEAMID>)'

# temporary keychain password (any random string)
gh secret set KEYCHAIN_PASSWORD         --body "$(openssl rand -base64 24)"

# App Store Connect API key (base64 .p8) + identifiers
gh secret set ASC_KEY_P8_BASE64         < <(base64 -i AuthKey_XXXXXX.p8)
gh secret set ASC_KEY_ID                --body 'XXXXXX'
gh secret set ASC_ISSUER_ID             --body '00000000-0000-0000-0000-000000000000'
```

Verify:
```bash
gh secret list   # expect all 11 names above
```

After setting secrets, **delete the local .p12 / .p8 / .provisionprofile files** —
they are sensitive and are already gitignored.

## Release

```bash
git tag v1.0.0
git push origin v1.0.0      # triggers release.yml → uploads the build
```
Then in App Store Connect: attach the uploaded build to the version, add screenshots
+ description, and **Submit for Review**. On approval it goes live at the set price.

Subsequent releases: bump the tag (`v1.0.1`, …) — `CFBundleVersion` auto-increments
from the CI run number.

## Definition of Done

- [x] FR-DIST.MAS: CI + release workflows present and YAML-valid.
  - Evidence: `python3 -c "import yaml;yaml.safe_load(open('.github/workflows/release.yml'))"`
- [ ] FR-DIST.MAS: secrets configured; a tag push uploads a build to App Store Connect.
  - Evidence: `manual — maintainer — gh secret list shows 11 secrets; release.yml run succeeds`
- [ ] FR-DIST.MAS: app priced ~$3 and submitted for review.
  - Evidence: `manual — maintainer — App Store Connect`

## Secrets reference (11)

- `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`
- `INSTALLER_CERT_P12_BASE64`, `INSTALLER_CERT_PASSWORD`
- `PROVISION_PROFILE_BASE64`
- `MAS_APP_IDENTITY`, `MAS_INSTALLER_IDENTITY`
- `KEYCHAIN_PASSWORD`
- `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`
