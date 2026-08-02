---
date: 2026-08-02
status: done
implements:
  - FR-DIST.MAS
tags: [ci-cd, app-store, distribution]
related_tasks:
  - "[appstore-cicd-setup](../06/appstore-cicd-setup.md)"
---
# Drop the App Store release path from CI

## Goal

Every store release is prepared and shipped outside this repository. This repo
must not be able to upload anything to App Store Connect, and must not hold or
reference any signing material or store credential.

## Overview

### Context

`.github/workflows/release.yml` ("Release to App Store") ran on a `v*` tag:
imported signing certificates into a temporary keychain, built a sandboxed
bundle, signed a `.pkg` with `productbuild` and uploaded it with
`xcrun altool --upload-app`. It read 11 GitHub repository secrets.

That path was already dead. Commit `0b8ba1b` replaced the `build.sh appstore`
target with `dist`, which assembles an **unsigned** bundle for signing
elsewhere, but `release.yml` still called `./build.sh appstore` — a subcommand
that no longer exists. A tag push produced a failing run, not a release. Live
docs (README, AGENTS.md, SRS, SDS) still promised the tag-ships-to-the-store
story and still named the removed `appstore` target.

### Current State

- `.github/workflows/ci.yml` — `./build.sh check` on push to `main` and on PRs.
  Untouched by this task; it uses none of the release secrets.
- `./build.sh dist` — unsigned `.build/dist/SmartLinksOpener.app`.
- `./build.sh prod` — Developer ID / ad-hoc build for open-source distribution.

### Constraints

- No tags created or pushed; no workflow triggered.
- `ci.yml`, bundle ids, version numbers, entitlements and signing config
  untouched.
- Historical task files keep their wording, including the names they mention.
  Only frontmatter may change on them.
- The repository names no external release system. Statements are impersonal:
  signing, packaging and upload happen outside this repository.

## Definition of Done

- [x] FR-DIST.MAS: no workflow here can reach App Store Connect, and `ci.yml` is
      unchanged. Guards the invariant (no upload step, no store credential), not
      the filename — an unrelated future workflow must not fail this.
  - Evidence: `test ! -e .github/workflows/release.yml && ! grep -rqE "altool|upload-app|ASC_|APP_STORE_CONNECT" .github/workflows/ && test -z "$(git diff HEAD -- .github/workflows/ci.yml)"`
- [x] FR-DIST.MAS: `./build.sh dist` still produces the App Store-ready unsigned
      bundle (binary + compiled asset catalog) and the sandbox entitlement stays
      declared.
  - Test: `documents/requirements.md` FR-DIST.MAS acceptance
  - Evidence: `./build.sh dist && test -x .build/dist/SmartLinksOpener.app/Contents/MacOS/SmartLinksOpener && test -f .build/dist/SmartLinksOpener.app/Contents/Resources/Assets.car && /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' Resources/SmartLinksOpener.appstore.entitlements | grep -q true`
- [x] FR-DIST.MAS: live docs and scripts no longer describe a release pipeline
      here. The one-time cleanup that removed the external system's name from
      `build.sh` (3 occurrences) is not re-checked mechanically — spelling the
      name in a guard command would reintroduce it.
  - Evidence: `! git grep -nE "altool|upload-app|release\.yml|build\.sh appstore" -- ':!documents/tasks'`
- [x] FR-DIST.MAS: the verification gate is green.
  - Evidence: `./build.sh check`

## Solution

1. `git rm .github/workflows/release.yml`.
2. README — replace the top note about tag-triggered releases with a statement
   that this repo only runs checks; replace the manual `productbuild`/`altool`
   recipe with `./build.sh dist` and the note that signing and upload happen
   outside; rename the `appstore` build config to `dist`.
3. AGENTS.md — "Two distributions" now describes `dist` as unsigned-only and
   states that this repo has no release pipeline; add `dist` to the command
   list.
4. SRS FR-DIST.MAS — description, scenario and a runnable acceptance built on
   `dist` plus the entitlement check; upload and pricing recorded as a manual
   maintainer step performed outside the repository.
5. SDS §7 — same for the Distribution and App icon notes (`dist` compiles the
   asset catalog instead of copying the `.icns`).
6. `build.sh` — comments and the final `echo` state impersonally that signing
   and packaging happen outside this repository.
7. Mark `appstore-cicd-setup` superseded (frontmatter only; body verbatim).

## Follow-up for the maintainer (not automatable)

These 11 GitHub repository secrets are now unused by every workflow and can be
deleted in Settings → Secrets and variables → Actions:

- `DIST_CERT_P12_BASE64`, `DIST_CERT_PASSWORD`
- `INSTALLER_CERT_P12_BASE64`, `INSTALLER_CERT_PASSWORD`
- `PROVISION_PROFILE_BASE64`
- `MAS_APP_IDENTITY`, `MAS_INSTALLER_IDENTITY`
- `KEYCHAIN_PASSWORD`
- `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`
