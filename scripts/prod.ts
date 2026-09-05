/**
 * `deno task prod` — build the .app, sign it ad-hoc and install it in
 * /Applications as "Reroute Dev" (see install.ts), so the locally installed
 * browser-router is the code you just wrote and sits next to the store build.
 * This is the open-source build; the App Store bundle is `dist`.
 */

import { run, section } from "./lib.ts";
import { APP_NAME, assembleBundle, buildRelease, copyLooseIcon } from "./bundle.ts";
import { installDevCopy, INSTALLED } from "./install.ts";

export async function prod(): Promise<void> {
  await buildRelease();
  await assembleBundle(APP_NAME);
  await copyLooseIcon(APP_NAME);

  section("Ad-hoc code signing (Hardened Runtime)");
  const signed = await run("codesign", {
    args: [
      "--force",
      "--options",
      "runtime",
      "--entitlements",
      "Resources/SmartLinksOpener.entitlements",
      "--sign",
      "-",
      APP_NAME,
    ],
    allowFailure: true,
    capture: true,
  });
  if (signed.code !== 0) {
    console.log("    (codesign skipped/failed — app still runnable locally)");
  }

  await installDevCopy(APP_NAME);

  section(`Done: ${INSTALLED}`);
  console.log("    Click 'Set as default browser' in it to route links through this build.");
}

if (import.meta.main) await prod();
