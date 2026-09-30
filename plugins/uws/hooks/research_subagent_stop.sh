#!/bin/bash
# UWS plugin SubagentStop hook for the research team (docs/design/research-team.md
# section 6.7, layer L2). It runs `research_check.py role-exit` when a research subagent
# (uws-rt-scout, uws-rt-verifier, uws-rt-redteam) tries to stop.
#
# Hook contract (Claude Code hooks reference, https://code.claude.com/docs/en/hooks,
# section "SubagentStop", checked 2026-09-26):
#   - stdin is JSON with the common fields plus stop_hook_active, agent_id, agent_type,
#     agent_transcript_path and last_assistant_message. agent_type is the value the
#     matcher filters on; plugin agents can appear plugin-scoped (for example
#     "uws:uws-rt-verifier"), so hooks.json matches both forms.
#   - "A hook that blocks by exiting 2 delivers its stderr message the same way" as a
#     decision "block" reason: the subagent keeps running with that text as its next
#     instruction. Exit 0 lets it stop.
#   - A subagent that ends with the SubagentHandback tool delivers its report as that
#     tool's input, so role-exit also reads the handback message from the transcript.
# Why here and not in agent frontmatter: "plugin subagents don't support the hooks,
# mcpServers, or permissionMode frontmatter fields. These fields are ignored when loading
# agents from a plugin" (https://code.claude.com/docs/en/sub-agents, checked 2026-09-26).
#
# Bounded retries: role-exit counts failures per agent_id and blocks at most
# UWS_RESEARCH_HOOK_RETRIES times (default 2). After that the subagent may stop and a
# blocker is written to .workflow/logs/decisions.log, so a stuck agent cannot loop.
#
# Fails open on its own errors (python3 missing, checker crash): the phase gate
# (research.sh next -> research_check.py gate) is the main control and still applies.

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
[[ -d "${PROJECT_DIR}/research/ledger" ]] || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CHECK="${PLUGIN_ROOT}/scripts/research_check.py"

if ! command -v python3 >/dev/null 2>&1; then
    echo "UWS: python3 not found; research exit checks skipped (the phase gate still applies)" >&2
    exit 0
fi
if [[ ! -f "$CHECK" ]]; then
    echo "UWS: ${CHECK} not found; research exit checks skipped" >&2
    exit 0
fi

input="$(cat)"
rc=0
out="$(printf '%s' "$input" | python3 "$CHECK" --root "$PROJECT_DIR" role-exit 2>&1)" || rc=$?

case "$rc" in
    0)
        exit 0
        ;;
    10)
        # Block: the text goes back to the subagent as its next instruction.
        printf '%s\n' "$out" >&2
        exit 2
        ;;
    11)
        # Retries exhausted: let it stop, record a blocker for the lead and the PI.
        blocker_id=""
        if [[ -d "${PROJECT_DIR}/.workflow" && -f "${PLUGIN_ROOT}/scripts/lib/decision_utils.sh" ]]; then
            desc="$(printf '%s' "$out" | tr '\n\r"\\' "  ''")"
            blocker_id="$(
                cd "$PROJECT_DIR" || exit 1
                export DECISION_LOG_DIR="${PROJECT_DIR}/.workflow/logs"
                # shellcheck source=/dev/null
                source "${PLUGIN_ROOT}/scripts/lib/decision_utils.sh" >/dev/null 2>&1 || exit 1
                log_blocker "$desc" "research-exit-check" "high" "research-team" 2>/dev/null | tail -1
            )" || blocker_id=""
        fi
        python3 -c 'import json, sys; print(json.dumps({"systemMessage": sys.argv[1]}))' \
            "UWS research team: ${out} Blocker ${blocker_id:-not recorded (no .workflow/)}." 2>/dev/null || true
        exit 0
        ;;
    *)
        echo "UWS: research exit check could not run (exit ${rc}): ${out}" >&2
        exit 0
        ;;
esac
