---
date: 2026-11-09
status: done
implements:
  - FR-RATING-REQUEST
tags: [store, rating]
related_tasks:
  - "[close-abandoned-picker](close-abandoned-picker.md)"
---
# Ask for an App Store rating after real use [ANC:task:2026-11-app-store-rating-request]

## Goal

Reroute sells in the Mac App Store and has almost no ratings. Ask macOS for a
rating once the user has seen the app do its job, with Apple's own prompt, at a
moment that does not interrupt them. Approved by the owner 2026-11-09.

## Overview

### Context

- Owner's brief (2026-11-09): after a **successful** routing — a link actually
  handed to a browser — on the 3rd success, ask with the system API. Never at
  first launch, never after a failed or cancelled routing (abandoned picker,
  Esc, ✕, expiry). Persist the count in `UserDefaults`; at most one request per
  app version (`CFBundleShortVersionString`); a later version needs 3 new
  successes. Apple caps the prompt at 3 per year; no custom "rate us" UI.
- Reroute works in the background: a matched link opens with no Reroute UI,
  and a picker choice hands focus to the chosen browser (`OpenConfiguration.activates
  = true`). A sheet raised at that moment would land over the browser the user
  just switched to.
- API: `StoreKit.AppStore.requestReview(in: NSViewController)` (macOS 13+, the
  deployment target). `SKStoreReviewController.requestReview()` is deprecated
  since macOS 15 ("Use AppStore.requestReview(in:)", `SKStoreReviewController.h`
  in the macOS 27.2 SDK). The app's own type is also called `AppStore`, so the
  call is spelled `StoreKit.AppStore`.

### Current State

- `AppStore.open(_:in:)` is the single place a link goes to a browser: matched
  links (`handleIncoming`), picker choices (`choose`) and queued links a new rule
  covers (`openRouted`). It passes `completionHandler: nil`, so a failed open is
  invisible.
- Cancelled/abandoned/expired pickers never reach `open` (`cancelPending`,
  `PickerQueue.dropIfAbandoned`, `expireIfIdle`).
- `AppDelegate.showRules()` is the only path to Reroute's own window (menu
  "Rules…", Finder/Dock reopen); it builds an `NSHostingController` once and
  re-shows it.
- No logging anywhere (SDS §6 "No logging/telemetry").

### Constraints

- Public Apple APIs only, no dependencies (AGENTS.md). StoreKit is a system
  framework.
- No new UI strings (the sheet is the system's) → no `.lproj` changes.
- No new entitlement: the review request needs none, sandboxed or not.
- No version bump; 1.0.4 is held by the owner.

### Affected Surface

- `Sources/SmartLinksOpener/ReviewPrompt.swift` (new) — pure gate.
- `Tests/SmartLinksOpenerTests/ReviewPromptTests.swift` (new) — acceptance.
- `AppStore.swift` `open(_:in:)` — count on the completion handler's success;
  new `takeReviewRequest()`; persistence key `reviewPrompt.v1`; `os.Logger`.
- `App.swift` `showRules()` — the request site.
- Not affected: `PickerView` (calls `choose`/`cancelPending` as before),
  `PickerQueue` (drop paths never call `open`), `Snapshot.swift` (exits before
  any routing), `Resources/*.lproj`, entitlements, `Info.plist`.
- Docs: SRS new FR-RATING-REQUEST, SDS §3.1/§3.2/new §3.13/§4/§5/§6,
  `documents/index.md`, README layout list.

## Definition of Done

- [x] FR-RATING-REQUEST: the 3rd successful routing makes a request due; the
      1st and 2nd do not; once requested in a version it is never due again in
      that version, successes in that version do not count, and a later version
      needs 3 new successes; the state survives a JSON round-trip.
  - Test: `Tests/SmartLinksOpenerTests/ReviewPromptTests.swift`
  - Evidence: `deno task test ReviewPromptTests`
- [x] FR-RATING-REQUEST: only a link macOS actually handed to a browser counts
      (completion handler without error); the request is made when Reroute's
      own rules window opens while a request is due, never from the picker or a
      matched link.
  - Test: manual — korchasa
  - Evidence: `grep -n "noteRoutingSuccess\|takeReviewRequest\|requestReview" Sources/SmartLinksOpener/*.swift`
- [x] FR-RATING-REQUEST: on the real app, signed ad-hoc with the App Store
      entitlements (sandboxed), 3 routed links each followed by opening the
      rules window: no request after the 1st and 2nd, a request after the 3rd.
  - Test: manual — korchasa
  - Evidence: `/usr/bin/log show --info --last 30m --predicate 'subsystem BEGINSWITH "dev.korchasa.SmartLinksOpener"'`
  - Agent-verified 2026-11-09 on a scratch copy of `deno task dist` renamed to
    "Reroute Walk" (`dev.korchasa.SmartLinksOpener.walk`, v1.0.3), signed
    `codesign --options runtime --entitlements Resources/SmartLinksOpener.appstore.entitlements -s -`
    (`codesign -d --entitlements -` → `com.apple.security.app-sandbox = true`;
    container created). One seeded rule `example.com → Safari`; links sent with
    `open -a <copy> https://example.com/?reroute-walk=N`, rules window via a
    reopen (`open -a <copy>`). Log, category `review`: rules window at launch
    `0/3`; `routing succeeded: 1/3` → rules `no rating request: 1/3`; `2/3` →
    `no rating request: 2/3`; `3/3` → `rating requested in 1.0.3`; rules again
    → `no rating request: 0/3, requested in 1.0.3`. `storeuid` started 0.3 s
    after the request (20:01:58) and drew the system sheet "Enjoying Reroute
    Walk? Click a star to rate it on the App Store." with five stars and "Not
    Now" — captured by window id; dismissed with "Not Now". No `storeuid`
    process before the 3rd. The sheet is a separate system window, not
    attached to the rules window.
- [x] FR-RATING-REQUEST: SRS, SDS, index and README describe the behaviour.
  - Test: manual — korchasa
  - Evidence: `grep -n "rating-request" documents/requirements.md documents/design.md documents/index.md`
- [x] `deno task check` passes.
  - Test: whole suite
  - Evidence: `CI=1 deno task check`

## Solution

### Moment: when the user opens Reroute's rules window

Chosen over "right after a picker choice". The picker closes and the chosen
browser is activated in the same instant, so a sheet raised then competes with
the browser for focus and lands over the page the user is about to read — the
intrusive case the brief warns about. A matched link shows no Reroute UI at all,
so there is nothing to attach a sheet to. The rules window is the one moment
the user has deliberately turned to Reroute itself, the app is active, and the
sheet has a window to sit on (`requestReview(in:)` needs a view controller).
Cost: a user who never reopens the window is never asked — accepted; a prompt
nobody asked to see is worse than no prompt.

### Rules

- `successes` counts routings macOS confirmed (`NSWorkspace.open` completion
  with no error) since the last request.
- Due ⇔ `successes ≥ 3` and no request was made in the running version.
- When due and the rules window opens: request, remember the version, reset
  `successes` to 0.
- While the running version has already been asked, successes are not counted,
  so the next version starts from 0 and needs 3 of its own.
- Whether macOS draws the sheet is its decision (3 per 365 days, user setting);
  the app records the request either way and never retries in that version.

### Steps

1. RED: `ReviewPromptTests` — none due at start, not after 1 and 2, due after 3;
   once requested not due again in that version and later successes in that
   version do not count; next version due after 3 new successes, not 2; Codable
   round-trip.
2. GREEN: `ReviewPrompt.swift` — `struct ReviewPrompt: Codable, Equatable`,
   `threshold = 3`, `successes`, `requestedVersion`, `noteSuccess(version:)`,
   `isDue(version:)`, `markRequested(version:)`.
3. `AppStore.swift`: load/save `reviewPrompt.v1` (JSON, like `usage.v1`);
   `open` passes a completion handler that hops to the main actor and calls
   `noteRoutingSuccess()` on success; `takeReviewRequest() -> Bool`; info-level
   `Logger(subsystem: <bundle id>, category: "review")` lines carrying counts
   and the version only, never a URL.
4. `App.swift` `showRules()`: after `makeKeyAndOrderFront`, if
   `store.takeReviewRequest()` → `StoreKit.AppStore.requestReview(in: host)`.
5. Docs (SRS → SDS → index, README).
6. Verify: `deno task test`, `CI=1 deno task check` (CI skips the reinstall of
   the owner's Reroute Dev), real-app walk on a scratch copy signed ad-hoc with
   `Resources/SmartLinksOpener.appstore.entitlements` under its own bundle id.

## Follow-ups

- The sheet drew for an ad-hoc signed copy; a store-signed build was not
  walked. On the store build Apple's 3-per-year cap and the user's "In-App
  Ratings & Reviews" setting decide.
- `PRIVACY.md` says the app stores "only your routing rules … and window
  position"; it already omits usage counts and hidden browsers, and now the
  rating counter. Public text — owner's call.
