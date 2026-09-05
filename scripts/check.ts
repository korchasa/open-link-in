/**
 * `deno task check` — the verification gate.
 *
 * Order is cheapest-failure-first: the task scripts themselves, then the debug
 * build, then the source scans, then the tests. The last step rebuilds and
 * reinstalls the "Reroute Dev" copy so a local run leaves the installed agent
 * matching the code — under CI that step is pointless and is skipped.
 */

import { checkTooling, fail, run, scanFiles, section } from "./lib.ts";
import { prod } from "./prod.ts";
import { test } from "./test.ts";
import { INSTALLED } from "./install.ts";

/** Work markers and suppression comments that must not reach a shipped build. */
const MARKERS = /TODO|FIXME|HACK|XXX|swiftlint:disable|swift-format-ignore/;

const TOTAL = 6;

async function relaunch(): Promise<void> {
  // `prod` installs and relaunches the dev copy itself; the App Store copy,
  // which shares the binary name, is left alone.
  await prod();
  const running = await run("pgrep", {
    args: ["-f", `${INSTALLED}/Contents/MacOS/`],
    allowFailure: true,
    capture: true,
  });
  console.log(`    running dev instances: ${running.stdout.trim().split("\n").join(" ")}`);
}

async function check(): Promise<void> {
  section(`[1/${TOTAL}] Tooling (deno fmt --check, lint, type-check)`);
  await checkTooling();

  section(`[2/${TOTAL}] Build (debug)`);
  await run("swift", { args: ["build"] });

  section(`[3/${TOTAL}] Comment scan (TODO/FIXME/HACK/XXX, swiftlint:disable)`);
  const hits = await scanFiles(["Sources"], [".swift"], MARKERS);
  if (hits.length > 0) {
    hits.forEach((hit) => console.log(hit));
    fail("leftover markers above — resolve before shipping");
  }
  console.log("    clean");

  section(`[4/${TOTAL}] Format check (swift format lint)`);
  await run("swift", { args: ["format", "lint", "--strict", "--recursive", "Sources"] });

  section(`[5/${TOTAL}] Tests`);
  await test();

  if (Deno.env.get("CI")) {
    section(`[6/${TOTAL}] Rebuild & relaunch — skipped (CI: verification only)`);
  } else {
    section(`[6/${TOTAL}] Rebuild & relaunch app`);
    await relaunch();
  }

  section("check passed");
}

if (import.meta.main) await check();
