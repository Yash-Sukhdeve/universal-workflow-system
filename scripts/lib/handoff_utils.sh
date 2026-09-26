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
#   uws_handoff_strip_machine_sections <handoff_file>   (called by uws_handoff_sync)

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
# Phase deliverables text for the managed block. Intentionally mirrored from
# get_phase_deliverables() in scripts/sdlc.sh and scripts/research.sh rather
# than sourced from there: those scripts run `main "$@"` unconditionally at
# EOF, so sourcing them would execute a CLI invocation as a side effect of
# rendering a handoff summary. Kept here instead of a new shared lib per
# "Minimal Files" — if this ever drifts from sdlc.sh/research.sh, extract one.
# Arguments: $1 - methodology (sdlc|research), $2 - phase
# Outputs: one "- ..." line per deliverable (possibly none)
#######################################
_uws_hu_deliverables() {
    local m="$1" phase="$2"
    case "$m" in
        sdlc)
            case "$phase" in
                requirements)
                    echo "- Requirements document with user stories and acceptance criteria"
                    echo "- Non-functional requirements defined"
                    echo "- Failure modes documented for each feature"
                    ;;
                design)
                    echo "- Architecture document with component diagram"
                    echo "- API specification with all endpoints"
                    echo "- Database schema documented"
                    echo "- Config system defined"
                    ;;
                implementation)
                    echo "- All features implemented per design"
                    echo "- No stubbed or placeholder code"
                    echo "- Dependencies declared in requirements file"
                    ;;
                verification)
                    echo "- All tests pass"
                    echo "- Input validation on all models"
                    echo "- Security review completed"
                    ;;
                deployment)
                    echo "- Docker/container build succeeds"
                    echo "- Health endpoint responds"
                    echo "- README updated with setup instructions"
                    ;;
            esac
            ;;
        research)
            case "$phase" in
                hypothesis)
                    echo "- Research question (RQ) stated"
                    echo "- Testable, falsifiable hypothesis defined"
                    echo "- Variables and expected outcomes identified"
                    ;;
                literature_review)
                    echo "- Survey of prior work related to the hypothesis"
                    echo "- Gap analysis documented"
                    echo "- Key references catalogued with citations"
                    ;;
                experiment_design)
                    echo "- Experimental methodology defined"
                    echo "- Sample size and controls specified"
                    echo "- Data-collection protocol documented"
                    ;;
                data_collection)
                    echo "- Data collected per protocol"
                    echo "- Deviations from protocol documented"
                    ;;
                analysis)
                    echo "- Statistical analysis performed"
                    echo "- Hypothesis tested against results"
                    echo "- Visualizations generated"
                    ;;
                peer_review)
                    echo "- Manuscript prepared for review"
                    echo "- Reviewer feedback addressed"
                    ;;
                publication)
                    echo "- Findings written up (paper/report)"
                    echo "- Figures and tables prepared"
                    echo "- Submitted to venue"
                    ;;
            esac
            ;;
    esac
}

#######################################
# Read-only total/done counts from the methodology_progress ledger (see
# mp_ensure/mark_deliverable in workflow_routing.sh for the writer side and
# the single-line-entry format rationale). Reimplemented here rather than
# sourced, matching this file's existing "small self-contained reader" style
# (see uws_state_value in hook_context.sh).
# Arguments: $1 - state file, $2 - methodology, $3 - phase
# Outputs: "<total> <done>" (both 0 when the ledger has no entry yet)
#######################################
_uws_hu_ledger_counts() {
    local file="$1" key="${2}_${3}" line total="0" done_n="0" inner
    line="$(grep "^  ${key}:" "$file" 2>/dev/null | head -1 || true)"
    if [[ -n "$line" ]]; then
        total="$(printf '%s' "$line" | sed -n 's/.*total:[[:space:]]*\([0-9]*\).*/\1/p')"
        [[ -z "$total" ]] && total="0"
        inner="$(printf '%s' "$line" | sed -n 's/.*done:[[:space:]]*\[\([^]]*\)\].*/\1/p' | tr -d '[:space:]')"
        if [[ -n "$inner" ]]; then
            done_n="$(printf '%s' "$inner" | tr ',' '\n' | grep -c '[0-9]' || true)"
        fi
    fi
    echo "${total} ${done_n}"
}

#######################################
# Read-only "done" index list ("1,3") for the ledger entry, used to skip
# already-checked deliverables when rendering the remaining list.
# Arguments: $1 - state file, $2 - methodology, $3 - phase
#######################################
_uws_hu_ledger_done_csv() {
    local file="$1" key="${2}_${3}" line
    line="$(grep "^  ${key}:" "$file" 2>/dev/null | head -1 || true)"
    [[ -z "$line" ]] && return 0
    printf '%s' "$line" | sed -n 's/.*done:[[:space:]]*\[\([^]]*\)\].*/\1/p' | tr -d '[:space:]'
}

#######################################
# Render one "Deliverables" line + indented bullets for the managed block:
# remaining (not-yet-checked) deliverables of the current phase, with a
# done/total count from the ledger when one has been seeded (goal declared
# and at least one `sdlc.sh check`/`research.sh check` or phase transition
# has run). Capped at 5 bullets to keep the block short. Empty output (no
# lines at all) when the phase has no known deliverables.
# Arguments: $1 - state file, $2 - methodology, $3 - phase
#######################################
_uws_hu_render_deliverables() {
    local state="$1" m="$2" phase="$3"
    local counts total done_n remaining done_csv line i=0 shown=0 header body=""
    counts="$(_uws_hu_ledger_counts "$state" "$m" "$phase")"
    total="${counts% *}"; done_n="${counts#* }"
    done_csv="$(_uws_hu_ledger_done_csv "$state" "$m" "$phase")"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        i=$((i + 1))
        [[ -n "$done_csv" && ",${done_csv}," == *",${i},"* ]] && continue
        body+=$'\n'"  ${line}"
        shown=$((shown + 1))
        (( shown >= 5 )) && break
    done < <(_uws_hu_deliverables "$m" "$phase")

    [[ -z "$body" && "$i" -eq 0 ]] && return 0

    if [[ "${total:-0}" -gt 0 ]]; then
        remaining=$(( total - done_n ))
        (( remaining < 0 )) && remaining=0
        header="- **Deliverables (${m}: ${phase})** - ${done_n}/${total} done, ${remaining} remaining:"
    else
        header="- **Deliverables (${m}: ${phase})**:"
    fi
    [[ -z "$body" ]] && header+=" (all done)"
    printf '%s%s\n' "$header" "$body"
}

#######################################
# Render the managed block (markers included) from state.yaml.
# Arguments: $1 - state file, $2 - (optional) checkpoints.log
#            (default: next to the state file)
#######################################
uws_handoff_render_block() {
    local state="$1"
    local log="${2:-$(dirname "$state")/checkpoints.log}"
    local phase sdlc research cp goal ptype desc="" methodology="" agent agent_status

    phase="$(uws_state_value "$state" current_phase)"
    sdlc="$(uws_state_value "$state" sdlc_phase)"
    research="$(uws_state_value "$state" research_phase)"
    cp="$(uws_state_value "$state" current_checkpoint)"
    goal="$(uws_state_value "$state" goal)"
    ptype="$(uws_state_value "$state" project_type project.type)"
    agent="$(uws_state_value "$state" _uws_no_such_key active_agent.name)"
    agent_status="$(uws_state_value "$state" _uws_no_such_key active_agent.status)"

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
    if [[ -n "$agent" && "$agent_status" == "active" ]]; then
        echo "- **Active agent**: ${agent} (docs/personas/${agent}.md)"
    fi
    [[ -n "$sdlc" ]] && _uws_hu_render_deliverables "$state" sdlc "$sdlc"
    [[ -n "$research" ]] && _uws_hu_render_deliverables "$state" research "$research"
    echo "$UWS_HANDOFF_END"
}

#######################################
# One-shot migration: remove machine-generated "## Agent Activated: ..." and
# "## Phase Transition: ..." sections (a section = the heading line through
# the line before the next "## " heading, or EOF). The now-retired
# scripts/activate_agent.sh and scripts/sdlc.sh used to append one of these
# on every agent activation / phase transition, which is exactly what made
# handoff.md grow without bound; agent dispatches and phase transitions now
# log a one-line event to checkpoints.log instead (already
# excluded from recovered context by uws_real_checkpoints in
# hook_context.sh, which only admits "| CP_..." lines). Everything else in
# the file — including any blank line immediately before a stripped heading,
# which is not part of the section per the definition above — is left
# byte-for-byte intact. Idempotent: a no-op (no backup, no rewrite) when
# neither pattern is present, which is true again right after the first run.
# Arguments: $1 - handoff file
#######################################
uws_handoff_strip_machine_sections() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    grep -qE '^## (Agent Activated|Phase Transition): ' "$file" 2>/dev/null || return 0

    local tmp bak
    tmp="$(mktemp "${TMPDIR:-/tmp}/uws_handoff_strip.XXXXXX")" || return 1
    if awk '
        /^## Agent Activated: / || /^## Phase Transition: / { skip = 1; next }
        skip && /^## / { skip = 0 }
        skip { next }
        { print }
    ' "$file" > "$tmp"; then
        bak="${file}.bak-$(date +%Y%m%d%H%M%S 2>/dev/null || echo 0)"
        cp "$file" "$bak" 2>/dev/null || { rm -f "$tmp"; return 1; }
        cat "$tmp" > "$file" || { rm -f "$tmp"; return 1; }
        rm -f "$tmp"
        return 0
    fi
    rm -f "$tmp"
    return 1
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
# Also runs uws_handoff_strip_machine_sections first (see above), so an old,
# growing handoff.md is cleaned up the next time it refreshes.
# Arguments: $1 - handoff file (default: $WORKFLOW_DIR/handoff.md)
#            $2 - state file   (default: next to the handoff file)
#######################################
uws_handoff_sync() {
    local file="${1:-${WORKFLOW_DIR:-.workflow}/handoff.md}"
    local state="${2:-$(dirname "$file")/state.yaml}"
    [[ -f "$file" && -f "$state" ]] || return 0

    uws_handoff_strip_machine_sections "$file" || true

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
