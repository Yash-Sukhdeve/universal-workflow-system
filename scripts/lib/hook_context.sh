#!/bin/bash
#
# Hook Context Library - compact, plain-text session context for Claude Code.
#
# Builds the text UWS injects into the model's context at SessionStart and
# wraps it in the SessionStart hook JSON contract:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
#
# Design constraints (the context window is a shared, scarce resource):
#   - plain text only: no ANSI escapes, emoji or box drawing
#   - bounded size: UWS_HOOK_MAX_BYTES (default 1200) for the whole text
#   - read-only: never writes state (a hook must not dirty the working tree)
#   - portable: bash 3.2, BSD sed/awk/tr (no GNU-only flags)
#
# Public functions:
#   uws_state_value <state_file> <key> [fallback_nested_key]
#   uws_real_checkpoints <checkpoints_log> [count]
#   uws_handoff_items <handoff_file> <heading_regex> [max]
#   uws_git_summary <project_root>
#   uws_hook_context <workflow_dir>
#   uws_json_escape <text>
#   uws_hook_json <workflow_dir>

# Guard against double-sourcing
if [[ "${_UWS_HOOK_CONTEXT_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UWS_HOOK_CONTEXT_LOADED="true"

UWS_HOOK_MAX_BYTES="${UWS_HOOK_MAX_BYTES:-1200}"

#######################################
# Read a scalar from state.yaml without yq.
# Accepts both quoted (grep/sed writers) and unquoted (yq writers) scalars.
# Arguments: $1 - state file, $2 - top-level key, $3 - (optional) nested
#            "parent.child" key tried when the flat key is absent/empty
# Outputs: value, or nothing when absent / null / empty
#######################################
uws_state_value() {
    local file="$1" key="$2" alt="${3:-}" v=""
    [[ -f "$file" ]] || return 0
    v="$(grep -E "^${key}:" "$file" 2>/dev/null | head -1 | sed -e 's/^[^:]*:[[:space:]]*//' -e 's/[[:space:]]*$//' || true)"
    if [[ -z "$v" || "$v" == "null" || "$v" == '""' || "$v" == "''" ]] && [[ -n "$alt" ]]; then
        local parent="${alt%%.*}" child="${alt#*.}"
        v="$(awk -v p="$parent" -v c="$child" '
            /^[^[:space:]#]/ { insec = ($0 ~ ("^" p ":")) ; next }
            insec && $0 ~ ("^  " c ":") {
                sub("^  " c ":[[:space:]]*", ""); sub("[[:space:]]*$", ""); print; exit
            }' "$file" 2>/dev/null || true)"
    fi
    # Strip one pair of surrounding quotes
    case "$v" in
        \"*\") v="${v#\"}"; v="${v%\"}" ;;
        \'*\') v="${v#\'}"; v="${v%\'}" ;;
    esac
    [[ "$v" == "null" ]] && v=""
    printf '%s' "$v"
}

#######################################
# Print the last N real checkpoint lines ("TS | CP_x_nnn | description").
# Comments, INIT, AUTO pre-commit entries and AGENT_*/SKILL_* events are
# excluded: only lines whose ID field starts with CP_ count.
# Arguments: $1 - checkpoints.log, $2 - count (default 3)
#######################################
uws_real_checkpoints() {
    local log="$1" n="${2:-3}"
    [[ -f "$log" ]] || return 0
    grep -E '^[^#].*\|[[:space:]]*CP_[A-Za-z0-9_]+[[:space:]]*\|' "$log" 2>/dev/null | tail -n "$n" || true
}

#######################################
# List top-level list items from the FIRST handoff section whose heading
# matches a (lower-case, extended) regex. Checked "[x]" items and
# placeholders ("None", "N/A", "_..._") are skipped; "- [ ] " prefixes are
# normalised to "- ".
# Arguments: $1 - handoff.md, $2 - heading regex, $3 - max items (default 5)
#######################################
uws_handoff_items() {
    local file="$1" re="$2" max="${3:-5}"
    [[ -f "$file" ]] || return 0
    awk -v re="$re" -v max="$max" '
        /^#+[[:space:]]/ {
            if (insec) { done = 1 }
            h = tolower($0)
            insec = (!done && h ~ re)
            next
        }
        insec && /^([-*+]|[0-9]+[.)])[[:space:]]/ {
            line = $0
            if (line ~ /^[-*+][[:space:]]+\[[xX]\]/) next
            sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/, "", line)
            sub(/^\[[[:space:]]\][[:space:]]*/, "", line)
            sub(/[[:space:]]+$/, "", line)
            low = tolower(line)
            if (line == "" || low ~ /^(none|n\/a|-|tbd)[.]?$/ || line ~ /^_.*_$/) next
            print "- " line
            if (++count >= max) exit
        }
    ' "$file" 2>/dev/null || true
}

#######################################
# One-line git summary for a project root, or nothing outside a repo.
# Counts come from `git status --porcelain` columns: X (index) = staged,
# Y (worktree) = modified, "??" = untracked.
# Arguments: $1 - project root
#######################################
uws_git_summary() {
    local root="$1" branch counts
    command -v git >/dev/null 2>&1 || return 0
    git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0
    branch="$(git -C "$root" branch --show-current 2>/dev/null || true)"
    [[ -z "$branch" ]] && branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [[ -z "$branch" || "$branch" == "HEAD" ]] && branch="(detached)"
    # GIT_OPTIONAL_LOCKS=0: a read-only hook must not take the index lock
    counts="$(GIT_OPTIONAL_LOCKS=0 git -C "$root" status --porcelain 2>/dev/null | awk '
        { x = substr($0, 1, 1); y = substr($0, 2, 1)
          if (x == "?") { u++ } else { if (x != " ") s++; if (y != " ") m++ } }
        END { printf "%d modified, %d staged, %d untracked", m, s, u }' || true)"
    printf 'Git: branch %s; %s' "$branch" "${counts:-status unavailable}"
}

#######################################
# Truncate to at most N bytes without splitting a UTF-8 character.
# Trailing non-ASCII bytes of a cut string are dropped whole, then "..." added.
# Arguments: $1 - text, $2 - max bytes
#######################################
_uws_trunc() {
    local LC_ALL=C
    local s="$1" max="$2" c
    if (( ${#s} <= max )); then
        printf '%s' "$s"
        return 0
    fi
    s="${s:0:$((max - 3))}"
    while [[ -n "$s" ]]; do
        c="${s:${#s}-1:1}"
        case "$c" in
            [[:alnum:][:punct:][:space:]]) break ;;
            *) s="${s%?}" ;;
        esac
    done
    printf '%s...' "$s"
}

# Byte length (locale-independent)
_uws_bytes() {
    local LC_ALL=C
    printf '%s' "${#1}"
}

#######################################
# Build a titled section into the global _UWS_SECTION (empty if nothing fits),
# admitting items one by one while the caller's `used` stays within the
# caller's `budget`; sets the caller's `omitted=true` when an item is dropped.
# Uses bash dynamic scoping: only call from uws_hook_context.
# Arguments: $1 - title, $2 - newline-separated items, $3 - per-item byte cap
#######################################
_uws_ctx_section() {
    _UWS_SECTION=""
    [[ -n "$2" ]] || return 0
    local chunk="$1" it added=0 cost
    cost=$(( $(_uws_bytes "$1") + 1 ))
    while IFS= read -r it; do
        [[ -n "$it" ]] || continue
        it="$(_uws_trunc "$it" "$3")"
        if (( used + cost + $(_uws_bytes "$it") + 1 > budget )); then
            omitted=true
            break
        fi
        chunk+=$'\n'"${it}"
        cost=$(( cost + $(_uws_bytes "$it") + 1 ))
        added=$((added + 1))
    done <<< "$2"
    if (( added > 0 )); then
        _UWS_SECTION=$'\n'"${chunk}"
        used=$(( used + cost ))
    fi
    return 0
}

#######################################
# Build the plain-text session context (<= UWS_HOOK_MAX_BYTES bytes).
# Arguments: $1 - workflow dir (the project's .workflow)
# Outputs: text on stdout; nothing if state.yaml is absent
#######################################
uws_hook_context() {
    local wf="$1"
    local state="${wf}/state.yaml" log="${wf}/checkpoints.log" handoff="${wf}/handoff.md"
    [[ -f "$state" ]] || return 0
    local root
    root="$(cd "${wf}/.." 2>/dev/null && pwd)" || root="."

    local goal ptype cphase sdlc research cp updated
    goal="$(uws_state_value "$state" goal)"
    ptype="$(uws_state_value "$state" project_type project.type)"
    cphase="$(uws_state_value "$state" current_phase)"
    sdlc="$(uws_state_value "$state" sdlc_phase)"
    research="$(uws_state_value "$state" research_phase)"
    cp="$(uws_state_value "$state" current_checkpoint)"
    updated="$(uws_state_value "$state" last_updated metadata.last_updated)"

    local head="UWS workflow state (.workflow/ in this project):"
    head+=$'\n'"- goal: $(_uws_trunc "${goal:-(none declared)}" 220)"
    [[ -n "$ptype" ]]    && head+=$'\n'"- project_type: ${ptype}"
    head+=$'\n'"- current_phase: ${cphase:-unknown}"
    [[ -n "$sdlc" ]]     && head+=$'\n'"- sdlc_phase: ${sdlc}"
    [[ -n "$research" ]] && head+=$'\n'"- research_phase: ${research}"
    head+=$'\n'"- current_checkpoint: ${cp:-none}"
    [[ -n "$updated" ]]  && head+=$'\n'"- last_updated: ${updated}"

    local tail="" git
    git="$(uws_git_summary "$root")"
    [[ -n "$git" ]] && tail+="${git}"$'\n'
    tail+="Full handoff: .workflow/handoff.md. Save progress with /uws:checkpoint <msg> (or: uws checkpoint create <msg>)."

    local note="(some items omitted; read .workflow/handoff.md)"
    local budget
    budget=$(( UWS_HOOK_MAX_BYTES - $(_uws_bytes "$head") - $(_uws_bytes "$tail") - $(_uws_bytes "$note") - 4 ))

    # Variable-length sections are admitted in priority order (blockers, next
    # actions, recent checkpoints) while they fit, then shown in reading order.
    local used=0 omitted=false items s_block="" s_next="" s_cps=""
    items="$(uws_handoff_items "$handoff" 'blocker' 3)"
    _uws_ctx_section "Blockers (handoff.md):" "$items" 140
    s_block="$_UWS_SECTION"
    items="$(uws_handoff_items "$handoff" '(next (actions|steps)|priority actions|todo)' 5)"
    _uws_ctx_section "Next actions (handoff.md):" "$items" 140
    s_next="$_UWS_SECTION"
    # Newest first, so a tight budget drops the oldest entry
    items="$(uws_real_checkpoints "$log" 3 \
        | awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }' \
        | sed -e 's/^\([0-9-]*T[0-9][0-9]:[0-9][0-9]\)[^ |]*/\1/' -e 's/^/- /')"
    _uws_ctx_section "Recent checkpoints (newest first):" "$items" 140
    s_cps="$_UWS_SECTION"

    local out="${head}${s_cps}${s_next}${s_block}"
    [[ "$omitted" == "true" ]] && out+=$'\n'"${note}"
    out+=$'\n'"${tail}"
    # Final hard cap (defensive: fixed lines are already bounded)
    _uws_trunc "$out" "$UWS_HOOK_MAX_BYTES"
    printf '\n'
}

#######################################
# Escape text for a JSON string literal. Control characters other than tab
# and newline are dropped (this also removes any ANSI ESC), then backslash,
# quote and tab are escaped and newlines joined as \n. Portable sed/awk/tr.
# Arguments: $1 - text
#######################################
uws_json_escape() {
    local tab
    tab="$(printf '\t')"
    printf '%s' "$1" \
        | LC_ALL=C tr -d '\000-\010\013-\037\177' \
        | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/${tab}/\\\\t/g" \
        | LC_ALL=C awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

#######################################
# Emit one line of SessionStart hook JSON, or nothing when the directory is
# not a UWS project.
# Arguments: $1 - workflow dir
#######################################
uws_hook_json() {
    local wf="$1" ctx
    [[ -f "${wf}/state.yaml" ]] || return 0
    ctx="$(uws_hook_context "$wf")"
    [[ -n "$ctx" ]] || return 0
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
        "$(uws_json_escape "$ctx")"
}
