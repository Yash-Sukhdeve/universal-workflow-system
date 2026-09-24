#!/bin/bash
# UWS plugin SessionStart hook.
# Injects a short, plain-text summary of the project's UWS state into Claude's
# context. Does nothing in projects that have no .workflow/ directory.
#
# The summary is built by the same code path as `recover_context.sh --hook`
# (scripts/lib/hook_context.sh), so the plugin and repo-local hooks agree.
# Never fails the session: errors go to stderr (visible with --debug) and the
# hook exits 0 without output.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
WF="${PROJECT_DIR}/.workflow"

[[ -f "${WF}/state.yaml" ]] || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RECOVER="${PLUGIN_ROOT}/scripts/recover_context.sh"

if [[ ! -f "$RECOVER" ]]; then
    echo "UWS: ${RECOVER} not found; no session context injected" >&2
    exit 0
fi

cd "$PROJECT_DIR" || exit 0
WORKFLOW_DIR="$WF" bash "$RECOVER" --hook || echo "UWS: session context hook failed" >&2
exit 0
