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
- **Desc:** When no rule matches, show a floating picker of installed browsers; selecting one opens the link; optional "remember" creates a rule for the domain.
- **Scenario:** Open `https://news.ycombinator.com` with no rule → picker appears → pick Firefox + remember → opens Firefox and stores rule.
- **Acceptance:** `manual — maintainer — picker window "Choose browser" appears for an unmatched link; "remember" adds a rule visible in the rules window`.
- **Status:** [x]

### 3.4 FR-RULES-MGMT: Manage rules [ANC:fr:rules-mgmt]
- **Desc:** Rules window lists rules (domain→browser), allows changing the browser, deleting, and adding a rule manually; refresh installed-browser list.
- **Scenario:** Open rules window → add `example.com→Chrome` → appears in list → delete → removed.
- **Acceptance:** `manual — maintainer — add/change/delete reflected in UI and persisted across relaunch`.
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
- **Desc:** Rules stored in `UserDefaults` (key `rules.v1`) as `Codable`→JSON; survive relaunch.
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
