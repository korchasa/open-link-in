# Contributing

Thanks for your interest in Reroute.

## License of the project

The source code is licensed under **PolyForm Noncommercial 1.0.0** (see
`LICENSE`). Anyone may read it, study it, change it, and build it for any
noncommercial purpose — personal use, hobby projects, education, research.
Commercial use is not granted, so **nobody may sell a build of this code**,
modified or not, on the Mac App Store or anywhere else.

This replaced GPL-3.0-or-later on 2026-08-16. The GPL protected the project only
sideways: it clashes with Mac App Store terms, so forks could not ship there —
but it left them free to sell copies outside the store. The new licence names the
restriction directly. Everything published under the GPL stays available on GPL
terms in those commits; the change applies going forward.

## Why there is a paid App Store build

The author maintains an official, notarized build on the **Mac App Store** for a
small price. As the sole copyright holder, the author is not bound by the licence
they grant to others and may sell their own work. Paying for the App Store build
buys convenience (auto-updates, a signed sandboxed binary) and supports
development; building from source for yourself stays free.

## Contributor License Agreement (CLA)

So the maintainer can keep shipping the official App Store build, contributions
require a lightweight grant. By submitting a pull request you agree that:

1. You are the author of the contribution (or have the right to submit it).
2. You license your contribution to the project under **PolyForm Noncommercial
   1.0.0**, and
3. You **also grant the maintainer (copyright holder) a perpetual, irrevocable,
   royalty-free right to distribute your contribution under other terms**,
   including the paid Mac App Store build.

The second grant is what lets your code ship in the official paid build: without
it you keep the copyright on your lines, and the maintainer could not sell them.
If you do not agree, please open an issue to discuss instead of sending code.

## Development

- Requirements: macOS 13+, Swift 6 toolchain (Xcode 16+).
- Verify before opening a PR: `deno task check` (build + comment-scan + format + tests) must pass.
- Format: `deno task fmt` (Apple `swift format`, config in `.swift-format`).
- See `AGENTS.md`, `documents/requirements.md` (SRS), and `documents/design.md` (SDS).
