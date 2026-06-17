---
date: "2026-06-17"
status: done
implements:
  - FR-RULES-MGMT
  - FR-BROWSER-VISIBILITY
tags:
  - ui
  - settings
  - picker
related_tasks:
  - "[rules-window-redesign-two-pane](./rules-window-redesign-two-pane.md)"
---
# Settings window resize + browser visibility [ANC:task:2026-06-settings-window-browser-visibility]

## Goal

Make the settings (Rules) window comfortable and give the user control over
which browsers appear in the picker. Two pains: the window is fixed-size and
forces the rule list to scroll in a cramped band; and the picker always shows
every real browser with no way to hide ones the user never routes to.

## Overview

### Context

User request: "сделать окно настроек больше (не хочу прокрутку правил) + добавить
выбор браузеров для показа". UX analysis of `RulesView.swift` + `App.swift`
surfaced:
- Window created fixed `500×480`, `styleMask` lacks `.resizable` — user cannot
  enlarge it (`App.swift:107`).
- Rule list double-bounded: `ScrollView` + `.frame(minHeight: 120)` inside the
  fixed window → inner scroll appears past ~6 rules (`RulesView.swift:86-93`).
- No UI to hide browsers from the picker grid; `PickerView` renders all of
  `store.browsers`.

Settled design decisions (user-approved):
- Window: bigger default (~640×620) + `.resizable`; keep inner `ScrollView` only
  as overflow safety (rarely triggers).
- Visibility scope: hidden browsers vanish from the **picker grid + frequency
  order only**; rule-assignment dropdowns still list every installed browser.
- Location: a new "Browsers" section inside the existing settings window.

### Current State

- `App.swift:100-113` `showRules()` — builds the `NSWindow` (fixed size, no
  `.resizable`). `App.swift:115+` picker uses `store.pendingURL`.
- `AppStore.swift` — `browsers: [Browser]` = all real browsers (http∩https),
  sorted by `BrowserRanking.sorted(_, counts: usageCounts)`; `usageCounts`
  persisted under `usage.v1`; `refreshBrowsers()` rebuilds the list.
- `PickerView.swift` — `private var browsers: [Browser] { store.browsers }`
  drives the icon grid + 1–9 keys.
- `RulesView.swift` — header, `rulesSection` (ScrollView), `addRow`, launch-at-
  login toggle.
- `BrowserRanking.swift` — pure sort, unit-tested in `BrowserRankingTests`.

### Constraints

- Public Apple frameworks only; SwiftUI/AppKit; no third-party deps.
- i18n discipline: any new user-facing string → key in all 10 `*.lproj`
  catalogs; browser names stay `Text(verbatim:)` (data, not localized).
- Persistence via `UserDefaults` `Codable`→JSON under a versioned key
  (`hiddenBrowsers.v1`), consistent with `rules.v1` / `usage.v1`.
- Background-agent invariants unchanged (no self-terminate; no focus steal).
- No silent fallback: the picker must never become empty — guard against hiding
  the last visible browser instead of silently re-showing all.

## Definition of Done

- [x] FR-BROWSER-VISIBILITY: add the FR section to SRS with `**Acceptance:**` filled.
  - Test: n/a (doc)
  - Evidence: `grep -q 'FR-BROWSER-VISIBILITY' documents/requirements.md`
- [x] FR-BROWSER-VISIBILITY: the picker grid shows only non-hidden browsers, still ordered by frequency.
  - Test: `Tests/SmartLinksOpenerTests/BrowserVisibilityTests.swift::testHiddenExcludedFromPicker`
  - Evidence: `./build.sh test BrowserVisibilityTests`
- [x] FR-BROWSER-VISIBILITY: hiding is blocked when it would leave zero visible browsers (last-one guard).
  - Test: `Tests/SmartLinksOpenerTests/BrowserVisibilityTests.swift::testCannotHideLastVisible`
  - Evidence: `./build.sh test BrowserVisibilityTests`
- [x] FR-BROWSER-VISIBILITY: hidden set persists across relaunch under `hiddenBrowsers.v1`.
  - Test: `manual — maintainer — toggle a browser off, relaunch, it stays hidden`
  - Evidence: `defaults read dev.korchasa.SmartLinksOpener hiddenBrowsers.v1`
- [x] FR-RULES-MGMT: settings window is resizable and opens larger (≈640×620); ~12 rules fit without scrolling at default size.
  - Test: `manual — maintainer — window shows a resize handle; default size lists ~12 rules without inner scroll`
  - Evidence: `manual — maintainer`
- [x] FR-RULES-MGMT: a "Browsers" section lists every real browser with a show-in-picker toggle reflecting/persisting state.
  - Test: `manual — maintainer — toggling a browser updates the picker on next unmatched link`
  - Evidence: `manual — maintainer`
- [x] FR-I18N: new UI string(s) (e.g. "Browsers", "Show in picker") added to all 10 catalogs.
  - Test: n/a
  - Evidence: `for f in Resources/*.lproj/Localizable.strings; do plutil -lint "$f"; done` all OK

## Solution

Selected approach: single consolidated variant (quick-fix and
architecturally-correct collapse — changes are local, no new layers; the
separate-Preferences-window long-term option was rejected by the user in favour
of an in-window section).

### 1. Pure visibility logic — `Sources/SmartLinksOpener/BrowserVisibility.swift` (new)
- `enum BrowserVisibility` with `// [REF:fr:browser-visibility]`:
  - `static func visible(_ browsers: [Browser], hidden: Set<String>) -> [Browser]` — returns `browsers.filter { !hidden.contains($0.bundleID) }` (order preserved).
  - `static func canHide(_ id: String, hidden: Set<String>, all: [Browser]) -> Bool` — `true` iff `id` is not already hidden AND the count of currently-visible browsers is > 1 (hiding it still leaves ≥1). Protects the picker from going empty.

### 2. State & persistence — `AppStore.swift`
- Add `private let hiddenKey = "hiddenBrowsers.v1"`.
- Add `@Published private(set) var hiddenBrowserIDs: Set<String> = []`.
- `loadHidden()` in `init` (decode JSON `[String]` → `Set`).
- `var pickerBrowsers: [Browser] { BrowserRanking.sorted(BrowserVisibility.visible(browsers, hidden: hiddenBrowserIDs), counts: usageCounts) }` — what the picker renders. `// [REF:fr:browser-visibility]`.
- `func canHideBrowser(_ id: String) -> Bool { BrowserVisibility.canHide(id, hidden: hiddenBrowserIDs, all: browsers) }`.
- `func setBrowserHidden(_ id: String, _ hidden: Bool)` — if hiding, return early when `!canHideBrowser(id)`; mutate `hiddenBrowserIDs`; persist JSON under `hiddenKey`; `objectWillChange` fires via `@Published`.
- `browsers` (all real) is untouched → rule-assignment dropdowns keep listing every installed browser.

### 3. Picker uses visible set — `PickerView.swift`
- Change `private var browsers: [Browser] { store.browsers }` → `{ store.pickerBrowsers }`. Grid, 1–9 keys, frequency order all flow through unchanged.

### 4. Window sizing — `App.swift` `showRules()`
- `window.styleMask = [.titled, .closable, .miniaturizable, .resizable]`.
- `window.minSize = NSSize(width: 480, height: 420)` — keeps the Browsers section from clipping when shrunk.
- `window.setFrameAutosaveName("RulesWindow")` BEFORE sizing; apply the 640×620 default **only when no frame was restored** (e.g. `if !window.setFrameUsingName("RulesWindow") { window.setContentSize(NSSize(width: 640, height: 620)); window.center() }`) so the remembered size is not overwritten on later launches.

### 5. Browsers section — `RulesView.swift`
- New `browsersSection` inserted between `rulesSection` and `addRow`:
  - Header `Text("Browsers").font(.headline)`.
  - For each `store.browsers`: a row with `store.icon(for:)` + `Text(verbatim: browser.name)` + a trailing `Toggle` bound to "shown" (`get: !hidden.contains(id)`, `set: store.setBrowserHidden(id, !$0)`).
  - **Last-one invariant (UI enforcement):** the toggle is `.disabled(isShown && !store.canHideBrowser(id))` — this disabled binding is what actually prevents the picker from going empty (the pure `canHide` is the testable backstop; `setBrowserHidden` also early-returns as defence-in-depth).
  - Keep it compact (`.toggleStyle(.switch)`, `.controlSize(.small)`); with the bigger window it fits without its own scroll for a typical handful of browsers.

### 6. i18n — all 10 `Resources/*.lproj/Localizable.strings`
- Add `"Browsers"` (section header) — required — to en/ru/uk/de/fr/es/it/pt-BR/ja/zh-Hans. Browser names stay `Text(verbatim:)`.
- Add `"Show in picker"` ONLY if a visible label/tooltip is rendered for the toggles; if the switches sit unlabeled beside each browser name, skip this key to avoid needless ×10 i18n surface.
- `CFBundleLocalizations` already lists all 10 languages — no change.

### 7. Tests — `Tests/SmartLinksOpenerTests/BrowserVisibilityTests.swift` (new)
- `testHiddenExcludedFromPicker` — `visible([a,b,c], hidden:["b"])` == `[a,c]`, order preserved.
- `testCannotHideLastVisible` — with 2 browsers and one already hidden, `canHide(remainingID, …)` == `false`; with none hidden, `canHide(anyID, …)` == `true`; `canHide` of an already-hidden id == `false`.

### 8. Docs sync (commit phase)
- SRS: add `### 3.x FR-BROWSER-VISIBILITY … [ANC:fr:browser-visibility]` with `**Acceptance:**` (automated `./build.sh test BrowserVisibilityTests` + manual reviewer); extend FR-RULES-MGMT `**Desc:**` (resizable, larger, Browsers section).
- SDS: §3.1 (window resizable/size + autosave), §3.2 (`hiddenBrowserIDs`, `pickerBrowsers`, `setBrowserHidden`, `canHideBrowser`), §3.3 (picker reads `pickerBrowsers`), new §3.8 BrowserVisibility, §4 Data (`hiddenBrowsers.v1`), §5 Logic (visibility filter + last-one guard).
- `AGENTS.md` Documentation Map: add `BrowserVisibility.swift` + `BrowserVisibilityTests.swift` rows.

### Verification
- `./build.sh test BrowserVisibilityTests` — pure-logic acceptance (RED first).
- `./build.sh check` — build + comment-scan + `swift format --strict` + full suite (now 12 tests).
- `for f in Resources/*.lproj/Localizable.strings; do plutil -lint "$f"; done` — all OK.
- Manual: open settings → window resizes, ~12 rules without scroll; toggle a browser off → next unmatched link's picker omits it; relaunch → choice persisted (`defaults read dev.korchasa.SmartLinksOpener hiddenBrowsers.v1`); cannot disable the last visible browser.

## Follow-ups

None — triage applied 4 refinements inline, deferred 0.

> **Realization note (2026-06-17):** the browser-visibility logic/persistence shipped as planned. The window/UI portion (DoD items: resizable larger window + per-browser show toggles) was ultimately realized via the two-pane redesign (sidebar toggles, 720×560) rather than the inline "Browsers section" / ~640×620 in this plan — see [rules-window-redesign-two-pane](./rules-window-redesign-two-pane.md). Behavior is equivalent; sizes/placement differ.

