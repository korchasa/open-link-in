/**
 * `deno task dist` — assemble the UNSIGNED Mac App Store bundle.
 *
 * Signing (codesign with the distribution identity, embedding the provisioning
 * profile) and .pkg packaging are NOT done here — they happen outside this
 * repository. This task only produces the bundle. The App Sandbox is declared
 * in Resources/SmartLinksOpener.appstore.entitlements and applied at signing
 * time, so the layout below carries no entitlements of its own.
 */

import { section } from "./lib.ts";
import { APP_NAME, assembleBundle, buildRelease, compileAssetCatalog } from "./bundle.ts";

const OUT = `.build/dist/${APP_NAME}`;

export async function dist(): Promise<void> {
  await buildRelease();
  await assembleBundle(OUT);
  await compileAssetCatalog(OUT);

  section(`Done (unsigned): ${Deno.cwd()}/${OUT}`);
  console.log("    Signing + .pkg packaging happen outside this repository.");
}

if (import.meta.main) await dist();
