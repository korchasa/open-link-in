---
date: 2026-09-10
status: canceled
implements: []
tags: [accessibility, ui, macos]
related_tasks:
  - "[always-ask-rule-mode](always-ask-rule-mode.md)"
---
# System text size [ANC:task:2026-09-system-text-size]

## Goal

Make the app's text follow the size the user picks in System Settings →
Accessibility → Display → Text size, so someone who needs larger text gets it in
the picker and in the rules window.

Canceled on 2026-09-10: macOS offers no way for an app like this one to read that
setting. Nothing was changed in the app.

## Overview

### Where the question came from

A screen walk before the 1.0.2 release rendered every screen twice, once at the
default text size and once at an accessibility size. The two sets came out
identical: the picker was the same to the pixel, the rules window differed by 751
pixels out of 2.4 million. Every font in `PickerView`, `RulesView` and `App.swift`
is declared as `.system(size:)` with a constant — 31 declarations — so the obvious
reading was "the app hardcodes its sizes, switch to text styles and it will
scale".

That reading is wrong. Text styles do not scale on macOS either.

### What was measured

Two independent probes on macOS 26.6.2, both rendering the string "Always ask":

- `NSHostingView.fittingSize` and `ImageRenderer` agree that `.font(.body)`
  measures 67×16 points at every `DynamicTypeSize` from `.large` through
  `.accessibility5`. The measurement is sensitive — `.system(size: 26)` gives 125
  points wide and `.caption2` gives 55 — so the constant result is the answer, not
  a broken probe.
- `@ScaledMetric(relativeTo: .body)` returns its base value unchanged at
  `.accessibility5`.
- `NSFont.preferredFont(forTextStyle: .body).pointSize` is 13 whatever
  `UIPreferredContentSizeCategoryName` says, even when the process reads the
  overridden category back correctly.

### What Apple says

- The SwiftUI documentation for `EnvironmentValues.dynamicTypeSize`: "On macOS,
  this value cannot be changed by users and does not affect the text size."
  <https://developer.apple.com/documentation/swiftui/environmentvalues/dynamictypesize>
- Apple's developer support answered the same question for macOS 26 in March
  2026: "Dynamic Type is a system-level feature for iOS, iPadOS, tvOS, visionOS,
  and watchOS." macOS is not in that list, and no notification or accessor for the
  Text size slider was named.
  <https://developer.apple.com/forums/thread/818858>
- The Text size sheet in System Settings describes itself as being for "supported
  apps and system features", and no `Info.plist` key, entitlement or API puts an
  app into that list.
  <https://developer.apple.com/forums/thread/771719>

The `preferredFontForTextStyle(_:options:)` options dictionary, which would be the
natural hook, has no option keys declared in the macOS 26 SDK.

## Decision

Not implemented. The fixed `.system(size:)` declarations stay as they are: they
are not the reason large text does nothing, and replacing them with `.body` or
`.headline` would change no pixel while making every size harder to see in the
source.

The only way to give a user larger text here is a size control of the app's own —
which is what the system sheet means by its "Customized in App" label. That is a
new feature with its own settings surface, layout work (the picker is a fixed 320
points wide and would have to grow with the text) and its own screen walk. The
owner declined it on 2026-09-10; the app stays as it is.

## Verification

No code changed, so nothing to verify. The probes live outside the repository;
re-running them is three files and a `swift` invocation, described above in enough
detail to rebuild.

## Revisit when

Apple opens the Text size list to third-party apps, or ships a public accessor for
the preferred reading size. Until then the answer for this app is unchanged, and a
future session should not spend the investigation again.
