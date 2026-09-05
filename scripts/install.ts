/**
 * The copy of the current build that lives in /Applications as "Reroute Dev".
 *
 * `prod` assembles the bundle and then calls this, so the locally installed
 * copy is always the build you just made. What ships to the store is not that
 * copy — it arrives signed from outside this repository and is installed by
 * the App Store under the real name and bundle id — so the two must sit side
 * by side. This one is therefore renamed and given its own bundle id: with
 * identical ids LaunchServices would choose between two apps with the same
 * identity, and it does not choose the one you just built.
 *
 * Being a browser, the dev copy registers for http/https like any other, so it
 * shows up in the store build's own browser list (and the store build in its).
 * Hide it there if it gets in the way. Its rules live under its own defaults
 * domain and start empty.
 *
 * The packaging plists are never touched: every rename is made in the copy
 * under /Applications.
 */

import { fail, run, section } from "./lib.ts";

const DEV_NAME = "Reroute Dev";
const DEV_ID = "dev.korchasa.SmartLinksOpener.dev";
export const INSTALLED = `/Applications/${DEV_NAME}.app`;
const LSREGISTER =
  "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister";

/** Replace one plist value, leaving the rest of the file exactly as it was. */
async function setValue(plist: string, key: string, value: string): Promise<void> {
  const text = await Deno.readTextFile(plist);
  const pattern = new RegExp(`(<key>${key}</key>\\s*<string>)[^<]*(</string>)`);
  if (!pattern.test(text)) fail(`${plist} has no ${key} to set`);
  await Deno.writeTextFile(plist, text.replace(pattern, `$1${value}$2`));
}

/** The commit this build came from, so the About panel says which one it is. */
async function commit(): Promise<string> {
  const head = await run("git", {
    args: ["rev-parse", "--short", "HEAD"],
    capture: true,
    allowFailure: true,
  });
  if (head.code !== 0) return "unknown";
  const dirty = await run("git", {
    args: ["status", "--porcelain"],
    capture: true,
    allowFailure: true,
  });
  return head.stdout.trim() + (dirty.stdout.trim() === "" ? "" : "+");
}

/** Put `bundle` in /Applications under the local name and id, and relaunch it. */
export async function installDevCopy(bundle: string): Promise<void> {
  section(`Installing ${INSTALLED}`);
  const existing = await Deno.stat(INSTALLED).catch(() => null);
  if (existing) {
    const writable = await run("test", { args: ["-w", INSTALLED], allowFailure: true });
    if (writable.code !== 0) {
      fail(`${INSTALLED} is not yours to replace — remove it with sudo and run this again`);
    }
  }
  // A running copy keeps its old code until it is relaunched, and a stale
  // menu-bar agent is exactly the confusion this script exists to prevent.
  await run("pkill", { args: ["-f", `${INSTALLED}/Contents/MacOS/`], allowFailure: true });
  await Deno.remove(INSTALLED, { recursive: true }).catch(() => {});
  await run("cp", { args: ["-R", bundle, INSTALLED] });

  section("Naming it apart from the store build");
  const plist = `${INSTALLED}/Contents/Info.plist`;
  const version = await run("/usr/bin/plutil", {
    args: ["-extract", "CFBundleShortVersionString", "raw", "-o", "-", "--", plist],
    capture: true,
  });
  await setValue(plist, "CFBundleName", DEV_NAME);
  await setValue(plist, "CFBundleDisplayName", DEV_NAME);
  await setValue(plist, "CFBundleIdentifier", DEV_ID);
  await setValue(
    plist,
    "CFBundleShortVersionString",
    `${version.stdout.trim()}-dev ${await commit()}`,
  );

  // Editing the plist broke the seal made at assembly; seal it again over the
  // names it now carries (ad-hoc, Hardened Runtime, same entitlements).
  section("Signing the dev copy (ad-hoc)");
  await run("codesign", {
    args: [
      "--force",
      "--options",
      "runtime",
      "--entitlements",
      "Resources/SmartLinksOpener.entitlements",
      "--sign",
      "-",
      INSTALLED,
    ],
  });

  // The bundle assembled in the repo carries the store bundle id; leaving it
  // registered would give LaunchServices two apps with that id.
  section("Registering it with LaunchServices");
  await run(LSREGISTER, { args: ["-u", `${Deno.cwd()}/${bundle}`], allowFailure: true });
  await run(LSREGISTER, { args: ["-f", INSTALLED] });

  // A GUI-less session (SSH, sandbox) cannot launch an Aqua app and `open`
  // fails with -600; the copy is installed by then, so only warn.
  section(`Launching ${DEV_NAME}`);
  const opened = await run("open", { args: [INSTALLED], allowFailure: true, capture: true });
  if (opened.code !== 0) {
    console.error(`    warning: could not launch ${INSTALLED} (no GUI session?)`);
  }
  section(`install: ${INSTALLED} is this build`);
}
