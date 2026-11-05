---
date: 2026-11-05
status: in progress
implements:
  - FR-PICKER
tags: [picker, bug]
related_tasks: []
---
# Close an abandoned picker [ANC:task:2026-11-close-abandoned-picker]

## Goal

The browser picker must never hang on screen after the user walks away from it.
Today a picker the user ignored stays up forever with the old link, and every
later link — even one a rule routes — shows up under that stale panel. The owner
hits this in daily use.

## Overview

### Context

Owner's report (2026-11-05, translated): the picker window gets stuck at some
point and keeps showing; it shows even when a route exists, because it was left
hanging from an earlier time.

Diagnosis (same day): the picker closes on exactly three paths — a browser is
chosen, Esc, or ✕ (`AppStore.advanceQueue`, reached from `choose` and
`cancelPending`). Nothing reacts to the user leaving it. A probe app built with
the same panel recipe (`PickerPanel(contentViewController:)`, borderless +
`.nonactivatingPanel`, `.floating`) stayed visible after another app was
activated, so the system does not hide it either. Once abandoned, the panel
floats above every app, keystrokes go elsewhere (Esc is dead), and the link stays
at the head of `pendingURLs` forever: a matched link opens under the stale panel,
an unmatched one queues behind it as "+1".

Rejected while discussing: dismissing on focus loss (resign key / app
deactivation). It cancels the wrong link when the chosen browser takes focus
while the next queued link is shown, never fires when the panel did not get focus
in the first place, and drops a link on a click into Reroute's own menu or rules
window — exactly where the always-ask hint sends the user.

### Current State

- `AppStore.handleIncoming`: matched → `open`; unmatched → append to
  `pendingURLs`, `onShowPicker` only when the queue was empty.
- `AppStore.advanceQueue`: pops the head, shows the next or closes.
- `AppDelegate.showPicker` / `closePicker`: one `PickerPanel` at a time, 0.2 s
  alpha fades.
- `PickerView`: `KeyCatcher` maps keys to `KeyCommand`; no activity reporting.
- Tests cover pure helpers only (`PickerKeys`, `BrowserRanking`, `Routing`…);
  `AppStore` is an AppKit-bound singleton with no tests.

### Constraints

- Public Apple APIs only, no dependencies (AGENTS.md).
- Matched links must still open without Reroute stealing focus.
- A burst of links arriving together still queues while the picker is in use
  ([REF:fr:picker]). An abandoned picker drops its whole queue, unseen links
  included — the owner's choice of 2026-11-05, which narrows FR-PICKER's
  "never dropped"; the SRS text changes with it.
- No new UI strings expected; if one appears, all ten `.lproj` catalogs get it.

### Affected Surface

Scout report (surface-scout, verbatim):

````text
## Surface

Repo: /Users/korchasa/www/factory/projects/open-link-in. Top-level: Sources, Tests, Resources, documents, scripts, README.md, CONTRIBUTING.md, PRIVACY.md, AGENTS.md/CLAUDE.md, deno.json, Package.swift. There is also a prebuilt `SmartLinksOpener.app`, which is a build artifact.

**Primary code: the picker window lifecycle**
- `Sources/SmartLinksOpener/App.swift` 66, 139-165 (`showPicker`) — creates a borderless, `.nonactivatingPanel`, `.floating` `PickerPanel`. It stores the panel in `pickerWindow`. There is no timer, no resign-key or app-deactivation observer, and no auto-dismiss. A panel that loses focus, sits on another Space or screen, or is hidden behind something stays alive until a user action closes it. This is the most likely home of the stuck window, and also where any "close after N minutes" timer would be installed.
- `App.swift` 183-192 (`closePicker`) — the only place that closes the panel. It sets `pickerWindow = nil` immediately, then fades the panel out and calls `orderOut` in the completion handler. If the animation completion never fires, or `pickerWindow` was already overwritten, the panel stays on screen as an orphan with no reference.
- `App.swift` 140-141 — `showPicker` calls `closePicker()` first, then builds a new panel. The old panel is only faded out asynchronously, so the old and new panels overlap during the fade. Rapid calls can leave an orphan.
- `App.swift` 140 — `guard let url = store.pendingURL else { return }` returns early without closing an existing panel. An empty queue with a visible panel is therefore not reconciled.
- `App.swift` 196-199 (`PickerPanel`) — `canBecomeKey` and `canBecomeMain` are true. A non-activating panel without a key window does not receive Esc, so the user may be unable to cancel from the keyboard once focus is gone.
- `App.swift` 83-85 — wiring of `onShowPicker` and `onClosePicker`, which are the only two entry points (`store.onShowPicker` and `store.onClosePicker`).
- `Sources/SmartLinksOpener/AppStore.swift` 24-26, 287-318 — the pending-link queue and its operations:
  - `pendingURLs` is the FIFO queue.
  - `handleIncoming` raises the picker only when the queue was empty. If the queue is non-empty but the panel is lost or stale, new unmatched links are appended and the picker is never re-raised. The picker stays "stuck" and invisible, or visible forever.
  - `advanceQueue` shows the next queued URL without re-evaluating `matchingBrowser`/`decision(for:)`. After the user remembers a rule for domain X, other queued X links, and the panel still showing X, are still presented as unmatched. This matches "route exists but picker still shows".
  - `cancelPending` / `choose` are the only pop paths. A timeout would need to call one of them, or a new path, to clear the queue.
  - Lines 253-270 (`decision(for:)`, `matchingBrowser`, `alwaysAsks`) — the routing check that is bypassed for already-queued URLs.
  - Lines 275-282 (`open`) — `activates = true` and the `recordUse` side effect. A timeout that auto-closes without choosing must not call this.
- `Sources/SmartLinksOpener/PickerView.swift`:
  - 106, 225, 230 — `store.choose` call sites.
  - 211-233 (`handle`) — Esc triggers `store.cancelPending()`. There is a `.topTrailing` ✕ button near line 159. All of these are the only user-driven dismissals.
  - 180 — the "+N" queue badge reads `pendingCount`.
  - 28-30, 84 — always-ask mode.
  - Lines 255-291 (`KeyCatcher`) — keystrokes arrive only while the panel is key and first responder. This is the same Esc dependency as above.
- `Sources/SmartLinksOpener/Routing.swift` — pure decision logic (`.open` / `.ask` / unmatched). Not a source of the bug, but a recheck at dismissal time would use it.

**Documentation that describes this behaviour**
- `documents/requirements.md` — FR-PICKER at 37-40, FR-ALWAYS-ASK at 58-61, FR-FILE-OPEN at 26-28, and the background-agent FR around 73. A new timeout or auto-dismiss requirement needs an SRS entry with an `**Acceptance:**` line. The workflow rule is SRS, then SDS, then code.
- `documents/design.md` — 3.1 App shell at 26-27 (lists `showPicker`/`closePicker`/`PickerPanel`), the AppStore section at 31-32 (queue, `advanceQueue`), 3.3 picker view at 35-37, and the Queue and Rules lines at 105-107. Any lifecycle change must be reflected here.
- `documents/index.md` — navigation aggregator. It may need a new entry if a task file is added.
- `documents/tasks/2026/...` — new task file needed per the repo convention. Related existing tasks: `09/always-ask-rule-mode.md` and `06/route-local-html-files.md`. They are precedent, not edit targets.
- `README.md` — 124 mentions `PickerView.swift`; check whether the behaviour description needs updating.

**Tests**
- `Tests/SmartLinksOpenerTests/` — `PickerKeysTests`, `RoutingTests`, `LinkLabelTests`, `BrowserRankingTests`, `BrowserVisibilityTests`. No test exists for the queue or the panel lifecycle, because `design.md` 113 says the AppKit-bound store is not tested. A pure timeout or expiry policy would need a new pure type plus a test. The test runner is `deno task test`, defined in `scripts/test.ts`.

**Parallel or sibling implementations and not-affected places**
- `Sources/SmartLinksOpener/Snapshot.swift` 114-142 — a second `NSWindow` use (offscreen screenshot, `orderOut` at the end). Not affected; it is a separate code path that exits the process.
- `App.swift` 118-137 (`showRules` / `rulesWindow`) — the rules window is a separate on-demand `NSWindow` with the same "window is kept in a property" pattern. It is not stuck-prone, because it is a normal titled window with `isReleasedWhenClosed = false`. Not affected, but it is the sibling of the code in question.
- `App.swift` 105-107 — `applicationShouldHandleReopen` calls `showRules`. This is unrelated to the picker.
- `Sources/SmartLinksOpener/Models.swift`, `Domain.swift`, `LinkLabel.swift`, `BrowserRanking.swift`, `BrowserVisibility.swift`, `MenuBarIcon.swift`, `Motion.swift`, `RulesView.swift`, `RuleFilter.swift` — not affected by this request, but `Motion.swift` was not opened. It may hold the animation constants that `closePicker` uses.
- `Resources/*.lproj/Localizable.strings` (10 locales) — affected only if the user-visible picker text changes, for example an "expires" hint. Not needed for a silent auto-close.
- `scripts/*` and `deno.json` — build tooling; not affected, apart from the test and check tasks that must be run for verification.
- The factory hub (`/Users/korchasa/www/factory`) — `apps.yml` and `APPS.md` hold store state only. Per the hub rules, no bug fix touches them unless a release is made. Release is out of scope here.

**Consumers and producers of the data**
- Producers of `pendingURLs`: `handleGetURL` (Apple Event `kAEGetURL`) at App.swift 77-82, and `application(_:open:)` at App.swift 90-92 for local files. Both feed `store.handleIncoming`.
- Consumers: `PickerView`, via `pendingURL` and `pendingCount`, and `showPicker`.

## Queries used
- `ls`, `git ls-files` for the tree.
- grep for `NSPanel|NSWindow|orderOut|makeKey|isVisible|close(|pickerWindow|showPicker|resignKey|hidesOnDeactivate|didResign|Timer|asyncAfter|Task.sleep|activate` in the Sources files.
- grep for `pending|onShowPicker|onDismiss|dismiss|choose|ask` in AppStore, PickerView and Routing.
- grep for `picker|dismiss|hang|stuck` in the docs and README.
- Read App.swift 55-199, AppStore.swift 270-330, PickerView.swift 95-130 and 205-291, and Snapshot.swift 100-144.

## Not examined (budget)
- `Motion.swift` and `Models.swift` contents.
- The full PickerView body, lines 1-95 and 130-205.
- Tests file contents.
- `.github/workflows/ci.yml`.
- CONTRIBUTING.md.
- The prebuilt `SmartLinksOpener.app`.
- No runtime reproduction was done.

## Could not rule out
- The panel orphaned by overlapping `showPicker`/`closePicker` calls. During the 0.2 s fade the old panel is still on screen with `pickerWindow` already nil, so nothing can close it afterwards if its completion handler is lost.
- The panel living on another Space or display, or hidden when the app is deactivated. A `.nonactivatingPanel` at `.floating` level may behave differently across fullscreen Spaces. There is no `collectionBehavior` set on the panel.
- `pendingURLs` left non-empty by some path that never pops. `handleIncoming` then never re-raises the picker, and the user sees a stale panel or none at all.
- A timer-based auto-close (the user's second clarification turn) interacts with the queue. It must decide whether to drop only the current link or the whole queue, and whether it counts from `showPicker` or from the last user interaction. It must also reset when `advanceQueue` shows the next link. A queued link dropped silently is lost, because the user's link never opens.
- The risk of a stale-state mismatch: a timer fired after `closePicker` already ran, or one tied to a replaced panel.
````

Dispositions (union of the scout's list and own enumeration):

- `App.swift` `showPicker` (no auto-dismiss) — covered-by Solution step 3 (expiry + displacement call the existing `onClosePicker`/`onShowPicker`); DoD 1–3.
- `App.swift` `closePicker` orphan risk (fade completion lost / overlapping calls) — deferred — human choice; unverified either way (the agent's probe is not kept in the repo), see Follow-ups.
- `pendingURLs` left non-empty by a path that never pops (scout) — covered-by Solution step 3: expiry is a pop path that needs no user action, so a non-empty queue empties within 60 s of inactivity.
- Stale timer after `closePicker` / tied to a replaced head (scout) — covered-by Solution step 3 (`expiryTask` cancelled on every reschedule and on an empty queue; `guard !Task.isCancelled`).
- Drop current vs whole queue; clock from show vs last interaction (scout) — covered-by Solution "Rules" (whole queue, owner's answer; clock from last activity).
- `App.swift` `showPicker` early return on empty queue — not affected — `pendingURL` is nil only after `advanceQueue` already called `onClosePicker` (`AppStore.swift` `advanceQueue`).
- `App.swift` `PickerPanel` key/Esc dependency — covered-by DoD 1 (an unfocused panel still expires; it no longer needs Esc).
- `App.swift` 83-85 callback wiring — covered-by Solution step 3 (same two callbacks, no new entry points).
- `AppStore.swift` `pendingURLs` / `handleIncoming` — covered-by DoD 2–3.
- `AppStore.swift` `advanceQueue` shows queued links without re-checking rules — covered-by Solution steps 1 and 3 (`advance(now:isRouted:)`); DoD 2.
- `AppStore.swift` `cancelPending` / `choose` pop paths — covered-by DoD 1–3 (expiry and displacement are new pop paths).
- `AppStore.swift` `decision(for:)` / `matchingBrowser` / `alwaysAsks` — covered-by DoD 2 (used for the displacement decision); unchanged.
- `AppStore.swift` `open` (`activates`, `recordUse`) — not affected — expiry/displacement never call it for the dropped link; matched link keeps today's call.
- `PickerView.swift` `store.choose` call sites, ✕, Esc — not affected — behaviour unchanged.
- `PickerView.swift` `handle` / `KeyCatcher` — covered-by DoD 1 (key commands report activity so an active picker does not expire).
- `PickerView.swift` "+N" badge — not affected — still reads `pendingCount`.
- `PickerView.swift` always-ask mode — not affected — always-ask links queue and expire like any other.
- `Routing.swift` — not affected — pure decision reused as is.
- `documents/requirements.md` FR-PICKER — covered-by DoD 5.
- `documents/requirements.md` FR-ALWAYS-ASK, FR-FILE-OPEN, FR-BACKGROUND-AGENT — not affected — their text says nothing about dismissal (`requirements.md` 26-28, 58-61, ~73).
- `documents/design.md` 3.1, 3.2, 3.3, §5 Queue line, §7 test-coverage line — covered-by DoD 5.
- `documents/index.md` — covered-by Solution step 5 (FR-PICKER row).
- `documents/tasks/2026/09/always-ask-rule-mode.md`, `06/route-local-html-files.md` — not affected — precedent only.
- `README.md` 124 — not affected — names the file in a layout list, no behaviour text (checked in commit phase doc sync).
- `Tests/SmartLinksOpenerTests/` — covered-by DoD 1–3 (new `PickerQueueTests`).
- `Snapshot.swift` 114-142 — not affected — builds `PickerView(url:)` / `PickerView(url:shiftHeld:)` (`Snapshot.swift` 46, 68); the init is unchanged.
- `App.swift` `showRules` / `rulesWindow`, `applicationShouldHandleReopen` — not affected — separate window.
- `Models.swift`, `Domain.swift`, `LinkLabel.swift`, `BrowserRanking.swift`, `BrowserVisibility.swift`, `MenuBarIcon.swift`, `RulesView.swift`, `RuleFilter.swift` — not affected — no queue or panel code (read during diagnosis).
- `Motion.swift` — not affected — holds SwiftUI spring presets only; `closePicker` uses a literal 0.2 s.
- `Resources/*.lproj/Localizable.strings` — not affected — no new visible text planned.
- `scripts/*`, `deno.json` — not affected — used for verification only.
- Panel on another Space / fullscreen, no `collectionBehavior` — covered-by DoD 1 (the timer closes it wherever it sits).
- Factory hub `apps.yml` / `APPS.md` — not affected — no release in scope.

## Definition of Done

- [x] FR-PICKER: an ignored picker closes by itself; it never stays on screen
      indefinitely.
  - Test: `Tests/SmartLinksOpenerTests/PickerQueueTests.swift` (expiry cases)
  - Evidence: `deno task test PickerQueueTests`
- [x] FR-PICKER: a link that a rule routes opens without a stale picker left on
      screen.
  - Test: `Tests/SmartLinksOpenerTests/PickerQueueTests.swift` (displacement by
    a matched link)
  - Evidence: `deno task test PickerQueueTests`
- [x] FR-PICKER: a new unmatched link after an abandoned picker shows its own
      picker, not the old link with "+1"; a burst of links still queues.
  - Test: `Tests/SmartLinksOpenerTests/PickerQueueTests.swift` (displacement by
    an unmatched link, burst stays queued)
  - Evidence: `deno task test PickerQueueTests`
- [ ] FR-PICKER: the three cases above behave on the real app (Reroute Dev):
      ignored picker closes; matched link after an abandoned picker opens with
      no panel left; unmatched link after an abandoned picker shows its own
      picker, no "+1"; burst of 2 links still queues; choosing with remember
      opens a queued link of the same site without a picker.
  - Test: manual — korchasa
  - Evidence: `deno task prod` then `open -a "Reroute Dev" <url>` walk
  - Agent-verified 2026-11-05 on Reroute Dev (window list via
    `CGWindowListCopyWindowInfo`): untouched picker gone ~60 s after the link;
    link after 4 s → new panel id (displaced); link 1.2 s later → same panel
    (queued). Second pass: matched link 5.5 s after an unmatched one → no
    panel left; burst of 2 → screenshot shows "+1" in the footer. Both passes
    confounded by the owner's live desktop: probe panels became key and one got
    a Return/1 from another app (stray rule `reroute-probe-a.invalid` appeared;
    removed). Owner still to walk: choose-with-remember opening a queued
    same-site link (needs real key input; not injected into the owner's screen).
- [x] FR-PICKER: a shown or queued link whose site gains a rule in the rules
      window opens by itself and the picker moves on.
  - Test: `Tests/SmartLinksOpenerTests/PickerQueueTests.swift` (reroute cases)
  - Evidence: `deno task test PickerQueueTests`
- [x] FR-PICKER: SRS FR-PICKER and SDS picker/queue sections describe the
      abandonment rules; FR-PICKER no longer promises an unconditional "never
      dropped".
  - Test: manual — korchasa
  - Evidence: `grep -n "abandon" documents/requirements.md documents/design.md`
    lists both files, and `grep -n "never dropped\|not dropped"
    documents/requirements.md` shows only the in-use qualified wording
- [x] `deno task check` passes.
  - Test: whole suite
  - Evidence: `deno task check`

## Solution

Selected 2026-11-05: idle timer + displacement by a new link + re-check of the
queue against rules (variant B); an abandoned picker drops the **whole** queue.
The 60 s and 3 s thresholds were stated in the option the owner picked.
Rejected: timer only (leaves the stale panel for up to 60 s), click-outside
dismissal (needs a global mouse monitor whose App Sandbox status is unverified).

### Rules

- Head activity clock: `lastActivity` = moment the head was shown (first link
  into an empty queue, `advance`, `reroute`) or the last sign of the user at the
  picker: a key/⇧ event or the mouse over the panel (hover, scroll, drag).
- **Abandoned**: queue non-empty and `now − lastActivity ≥ 3 s`.
- **Expired**: queue non-empty and `now − lastActivity ≥ 60 s` → whole queue
  dropped, panel closed. Nothing opens.
- **Unmatched arrival**: abandoned → drop whole queue, the new link becomes the
  head and its picker shows. Not abandoned (burst, or user active) → append
  behind the head, as today.
- **Matched arrival**: abandoned → drop whole queue and close the panel, then
  open as today. Not abandoned → open as today, queue untouched.
- **Advance** (choose / Esc / ✕): pop the head, then remove every remaining
  link a rule now routes and open each silently; the next unrouted link becomes
  the head with a fresh clock, or the panel closes.
- **Rules change** (rule added or re-pointed from the rules window): every
  queued link a rule now routes — the head included — opens silently and leaves
  the queue; a new head gets a fresh clock, an empty queue closes the panel; an
  unchanged head counts the change as activity. `choose` stores its rule
  without this pass, then advances, so the chosen link opens once.
- Clock = `Date()` (wall time). The wait between checks uses
  `Task.sleep(for:)` on `ContinuousClock`, which keeps counting while the Mac
  sleeps, so a panel left before sleep closes right after wake.

### Steps

1. `Sources/SmartLinksOpener/PickerQueue.swift` (new) — pure `struct
   PickerQueue` (Foundation only), `// [REF:fr:picker]`:
   - `static let abandonAfter: TimeInterval = 3`, `static let idleTimeout:
     TimeInterval = 60`.
   - `private(set) var urls: [URL]`, `private(set) var lastActivity: Date?`;
     `head`, `count`.
   - `enum Arrival { case showHead, queued }`;
     `mutating func enqueue(_:now:) -> Arrival` (drops an abandoned queue first).
   - `mutating func dropIfAbandoned(now:) -> Bool`.
   - `mutating func noteActivity(now:)` (no-op on an empty queue).
   - `mutating func reroute(now:isRouted:) -> [URL]` — removes every routed
     link (head included) and returns them in queue order; fresh clock when the
     head changed, activity otherwise.
   - `mutating func advance(now:isRouted:) -> [URL]` — pops the head, then
     `reroute`.
   - `func secondsUntilExpiry(now:) -> TimeInterval?` (nil when empty, ≥ 0).
   - `mutating func expireIfIdle(now:) -> Bool`.
2. `Tests/SmartLinksOpenerTests/PickerQueueTests.swift` (new, written first —
   RED): first link shows; burst within 3 s queues; link after an abandoned
   head replaces the whole queue; activity keeps the head alive; matched link
   drops an abandoned queue but not an active one; expiry at 60 s, not 59 s;
   activity postpones expiry; `secondsUntilExpiry` nil/remaining; advance
   restarts the clock; advance returns queued links that gained a rule and skips
   them as head; reroute opens a shown head that gained a rule and refreshes
   the clock when the head stays.
3. `Sources/SmartLinksOpener/AppStore.swift` — replace `pendingURLs` with
   a plain `private var queue = PickerQueue()` plus `@Published private(set)
   var pendingURL` / `pendingCount`, assigned only when their value changes, so
   mouse-move activity does not re-render the picker (public surface
   unchanged). Rule writes split: private `storeRule(domain:target:)` (no
   reroute) used by `choose`; public `addRule(domain:target:)` and
   `updateRule(_:target:)` store, then reroute the queue (`deleteRule` cannot
   route anything and does not). `handleIncoming`, `advanceQueue`
   follow the rules above; new `func notePickerActivity()`; private
   `expiryTask: Task<Void, Never>?` + `scheduleExpiryCheck()` (cancel previous,
   `try? await Task.sleep(for:)` then `guard !Task.isCancelled` — `try?`
   swallows the cancellation, so the guard is what stops a replaced timer —
   then `expireIfIdle` → `onClosePicker`, else reschedule) started whenever a head is shown, cancelled when the queue
   empties.
4. `Sources/SmartLinksOpener/PickerView.swift` — `handle(_:)` calls
   `store.notePickerActivity()` for every `KeyCommand`; the panel root gets
   `.onContinuousHover` (macOS 13+) calling it on `.active`. `Snapshot.swift` builds
   `PickerView(url:)` and needs no change.
5. Docs: SRS FR-PICKER `Desc` + `Scenario` + `Acceptance` (add
   `deno task test PickerQueueTests`; replace "never dropped" / "queued, not
   dropped" with the in-use vs abandoned rule) + `**Tasks:**` back-pointer; SDS §3.2
   interfaces, new §3.12 `PickerQueue`, §5 Queue line, §7 test-coverage line;
   `documents/index.md` row for FR-PICKER.
6. Verify: `deno task test PickerQueueTests`, `deno task check` (also rebuilds
   and relaunches Reroute Dev), then the manual walk on Reroute Dev from DoD 4.

### Error handling

No new failure paths: the queue is in-memory, the timer task is cancelled on
every reschedule, and a cancelled sleep exits without touching state.

## Follow-ups

- Orphaned panel on overlapping `showPicker`/`closePicker` (scout, "could not rule out"): no evidence it happens; revisit if a panel survives an expiry.
- Panel `collectionBehavior` across Spaces / fullscreen: not set; the timer closes the panel wherever it sits, so not needed for this fix.
- Picker takes keyboard focus from the app the user types in (`showPicker` calls `NSApp.activate(ignoringOtherApps:)` + `makeKeyAndOrderFront`, by keyboard-first design): a Return or digit meant for that app picks a browser and may create a rule. Seen 2026-11-05 during probes. Pre-existing, outside this fix; product decision.
