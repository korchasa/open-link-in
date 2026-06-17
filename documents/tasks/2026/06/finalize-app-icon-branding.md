---
date: 2026-06-18
status: done
implements:
  - FR-APP-ICON
tags: [branding, icon, appstore]
---
# Finalize app icon & menu-bar branding [ANC:task:2026-06-finalize-app-icon-branding]

## Goal

Replace the generated placeholder app icon with the final brand art, make the
`.icns` reproducible from committed source, render the brand icon in the menu
bar, and commit the App Store screenshots referenced by the listing. Removes the
"placeholder — replace before release" caveat blocking a polished release / MAS
upload.

## Overview

### Context

Final artwork was delivered in `/Users/korchasa/Downloads/appstore/`:
`AppIcon.svg` (vector source), `AppIcon-1024.png` (App Store master),
`AppIcon.appiconset/` (10 sized PNGs + Contents.json, Xcode naming), `icons/`
(flat duplicates), and `screenshot-1..3.png` (1280×800 App Store shots).

`documents/design.md` §7 states: "App icon (`Resources/AppIcon.icns`) is a
generated placeholder — replace with final art before release."
`appstore-cicd-setup.md` §A and `appstore-listing.md` both depend on a real
1024 icon + screenshots before the first MAS upload.

### Current State

- `Resources/AppIcon.icns` (961 KB placeholder) is the ONLY icon artefact in the
  repo — no source PNG/SVG, so it cannot be regenerated.
- `build.sh prod`/`appstore` copy `Resources/AppIcon.icns` into the bundle;
  `Resources/Info.plist` sets `CFBundleIconFile`/`CFBundleIconName` = `AppIcon`.
- `Sources/SmartLinksOpener/App.swift` menu bar uses `systemImage:
  "link.circle.fill"` (a system glyph, not the brand icon).
- `appstore-listing.md` "Screenshots" section says only "capture from the
  running app" — no committed assets.
- Dry-run confirmed `iconutil -c icns Resources/AppIcon.iconset` from the
  delivered PNGs yields a valid `.icns` with the required 1024 (512@2x) rep.

### Constraints

- Public Apple frameworks only (AppKit `NSImage`). No third-party deps.
- Menu-bar image is the user-chosen full-color brand icon (NON-template), not a
  monochrome glyph — accept it won't auto-tint to light/dark.
- Source assets live under `Resources/` (icns reproducible) + screenshots under
  `documents/assets/appstore/`. The `.iconset/` dir MUST NOT land in the bundle
  (build.sh copies only `*.lproj` + `AppIcon.icns`).
- swift-format strict + comment-scan must stay green.

## Definition of Done

- [x] FR-APP-ICON: brand `.icns` reproducible from committed source, carries the
      1024px App Store rep, bundled by `build.sh`.
  - Test: `./build.sh icon` regenerates `Resources/AppIcon.icns` from
    `Resources/AppIcon.iconset/`.
  - Evidence: `./build.sh icon && iconutil -c iconset Resources/AppIcon.icns -o /tmp/i.iconset && sips -g pixelWidth /tmp/i.iconset/icon_512x512@2x.png | grep -q 1024`
- [x] FR-APP-ICON: brand icon rendered in the menu bar (full-color, fixed size).
  - Test: `Tests/SmartLinksOpenerTests/MenuBarIconTests.swift::testRenderProducesFixedPointSize`
  - Evidence: `./build.sh test MenuBarIconTests`
- [x] FR-APP-ICON: source + listing collateral committed (SVG, 1024 master,
      iconset, screenshots) and `appstore-listing.md` references the screenshots.
  - Test: file existence.
  - Evidence: `test -f Resources/AppIcon-1024.png && test -f documents/assets/appstore/screenshot-1.png && grep -q 'assets/appstore' documents/appstore-listing.md`

## Solution

Selected approach (user-confirmed across 3 axes: menu-bar usage = YES, commit
full source = YES, commit+link screenshots = YES).

1. **Import assets**
   - Copy delivered PNGs (Xcode `icon_*` names) → `Resources/AppIcon.iconset/`.
   - Copy `AppIcon.svg` → `Resources/AppIcon.svg`; `AppIcon-1024.png` →
     `Resources/AppIcon-1024.png`.
   - Copy `screenshot-1..3.png` → `documents/assets/appstore/`.
2. **Regenerate icns** via new `build.sh icon` subcommand:
   `iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns`.
   Overwrites the placeholder. Add `icon` to the `case` dispatcher + usage line.
3. **Menu-bar rendering** — new `Sources/SmartLinksOpener/MenuBarIcon.swift`:
   - `enum MenuBarIcon`: `pointSize = 18`; `render(from: NSImage) -> NSImage`
     (pure: rescale to pointSize², `isTemplate = false`); `statusItem()`
     sources `NSImage(named: .applicationIconName)` with a system-symbol
     fallback, then `render`.
   - `App.swift`: switch `MenuBarExtra(_:systemImage:content:)` →
     `MenuBarExtra(content:label:)` with
     `Image(nsImage: MenuBarIcon.statusItem()).renderingMode(.original)` +
     `.accessibilityLabel`.
4. **Tests (RED first)** — `Tests/SmartLinksOpenerTests/MenuBarIconTests.swift`:
   `testRenderProducesFixedPointSize` (size == pointSize²),
   `testRenderKeepsFullColorNotTemplate` (`isTemplate == false`).
5. **Docs**: add FR-APP-ICON to SRS (+ `**Tasks:**` back-pointer); update
   design.md §3 (menu-bar) + §7 (drop placeholder caveat, document icon
   pipeline + MenuBarIcon); index.md FR row; appstore-listing.md screenshot
   refs; CLAUDE.md Documentation Map (new files).
6. **Verify**: `./build.sh check` green; `./build.sh icon` + sips evidence;
   `./build.sh prod` bundles the new icns.

### Error handling

`statusItem()` degrades to a system symbol when no app icon resolves (e.g.
`swift run` without a bundle); never returns nil. `render` is total over any
non-nil `NSImage`.
