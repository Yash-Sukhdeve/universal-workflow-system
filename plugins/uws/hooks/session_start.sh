#!/bin/bash
# UWS plugin SessionStart hook.
# Injects a short, plain-text summary of the project's UWS state into Claude's
# context. Does nothing in projects that have no .workflow/ directory.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
WF="${PROJECT_DIR}/.workflow"
STATE="${WF}/state.yaml"

[[ -f "$STATE" ]] || exit 0

# Flat top-level key reader: key: "value"  ->  value
val() {
    grep -E "^$1:" "$STATE" 2>/dev/null | head -1 | cut -d: -f2- | sed -e 's/^ *//' -e 's/^"//' -e 's/"$//' || true
}

ctx="UWS workflow state for this project (.workflow/):"
for key in goal current_phase sdlc_phase research_phase current_checkpoint; do
    v="$(val "$key")"
    [[ -n "$v" && "$v" != "null" ]] && ctx+=$'\n'"- ${key}: ${v}"
done

if [[ -f "${WF}/checkpoints.log" ]]; then
    recent="$(grep -E '\| CP_' "${WF}/checkpoints.log" 2>/dev/null | tail -3 || true)"
    [[ -n "$recent" ]] && ctx+=$'\n'"Recent checkpoints:"$'\n'"${recent}"
fi

ctx+=$'\n'"Commands: /uws:status, /uws:checkpoint <msg>, /uws:recover, /uws:handoff, /uws:sdlc, /uws:research. Read .workflow/handoff.md for the full handoff."

# JSON-escape (backslash, quote, tab, CR, newline) with portable sed/awk
esc="$(printf '%s' "$ctx" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' | awk 'NR>1{printf "\\n"} {printf "%s", $0}')"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
exit 0
