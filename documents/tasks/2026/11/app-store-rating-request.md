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
moment that does not interrupt them. Approved by the owner 2026-11-09; the
moment moved from opening to closing the rules window the same day (below).

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

- Revision (owner, 2026-11-09, after the first version `187aec6`): Apple's
  StoreKit guidance says to ask "at a time that doesn't interrupt what someone
  is trying to achieve", "at the end of a sequence of events that they
  successfully complete", to "avoid requesting a review as the result of a
  user action", and to avoid first launch / onboarding. Opening the rules
  window is the user starting a task there, so a sheet on open interrupts it.
  Decision: ask when the user **closes** the rules window, and never on the
  calendar day of the first counted success (first day of use).

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
      1st and 2nd do not; never on the calendar day of the first success (the
      first, not the third; kept across a request; old state without the day
      waits for the next success); never at `.rulesWindowOpened`, only at
      `.rulesWindowClosed`; once requested in a version it is never due again in
      that version, successes in that version do not count, and a later version
      needs 3 new successes; the state survives a JSON round-trip.
  - Test: `Tests/SmartLinksOpenerTests/ReviewPromptTests.swift`
  - Evidence: `deno task test ReviewPromptTests`
- [x] FR-RATING-REQUEST: only a link macOS actually handed to a browser counts
      (completion handler without error); the request is made when the user
      closes Reroute's rules window (`windowShouldClose`) while a request is
      due, never when it opens, never from the picker or a matched link.
  - Test: manual — korchasa
  - Evidence: `grep -n "noteRoutingResult\|takeReviewRequest\|noteRulesWindowOpened\|requestReview" Sources/SmartLinksOpener/*.swift`
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
    attached to the rules window. (Superseded by the close-time walk below.)
- [x] FR-RATING-REQUEST: on the real app, sandboxed as above, the request comes
      on close, not on open, not on the first day of use, once per version.
  - Test: manual — korchasa
  - Evidence: `/usr/bin/log show --info --last 30m --predicate 'subsystem BEGINSWITH "dev.korchasa.SmartLinksOpener" AND category == "review"'`
  - Agent-verified 2026-11-09 on a copy of `deno task dist` named "Reroute
    Walk2" (`dev.korchasa.SmartLinksOpener.walk2`, v1.0.3), signed ad-hoc with
    `Resources/SmartLinksOpener.appstore.entitlements` (`codesign -d
    --entitlements -` → `app-sandbox = true`). Rule `example.com → Safari`
    seeded in the container; links via `open -a <copy> <url>`; window opened by
    reopen, closed by its close button (System Events → `performClose` →
    `windowShouldClose`). Log, category `review`: (1) `routing succeeded:
    1/3…3/3` → `rules window opened, no rating request on open: 3/3, first day
    of use yes` → `rules window closed, no rating request: 3/3, first day of use
    yes`; (2) stored `firstSuccess` moved to the day before → `opened, no rating
    request on open: 3/3, first day of use no` → `closed, rating requested in
    1.0.3`; StoreKit `Starting review request` 9 ms later, `storekitagent`
    `displayMacReviewUI`, `storeuid` ordered the sheet window front 3.5 s after
    the request — the rules window was already gone. Sheet "Enjoying Reroute
    Walk2? Click a star to rate it on the App Store." captured by window id,
    dismissed with "Not Now"; (3) open/close again → `0/3, requested in 1.0.3`,
    no request, no sheet. A repeat of (2) listed the sheet first in front-to-back
    order of all on-screen windows, above another app that was frontmost.
    Finding: `requestReview(in:)` with the closing window's view controller,
    called from `windowShouldClose` before the window orders out, is enough —
    no delay or other view controller needed.
- [x] FR-RATING-REQUEST: SRS, SDS, index and README describe the behaviour.
  - Test: manual — korchasa
  - Evidence: `grep -n "rating-request" documents/requirements.md documents/design.md documents/index.md`
- [x] `deno task check` passes.
  - Test: whole suite
  - Evidence: `CI=1 deno task check`

## Solution

### Moment: when the user closes Reroute's rules window

Revised 2026-11-09 from "when the window opens" (see Context): opening the
window starts a task there, and Apple asks to request at the end of a completed
sequence rather than as the result of a user action. Closing the window is that
end. `windowShouldClose(_:)` fires only for a user close (button, ⌘W), and the
request is made there while the window and its view controller are still on
screen; the sheet is a separate `storeuid` window and appears after the rules
window is gone (verified live). Plus: never on the calendar day of the first
counted success (`ReviewPrompt.firstSuccess`, kept across versions; missing in
older stored state → unknown → set by the next success).

Original reasoning, still valid for rejecting the other moments — chosen over
"right after a picker choice". The picker closes and the chosen
browser is activated in the same instant, so a sheet raised then competes with
the browser for focus and lands over the page the user is about to read — the
intrusive case the brief warns about. A matched link shows no Reroute UI at all,
so there is nothing to attach a sheet to. The rules window is the one place
the user has deliberately turned to Reroute itself, and the sheet has a window
to attach to (`requestReview(in:)` needs a view controller).
Cost: a user who never opens and closes the window is never asked — accepted; a prompt
nobody asked to see is worse than no prompt.

### Rules

- `successes` counts routings macOS confirmed (`NSWorkspace.open` completion
  with no error) since the last request.
- Due ⇔ moment is the rules window closing, `successes ≥ 3`, no request was
  made in the running version, and today is not the calendar day of
  `firstSuccess`.
- When due and the user closes the rules window: request, remember the version,
  reset `successes` to 0. Opening the window only logs the gate.
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
   `noteRoutingResult(failure:)`, which counts a success; `takeReviewRequest() -> Bool`; info-level
   `Logger(subsystem: <bundle id>, category: "review")` lines carrying counts
   and the version only, never a URL.
4. `App.swift`: `AppDelegate` is the rules window's `NSWindowDelegate`;
   `windowShouldClose(_:)` → `store.takeReviewRequest(at: .rulesWindowClosed)`
   → `StoreKit.AppStore.requestReview(in: sender.contentViewController)`;
   `showRules()` → `store.noteRulesWindowOpened()` (log only). Revision: RED
   tests for the first-day rule and `Moment` first, then `firstSuccess`,
   `noteSuccess(version:at:)`, `isDue(at:version:now:calendar:)`.
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
