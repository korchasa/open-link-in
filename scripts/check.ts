/**
 * `deno task check` — the verification gate.
 *
 * Order is cheapest-failure-first: the task scripts themselves, then the debug
 * build, then the source scans, then the tests. The last step rebuilds and
 * relaunches the app so a local run leaves the installed agent matching the
 * code — under CI that step is pointless and is skipped.
 */

import { checkTooling, fail, run, scanFiles, section } from "./lib.ts";
import { prod } from "./prod.ts";
import { test } from "./test.ts";
import { APP_NAME, BIN_NAME } from "./bundle.ts";

/** Work markers and suppression comments that must not reach a shipped build. */
const MARKERS = /TODO|FIXME|HACK|XXX|swiftlint:disable|swift-format-ignore/;

const TOTAL = 6;

async function relaunch(): Promise<void> {
  await prod();
  section(`Relaunching ${APP_NAME}`);
  await run("pkill", { args: ["-9", "-f", BIN_NAME], allowFailure: true, capture: true });
  // A GUI-less session (SSH, remote, sandbox) cannot launch an Aqua app and
  // `open` fails with -600. The bundle is built and verified by then, so a
  // failed relaunch must not fail the gate — degrade to a warning.
  const opened = await run("open", { args: [APP_NAME], allowFailure: true, capture: true });
  if (opened.code !== 0) {
    console.error(
      `    warning: could not relaunch (no GUI session?) — bundle built at ${APP_NAME}`,
    );
    return;
  }
  const running = await run("pgrep", { args: ["-x", BIN_NAME], allowFailure: true, capture: true });
  console.log(`    running instances: ${running.stdout.trim().split("\n").join(" ")}`);
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
