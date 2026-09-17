#!/bin/bash
# Claude Code Stop hook — Smart Links Opener post-task gate.
#
# Flow: run `deno task check`.
#   pass  -> report; the task itself rebuilds the bundle and relaunches the app
#            as its last step outside CI, so nothing more is needed here.
#   fail  -> feed the check output back to Claude (decision:block) so it fixes
#            before finishing; on a repeat failure just report, to avoid loops.
#
# Reads the Stop-hook JSON on stdin; uses .stop_hook_active as the loop guard.
# Respects NO_COLOR (https://no-color.org/).
set -uo pipefail

# Claude Code sets CLAUDE_PROJECT_DIR. The fallback derives the repository
# from the hook's own location — it lives in <repo>/.claude/hooks — so a
# hand-run works too and no absolute path is baked in.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG="$(mktemp -t slo-stop-hook.XXXXXX)"

input="$(cat)"
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false')"

cd "$PROJECT_DIR" 2>/dev/null || {
    jq -n --arg d "$PROJECT_DIR" \
        '{systemMessage: ("post-task hook: project dir not found: " + $d)}'
    rm -f "$LOG"
    exit 0
}

if NO_COLOR=1 deno task check >"$LOG" 2>&1; then
    rm -f "$LOG"
    echo '{"systemMessage":"✅ deno task check passed → app rebuilt & relaunched"}'
    exit 0
fi

# check failed
out="$(tail -60 "$LOG")"
rm -f "$LOG"
if [ "$stop_active" = "true" ]; then
    # Already fed back once and check still fails — surface to the user, do not loop.
    jq -n --arg t "$out" '{systemMessage: ("❌ deno task check still failing:\n" + $t)}'
    exit 0
fi
jq -n --arg t "$out" \
    '{decision: "block", reason: ("deno task check failed — fix before finishing:\n" + $t)}'
exit 0
