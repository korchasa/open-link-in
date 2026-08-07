/**
 * `deno task fmt` — format both languages in the repository in place: the Swift
 * sources and the TypeScript task scripts. `check` verifies the same two
 * without writing.
 */

import { run, section } from "./lib.ts";

section("swift format");
await run("swift", { args: ["format", "--in-place", "--recursive", "Sources"] });

section("deno fmt");
await run("deno", { args: ["fmt"] });

console.log("==> formatted Sources/ and scripts/");
