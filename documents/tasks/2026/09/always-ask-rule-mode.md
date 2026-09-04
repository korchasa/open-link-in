---
date: 2026-09-04
status: done
implements:
  - FR-ALWAYS-ASK
tags: [rules, picker, i18n]
related_tasks:
  - "[search-rules-by-domain](../08/search-rules-by-domain.md)"
---
# Always-ask rule mode [ANC:task:2026-09-always-ask-rule-mode]

## Goal

Let a domain be marked "ask me every time": every link to it raises the picker,
and the pick is never remembered. Before this, a rule could only name a browser,
and the picker's default action created a rule — so a site the owner opens in
different browsers depending on the moment had no place to live.

## Overview

### Context

`Rule` was `domain → bundleID`; `AppStore.matchingBrowser` returned a browser or
nothing; the picker defaulted to "open & remember" with ⇧ for a one-time open.

### Constraints

Stored rules (`rules.v1`) must keep working; no third-party code; ten `.lproj`
catalogs get every new key.

## Definition of Done

- [x] FR-ALWAYS-ASK: an ask rule raises the picker, longest match across modes, no browser needed, legacy JSON decodes as open
  - Test: `Tests/SmartLinksOpenerTests/RoutingTests.swift::*`
  - Evidence: `deno task test RoutingTests`
- [x] FR-ALWAYS-ASK: dropdowns offer "Always ask"; picker shows the always-ask header and no ⇧ hint; the pick does not change the rule
  - Test: manual — maintainer — walked in light + dark (see Verification)
  - Evidence: `deno task check`

## Solution

Decisions taken with the owner (1A, 2A, 3A):

- **Model.** `Rule.mode: RuleMode` (`open` | `ask`), decoded as `open` when absent, so `rules.v1` needs no migration. `RuleTarget` (`browser(id)` | `ask`) is what the UI controls hand to the store.
- **Where it is set.** Rules window only: `BrowserMenuButton` (rule row) and `BrowserPicker` (add row) end with a separator + "Always ask". An ask row shows a question-mark glyph instead of a browser icon.
- **Picker behaviour.** `Routing.decide` (new pure file) returns `.open` / `.ask` / `.unmatched`; `.ask` goes down the existing unmatched path into the queue. `PickerView` reads `store.alwaysAsks(url)`: one-time mode, header "Choose for this link — this site always asks", footer "change this in Routing rules", ⇧ ignored. `AppStore.choose` additionally refuses to remember for such a URL, so the rule cannot be replaced by accident.
- **Strings.** Three keys in all ten catalogs.
