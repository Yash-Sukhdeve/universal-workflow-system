#!/bin/bash
#
# Handoff Utilities - keep .workflow/handoff.md trustworthy.
#
# handoff.md mixes two kinds of content:
#   - a UWS-managed summary (date, phase, checkpoint, goal) derived from
#     state.yaml, delimited by
#         <!-- uws:managed:start -->
#         ...
#         <!-- uws:managed:end -->
#   - everything else (Critical Context, Next Actions, Blockers, Notes,
#     appended transition logs), which is written by people and agents and
#     is NEVER rewritten here.
#
# uws_handoff_sync rewrites only the managed block. Handoffs created before
# the markers existed are migrated in place: their "## Last Session Summary"
# section (heading up to the next "## " heading) becomes the managed block.
#
# Public functions:
#   uws_handoff_render_block <state_file> [checkpoints_log]
#   uws_handoff_sync [handoff_file] [state_file]

# Guard against double-sourcing
if [[ "${_UWS_HANDOFF_UTILS_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UWS_HANDOFF_UTILS_LOADED="true"

_UWS_HU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_UWS_HU_DIR}/hook_context.sh"

UWS_HANDOFF_START='<!-- uws:managed:start -->'
UWS_HANDOFF_END='<!-- uws:managed:end -->'

# ISO-8601 timestamp; BSD date before macOS 13 has no -I
_uws_hu_now() {
    date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z
}

#######################################
# Render the managed block (markers included) from state.yaml.
# Arguments: $1 - state file, $2 - (optional) checkpoints.log
#            (default: next to the state file)
#######################################
uws_handoff_render_block() {
    local state="$1"
    local log="${2:-$(dirname "$state")/checkpoints.log}"
    local phase sdlc research cp goal ptype desc="" methodology=""

    phase="$(uws_state_value "$state" current_phase)"
    sdlc="$(uws_state_value "$state" sdlc_phase)"
    research="$(uws_state_value "$state" research_phase)"
    cp="$(uws_state_value "$state" current_checkpoint)"
    goal="$(uws_state_value "$state" goal)"
    ptype="$(uws_state_value "$state" project_type project.type)"

    [[ -n "$sdlc" ]] && methodology="sdlc: ${sdlc}"
    if [[ -n "$research" ]]; then
        [[ -n "$methodology" ]] && methodology+=", "
        methodology+="research: ${research}"
    fi

    # Description of the current checkpoint, from its log line
    if [[ -n "$cp" && -f "$log" ]]; then
        desc="$(grep -E "\|[[:space:]]*${cp}[[:space:]]*\|" "$log" 2>/dev/null | tail -1 \
            | sed -e 's/^[^|]*|[^|]*|[[:space:]]*//' || true)"
    fi

    echo "$UWS_HANDOFF_START"
    echo "<!-- Maintained by UWS from .workflow/state.yaml on every checkpoint and phase change; edits inside this block are overwritten. -->"
    echo "## Last Session Summary"
    echo "- **Date**: $(_uws_hu_now)"
    echo "- **Phase**: ${phase:-unknown}"
    [[ -n "$methodology" ]] && echo "- **Methodology phase**: ${methodology}"
    if [[ -n "$desc" ]]; then
        echo "- **Checkpoint**: ${cp} - ${desc}"
    else
        echo "- **Checkpoint**: ${cp:-none}"
    fi
    echo "- **Goal**: ${goal:-(none declared; set with: uws sdlc goal \"...\" or uws research goal \"...\")}"
    [[ -n "$ptype" ]] && echo "- **Project type**: ${ptype}"
    echo "$UWS_HANDOFF_END"
}

#######################################
# Rewrite the managed block of handoff.md from state.yaml, leaving every other
# line byte-for-byte intact. No-op (success) if either file is missing.
#   - markers present      -> replace start..end (inclusive); extra managed
#                             blocks, if any, are removed
#   - no markers, legacy   -> the "## Last Session Summary" section is replaced
#     summary section         by the managed block (one-time migration)
#   - neither              -> the block is inserted after the H1 title (or at
#                             the top when there is no title)
# A start marker without a matching end marker is treated as corrupt: the
# dangling marker line is dropped and the file is handled as unmarked.
# Arguments: $1 - handoff file (default: $WORKFLOW_DIR/handoff.md)
#            $2 - state file   (default: next to the handoff file)
#######################################
uws_handoff_sync() {
    local file="${1:-${WORKFLOW_DIR:-.workflow}/handoff.md}"
    local state="${2:-$(dirname "$file")/state.yaml}"
    [[ -f "$file" && -f "$state" ]] || return 0

    local block tmp starts ends mode
    block="$(mktemp "${TMPDIR:-/tmp}/uws_handoff_block.XXXXXX")" || return 1
    tmp="$(mktemp "${TMPDIR:-/tmp}/uws_handoff_new.XXXXXX")" || { rm -f "$block"; return 1; }

    if ! uws_handoff_render_block "$state" > "$block"; then
        rm -f "$block" "$tmp"
        return 1
    fi

    starts="$(grep -cF "$UWS_HANDOFF_START" "$file" 2>/dev/null || true)"
    ends="$(grep -cF "$UWS_HANDOFF_END" "$file" 2>/dev/null || true)"
    if [[ "${starts:-0}" -gt 0 && "${ends:-0}" -gt 0 ]]; then
        mode="markers"
    elif grep -qE '^## Last Session Summary' "$file" 2>/dev/null; then
        mode="legacy"
    else
        mode="insert"
    fi

    if awk -v mode="$mode" -v bf="$block" -v s="$UWS_HANDOFF_START" -v e="$UWS_HANDOFF_END" '
        function emit(   l) {
            while ((getline l < bf) > 0) print l
            close(bf)
            emitted = 1
        }
        mode == "markers" {
            if (skipping) { if (index($0, e) == 1) skipping = 0; next }
            if (index($0, s) == 1) {
                if (!emitted) emit()
                skipping = 1
                next
            }
            if (index($0, e) == 1) next      # stray end marker
            print
            next
        }
        # legacy / insert: drop any dangling marker lines
        index($0, s) == 1 || index($0, e) == 1 { next }
        mode == "legacy" {
            if (skipping) {
                if ($0 ~ /^## /) { skipping = 0 } else { next }
            } else if (!emitted && $0 ~ /^## Last Session Summary/) {
                emit(); print ""; skipping = 1; next
            }
            print
            next
        }
        mode == "insert" {
            if (!emitted && NR == 1 && $0 ~ /^# /) { print; print ""; emit(); next }
            if (!emitted) { emit(); print "" }
            print
        }
        END { if (!emitted) emit() }
    ' "$file" > "$tmp"; then
        # Replace content in place (keeps the file's inode and permissions)
        local rc=0
        cat "$tmp" > "$file" || rc=1
        rm -f "$tmp" "$block"
        return "$rc"
    fi
    rm -f "$tmp" "$block"
    return 1
}
