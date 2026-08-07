/** `deno task dev` — run the executable straight from the debug build. */

import { run, section } from "./lib.ts";
import { BIN_NAME } from "./bundle.ts";

section("Running via swift run (Ctrl-C to stop)");
await run("swift", { args: ["run", BIN_NAME] });
