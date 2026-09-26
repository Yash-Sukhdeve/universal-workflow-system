#!/usr/bin/env bats
# Context hygiene regression tests.
#
# What UWS injects into Claude's context at session start must be small,
# correct, plain text and current. Each test pins one defect that shipped:
#   - recovery read project.type / metadata.last_updated, so a real (flat)
#     state.yaml showed "Project Type: null" and "Last Updated: null"
#   - completeness scored an obsolete nested schema (every project ~61%)
#   - the SessionStart hook piped ~6 KB of ANSI/emoji/box-drawing output
#   - handoff.md was written once at init and went stale
#   - "Recent Checkpoints" listed comment lines and AGENT_*/SKILL_* events

load '../helpers/test_helper'

setup() {
    setup_test_environment
    # A bare user project initialized the way users do it
    PROJ="$(mktemp -d)"
    git -C "$PROJ" init -q
    git -C "$PROJ" config user.email "test@test.com"
    git -C "$PROJ" config user.name "Test User"
    # The helper exports WORKFLOW_DIR for its own fixture; these tests resolve
    # the project from the working directory like a real session does
    unset WORKFLOW_DIR
}

teardown() {
    rm -rf "$PROJ"
    teardown_test_environment
}

init_project() {
    (cd "$PROJ" && UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null 2>&1)
}

hook() {
    (cd "$PROJ" && "${PROJECT_ROOT}/scripts/recover_context.sh" --hook)
}

hook_context() {
    hook | jq -r '.hookSpecificOutput.additionalContext'
}

# ── --hook output contract ───────────────────────────────────────────────────

@test "hook: emits one line of valid SessionStart JSON" {
    init_project
    run hook
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | type == "string" and length > 0'
}

@test "hook: output is under 1.5 KB and contains no ESC characters" {
    init_project
    run hook
    [ "$status" -eq 0 ]
    local bytes
    bytes=$(printf '%s' "$output" | LC_ALL=C wc -c | tr -d ' ')
    [ "$bytes" -lt 1536 ]
    run bash -c "printf '%s' \"\$1\" | LC_ALL=C grep -c $'\\033'" _ "$output"
    [ "$output" = "0" ]
}

@test "hook: stays under 1.5 KB with a huge handoff and long checkpoint messages" {
    init_project
    local i long
    long="$(printf 'x%.0s' $(seq 1 400))"
    for i in 1 2 3 4 5 6; do
        echo "2026-01-0${i}T10:00:00Z | CP_1_10${i} | ${long}" >> "$PROJ/.workflow/checkpoints.log"
    done
    {
        echo "## Next Actions"
        for i in $(seq 1 50); do echo "- [ ] action ${i} ${long}"; done
        echo "## Blockers"
        for i in $(seq 1 20); do echo "- blocker ${i} ${long}"; done
    } >> "$PROJ/.workflow/handoff.md"
    run hook
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    local bytes
    bytes=$(printf '%s' "$output" | LC_ALL=C wc -c | tr -d ' ')
    [ "$bytes" -lt 1536 ]
    # The newest checkpoint survives the budget
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("CP_1_106")'
}

@test "hook: reads the flat state schema (project_type, goal, last_updated)" {
    init_project
    source "${PROJECT_ROOT}/scripts/lib/portable.sh"
    sed_inplace 's/^goal:.*/goal: "Ship the parser"/' "$PROJ/.workflow/state.yaml"
    run hook_context
    [ "$status" -eq 0 ]
    [[ "$output" == *"goal: Ship the parser"* ]]
    [[ "$output" == *"project_type: software"* ]]
    [[ "$output" == *"current_phase: phase_1_planning"* ]]
    [[ "$output" == *"current_checkpoint: CP_1_001"* ]]
    [[ "$output" =~ last_updated:\ [0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
    [[ "$output" != *"null"* ]]
}

@test "hook: accepts unquoted scalars as written by yq" {
    init_project
    cat > "$PROJ/.workflow/state.yaml" <<'EOF'
project_type: research
goal: Measure recovery latency
current_phase: phase_2_implementation
current_checkpoint: CP_2_004
last_updated: 2026-01-01T00:00:00Z
research_phase: data_collection
EOF
    run hook_context
    [ "$status" -eq 0 ]
    [[ "$output" == *"goal: Measure recovery latency"* ]]
    [[ "$output" == *"research_phase: data_collection"* ]]
    [[ "$output" == *"current_checkpoint: CP_2_004"* ]]
}

@test "hook: JSON-escapes quotes, backslashes, tabs and control characters" {
    init_project
    printf 'goal: "say \\"hi\\" C:\\\\tmp\ttab \033[31mred"\n' > "$PROJ/.workflow/goal.tmp"
    grep -v '^goal:' "$PROJ/.workflow/state.yaml" > "$PROJ/.workflow/state.new"
    cat "$PROJ/.workflow/goal.tmp" >> "$PROJ/.workflow/state.new"
    mv "$PROJ/.workflow/state.new" "$PROJ/.workflow/state.yaml"
    run hook
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *'say \"hi\"'* ]]
    [[ "$ctx" == *$'\t'"tab"* ]]
    # ESC removed, the rest of the text kept
    [[ "$ctx" != *$'\033'* ]]
    [[ "$ctx" == *"[31mred"* ]]
}

@test "hook: silent outside UWS projects" {
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/recover_context.sh' --hook"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "hook: is read-only (state.yaml and handoff.md unchanged)" {
    init_project
    local before_state before_handoff
    before_state="$(cat "$PROJ/.workflow/state.yaml")"
    before_handoff="$(cat "$PROJ/.workflow/handoff.md")"
    run hook
    [ "$status" -eq 0 ]
    [ "$(cat "$PROJ/.workflow/state.yaml")" = "$before_state" ]
    [ "$(cat "$PROJ/.workflow/handoff.md")" = "$before_handoff" ]
}

@test "hook: lists next actions and blockers from handoff.md" {
    init_project
    # Replace the template sections with user content
    awk '
        /^## Next Actions/ { print; print "- [ ] Wire the parser"; print "- [x] Done already"; skip=1; next }
        /^## Blockers/ { print; print "- Waiting on API key"; skip=1; next }
        /^## / { skip=0 }
        !skip { print }
    ' "$PROJ/.workflow/handoff.md" > "$PROJ/h.tmp" && mv "$PROJ/h.tmp" "$PROJ/.workflow/handoff.md"
    run hook_context
    [ "$status" -eq 0 ]
    [[ "$output" == *"- Wire the parser"* ]]
    [[ "$output" != *"Done already"* ]]
    [[ "$output" == *"Blockers (handoff.md):"* ]]
    [[ "$output" == *"- Waiting on API key"* ]]
}

@test "hook: git line reports branch and change counts" {
    init_project
    echo "x" > "$PROJ/new_file.txt"
    run hook_context
    [ "$status" -eq 0 ]
    [[ "$output" =~ Git:\ branch\ [^\;]+\;\ [0-9]+\ modified,\ [0-9]+\ staged,\ [1-9][0-9]*\ untracked ]]
}

@test "plugin hook uses the same code path as recover_context.sh --hook" {
    init_project
    local direct plugin
    direct="$(hook | jq -r '.hookSpecificOutput.additionalContext')"
    plugin="$(cd "$PROJ" && CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}/plugins/uws" \
        "${PROJECT_ROOT}/plugins/uws/hooks/session_start.sh" | jq -r '.hookSpecificOutput.additionalContext')"
    [ -n "$direct" ]
    [ "$direct" = "$plugin" ]
}

@test "repo settings.json: SessionStart runs recover_context.sh --hook without discarding stderr" {
    local cmd
    cmd="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "${PROJECT_ROOT}/.claude/settings.json")"
    [[ "$cmd" == *"recover_context.sh --hook"* ]]
    # Errors from the script reach Claude Code's hook log instead of vanishing
    [[ "$cmd" != *"recover_context.sh --hook 2>"* ]]
    [[ "$cmd" != *"recover_context.sh 2>"* ]]
    # ...but a failure never blocks the session
    [[ "$cmd" == *"|| true"* ]]
}

# ── Checkpoint list hygiene ──────────────────────────────────────────────────

@test "checkpoints: comment, INIT/AUTO and AGENT_/SKILL_/PHASE_ event lines are excluded" {
    init_project
    cat >> "$PROJ/.workflow/checkpoints.log" <<'EOF'
2026-01-01T10:00:00Z | AGENT_ACTIVATED | researcher
2026-01-01T10:00:30Z | AGENT_DISPATCHED | architect
2026-01-01T10:01:00Z | SKILL_ENABLED | literature_review
2026-01-01T10:02:00Z | AUTO | Pre-commit checkpoint
2026-01-01T10:03:00Z | PHASE_TRANSITION | sdlc: requirements -> design
2026-01-01T10:04:00Z | CP_1_002 | Real work saved
EOF
    run hook_context
    [ "$status" -eq 0 ]
    [[ "$output" == *"CP_1_002 | Real work saved"* ]]
    [[ "$output" != *"Format:"* ]]
    [[ "$output" != *"AGENT_ACTIVATED"* ]]
    [[ "$output" != *"AGENT_DISPATCHED"* ]]
    [[ "$output" != *"SKILL_ENABLED"* ]]
    [[ "$output" != *"AUTO"* ]]
    [[ "$output" != *"PHASE_TRANSITION"* ]]
    [[ "$output" != *"| INIT |"* ]]

    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/recover_context.sh' </dev/null"
    [ "$status" -eq 0 ]
    local section
    section="$(printf '%s\n' "$output" | awk '/Recent Checkpoints:/{f=1;next} /Active Agent:/{f=0} f')"
    [[ "$section" == *"CP_1_002 - Real work saved"* ]]
    [[ "$section" != *"Format"* ]]
    [[ "$section" != *"AGENT_ACTIVATED"* ]]
    [[ "$section" != *"AGENT_DISPATCHED"* ]]
    [[ "$section" != *"SKILL_ENABLED"* ]]
    [[ "$section" != *"PHASE_TRANSITION"* ]]
    [[ "$section" != *"INIT"* ]]
}

# ── Human-mode recovery ──────────────────────────────────────────────────────

@test "recover: human mode reads the flat schema (no null project type or date)" {
    init_project
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/recover_context.sh' </dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Project Type:     software"* ]]
    [[ "$output" =~ Last\ Updated:\ +[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
    [[ "$output" != *": null"* ]]
    [[ "$output" != *"Score: 61%"* ]]
}

@test "recover: no ANSI escapes when stdout is not a terminal" {
    init_project
    # stdout and stderr (log lines) both piped, neither is a terminal
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/recover_context.sh' </dev/null 2>&1 | LC_ALL=C grep -c $'\\033'"
    [ "$output" = "0" ]
}

@test "recover: NO_COLOR disables colour" {
    init_project
    run bash -c "cd '$PROJ' && NO_COLOR=1 '${PROJECT_ROOT}/scripts/recover_context.sh' </dev/null 2>&1 | LC_ALL=C grep -c $'\\033'"
    [ "$output" = "0" ]
}

# ── Completeness ─────────────────────────────────────────────────────────────

@test "completeness: a freshly initialized project scores 100%" {
    init_project
    run bash -c "cd '$PROJ' && source '${PROJECT_ROOT}/scripts/lib/completeness_utils.sh' 2>/dev/null && calculate_completeness_score"
    [ "$status" -eq 0 ]
    [ "$output" = "100" ]
    run bash -c "cd '$PROJ' && source '${PROJECT_ROOT}/scripts/lib/completeness_utils.sh' 2>/dev/null && check_required_fields"
    [ -z "$output" ]
}

@test "completeness: recovery report shows 100% for a fresh project" {
    init_project
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/recover_context.sh' </dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Score: 100% [GOOD]"* ]]
}

# ── Handoff trustworthiness ──────────────────────────────────────────────────

@test "handoff: init template states facts, points at uws recover, has managed markers" {
    init_project
    local h="$PROJ/.workflow/handoff.md"
    run grep -c "Ready to begin planning phase" "$h"
    [ "$output" = "0" ]
    run grep -c "scripts/recover_context.sh" "$h"
    [ "$output" = "0" ]
    grep -q "uws recover" "$h"
    grep -q "/uws:recover" "$h"
    [ "$(grep -c '<!-- uws:managed:start -->' "$h")" -eq 1 ]
    [ "$(grep -c '<!-- uws:managed:end -->' "$h")" -eq 1 ]
    grep -q -- "- \*\*Phase\*\*: phase_1_planning" "$h"
    grep -q -- "- \*\*Checkpoint\*\*: CP_1_001" "$h"
    grep -q "1. Project type: software" "$h"
}

@test "handoff: checkpoint refreshes the managed block and keeps user-written sections" {
    init_project
    local h="$PROJ/.workflow/handoff.md"
    # A user edits the handoff outside the managed block
    awk '
        /^## Next Actions/ { print; print "- [ ] USER: wire the parser"; skip=1; next }
        /^## / { skip=0 }
        !skip { print }
    ' "$h" > "$PROJ/h.tmp" && mv "$PROJ/h.tmp" "$h"
    echo "Custom note written by a human." >> "$h"
    local outside_before
    outside_before="$(sed '/<!-- uws:managed:start -->/,/<!-- uws:managed:end -->/d' "$h")"

    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/checkpoint.sh' create 'Parser milestone' </dev/null"
    [ "$status" -eq 0 ]

    grep -q -- "- \*\*Checkpoint\*\*: CP_1_002 - Parser milestone" "$h"
    grep -q -- "- \[ \] USER: wire the parser" "$h"
    grep -q "Custom note written by a human." "$h"
    [ "$(sed '/<!-- uws:managed:start -->/,/<!-- uws:managed:end -->/d' "$h")" = "$outside_before" ]
    [ "$(grep -c '<!-- uws:managed:start -->' "$h")" -eq 1 ]
    # The snapshot carries the refreshed handoff
    grep -q "CP_1_002 - Parser milestone" "$PROJ/.workflow/checkpoints/snapshots/CP_1_002/handoff.md"
}

@test "handoff: checkpoint updates flat last_updated in state.yaml" {
    init_project
    source "${PROJECT_ROOT}/scripts/lib/portable.sh"
    sed_inplace 's/^last_updated:.*/last_updated: "2000-01-01T00:00:00Z"/' "$PROJ/.workflow/state.yaml"
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/checkpoint.sh' create 'touch' </dev/null"
    [ "$status" -eq 0 ]
    run grep -c '2000-01-01' "$PROJ/.workflow/state.yaml"
    [ "$output" = "0" ]
    # Quote style depends on the writer (sed fallback: "..", yq: plain or '..')
    grep -qE "^last_updated: [\"']?[0-9]{4}-" "$PROJ/.workflow/state.yaml"
}

@test "handoff: legacy handoff is migrated into a managed block once, human text kept" {
    init_project
    local h="$PROJ/.workflow/handoff.md"
    cat > "$h" <<'EOF'
# Context Handoff Document

## Last Session Summary
- **Date**: 2020-01-01T00:00:00Z
- **Phase**: implementation
- **Checkpoint**: CP_1_023
- **Working on**: Initial setup
## Critical Context
1. Uses Postgres 15, not SQLite

## Next Actions
- [ ] Human-written action

## Agent Activated: researcher
- **When**: 2020-01-02T00:00:00Z
- **Responsibilities**:
  - Some stale, machine-written text

## Phase Transition: requirements -> design
- **When**: 2020-01-02T00:00:00Z
EOF
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/checkpoint.sh' create 'after migration' </dev/null"
    [ "$status" -eq 0 ]
    [ "$(grep -c '<!-- uws:managed:start -->' "$h")" -eq 1 ]
    [ "$(grep -c '<!-- uws:managed:end -->' "$h")" -eq 1 ]
    [ "$(grep -c '^## Last Session Summary' "$h")" -eq 1 ]
    run grep -cE "Working on|2020-01-01T00:00:00Z|CP_1_023" "$h"
    [ "$output" = "0" ]
    # Human-written sections and content survive byte-for-byte
    grep -q "1. Uses Postgres 15, not SQLite" "$h"
    grep -q -- "- \[ \] Human-written action" "$h"
    grep -q -- "- \*\*Checkpoint\*\*: CP_1_002 - after migration" "$h"
    # Machine-generated sections are removed, not kept
    run grep -cE "## (Agent Activated|Phase Transition):" "$h"
    [ "$output" = "0" ]
    run grep -c "Some stale, machine-written text" "$h"
    [ "$output" = "0" ]
    # A timestamped backup of the pre-migration file was written
    local backups
    backups=$(find "$PROJ/.workflow" -maxdepth 1 -name 'handoff.md.bak-*' | wc -l | tr -d ' ')
    [ "$backups" = "1" ]
    grep -q "## Agent Activated: researcher" "$PROJ/.workflow"/handoff.md.bak-*
    grep -q "## Phase Transition: requirements -> design" "$PROJ/.workflow"/handoff.md.bak-*

    # Idempotent: a second refresh keeps exactly one block, no new backup
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/checkpoint.sh' create 'again' </dev/null"
    [ "$status" -eq 0 ]
    [ "$(grep -c '<!-- uws:managed:start -->' "$h")" -eq 1 ]
    [ "$(grep -c '^## Last Session Summary' "$h")" -eq 1 ]
    backups=$(find "$PROJ/.workflow" -maxdepth 1 -name 'handoff.md.bak-*' | wc -l | tr -d ' ')
    [ "$backups" = "1" ]
}

@test "handoff: phase change refreshes the managed block (goal and methodology phase)" {
    init_project
    local h="$PROJ/.workflow/handoff.md"
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/sdlc.sh' start </dev/null"
    [ "$status" -eq 0 ]
    grep -q -- "- \*\*Methodology phase\*\*: sdlc: requirements" "$h"
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/sdlc.sh' goal 'Ship the parser' </dev/null"
    [ "$status" -eq 0 ]
    grep -q -- "- \*\*Goal\*\*: Ship the parser" "$h"
    [ "$(grep -c '<!-- uws:managed:start -->' "$h")" -eq 1 ]
}

# ── Bounded growth (the defect this file exists to pin) ─────────────────────

@test "handoff: line count stays bounded across repeated phase transitions" {
    init_project
    local h="$PROJ/.workflow/handoff.md"
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/sdlc.sh' start </dev/null"
    [ "$status" -eq 0 ]
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/sdlc.sh' goal 'Ship the parser' </dev/null"
    [ "$status" -eq 0 ]

    local lines_after_2 lines_after_10 target i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        target="design"; [ $(( i % 2 )) -eq 0 ] && target="requirements"
        run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/sdlc.sh' goto ${target} --force </dev/null"
        [ "$status" -eq 0 ]
        [ "$i" -eq 2 ]  && lines_after_2=$(wc -l < "$h")
        [ "$i" -eq 10 ] && lines_after_10=$(wc -l < "$h")
    done

    [ "$lines_after_10" -eq "$lines_after_2" ]
    # Every transition is still recorded, just not in handoff.md
    [ "$(grep -c 'PHASE_TRANSITION' "$PROJ/.workflow/checkpoints.log")" -eq 10 ]
    # Never appended: exactly one managed block, no stray "## Phase Transition" section
    [ "$(grep -c '<!-- uws:managed:start -->' "$h")" -eq 1 ]
    run grep -c '^## Phase Transition:' "$h"
    [ "$output" = "0" ]
}

@test "handoff: line count stays bounded across repeated agent dispatches" {
    init_project
    local h="$PROJ/.workflow/handoff.md"
    local agents=(researcher architect implementer experimenter optimizer deployer documenter researcher architect implementer)
    local lines_after_2 lines_after_10 i=0 a
    for a in "${agents[@]}"; do
        i=$(( i + 1 ))
        run bash -c "cd '$PROJ' && source '${PROJECT_ROOT}/scripts/lib/workflow_routing.sh' && record_active_agent '${a}' </dev/null"
        [ "$status" -eq 0 ]
        [ "$i" -eq 2 ]  && lines_after_2=$(wc -l < "$h")
        [ "$i" -eq 10 ] && lines_after_10=$(wc -l < "$h")
    done

    [ "$lines_after_10" -eq "$lines_after_2" ]
    [ "$(grep -c 'AGENT_DISPATCHED' "$PROJ/.workflow/checkpoints.log")" -eq 10 ]
    [ "$(grep -c '^active_agent:' "$PROJ/.workflow/state.yaml")" -eq 1 ]
    [ "$(grep -c '<!-- uws:managed:start -->' "$h")" -eq 1 ]
    run grep -c '^## Agent Activated:' "$h"
    [ "$output" = "0" ]
    grep -q -- "- \*\*Active agent\*\*: implementer (docs/personas/implementer.md)" "$h"
}

@test "handoff: managed block shows the current phase's deliverables and remaining count" {
    init_project
    local h="$PROJ/.workflow/handoff.md"
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/sdlc.sh' start </dev/null && '${PROJECT_ROOT}/scripts/sdlc.sh' goal 'Ship the parser' </dev/null"
    [ "$status" -eq 0 ]
    grep -q -- "- \*\*Deliverables (sdlc: requirements)\*\* - 0/3 done, 3 remaining:" "$h"
    grep -q -- "  - Requirements document with user stories and acceptance criteria" "$h"

    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/sdlc.sh' check 1 </dev/null"
    [ "$status" -eq 0 ]
    run bash -c "cd '$PROJ' && '${PROJECT_ROOT}/scripts/checkpoint.sh' create 'partial' </dev/null"
    [ "$status" -eq 0 ]
    grep -q -- "- \*\*Deliverables (sdlc: requirements)\*\* - 1/3 done, 2 remaining:" "$h"
    # The checked-off item no longer appears in the remaining list
    run grep -c -- "- Requirements document with user stories and acceptance criteria" "$h"
    [ "$output" = "0" ]
    grep -q -- "  - Non-functional requirements defined" "$h"
}

@test "status and checkpoint show the last real checkpoint, not event lines, and survive apostrophes" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    "${PROJECT_ROOT}/bin/uws" checkpoint create "fixed the user's login flow" </dev/null >/dev/null
    # An event logged after the checkpoint must not be shown as the last checkpoint
    echo "2026-01-01T00:00:00Z | AGENT_DISPATCHED | implementer" >> .workflow/checkpoints.log

    # Recent checkpoints are listed in verbose mode
    run "${PROJECT_ROOT}/bin/uws" status --verbose </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"fixed the user's login flow"* ]]
    [[ "$output" != *"AGENT_DISPATCHED"* ]]
    [[ "$output" != *"unmatched"* ]]

    run "${PROJECT_ROOT}/bin/uws" checkpoint status </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"fixed the user's login flow"* ]]
    [[ "$output" != *"unmatched"* ]]
}
