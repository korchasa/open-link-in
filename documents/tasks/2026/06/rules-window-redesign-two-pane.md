---
date: 2026-06-17
status: done
implements:
  - FR-RULES-MGMT
tags: [ui, redesign]
---
# Rules window redesign — two-pane (Claude Design "Variant 2") [ANC:task:2026-06-rules-window-redesign-two-pane]

## Goal

Give routing rules the screen space they deserve. The old single-column window
cramped rules into a tiny scroll area while the browser list dominated. The
maintainer mocked up a redesign in Claude Design and handed it off for build.

## Overview

### Context

Handoff bundle from claude.ai/design (`Smart Links Opener - Redesign.dc.html` +
chat transcript). The user iterated to a single chosen direction ("Variant 2"):
browsers as a left sidebar of availability toggles, rules across the full right
pane. Explicit decisions from the chat: keep the default-browser check + "Make
default" button; drop any "everything else → Safari" notion; drop the refresh
button; placeholder is just `github.com` (no "e.g.").

### Current State (before)

`RulesView.swift` — one `VStack`: header (title + default-browser control
top-right), rules `ScrollView`, browsers section with toggles, add row, launch
checkbox. Window default 640×620.

### Constraints

- Native macOS, public APIs, zero deps (project rules).
- i18n: English `LocalizedStringKey` base; data values (`domain`, browser names)
  via `Text(verbatim:)`; every UI key in all 10 `.lproj` catalogs.
- AppStore API consumed as-is; no model changes.

## Definition of Done

- [x] FR-RULES-MGMT: two-pane layout — sidebar (brand, browser toggles, launch
  checkbox) + rules pane (title, default banner, column header, rule list,
  pinned add row); add/change/delete still work and persist.
  - Test: `manual — maintainer — open window; add/change/delete a rule; toggle a
    browser; verify persistence across relaunch`
  - Evidence: `NO_COLOR=1 ./build.sh check` (build + lint + 12 tests green)
- [x] Rule/add browser dropdowns offer only enabled (non-hidden) browsers; a
  rule pointing at a hidden/uninstalled browser keeps showing its target.
  - Test: `Tests/SmartLinksOpenerTests/BrowserVisibilityTests.swift` (visible-set
    logic the dropdowns consume via `store.pickerBrowsers`)
  - Evidence: `NO_COLOR=1 ./build.sh test BrowserVisibilityTests`
- [x] Default-browser status as a prominent banner (amber + "Make default" when
  not default; green confirmation when default). [REF:fr:default-browser]
  - Test: `manual — maintainer — banner state flips after Make default`
- [x] i18n parity: 8 new keys added, 4 unused removed, all 10 catalogs lint and
  hold the same 28 keys.
  - Evidence: `for f in Resources/*.lproj/Localizable.strings; do plutil -lint "$f"; done`

## Solution

- `RulesView.swift` rewritten as `HStack { sidebar | Divider | rulesPane }`.
  - Sidebar (236pt): `brandHeader` (gradient link tile + wordmark),
    `sectionLabel("Browsers")`, `browserList` (icon + name + `.switch` toggle,
    last-visible hide blocked via `store.canHideBrowser`), `sidebarFooter`
    (hint + launch-at-login `.checkbox`).
  - Rules pane: "Routing rules" title, `defaultBrowserBanner`, `columnHeader`
    (Domain / Open in), `rulesList` (browser-icon + domain + `browserPicker` +
    trash), pinned `addRow` (domain `TextField` with verbatim `github.com`
    prompt + `browserPicker` + Add).
  - `browserPicker(selection:currentID:)` lists `store.pickerBrowsers`, appending
    the current target if it is hidden/unknown so a selection is never lost.
- `App.swift`: window default 720×560, min 560×420.
- Localization: removed `Route links by domain`, `Rules`, `Refresh browser list`,
  `domain, e.g. github.com`; added `Routing rules`, `Domain`, `Open in`,
  `Make default`, `Default browser in the system`, `Not the system default
  browser`, `Rules apply only when macOS hands links to this app.`, `Disabled
  browsers aren't offered in rules.` across all 10 catalogs.
- Docs: SDS §3.4 updated to describe the two-pane structure.
