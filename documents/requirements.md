# SRS

## 1. Intro
- **Desc:** Smart Links Opener — macOS default-browser agent that routes web links to a browser chosen per domain; offers a picker + rule creation when no rule matches.
- **Def/Abbr:** FR = functional requirement; rule = domain→browser mapping; agent = background `LSUIElement` app; bundleID = app bundle identifier.

## 2. General
- **Context:** Native macOS 13+ app (SwiftUI/AppKit, SPM). Registers as a web browser (`http`/`https`), runs background-resident, controlled from the menu bar. No third-party deps, public Apple APIs only.
- **Assumptions/Constraints:** macOS 13+; user grants default-browser consent via system dialog; no App Sandbox (must launch arbitrary browsers); distribution via Developer ID + notarization.

## 3. Functional Reqs

### 3.1 FR-DEFAULT-BROWSER: Register & become default browser [ANC:fr:default-browser]
- **Desc:** App is recognized by macOS as a web browser and can be set as the default handler for `http`/`https`.
- **Scenario:** User clicks "Set as default browser" → system consent dialog → app becomes default; LaunchServices lists app for `http`/`https`.
- **Acceptance:** `plutil -extract CFBundleURLTypes xml1 - SmartLinksOpener.app/Contents/Info.plist` lists `http`+`https`; `lsregister -dump | grep -A2 dev.korchasa.SmartLinksOpener | grep 'claimed schemes'` shows `http:, https:`.
- **Status:** [x]

### 3.2 FR-ROUTE: Domain-based routing [ANC:fr:route]
- **Desc:** Incoming link with a matching rule opens silently in the rule's browser; longest-domain match wins; `www.` ignored; subdomains match parent rules (see [REF:fr:subdomain]).
- **Scenario:** Rule `github.com→Safari`; opening `https://gist.github.com/x` → Safari, no window, app stays resident.
- **Acceptance:** `Tests/SmartLinksOpenerTests/DomainTests.swift::testAllSubdomainsMatchTheRule` (+ `testUnrelatedHostsDoNotMatch`) over `Domain.host(_:matchesRule:)`.
- **Status:** [x]

### 3.10 FR-SUBDOMAIN: Subdomain routing & registrable-domain persistence [ANC:fr:subdomain]
- **Desc:** Remembering a choice stores the **registrable (second-level) domain** — `mail.google.com` → `google.com` — and every subdomain of that domain routes to the chosen browser. Multi-label public suffixes (`co.uk`, `github.io`, …) reduce correctly (`news.bbc.co.uk` → `bbc.co.uk`); unknown suffixes fall back to the last two labels.
- **Scenario:** Open `https://drive.google.com` with no rule → pick a browser + remember → rule `google.com` stored; later `mail.google.com` and `google.com` both open silently in that browser.
- **Acceptance:** `Tests/SmartLinksOpenerTests/DomainTests.swift` (all cases over `Domain.registrable` + `Domain.host`); run `./build.sh test`.
- **Status:** [x]

### 3.3 FR-PICKER: Browser picker for unmatched links [ANC:fr:picker]
- **Desc:** When no rule matches, a compact borderless glass panel pops at the cursor for every such link. It lists **only real browsers** (apps handling both `http` and `https`) as a **vertical list** ordered **most-used first**, with 1–9 quick-keys (and `0` for the tenth), ↑/↓ navigation (wrapping), Return to open, Esc or a corner ✕ to cancel. The default action is **open & remember**: choosing a browser creates a rule for the second-level domain and opens. Holding **⇧ Shift** switches to a one-time open — the panel turns orange, the header reads "Open once — no rule created", and no rule is stored. Concurrent unmatched links are FIFO-queued (depth shown as a "+N" badge), never dropped.
- **Scenario:** Open `https://news.ycombinator.com` with no rule → glass panel appears at cursor → press `1` (or click) → opens the most-used browser and stores a rule for `ycombinator.com`; holding ⇧ while pressing `1` opens once without a rule; a second link opened meanwhile waits in queue and is shown next.
- **Acceptance:** automated — `./build.sh test BrowserRankingTests` (frequency ordering), `./build.sh test PickerKeysTests` (hotkey labels 1–9/0, number-key→row mapping, wrapping ↑/↓ navigation); `manual — maintainer — borderless glass panel pops at cursor for an unmatched link; only real browsers listed as a vertical list; 1–9/0/↑/↓/Return/Esc/✕ work; choosing a browser adds a rule and opens; holding ⇧ turns the panel orange and opens once without a rule; a burst of links is queued, not dropped`.
- **Status:** [x]

### 3.4 FR-RULES-MGMT: Manage rules [ANC:fr:rules-mgmt]
- **Desc:** Rules window (two-pane: browser sidebar + full-height rules pane) lists rules (domain→browser), allows changing the browser, deleting, and adding a rule manually.
- **Tasks:** [REF:task:2026-06-settings-window-browser-visibility | settings-window-browser-visibility]; [REF:task:2026-06-rules-window-redesign-two-pane | rules-window-redesign-two-pane]
- **Scenario:** Open rules window → add `example.com→Chrome` → appears in list → delete → removed.
- **Acceptance:** `manual — maintainer — add/change/delete reflected in UI and persisted across relaunch`.
- **Status:** [x]

### 3.12 FR-BROWSER-VISIBILITY: Hide browsers from picker [ANC:fr:browser-visibility]
- **Desc:** Settings sidebar toggles per-browser picker visibility. The "hidden" set is stored (not "visible"), so newly installed browsers appear by default. Hiding the last visible browser is blocked (picker can never be empty). Picker and rule/add dropdowns offer only non-hidden browsers; a rule already pointing at a hidden/uninstalled browser keeps showing its target.
- **Tasks:** [REF:task:2026-06-settings-window-browser-visibility | settings-window-browser-visibility]
- **Scenario:** Toggle off a browser in the sidebar → it disappears from the picker and dropdowns → attempt to hide the last remaining visible browser → blocked.
- **Acceptance:** automated — `./build.sh test BrowserVisibilityTests`; `manual — maintainer — toggling sidebar visibility updates picker/dropdowns; last visible browser cannot be hidden`.
- **Status:** [x]

### 3.5 FR-BACKGROUND-AGENT: Background menu-bar agent [ANC:fr:background-agent]
- **Desc:** Runs as `LSUIElement` accessory: no Dock icon, menu-bar control, never self-terminates after routing; matched links do not steal focus.
- **Scenario:** Route a link → app PID unchanged (resident); no Dock icon present.
- **Acceptance:** `plutil -extract LSUIElement raw SmartLinksOpener.app/Contents/Info.plist` = `true`; after `open -b … <url>` the process from `pgrep -x SmartLinksOpener` is unchanged.
- **Status:** [x]

### 3.6 FR-LOGIN-ITEM: Launch at login [ANC:fr:login-item]
- **Desc:** Toggle registers/unregisters the app as a login item via `SMAppService.mainApp`.
- **Scenario:** Enable "Launch at login" → `SMAppService.mainApp.status == .enabled`.
- **Acceptance:** `manual — maintainer — toggling updates SMAppService status; survives relaunch`.
- **Status:** [x]

### 3.7 FR-I18N: Automatic internationalization [ANC:fr:i18n]
- **Desc:** UI language follows system locale; English base keys with 10 `.strings` catalogs (en, ru, uk, de, fr, es, it, pt-BR, ja, zh-Hans); data values not localized.
- **Scenario:** System language = French → UI strings render in French; missing translation → English fallback.
- **Acceptance:** `for f in Resources/*.lproj/Localizable.strings; do plutil -lint "$f"; done` all OK; bundle lookup resolves a known key per language.
- **Status:** [x]

### 3.8 FR-PERSIST: Persist rules [ANC:fr:persist]
- **Desc:** Rules stored in `UserDefaults` (key `rules.v1`) as `Codable`→JSON; per-browser open counts under `usage.v1` (drives picker frequency order); both survive relaunch.
- **Scenario:** Add a rule → quit → relaunch → rule present.
- **Acceptance:** `defaults read dev.korchasa.SmartLinksOpener rules.v1` returns the stored rules blob after a rule is added.
- **Status:** [x]

### 3.9 FR-DIST: Build, sign, distribute [ANC:fr:dist]
- **Desc:** `build.sh` assembles the `.app` with Hardened Runtime ad-hoc signature and registers it; documents Developer ID + notarization path. Project is open source under GPL-3.0-or-later (`LICENSE`, `CONTRIBUTING.md`).
- **Scenario:** Run `./build.sh prod` → signed `SmartLinksOpener.app` registered with LaunchServices.
- **Acceptance:** `./build.sh prod && codesign -dvvv SmartLinksOpener.app 2>&1 | grep -q 'flags=.*runtime'`; `test -f LICENSE`.
- **Status:** [x]

### 3.11 FR-DIST.MAS: Paid sandboxed Mac App Store build [ANC:fr:dist.mas]
- **Desc:** A separate sandboxed build for the Mac App Store (App Sandbox mandatory), sold at a small price (~$3/€3). Source stays open (GPL); only the copyright holder publishes the paid binary. Build via `./build.sh appstore`.
- **Scenario:** `./build.sh appstore` → `SmartLinksOpener-AppStore.app` signed with `com.apple.security.app-sandbox`; runs sandboxed (container created), enumerates browsers, shows picker.
- **Acceptance:** `./build.sh appstore && codesign -d --entitlements - SmartLinksOpener-AppStore.app 2>&1 | grep -q app-sandbox`. App Store upload/pricing: `manual — maintainer — documents/tasks/2026/06/open-source-and-appstore.md`.
- **Status:** [x] (build) / [ ] (uploaded & priced — maintainer step)

---

## 4. Non-Functional
- **Perf/Reliability/Sec/Scale/UX:** Routing latency negligible (event-driven, no polling); only public Apple APIs (notarization-safe); no data collection; resident agent idle when not routing; native macOS minimalist UI; matched links never steal focus.

## 5. Interfaces
- **API/Proto/UI:** System entry via Apple Event `kAEGetURL` (default-browser invocation); `NSWorkspace` to open URLs in a specific app and to query/set default handler; `SMAppService` for login item. UI: menu-bar `MenuBarExtra`, on-demand rules window, floating picker window.

## 6. Acceptance
- **Criteria:** All FR acceptance references above pass on the current commit; `./build.sh check` is green; `./build.sh prod` produces a signed, browser-registered bundle.
