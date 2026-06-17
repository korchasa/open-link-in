#!/bin/bash
# Claude Code Stop hook — Smart Links Opener post-task gate.
#
# Flow: run ./build.sh check.
#   pass  -> ./build.sh prod (rebuild bundle) -> kill running app -> relaunch.
#   fail  -> feed the check output back to Claude (decision:block) so it fixes
#            before finishing; on a repeat failure just report, to avoid loops.
#
# Reads the Stop-hook JSON on stdin; uses .stop_hook_active as the loop guard.
# Respects NO_COLOR (https://no-color.org/).
set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/Users/korchasa/www/personal/open-link-in}"
APP="SmartLinksOpener.app"
LOG="$(mktemp -t slo-stop-hook.XXXXXX)"

input="$(cat)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"

cd "$PROJECT_DIR" 2>/dev/null || {
    jq -n --arg d "$PROJECT_DIR" \
        '{systemMessage: ("post-task hook: project dir not found: " + $d)}'
    rm -f "$LOG"
    exit 0
}

if NO_COLOR=1 ./build.sh check >"$LOG" 2>&1; then
    if NO_COLOR=1 ./build.sh prod >>"$LOG" 2>&1; then
        pkill -9 -f "$APP" 2>/dev/null || true
        open "$APP" 2>/dev/null || true
        echo '{"systemMessage":"✅ check passed → app rebuilt & restarted"}'
    else
        jq -n --arg t "$(tail -40 "$LOG")" \
            '{systemMessage: ("⚠️ check passed but ./build.sh prod failed:\n" + $t)}'
    fi
    rm -f "$LOG"
    exit 0
fi

# check failed
out="$(tail -60 "$LOG")"
rm -f "$LOG"
if [ "$stop_active" = "true" ]; then
    # Already fed back once and check still fails — surface to the user, do not loop.
    jq -n --arg t "$out" '{systemMessage: ("❌ ./build.sh check still failing:\n" + $t)}'
    exit 0
fi
jq -n --arg t "$out" \
    '{decision: "block", reason: ("./build.sh check failed — fix before finishing:\n" + $t)}'
exit 0
