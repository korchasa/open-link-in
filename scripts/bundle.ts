/**
 * Assembling the Smart Links Opener .app bundle.
 *
 * Shared by `deno task prod` (local, ad-hoc signed, registered with
 * LaunchServices) and `deno task dist` (unsigned, App Store layout). Both start
 * from the same release binary and resource layout; only the icon handling and
 * the signing differ, which is why they live side by side here.
 */

import { exists, run, section } from "./lib.ts";

export const APP_NAME = "SmartLinksOpener.app";
export const BIN_NAME = "SmartLinksOpener";
export const RELEASE_BIN = `.build/release/${BIN_NAME}`;

/** Compile the release binary. */
export async function buildRelease(): Promise<void> {
  section("Compiling (release)");
  await run("swift", { args: ["build", "-c", "release"] });
}

/**
 * Lay out `<out>/Contents` with the binary, Info.plist and every localization.
 * The icon is left to the caller: the two bundles source it differently.
 */
export async function assembleBundle(out: string): Promise<void> {
  section(`Assembling ${out}`);
  await Deno.remove(out, { recursive: true }).catch(() => {});
  await Deno.mkdir(`${out}/Contents/MacOS`, { recursive: true });
  await Deno.mkdir(`${out}/Contents/Resources`, { recursive: true });
  await Deno.copyFile(RELEASE_BIN, `${out}/Contents/MacOS/${BIN_NAME}`);
  await Deno.copyFile("Resources/Info.plist", `${out}/Contents/Info.plist`);

  section("Copying localizations (*.lproj)");
  for await (const entry of Deno.readDir("Resources")) {
    if (!entry.isDirectory || !entry.name.endsWith(".lproj")) continue;
    await run("cp", {
      args: ["-R", `Resources/${entry.name}`, `${out}/Contents/Resources/`],
    });
  }
}

/**
 * Compile Resources/Assets.xcassets into the bundle.
 *
 * App Store validation (ITMS-90546) requires the icon as a compiled asset
 * catalog (Assets.car), not just a loose .icns. actool also emits an
 * AppIcon.icns capped at 256×256; leaving it in place lets ingest pick the
 * low-res file over the catalog's 1024×1024, so it is deleted afterwards.
 */
export async function compileAssetCatalog(out: string): Promise<void> {
  section("Compiling asset catalog (Assets.car)");
  await run("xcrun", {
    args: [
      "actool",
      "Resources/Assets.xcassets",
      "--compile",
      `${out}/Contents/Resources`,
      "--platform",
      "macosx",
      "--minimum-deployment-target",
      "13.0",
      "--app-icon",
      "AppIcon",
      "--output-partial-info-plist",
      ".build/assetcatalog-info.plist",
    ],
    capture: true,
  });
  await Deno.remove(`${out}/Contents/Resources/AppIcon.icns`).catch(() => {});
}

/** Copy the committed .icns, which is all the local build needs. */
export async function copyLooseIcon(out: string): Promise<void> {
  if (await exists("Resources/AppIcon.icns")) {
    await Deno.copyFile("Resources/AppIcon.icns", `${out}/Contents/Resources/AppIcon.icns`);
  }
}
