# Core Project Rules
- Follow your assigned role strictly — it defines scope and boundaries for your actions.
- After finishing a session, review all project documents(readme.md, requirements.md, design.md, etc) to ensure they reflect the current state. Stale docs mislead future sessions.
- Verify every change by running appropriate tests or scripts — never assume correctness without evidence.
- Keep the project in a clean state: no errors, warnings, or issues in formatter and linter output. A broken baseline blocks all future work.
- Follow the TDD flow described below. Skipping it leads to untested code and regressions.
- Write all documentation in English, compressed style. Brevity preserves context window.
- If you see contradictions in the request or context, raise them explicitly, ask clarifying questions, and stop. Do not guess which interpretation is correct.
- **Forward motion after authorization**: once the user has authorized a plan (chosen a variant, agreed to a phase list, or just said "go"), execute it without re-confirming each step. Re-asking is appropriate ONLY when (a) a genuinely irreversible action surfaces that was NOT covered by the original authorization — force push to a shared branch, prod deploy, dropping a database table, sending an external message (Slack, email, PR merge), or any other external side-effect that cannot be undone via git — OR (b) new information surfaces that contradicts the authorized plan (failing precondition, ambiguity discovered mid-flight). "Action looks expensive" or "diff is large" are NOT valid triggers — local code changes are reversible. Test before asking: if the user can only answer "yes" to the question, the question is noise — proceed instead.
- Code should follow "fail fast, fail clearly" — surface errors immediately with clear messages rather than silently propagating bad state. Unless the user requests otherwise.
- When editing CI/CD pipelines, always validate locally first — broken CI is visible to the whole team and slow to debug remotely.
- Provide evidence for your claims — link to code, docs, or tool output. Unsupported assertions erode trust.
- Use standard tools (jq, yq, jc) to process and manage structured output — they are portable and well-understood.
- Do not add fallbacks, default behaviors, or error recovery silently — if the user didn't ask for it, it's an assumption. If you believe a fallback is genuinely needed, ask the user first.
- Do not use tables in chat output — use two-level lists instead. Tables render poorly in terminal and are harder to scan.
- **Decision-level engagement — the human owns decisions, the AI owns code.** The boundary is the level of individual classes/methods: the human initiates and approves every decision *above* it (business rules, architecture, public interfaces / data shapes, new dependencies, key technical trade-offs); the AI decides freely at or below it (local naming, private helpers, test layout).
- **Surface above-class/method decisions before implementing.** When a decision above the class/method line is NOT already settled by an approved plan, present it to the human as options + trade-offs + a recommendation and STOP — wait for the human's call; do NOT self-select a default and proceed.
- **Narrate upward, not in diffs.** Report work in terms of requirements AND the class/method structure you produced (names, responsibilities, relationships), in prose the human can accept WITHOUT reading the code. Every above-class/method decision you made or surfaced MUST appear in that summary — an omitted one is a defect (this keeps mental/cognitive debt at zero above the class/method line). Never make reading the diff the only way to understand what changed.
- **AI owns code review; diff review is optional (Model B).** The AI reviews the code itself and reports a decision-level verdict (task complete? design sound? key risks?); the human is NOT required to read the diff to accept it. Offer the diff for optional inspection — never block the workflow on the human reading code.

---
## Project-Specific Rules
- **Public APIs only.** Use only Apple public frameworks (`NSWorkspace`, LaunchServices via `NSWorkspace`, `ServiceManagement`, Apple Events). No private/deprecated calls — they break notarization and future macOS releases.
- **Native, dependency-free.** SwiftUI/AppKit + Swift Package Manager, zero third-party packages. Do not add dependencies without explicit approval.
- **Background-agent invariants.** The app is an `LSUIElement` accessory: no Dock icon, controlled from the menu bar. It must NOT self-terminate after routing a link, and matched links must open without stealing focus.
- **i18n discipline.** User-facing strings are English `LocalizedStringKey` / `String(localized:)` keys; translations live in `Resources/<lang>.lproj/Localizable.strings`. Data values (domains, browser names, bundle IDs) use `Text(verbatim:)` and are never localized. Adding a UI string means adding its key to every `*.lproj` catalog + `CFBundleLocalizations`.
- **Two distributions.** (1) Open-source Developer ID build (`./build.sh prod`): Hardened Runtime, **no sandbox**, distributed outside the Mac App Store. (2) Paid Mac App Store build (`./build.sh appstore`): **App Sandbox enabled** (`Resources/SmartLinksOpener.appstore.entitlements`). Browser enumeration via LaunchServices and opening URLs in another app via `NSWorkspace` are permitted inside the sandbox (verified; precedent: Velja). Keep MAS entitlements minimal — only `com.apple.security.app-sandbox`.
- **Licensing.** Source is **GPL-3.0-or-later**. The sole copyright holder ships the paid App Store build under the owner-exception; contributions require the `CONTRIBUTING.md` CLA so they can appear in that build. Do not change the license or relicense contributions without the maintainer's decision.

## Project Information
- Project Name: Smart Links Opener

## Project Vision
A minimalist macOS app that acts as the default web browser and routes every link to the right browser based on its domain. When no rule matches a domain, it offers a picker over installed browsers with a one-click "remember" to create a rule. Runs quietly in the background as a menu-bar agent; native macOS look, standard frameworks only.

## Project tooling Stack
- **Language:** Swift 6.3 (toolchain), targeting macOS 13+ (`platforms: [.macOS(.v13)]`).
- **UI:** SwiftUI (`App`, `MenuBarExtra`, views) + AppKit (`NSApplication`, `NSWindow`, `NSHostingController`, `NSWorkspace`).
- **System frameworks:** LaunchServices (browser enumeration / default handler), `ServiceManagement` (`SMAppService` login item), Apple Events (`kAEGetURL`).
- **Build:** Swift Package Manager (`Package.swift`, executable target) + `build.sh` that assembles, signs (Hardened Runtime, ad-hoc), and registers the `.app` bundle.
- **Tooling:** `swift format` (Apple, 6.3) for formatting; `codesign`, `lsregister`, `notarytool`/`stapler` for distribution.
- **Dependencies:** none (no SPM/third-party packages).

## Architecture
Single executable packaged into a macOS `.app` bundle that the system recognizes as a browser (`CFBundleURLTypes` for `http`/`https`).

- **Entry / agent shell** (`App.swift`): `@main SmartLinksOpenerApp` exposes only a `MenuBarExtra`. `AppDelegate` (`@MainActor`) sets `.accessory` activation policy, registers the `kAEGetURL` Apple Event handler, and owns on-demand AppKit windows (rules + picker) via `NSHostingController`.
- **State / domain logic** (`AppStore.swift`): `@MainActor ObservableObject` singleton. Holds rules + installed browsers, performs longest-suffix domain matching, opens URLs in a chosen browser via `NSWorkspace`, manages the default-browser handoff and the `SMAppService` login item. Persists rules in `UserDefaults` (key `rules.v1`, JSON via `Codable`).
- **Views** (`PickerView.swift`, `RulesView.swift`): SwiftUI. Picker = choose a browser for an unmatched link (+ remember). Rules = manage rules, default-browser status, launch-at-login.
- **Models** (`Models.swift`): `Rule` (domain → bundleID), `Browser` (name, bundleID, appURL).
- **Flow:** incoming link → Apple Event → `AppStore.handleIncoming` → matched: open silently; unmatched: raise picker. App stays resident throughout.

## Key Decisions
- **SPM executable + manual bundling.** No Xcode project; `build.sh` hand-assembles the `.app` with `Info.plist` and `*.lproj`. Keeps the repo Xcode-free and scriptable.
- **`UserDefaults` for rules.** Lightweight settings data → standard `UserDefaults` (`Codable`→JSON under one key), not a custom file. Window frame auto-persisted by AppKit.
- **Modern default-browser API.** `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` (system consent dialog), replacing deprecated `LSSetDefaultHandlerForURLScheme`.
- **`SMAppService` login item.** Modern replacement for `SMLoginItemSetEnabled`.
- **Background agent.** `LSUIElement` + `.accessory` + `MenuBarExtra`; never self-terminates.
- **Hardened Runtime, no Sandbox.** Signed with `--options runtime`; sandbox omitted by design; distributed via Developer ID + notarization.
- **Automatic i18n.** English base keys + 10 `.strings` catalogs; macOS picks the language.

## Documentation Hierarchy
1. **`AGENTS.md`**: Project vision, constraints, mandatory rules. READ-ONLY reference.
2. **SRS** (`documents/requirements.md`): "What" & "Why". Source of truth for requirements.
3. **SDS** (`documents/design.md`): "How". Architecture and implementation. Depends on SRS.
4. **Tasks** (`documents/tasks/<YYYY>/<MM>/<slug>.md`): Persistent committed plans/notes per task.
5. **Index** (`documents/index.md`): Agent-maintained navigation aggregator across all linkable artifacts (FR / SDS / NFR). Created on first write, never scaffolded. Task ↔ FR navigation lives inline in SRS as `**Tasks:**` back-pointers, not here.
7. **`README.md`**: Public-facing overview. Installation, usage, quick start. Derived from AGENTS.md + SRS + SDS.

## Interconnectedness Principle — SALP

Cross-references between any two pieces of project knowledge — doc-to-doc, **and code-to-doc** — use the **SALP grammar** (Semantic Anchor / Link Protocol). One mechanism, two tokens, namespace-disambiguated, machine-validated.

- **Anchor** — `[ANC:<ns>:<id>]` — declares a named target. Place it on the same line as the heading it labels, after the title text. Example: `### FR-CMD-EXEC: Command Execution [ANC:fr:cmd-exec]`.

- **Reference** — `[REF:<ns>:<id>]` or `[REF:<ns>:<id> | <display>]` — points at a target. The optional `| display` text is what readers see. Example: `See [REF:fr:cmd-exec | FR-CMD-EXEC] for details.`

- **Namespace grammar (open set)** — `<ns>` matches `[a-z][a-z0-9-]*`. The set is open: any grammar-conformant value is accepted by the validator. Examples currently in use: `fr` (functional requirements), `sds` (design sections), `task` (committed tasks), `nfr` (non-functional requirements), `code` (source-code references), `mx-concept` / `mx-person` / `mx-source` / `mx-answer` (memex pages). New consumers may introduce new namespaces without changing the validator.

- **ID grammar** — `<id>` is lower-kebab (`[a-z0-9][a-z0-9.-]*`). Hierarchical FR IDs preserve the period (`FR-DIST.MARKETPLACE` → `dist.marketplace`).

- **Applies in code too** — when source code needs to reference documentation, the comment carries a SALP REF, not a slug-style identifier or a GFM link. Example: `// [REF:fr:cmd-exec] — execution gate`. The legacy `// FR-<ID>` shortcut and the previous GFM-link form (`// [FR-X](path.md#…)`) are rejected by the validator.

- **Rejected forms** — do NOT use ID-only shortcuts (`[FR-CMD-EXEC]`), wikilinks (`[[X]]`), bare ID strings (`// FR-CMD-EXEC`), custom anchor mechanisms (`{#my-anchor}`, `<a name=...>`), GFM-form cross-references (`[FR-X](path.md#…)`), or salp-short (`[ANC:id]` without namespace). Validators ship with the framework reject all of these.

- **Drift discipline** — removing or renaming an anchor obliges updating every reference to it. Checked mechanically by `scripts/check-salp.ts` (dead-REF / duplicate-ANC / surviving-legacy-grammar) where the project ships such a script.

- **Local verification gap** — this repo ships NO `scripts/check-salp.ts`, and `./build.sh check` does NOT validate SALP; anchor/ref integrity is enforced only by the external `doc-anchors-validate` Stop hook. So a green `check` does not mean references resolve. After any edit that adds/moves a `[REF:ns:id]` or `[ANC:ns:id]`, verify before finishing that every new `[REF:...]` resolves to exactly one heading-line `[ANC:...]`. Do NOT trust a bare `grep` for anchors — matches inside backtick code spans or prose are NOT valid declarations (the validator ignores them), so a grep "hit" can be a false positive. When you add a `// [REF:fr:X]` code marker, add the `### FR-… [ANC:fr:X]` SRS section in the SAME change.

## Documentation Map

Maps source code paths to documentation sections that describe them. Used by commit workflows to determine which doc sections need updating when files change.

- `Sources/SmartLinksOpener/App.swift` → SDS §3 (Agent shell / window manager), SRS FR-DEFAULT-BROWSER, FR-BACKGROUND-AGENT, FR-FILE-OPEN
- `Sources/SmartLinksOpener/AppStore.swift` → SDS §3 (State & routing), §4 (Data), §5 (Logic); SRS FR-ROUTE, FR-PICKER, FR-LOGIN-ITEM, FR-DEFAULT-BROWSER
- `Sources/SmartLinksOpener/PickerView.swift` → SDS §3 (Picker view); SRS FR-PICKER, FR-FILE-OPEN
- `Sources/SmartLinksOpener/LinkLabel.swift` → SDS §3.10 (Link label), §5 (Logic); SRS FR-FILE-OPEN, FR-PICKER
- `Tests/SmartLinksOpenerTests/LinkLabelTests.swift` → SRS FR-FILE-OPEN (picker-title acceptance)
- `Sources/SmartLinksOpener/PickerKeys.swift` → SDS §3.9 (Picker keys), §5 (Logic); SRS FR-PICKER
- `Tests/SmartLinksOpenerTests/PickerKeysTests.swift` → SRS FR-PICKER (hotkey/navigation acceptance)
- `Sources/SmartLinksOpener/BrowserRanking.swift` → SDS §3.7 (Browser ranking), §5 (Logic); SRS FR-PICKER
- `Tests/SmartLinksOpenerTests/BrowserRankingTests.swift` → SRS FR-PICKER (frequency-order acceptance)
- `Sources/SmartLinksOpener/BrowserVisibility.swift` → SDS §3.8 (Browser visibility), §5 (Logic); SRS FR-BROWSER-VISIBILITY
- `Tests/SmartLinksOpenerTests/BrowserVisibilityTests.swift` → SRS FR-BROWSER-VISIBILITY (hidden-set + last-one-guard acceptance)
- `Sources/SmartLinksOpener/RulesView.swift` → SDS §3 (Rules view); SRS FR-RULES-MGMT
- `Sources/SmartLinksOpener/Domain.swift` → SDS §3.6 (Domain resolver), §5 (Logic); SRS FR-SUBDOMAIN, FR-ROUTE
- `Tests/SmartLinksOpenerTests/DomainTests.swift` → SRS FR-SUBDOMAIN, FR-ROUTE (acceptance)
- `Sources/SmartLinksOpener/Models.swift` → SDS §4 (Entities)
- `Resources/Info.plist` → SRS FR-DEFAULT-BROWSER, FR-BACKGROUND-AGENT
- `Resources/*.lproj/Localizable.strings` → SRS FR-I18N
- `build.sh` → Development Commands; SRS FR-DIST, FR-DIST.MAS
- `Resources/SmartLinksOpener.entitlements` → SRS FR-DIST (Developer ID build)
- `Resources/SmartLinksOpener.appstore.entitlements` → SRS FR-DIST.MAS (sandboxed App Store build)
- `LICENSE` / `CONTRIBUTING.md` → SRS FR-DIST (GPL-3.0-or-later + CLA)

If this section is empty or absent, commit workflows use a default mapping:
- New/changed exports, classes, types → SDS (component section)
- New feature, CLI command, skill, agent → SRS (new FR) + SDS (new component)
- Removed feature/component → remove from SRS + SDS
- Changed behavior → SDS (update description)
- Renamed/moved modules → SDS (update paths)
- README.md → only for user-facing changes

## Documentation Rules

Your memory resets between sessions. Documentation is the only link to past decisions and context. Keeping it accurate is not optional — stale docs actively mislead future sessions.

- Follow AGENTS.md, SRS, and SDS strictly — they define what the project is and how it works.
- Workflow for changes: new or updated requirement → update SRS → update SDS → implement. Skipping steps leads to docs-code drift.
- Status markers: `[x]` = implemented, `[ ]` = pending.
- **Traceability**: Every `[x]` criterion requires evidence. Placement depends on evidence type:
  1. **Code-evidenced**: Source files contain a SALP REF (in a `//` or `#` comment) pointing at the relevant SRS / SDS anchor near the implementing logic — e.g., `// [REF:fr:cmd-exec] — execution gate`. The REF IS the evidence; no paths are stored in SRS. Bare `// FR-<ID>` and GFM-form `// [FR-X](path.md#…)` comments are rejected by the SALP validator.
  2. **Non-code evidence** (acceptance tests, URLs, config files without comment support, file/dir existence): Placed directly in SRS/SDS next to the criterion.
  Without evidence of either type, the criterion stays `[ ]`.
- **Acceptance-as-gate**: Every FR in SRS MUST declare a runnable `**Acceptance:**` reference — a test path + test name, a benchmark scenario ID, or a verification command. Prose-only acceptance is not sufficient. An FR stays `[ ]` until its acceptance reference exists and passes on the current commit. Exception: when automation cost exceeds defect cost (pure visual design, external vendor dependency), mark `**Acceptance: manual — <reviewer> — <checklist path>**`. Manual is the exception, not the default.

### SRS Format (`documents/requirements.md`)
```markdown
# SRS
## 1. Intro
- **Desc:**
- **Def/Abbr:**
## 2. General
- **Context:**
- **Assumptions/Constraints:**
## 3. Functional Reqs
### 3.1 FR-CMD-EXEC
- **Desc:**
- **Scenario:**
- **Acceptance:** <test-path::test-name | benchmark-id | `evidence-command` | `manual — <reviewer>`>
- **Status:** [ ] / [x]
---

## 4. Non-Functional

- **Perf/Reliability/Sec/Scale/UX:**

## 5. Interfaces

- **API/Proto/UI:**

## 6. Acceptance

- **Criteria:**

````

### SDS Format (`documents/design.md`)
```markdown
# SDS
## 1. Intro
- **Purpose:**
- **Rel to SRS:**
## 2. Arch
- **Diagram:**
- **Subsystems:**
## 3. Components
### 3.1 Comp A
- **Purpose:**
- **Interfaces:**
- **Deps:**
...
## 4. Data
- **Entities:**
- **ERD:**
- **Migration:**
## 5. Logic
- **Algos:**
- **Rules:**
## 6. Non-Functional
- **Scale/Fault/Sec/Logs:**
## 7. Constraints
- **Simplified/Deferred:**
````

### Tasks (`documents/tasks/`)

- One file per task or session at a date-hierarchy path: `documents/tasks/<YYYY>/<MM>/<slug>.md` (kebab-case slug, max 40 chars).
- Examples: `documents/tasks/2026/03/add-dark-mode.md`, `documents/tasks/2026/03/fix-auth-bug.md`.
- Do not reuse another session's task file — create a new file. Old tasks are persistent canonical records.
- Use GODS format (see below). Architectural decisions are recorded as regular tasks with weighed alternatives in the body — there is no separate ADR primitive.
- Frontmatter: `date` (YYYY-MM-DD; required), `status: to do | in progress | done | superseded` (required), `implements: [FR-...]` (optional — present for FR-driven tasks, omitted for internal/maintenance), optional `tags`, optional `related_tasks` (markdown links to other task files), optional `migrated_from` for provenance, optional `superseded_by` (required when `status: superseded`).
- Status auto-derives from `## Definition of Done` checkbox count on every commit for non-superseded tasks (commit workflows handle this — never edit `status` manually mid-flight). `status: superseded` preserves provenance and is excluded from DoD derivation.
- Directory is **NOT gitignored** — tasks are persistent records. Validated by `scripts/check-task-format.ts` (path regex, status enum, status↔DoD consistency).

### GODS Format

```markdown
---
implements:
  - FR-XXX
---
# [Task Title]

## Goal

[Why? Business value.]

## Overview

### Context

[Full problematics, pain points, operational environment, constraints, tech debt, external URLs, @-refs to relevant files/docs.]

### Current State

[Technical description of existing system/code relevant to task.]

### Constraints

[Hard limits, anti-patterns, requirements (e.g., "Must use Deno", "No external libs").]

## Definition of Done

Every DoD item MUST pair with (a) an FR-ID and (b) a runnable acceptance reference. Items without this tuple are wishes, not contracts.

- [ ] FR-XXX: <observable behavior>
  - Test: `<path/to/test>::<test_name>` (or `Benchmark: <scenario-id>`)
  - Evidence: `<command that passes iff the item is done>`
- [ ] FR-YYY: <observable behavior>
  - Test: `...`
  - Evidence: `...`

## Solution

[Detailed step-by-step for SELECTED variant only. Filled AFTER user selects variant.]
```

### Compressed Style Rules (All Docs)

- No changelogs — docs reflect current state, not history.
- English only (except tasks, which may use the user's language).
- Summarize by extracting facts and compressing — no loss of information, just fewer words.
- Every word must carry meaning — no filler, no fluff, no stopwords where a shorter synonym works.
- Prefer compact formats: lists, tables, YAML, Mermaid diagrams.
- Abbreviate terms after first use — define once, abbreviate everywhere.
- Use symbols and numbers to replace words where unambiguous (e.g., `→` instead of "leads to").

## Requirements Lifecycle (Plan → Develop → Review → Commit)

Requirements are only real when a machine can verify them. Each phase of the cycle has a concrete, non-skippable binding between FR and acceptance test.

- **Plan** (`plan` / `epic`): a task plan is not accepted without (a) `implements:` frontmatter listing every FR it touches, (b) each DoD item paired with `(FR-ID, test-path-or-benchmark, evidence-command)`. If an FR is new, add its section to SRS with the `**Acceptance:**` field filled in the same pass.
- **Develop** (TDD): RED = write the acceptance test first, using the path declared in the plan, and confirm it fails. GREEN = minimal code + `// FR-<ID>` comment next to the implementing logic. CHECK = the project's `check` command passes, including the new test.
- **Review** (`review` / `review-and-commit`): for every FR in scope, verify (a) SRS declares runnable acceptance, (b) the acceptance test exists and passes in the current diff, (c) source files carry `// FR-<ID>` markers. Any gap → `[critical]`, verdict cannot be `Approve`. Review also runs a JiT subset that probes for hidden behavioural regressions via ephemeral pass-on-parent / fail-on-diff tests; surviving catching tests are `[critical]` findings.
- **Commit** (`commit` / `review-and-commit`): before committing, if the diff adds/modifies FR sections in SRS, each new/modified FR MUST have a filled `**Acceptance:**` field. If it touches implementing code, the paired acceptance test MUST pass. Missing either → block commit.

Scope discipline prevents over-formalization: (1) pure bug fixes reuse an existing FR — add a regression test, no new FR; (2) refactors that preserve behavior cite the FR already covering the behavior; (3) only user-visible or contract-level changes introduce new FRs. The gate applies to new/changed FRs, not to every edit.

## Planning Rules

- **Environment Side-Effects**: When changes touch infra, databases, or external services, the plan must include migration, sync, or deploy steps — otherwise the change works locally but breaks in production.
- **Verification Steps**: Every plan must include specific verification commands (tests, validation tools, connectivity checks) — a plan without verification is just a wish.
- **Functionality Preservation**: Before editing any file for refactoring, run existing tests and confirm they pass — this is a prerequisite, not a suggestion. Without a green baseline you cannot detect regressions. Run tests again after all edits. Add new tests if coverage is missing.
- **Data-First**: When integrating with external APIs or processes, inspect the actual protocol and data formats before planning — assumptions about data shape are the #1 source of integration bugs.
- **Architectural Validation**: For complex logic changes, visualize the event sequence (sequence diagram or pseudocode) — it catches race conditions and missing edges that prose descriptions miss.
- **Variant Analysis**: A format for comparing alternatives of any kind — approaches, designs, tools, libraries, vendors, data models, configurations. Present each candidate as a labeled option with Pros / Cons / Risks / Best-for, then analyze the trade-offs across options (e.g. speed vs. correctness, cost vs. flexibility). One option is acceptable when the path is clear; when it is non-obvious, surface multiple distinct options.
- **Plan Persistence**: After variant selection, save the detailed plan to `documents/tasks/<YYYY>/<MM>/<slug>.md` using GODS format — chat-only plans are lost between sessions.
- **Proactive Resolution**: Before asking the user, exhaust available resources (codebase, docs, web) to find the answer autonomously — unnecessary questions slow the workflow and signal lack of initiative.

## TDD Flow

1. **RED**: Write a failing test for new or changed logic. When the change maps to an FR (new or modified), the failing test is the **FR's acceptance test** at the path declared in the plan's DoD; it doubles as the gate for `Requirements Lifecycle`. Pure internal refactors may use narrower unit tests.
2. **GREEN**: Write minimal code to pass the test. When implementing an FR, add a `// FR-<ID>` (TS/JS/Go/Rust) or `# FR-<ID>` (YAML/shell/Python) comment next to the implementing logic.
3. **REFACTOR**: Improve code and tests without changing behavior. Re-run the test.
4. **CHECK**: Run `fmt`, `lint`, and full test suite. You are NOT done after GREEN — skipping CHECK leaves formatting errors and regressions undetected. This step is mandatory.

### Test Rules

- Test logic and behavior only — do not test constants or templates, they change without breaking anything.
- Tests live in the same package. Testing private methods is acceptable when it improves coverage of complex internals.
- Write code only to fix failing tests or reported issues — no speculative implementations.
- No stubs or mocks for internal code. Use real implementations — stubs hide integration bugs.
- Run all tests before finishing, not just the ones you changed.
- When a test fails, fix the source code — not the test. Do not modify a failing test to make it pass, do not add error swallowing or skip logic.
- Do not create source files with guessed or fabricated data to satisfy imports — if the data source is missing, that is a blocker (see Diagnosing Failures).

## Diagnosing Failures

The goal is to identify the root cause, not to suppress the symptom. A quick workaround that hides the root cause is worse than an unresolved issue with a correct diagnosis.

1. Read the relevant code and error output before making any changes.
2. Apply "5 WHY" analysis to find the root cause.
3. Root cause is fixable → apply the fix, retry.
4. Second fix attempt failed → STOP. Output "STOP-ANALYSIS REPORT" (state, expected, 5-why chain, root cause, hypotheses). Wait for user help.

When the root cause is outside your control (missing API keys/URLs, missing generator scripts, unavailable external services, wrong environment configuration) → STOP immediately and ask the user for the correct values. Do not guess, do not invent replacements, do not create workarounds.

## Development Commands

### Shell Environment
- Always use `NO_COLOR=1` when running shell commands — ANSI escape codes waste tokens and clutter output.
- When writing scripts, respect the `NO_COLOR` env var (https://no-color.org/) — disable ANSI colors when it is set.

### Standard Interface
- `check` — the main command for comprehensive project verification. Runs the following steps in order:
  - build the project
  - comment-scan: "TODO", "FIXME", "HACK", "XXX", debugger calls, linter and formatter suppression markers
  - code formatting check
  - static code analysis
  - all project tests
- `test <path>` — runs a single test file or test suite.
- `dev` — runs the application in development mode with watch mode enabled.
- `prod` — runs the application in production mode.

### Detected Commands
- `./build.sh check` — build (debug) + comment-scan + `swift format lint --strict` + tests (skips cleanly until a `Tests/` target exists).
- `./build.sh test [filter]` — run the test suite; the optional `filter` is **positional** (`./build.sh test BrowserRankingTests`, forwarded to `swift test --filter`), not a `--filter` flag. No-op until `Tests/` exists.
- `./build.sh dev` — run the executable directly via `swift run` (Ctrl-C to stop).
- `./build.sh prod` (default, also `./build.sh` / `./build.sh build`) — compile release, assemble `SmartLinksOpener.app`, sign (Hardened Runtime, ad-hoc), register with LaunchServices.
- `./build.sh fmt` — auto-format `Sources/` in place via `swift format`.

> ⚠️ **Local verification — bundle-id collision.** `prod` and `appstore` builds share `CFBundleIdentifier` `dev.korchasa.SmartLinksOpener`. With both present/running, `open -b dev.korchasa.SmartLinksOpener <url>` may route the Apple Event to a stale instance (e.g. an old picker still showing non-browsers). Before launch-testing: `pkill -9 -f SmartLinksOpener`, keep a single `.app` on disk, and `lsregister -u <path>` the other if it lingers in LaunchServices. Verify with `pgrep -fl SmartLinksOpener` (expect exactly one).

### Command Scripts
- `build.sh` — single entry point implementing the standard interface as subcommands (`check`/`test`/`dev`/`prod`/`fmt`). No separate `scripts/` directory; the project's command runner handles everything inline.

### Git notes
- Interactive git (`add -p`, `add -i`, `rebase -i`) is unavailable in this environment. To split ONE file's changes across two commits: temporarily edit the not-this-commit hunks back to their `HEAD` text, `git add <file>` (stages only this commit's delta), `git commit`, then edit the file to its final content and `git add` again for the next commit. Verify with `git diff --cached <file>` before every commit so content cannot leak into the wrong commit.

## Code Documentation

- **Module level**: each module gets an `AGENTS.md` describing its responsibility and key decisions.
- **Code level**: JSDoc/GoDoc for classes, methods, and functions. Focus on *why* and *how*, not *what*. Skip trivial comments — they add noise without value.
- **Requirement traceability**: when code implements a requirement from SRS (`documents/requirements.md`), add a `// FR-<ID>` (TS/JS/Go/Rust) or `# FR-<ID>` (YAML/shell/Python) comment next to the implementing logic. Code references requirements, not the reverse — SRS must not contain file paths. Exceptions: requirements verified by acceptance tests or proven by file existence need no comment.

> **Before you start:** read `documents/requirements.md` (SRS) and `documents/design.md` (SDS) if you haven't in this session. They contain project requirements and architecture that inform every task.
