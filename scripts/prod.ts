/**
 * `deno task prod` — build the .app, sign it ad-hoc and register it with
 * LaunchServices, so the locally installed browser-router is the code you just
 * wrote. This is the open-source build; the App Store bundle is `dist`.
 */

import { run, section } from "./lib.ts";
import { APP_NAME, assembleBundle, buildRelease, copyLooseIcon } from "./bundle.ts";

const LSREGISTER =
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

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

  section("Registering with LaunchServices");
  await run(LSREGISTER, { args: ["-f", `${Deno.cwd()}/${APP_NAME}`], allowFailure: true });

  section(`Done: ${Deno.cwd()}/${APP_NAME}`);
  console.log(`    Open it once (open ${APP_NAME}), then click 'Set as default browser'.`);
}

if (import.meta.main) await prod();
