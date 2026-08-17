---
date: 2026-08-11
status: done
implements:
  - FR-RULES-SEARCH
tags: [ui, rules, i18n]
related_tasks:
  - "[rules-window-redesign-two-pane](../06/rules-window-redesign-two-pane.md)"
---
# Search rules by domain [ANC:task:2026-08-search-rules-by-domain]

## Goal

Find a rule by typing part of its domain. The rules pane lists every rule at a
fixed row height and scrolls; past a few dozen rules, changing or deleting one
means hunting through the list by eye.

## Overview

### Context

`RulesView` rendered `store.rules` straight into a `ForEach`. The pane header
held only the "Routing rules" title, so there was room beside it for a field.

### Solution

A pure filter plus a field bound to it.

- `RuleFilter.matching(_ rules: [Rule], query: String) -> [Rule]` — new file,
  no view involvement, unit-tested. Case- and diacritic-insensitive substring
  match on `domain`; input trimmed; blank query returns the list unchanged;
  order preserved.
- `RulesView.paneHeader` — title + `searchField` (glyph, plain text field,
  clear button that appears once there is text). Rendered only when
  `store.rules` is non-empty: an empty list needs no filter.
- `RulesView.visibleRules` feeds the list; a query that matches nothing shows
  its own line ("No rules match “%@”.") rather than the first-run "no rules
  yet" text — a filtered list must never read as lost data.
- `addRule()` clears the query, so a rule added while a filter is active is
  visible immediately instead of landing outside it.
- Three keys added to all ten `.lproj` catalogs: `Search domains`,
  `Clear search`, `No rules match “%@”.`.

### Decisions

- **Substring, not prefix.** The useful question is "which rule mentions
  github", and rules are stored as registrable domains, so a prefix match would
  miss `gist.github.io`.
- **No URL parsing of the query.** Pasting `https://github.com/x` does not
  reduce to a host; adding that is an unrequested behaviour.
- **Search state is view state.** The query is not persisted and not part of
  `AppStore` — it does not survive closing the window, like any search field.

### Follow-up: the search felt slow, and the list was why

First build stuttered on the first keystroke and again when the field was
cleared. The filter was not the cost. Measured per-row, over 100 rows:

- text only — 25 ms
- text + icon, `NSWorkspace.icon(forFile:)` per render — 66 ms
- text + icon, memoised — 20 ms
- text + browser dropdown — **1249 ms** (≈12 ms per row)

So a `Picker` costs ~50× the rest of a row, and every keystroke re-evaluated
`RulesView`'s body and rebuilt every row, dropdown included. Three changes:

- `AppStore.icon(for:)` memoises by bundle ID. `NSWorkspace.icon(forFile:)`
  returns a fresh `NSImage` each call, which both costs a LaunchServices
  round-trip and denies SwiftUI the identity it needs to skip a row.
- `RuleRow` and `BrowserPicker` extracted from `RulesView` into their own views.
  `RuleRow` stores only its `Rule`, so SwiftUI can skip rows whose rule did not
  change — impossible while the row was built inline in the parent's body.
- The list is a `LazyVStack`, so rows below the fold are not built at all.

Measured on the same offscreen probe, 200 rules, updating an open window:

- narrowing the list to one row: 855 ms → 357 ms
- restoring all 200 rows (clearing the search): **4048 ms → 407 ms**

Full-window render also stopped growing with the rule count — 593/1819/2633/5224
ms at 10/50/100/200 rules before, 521/551/555/562 ms after.

### Follow-up 2: the lazy list moved the cost into scrolling

A lazy list builds a row when it scrolls into view, so a 12 ms row turned an
open-the-window stall into a scrolling stutter. Both symptoms are the same
defect: the row is too expensive, and the dropdown is why. Measured per 20 rows
(one viewport): `Picker` 251.6 ms, `Menu` 85.1 ms, `Menu` with lazily built
items 85.1 ms (so the cost is the control, not its items), a plain label with a
chevron 7.2 ms.

At most one dropdown is ever open, so the rows no longer hold one.
`BrowserMenuButton` draws popup-button chrome — rounded fill, separator border,
`chevron.up.chevron.down` — and opens a real `NSMenu` over itself on click, via
a one-`NSView` `MenuAnchor` for positioning and a `MenuHandler` for the ObjC
target/action pair `NSMenuItem` requires. The add row keeps a real
`BrowserPicker`: there is only one of it.

Measured on the real `RuleRow`, 20 rows: **207.0 ms → 56.6 ms** (10.4 → 2.8 ms
per row). Note this is 3.7×, not the 35× the isolated control measurement
suggested — the rest of the row (icon, domain, delete button, store
subscription) is unchanged and now dominates. A very fast scroll revealing ~10
rows in one frame can still cost ~28 ms; if that shows, the next candidates are
the per-row `MenuHandler` and `MenuAnchor` allocations, removable by opening the
menu at the click point instead of over the control.

## Verification

- `deno task test RuleFilterTests` — 5 cases (blank query, substring anywhere,
  case + spaces, order preserved, no match).
- `deno task check` — green (format, lint, build, 25 tests, bundle).
- Manual — offscreen render of the rules window with a seeded query showed the
  list filtered to the single matching rule; the running app filters live.
