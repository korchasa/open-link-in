/**
 * `deno task test [filter]` — run the Swift test suite, optionally filtered:
 *
 *   deno task test                 # everything
 *   deno task test LinkRoutingTests
 */

import { exists, run, section } from "./lib.ts";

export async function test(filter?: string): Promise<void> {
  // SwiftPM exits non-zero when there is no test target at all; treat "no
  // tests" as a pass so `check` stays green until tests are added.
  if (!(await exists("Tests"))) {
    console.log("    no Tests/ target yet — skipping (add tests under Tests/ to enable)");
    return;
  }
  section(filter ? `swift test --filter ${filter}` : "swift test");
  await run("swift", { args: filter ? ["test", "--filter", filter] : ["test"] });
}

if (import.meta.main) await test(Deno.args[0]);
