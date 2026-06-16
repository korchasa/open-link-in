---
date: 2026-06-16
status: done
tags: [init, brownfield]
---
# Init Context — Smart Links Opener

## Goal

Capture the discovered state of the project at agent-documentation init time, so future sessions start from an accurate baseline.

## Overview

### Context

Brownfield init via `flowai:init`. Existing native macOS app, no prior agent docs. README summary: a minimalist macOS app that acts as the default web browser and routes links to a per-domain browser; shows a picker over installed browsers (with optional rule creation) when no rule matches. Background menu-bar agent (`LSUIElement`), SwiftUI/AppKit, public Apple APIs only, automatic i18n (10 languages), no third-party deps.

### Current State

Discovered source layout (excluding `.build/` and the generated `SmartLinksOpener.app/`):

```
Package.swift
build.sh                      # standard interface: check/test/dev/prod/fmt
README.md
AGENTS.md  +  CLAUDE.md -> AGENTS.md
Sources/SmartLinksOpener/
  App.swift                   # @main + MenuBarExtra + AppDelegate (Apple Event, windows)
  AppStore.swift              # @MainActor store: rules, matching, routing, default-browser, login item
  PickerView.swift            # browser picker for unmatched links
  RulesView.swift             # rules management window
  Models.swift                # Rule, Browser
Resources/
  Info.plist                  # CFBundleURLTypes http/https, LSUIElement, CFBundleLocalizations
  SmartLinksOpener.entitlements
  {en,ru,uk,de,fr,es,it,pt-BR,ja,zh-Hans}.lproj/Localizable.strings
documents/
  requirements.md (SRS), design.md (SDS), tasks/
```

- Stack: Swift 6.3 toolchain, macOS 13+, Swift Package Manager (executable target), zero deps.
- Storage: `UserDefaults` key `rules.v1` (JSON). Window frame auto-persisted by AppKit.
- Tooling present: `swift format` (Apple 6.3), `codesign`, `lsregister`. `swiftformat` (Homebrew) also installed but unused.
- No `Tests/` target yet.

### Constraints

- Public Apple APIs only; no App Sandbox (router launches arbitrary browsers); Developer ID + notarization for distribution.
- Background agent must never self-terminate after routing; matched links must not steal focus.
- i18n: English base keys; all UI strings mirrored across every `*.lproj` + `CFBundleLocalizations`.

## Definition of Done

- [x] Root `AGENTS.md` generated with project rules, architecture, key decisions, doc map, dev commands.
  - Evidence: `test -f AGENTS.md`
- [x] `CLAUDE.md` relative symlink → `AGENTS.md`.
  - Evidence: `test "$(readlink CLAUDE.md)" = AGENTS.md`
- [x] SRS + SDS populated from actual project data.
  - Evidence: `test -f documents/requirements.md && test -f documents/design.md`
- [x] Standard command interface added to `build.sh` (`check`/`test`/`dev`/`prod`/`fmt`).
  - Evidence: `./build.sh check`

## Solution

Brownfield discovery (no interview). Inferred architecture and decisions from `Package.swift`, `README.md`, `Info.plist`, and `Sources/`. Extended the existing `build.sh` (per user choice) with the standard interface rather than adding a Makefile. Devcontainer declined (macOS-native GUI build). No legacy three-file layout to collapse.
