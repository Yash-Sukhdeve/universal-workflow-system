#!/bin/bash
# UWS plugin PreCompact hook: checkpoint the project's workflow state before
# Claude compacts the conversation. Does nothing without a .workflow/ directory.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ -f "${PROJECT_DIR}/.workflow/state.yaml" ]] || exit 0

cd "$PROJECT_DIR" || exit 0
export WORKFLOW_DIR="${PROJECT_DIR}/.workflow"
# stdout is not shown to the model for PreCompact; keep the log line on stderr for --debug
if "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/checkpoint.sh" \
        create "Auto-checkpoint before context compaction" >/dev/null 2>&1; then
    echo "UWS: checkpoint created before compaction" >&2
else
    echo "UWS: pre-compaction checkpoint failed (run /uws:checkpoint manually)" >&2
fi
exit 0
