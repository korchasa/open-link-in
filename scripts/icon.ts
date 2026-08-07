/**
 * `deno task icon` — regenerate Resources/AppIcon.icns from the committed
 * iconset source, keeping the brand icon reproducible. [REF:fr:app-icon]
 */

import { run, section } from "./lib.ts";

section("Generating Resources/AppIcon.icns from Resources/AppIcon.iconset");
await run("iconutil", {
  args: ["-c", "icns", "Resources/AppIcon.iconset", "-o", "Resources/AppIcon.icns"],
});
section("Done: Resources/AppIcon.icns");
