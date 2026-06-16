# Contributing

Thanks for your interest in Smart Links Opener.

## License of the project

The source code is licensed under **GPL-3.0-or-later** (see `LICENSE`). Anyone may
use, study, modify, and redistribute it under those terms — redistributed
versions must stay open source under the GPL.

## Why there is a paid App Store build

The author maintains an official, notarized build on the **Mac App Store** for a
small price. As the sole copyright holder, the author may distribute their own
work under additional terms (including Apple's proprietary App Store terms) — this
is the standard copyright-holder exception and does not affect your GPL rights to
the source. Paying for the App Store build is a convenience (auto-updates,
signed/sandboxed binary) and a way to support development; you are always free to
build from source yourself at no cost.

Note: because the GPL is incompatible with the Mac App Store distribution terms,
**third-party forks generally cannot be published on the Mac App Store.** They can
be distributed anywhere else under the GPL.

## Contributor License Agreement (CLA)

So the maintainer can keep shipping the official App Store build, contributions
require a lightweight grant. By submitting a pull request you agree that:

1. You are the author of the contribution (or have the right to submit it).
2. You license your contribution to the project under **GPL-3.0-or-later**, and
3. You **also grant the maintainer (copyright holder) a perpetual, irrevocable,
   royalty-free right to distribute your contribution under other terms**,
   including the proprietary Mac App Store build.

This dual grant lets your code live both in the open-source repo and in the
official paid build. If you do not agree, please open an issue to discuss instead
of sending code.

## Development

- Requirements: macOS 13+, Swift 6 toolchain (Xcode 16+).
- Verify before opening a PR: `./build.sh check` (build + comment-scan + format + tests) must pass.
- Format: `./build.sh fmt` (Apple `swift format`, config in `.swift-format`).
- See `AGENTS.md`, `documents/requirements.md` (SRS), and `documents/design.md` (SDS).
