#!/bin/bash
# Smart Links Opener — build & dev command interface.
#
# Standard interface (flowai): check / test / dev / prod.
#   ./build.sh prod      Build + bundle + sign (Developer ID) + register .app (default, open-source build)
#   ./build.sh appstore  Build the sandboxed Mac App Store variant (SmartLinksOpener-AppStore.app)
#   ./build.sh icon      Regenerate Resources/AppIcon.icns from Resources/AppIcon.iconset/
#   ./build.sh check     build + comment-scan + format check + tests (verification gate)
#   ./build.sh test      Run the test suite (optionally a filter: ./build.sh test <name>)
#   ./build.sh dev       Run the executable directly via `swift run`
#   ./build.sh build     Alias for `prod`
#
# Respect NO_COLOR (https://no-color.org/): this script emits no ANSI colors.
set -euo pipefail
cd "$(dirname "$0")"

APP="SmartLinksOpener.app"
BIN="SmartLinksOpener"

# --- prod: compile, assemble the .app bundle, sign, register -----------------
cmd_prod() {
    echo "==> Compiling (release)"
    swift build -c release

    echo "==> Assembling $APP"
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp ".build/release/$BIN" "$APP/Contents/MacOS/$BIN"
    cp "Resources/Info.plist" "$APP/Contents/Info.plist"

    echo "==> Copying localizations (*.lproj)"
    for lproj in Resources/*.lproj; do
        [ -d "$lproj" ] && cp -R "$lproj" "$APP/Contents/Resources/"
    done
    [ -f "Resources/AppIcon.icns" ] && cp "Resources/AppIcon.icns" "$APP/Contents/Resources/"

    echo "==> Ad-hoc code signing (Hardened Runtime)"
    codesign --force --options runtime \
        --entitlements "Resources/SmartLinksOpener.entitlements" \
        --sign - "$APP" >/dev/null 2>&1 || \
        echo "    (codesign skipped/failed — app still runnable locally)"

    echo "==> Registering with LaunchServices"
    LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    "$LSREGISTER" -f "$PWD/$APP" || true

    echo "==> Done: $PWD/$APP"
    echo "    Open it once (open $APP), then click 'Set as default browser'."
}

# --- appstore: sandboxed build for Mac App Store submission ------------------
cmd_appstore() {
    local app="SmartLinksOpener-AppStore.app"
    # Real MAS upload needs "Apple Distribution"/"3rd Party Mac Developer
    # Application: NAME (TEAMID)". Ad-hoc ("-") is fine to verify the sandbox
    # locally.
    local sign="${MAS_APP_IDENTITY:--}"

    echo "==> Compiling (release)"
    swift build -c release

    echo "==> Assembling $app (App Sandbox)"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp ".build/release/$BIN" "$app/Contents/MacOS/$BIN"
    cp "Resources/Info.plist" "$app/Contents/Info.plist"
    for lproj in Resources/*.lproj; do
        [ -d "$lproj" ] && cp -R "$lproj" "$app/Contents/Resources/"
    done
    [ -f "Resources/AppIcon.icns" ] && cp "Resources/AppIcon.icns" "$app/Contents/Resources/"

    # Each App Store upload needs a unique, increasing build number (CI sets it).
    if [ -n "${MAS_BUILD_NUMBER:-}" ]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${MAS_BUILD_NUMBER}" "$app/Contents/Info.plist"
        echo "    CFBundleVersion = ${MAS_BUILD_NUMBER}"
    fi

    # Embedded provisioning profile — required for a real MAS upload.
    if [ -n "${MAS_PROVISION_PROFILE:-}" ] && [ -f "${MAS_PROVISION_PROFILE:-}" ]; then
        cp "$MAS_PROVISION_PROFILE" "$app/Contents/embedded.provisionprofile"
    fi

    echo "==> Signing with App Sandbox entitlements (identity: $sign)"
    codesign --force \
        --entitlements "Resources/SmartLinksOpener.appstore.entitlements" \
        --sign "$sign" "$app"

    echo "==> Done: $PWD/$app (sandboxed)"
    if [ "$sign" = "-" ]; then
        echo "    NOTE: ad-hoc signed — LOCAL sandbox test only, NOT uploadable."
        echo "    For the real Mac App Store build set MAS_APP_IDENTITY +"
        echo "    MAS_PROVISION_PROFILE, then package with productbuild."
        echo "    Full playbook: documents/tasks/2026/06/open-source-and-appstore.md"
    fi
}

# --- check: the comprehensive verification gate ------------------------------
cmd_check() {
    echo "==> [1/4] Build (debug)"
    swift build

    echo "==> [2/4] Comment scan (TODO/FIXME/HACK/XXX, swiftlint:disable)"
    if grep -RInE 'TODO|FIXME|HACK|XXX|swiftlint:disable|swift-format-ignore' Sources; then
        echo "    Found leftover markers above — resolve before shipping." >&2
        exit 1
    fi
    echo "    clean"

    echo "==> [3/4] Format check (swift format lint)"
    swift format lint --strict --recursive Sources

    echo "==> [4/4] Tests"
    cmd_test

    echo "==> check passed"
}

# --- test: run the suite -----------------------------------------------------
cmd_test() {
    # Swift Package Manager exits non-zero when there is no test target yet;
    # treat "no tests" as a pass so `check` stays green until tests are added.
    if [ -d "Tests" ]; then
        if [ "$#" -gt 0 ]; then
            swift test --filter "$1"
        else
            swift test
        fi
    else
        echo "    no Tests/ target yet — skipping (add tests under Tests/ to enable)"
    fi
}

# --- dev: run the executable directly ----------------------------------------
cmd_dev() {
    echo "==> Running via swift run (Ctrl-C to stop)"
    swift run "$BIN"
}

# --- icon: regenerate AppIcon.icns from the committed iconset source ---------
cmd_icon() {
    # [REF:fr:app-icon] — the brand .icns is reproducible from Resources/AppIcon.iconset.
    echo "==> Generating Resources/AppIcon.icns from Resources/AppIcon.iconset"
    iconutil -c icns "Resources/AppIcon.iconset" -o "Resources/AppIcon.icns"
    echo "==> Done: Resources/AppIcon.icns"
}

# --- format: auto-format in place (helper) -----------------------------------
cmd_fmt() {
    swift format --in-place --recursive Sources
    echo "==> formatted Sources/"
}

case "${1:-prod}" in
    prod|build)  cmd_prod ;;
    appstore)    cmd_appstore ;;
    icon)        cmd_icon ;;
    check)       cmd_check ;;
    test)        shift; cmd_test "$@" ;;
    dev)         cmd_dev ;;
    fmt|format)  cmd_fmt ;;
    *)
        echo "Usage: ./build.sh [prod|appstore|icon|check|test|dev|fmt]" >&2
        exit 2
        ;;
esac
