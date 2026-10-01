#!/usr/bin/env bats
# Installability regression tests.
#
# Every test here pins a bug that made UWS impossible to install for a new user
# while the rest of the suite stayed green: the suite exercised scripts inside
# this repository, never the artifacts a user's project actually receives.

load '../helpers/test_helper'

INSTALLER="${PROJECT_ROOT}/claude-code-integration/install.sh"
PLUGIN_DIR="${PROJECT_ROOT}/plugins/uws"

setup() {
    setup_test_environment
    # A bare user project: git repo, no UWS files, no scripts/ directory
    PROJ="$(mktemp -d)"
    git -C "$PROJ" init -q
}

teardown() {
    rm -rf "$PROJ"
    teardown_test_environment
}

install_into_project() {
    (cd "$PROJ" && bash "$INSTALLER" "$@" </dev/null)
}

# ── Claude Code installer (claude-code-integration/install.sh) ─────────────

@test "installer: runs unattended with --yes and no terminal" {
    run install_into_project --yes
    [ "$status" -eq 0 ]
}

@test "installer: runs with no terminal and no flags (curl | bash case)" {
    run install_into_project
    [ "$status" -eq 0 ]
}

@test "installer: slash commands are .md files (Claude Code ignores other names)" {
    install_into_project --yes
    local cmd
    for cmd in uws uws-status uws-checkpoint uws-recover uws-handoff uws-sdlc uws-research; do
        [ -f "$PROJ/.claude/commands/${cmd}.md" ]
        [ ! -e "$PROJ/.claude/commands/${cmd}" ]
    done
}

@test "installer: hooks use the nested event -> matcher group -> hooks format" {
    install_into_project --yes
    local s="$PROJ/.claude/settings.json"
    run jq -e '.hooks | type == "object"' "$s"
    [ "$status" -eq 0 ]
    run jq -e '.hooks.SessionStart[0].hooks[0].type == "command"' "$s"
    [ "$status" -eq 0 ]
    run jq -e '.hooks.PreCompact[0].hooks[0].command | test("\\.uws/hooks/pre_compact\\.sh")' "$s"
    [ "$status" -eq 0 ]
}

@test "installer: SessionStart hook emits valid hookSpecificOutput JSON" {
    install_into_project --yes
    run bash -c "cd '$PROJ' && CLAUDE_PROJECT_DIR='$PROJ' .uws/hooks/session_start.sh"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
    echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Checkpoint:"
    # grep -c || echo 0 used to print "0\n0"
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$(echo "$ctx" | grep -A1 'Modified files:' | tail -1)" != "0" ]] || false
}

@test "installer: upgrade migrates a v1.2.0 flat hooks array and keeps other permissions" {
    mkdir -p "$PROJ/.claude" "$PROJ/.uws"
    echo "1.2.0" > "$PROJ/.uws/version"
    cat > "$PROJ/.claude/settings.json" <<'EOF'
{
  "permissions": { "allow": ["Bash(git:*)", "Bash(sed:*)", "Bash(npm test:*)"] },
  "hooks": [ { "event": "SessionStart", "type": "command", "command": "./.uws/hooks/session_start.sh" } ]
}
EOF
    printf '# UWS internal hooks (session-specific)\n.uws/\n\n# Claude Code project config\n.claude/\nnode_modules/\n' > "$PROJ/.gitignore"

    run install_into_project --yes
    [ "$status" -eq 0 ]
    local s="$PROJ/.claude/settings.json"
    run jq -e '.hooks | type == "object"' "$s";                       [ "$status" -eq 0 ]
    run jq -e '.hooks.SessionStart | length == 1' "$s";                [ "$status" -eq 0 ]
    run jq -e '.permissions.allow | index("Bash(npm test:*)")' "$s";   [ "$status" -eq 0 ]
    run jq -e '.permissions.allow | index("Bash(git:*)") | not' "$s";  [ "$status" -eq 0 ]
    run grep -cx -e ".uws/" -e ".claude/" "$PROJ/.gitignore"
    [ "$output" = "0" ]
    grep -qx "node_modules/" "$PROJ/.gitignore"
}

@test "installer: re-running is idempotent (one hook group per event)" {
    install_into_project --yes
    install_into_project --yes
    run jq -e '(.hooks.SessionStart | length) == 1 and (.hooks.PreCompact | length) == 1' "$PROJ/.claude/settings.json"
    [ "$status" -eq 0 ]
}

@test "installer: bundled checkpoint script advances the checkpoint" {
    install_into_project --yes
    run env -u WORKFLOW_DIR bash -c "cd '$PROJ' && ./.uws/scripts/checkpoint.sh 'first | second'"
    [ "$status" -eq 0 ]
    grep -q "| CP_1_002 | first - second$" "$PROJ/.workflow/checkpoints.log"
    grep -Eq 'current_checkpoint: "?CP_1_002"?$' "$PROJ/.workflow/state.yaml"
}

@test "installer: generated commands contain no GNU-only sed -i.bak or date -I" {
    install_into_project --yes
    run grep -rE "sed -i [^.]|date -I" "$PROJ/.claude/commands" "$PROJ/.uws"
    [ "$status" -eq 1 ]
}

# ── Global CLI (bin/uws) ──────────────────────────────────────────────────

@test "cli: uws init + status + checkpoint work in a project without scripts/" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true run "${PROJECT_ROOT}/bin/uws" init software </dev/null
    [ "$status" -eq 0 ]
    [ ! -e "$PROJ/uws" ]   # global CLI in use, so no per-project wrapper
    run "${PROJECT_ROOT}/bin/uws" status </dev/null
    [ "$status" -eq 0 ]
    run "${PROJECT_ROOT}/bin/uws" checkpoint create "cli check" </dev/null
    [ "$status" -eq 0 ]
    grep -q "cli check" "$PROJ/.workflow/checkpoints.log"
}

@test "cli: uws status succeeds without a terminal or TERM (agents, hooks, CI)" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    run env -u TERM "${PROJECT_ROOT}/bin/uws" status </dev/null
    [ "$status" -eq 0 ]
}

@test "init: non-interactive re-run leaves existing .workflow in place" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    echo "# keep me" >> "$PROJ/.workflow/state.yaml"
    UWS_SKIP_VECTOR_MEMORY=true run "${PROJECT_ROOT}/bin/uws" init software </dev/null
    [ "$status" -eq 0 ]
    grep -q "# keep me" "$PROJ/.workflow/state.yaml"
    run compgen -G "$PROJ/.workflow.backup.*"
    [ "$status" -ne 0 ]
}

@test "init: an existing pre-commit hook is not overwritten" {
    mkdir -p "$PROJ/.git/hooks"
    printf '#!/bin/sh\necho project-hook\n' > "$PROJ/.git/hooks/pre-commit"
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true run "${PROJECT_ROOT}/bin/uws" init software </dev/null
    [ "$status" -eq 0 ]
    grep -q "project-hook" "$PROJ/.git/hooks/pre-commit"
}

# ── Claude Code plugin (plugins/uws, .claude-plugin/marketplace.json) ─────

@test "plugin: marketplace lists the uws plugin from ./plugins/uws" {
    local m="${PROJECT_ROOT}/.claude-plugin/marketplace.json"
    run jq -e '.name == "uws" and (.owner.name | length > 0)' "$m"
    [ "$status" -eq 0 ]
    run jq -e '.plugins[] | select(.name == "uws") | .source == "./plugins/uws"' "$m"
    [ "$status" -eq 0 ]
}

@test "plugin: manifest, hooks and bundled CLI are in place" {
    run jq -e '.name == "uws" and (.author | type == "object")' "$PLUGIN_DIR/.claude-plugin/plugin.json"
    [ "$status" -eq 0 ]
    run jq -e '.hooks.SessionStart[0].hooks[0].command | test("CLAUDE_PLUGIN_ROOT")' "$PLUGIN_DIR/hooks/hooks.json"
    [ "$status" -eq 0 ]
    [ -x "$PLUGIN_DIR/bin/uws" ]
    [ -x "$PLUGIN_DIR/scripts/init_workflow.sh" ]
    [ -f "$PLUGIN_DIR/agents/uws-architect.md" ]
    # `uws dashboard` serves <install>/dashboard via scripts/start_dashboard.sh
    [ -x "$PLUGIN_DIR/scripts/start_dashboard.sh" ]
    [ -f "$PLUGIN_DIR/dashboard/index.html" ]
    grep -q '<title>UWS Dashboard</title>' "$PLUGIN_DIR/dashboard/index.html"
}

@test "plugin: every command calls the plugin's own uws, never a PATH lookup" {
    local f
    for f in "$PLUGIN_DIR"/commands/*.md "$PLUGIN_DIR"/skills/*/SKILL.md; do
        if grep -qE '(^|[`!( ])uws (init|status|checkpoint|recover|sdlc|research|kb|orchestrate|dashboard)' "$f"; then
            echo "PATH-dependent uws call in $f" >&2
            return 1
        fi
    done
}

@test "plugin: ships the uws-kb skill and /uws:kb command, in step with the repo copy" {
    [ -f "$PLUGIN_DIR/skills/uws-kb/SKILL.md" ]
    grep -q '^name: uws-kb$' "$PLUGIN_DIR/skills/uws-kb/SKILL.md"
    grep -q 'CLAUDE_PLUGIN_ROOT}/bin/uws kb stats' "$PLUGIN_DIR/skills/uws-kb/SKILL.md"
    grep -q 'CLAUDE_PLUGIN_ROOT}/bin/uws kb' "$PLUGIN_DIR/commands/kb.md"
    # .claude/skills/uws-kb is the same text with ./bin/uws (for work on UWS itself)
    run diff <(sed -e 's|\${CLAUDE_PLUGIN_ROOT}/bin/uws|./bin/uws|g' "$PLUGIN_DIR/skills/uws-kb/SKILL.md" | grep -v 'never a bare') \
             <(grep -v 'never a bare' "${PROJECT_ROOT}/.claude/skills/uws-kb/SKILL.md")
    [ "$status" -eq 0 ]
}

@test "plugin: ships the uws-research-lead skill, in step with the repo copy" {
    [ -f "$PLUGIN_DIR/skills/uws-research-lead/SKILL.md" ]
    [ ! -L "$PLUGIN_DIR/skills/uws-research-lead" ]
    grep -q 'CLAUDE_PLUGIN_ROOT}/bin/uws research check gate' "$PLUGIN_DIR/skills/uws-research-lead/SKILL.md"
    # .claude/skills/uws-research-lead is the same text with ./bin/uws (for work on UWS itself)
    run diff <(sed -e 's|\${CLAUDE_PLUGIN_ROOT}/bin/uws|./bin/uws|g' "$PLUGIN_DIR/skills/uws-research-lead/SKILL.md" | grep -v 'never a bare') \
             <(grep -v 'never a bare' "${PROJECT_ROOT}/.claude/skills/uws-research-lead/SKILL.md")
    [ "$status" -eq 0 ]
}

@test "plugin: SessionStart hook is silent outside UWS projects" {
    run env CLAUDE_PROJECT_DIR="$PROJ" "$PLUGIN_DIR/hooks/session_start.sh"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "plugin: SessionStart hook emits valid JSON with phase and checkpoint" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    run env CLAUDE_PROJECT_DIR="$PROJ" "$PLUGIN_DIR/hooks/session_start.sh"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("current_phase: phase_1_planning")'
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("CP_1_001")'
}

@test "plugin: PreCompact hook creates a checkpoint" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    run env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" "$PLUGIN_DIR/hooks/pre_compact.sh"
    [ "$status" -eq 0 ]
    grep -q "Auto-checkpoint before context compaction" "$PROJ/.workflow/checkpoints.log"
}

@test "plugin: claude plugin validate passes (when the claude CLI is installed)" {
    command -v claude >/dev/null 2>&1 || skip "claude CLI not installed"
    run claude plugin validate "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
}

@test "output: piped output carries no ANSI escapes, and init prints no yq notice" {
    cd "$PROJ"
    run bash -c "UWS_SKIP_VECTOR_MEMORY=true PATH='/usr/bin:/bin' '${PROJECT_ROOT}/bin/uws' init software </dev/null 2>&1 | cat"
    [ "$status" -eq 0 ]
    [[ "$output" != *$'\033'* ]] || false
    [[ "$output" != *"yq not found"* ]] || false
    local c
    for c in "status" "sdlc status" "checkpoint list" "recover" "sdlc nope"; do
        run bash -c "'${PROJECT_ROOT}/bin/uws' $c </dev/null 2>&1 | cat"
        [[ "$output" != *$'\033'* && "$output" != *'\033'* ]] || false
    done
}

# materialize_plugin: a dereferenced copy, as the plugin cache holds it
materialize_plugin() {
    MAT="$(mktemp -d)/uws"
    cp -RL "$PLUGIN_DIR" "$MAT"
}

no_stale_hint() {
    [[ "$1" != *"scripts/sdlc.sh"* && "$1" != *"scripts/research.sh"* ]] || false
    [[ "$1" != *"./scripts/"* && "$1" != *"scripts/checkpoint.sh"* && "$1" != *"scripts/orchestrate.sh"* ]] || false
    [[ "$1" != *$'\033'* && "$1" != *'\033'* ]] || false
}

@test "hints: from the plugin, sdlc/status/init name /uws: slash commands, never scripts/ or bare uws" {
    materialize_plugin
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true run "$MAT/bin/uws" init software </dev/null
    [ "$status" -eq 0 ]
    no_stale_hint "$output"
    [[ "$output" == *"/uws:sdlc start"* ]] || false
    [[ "$output" != *" uws sdlc"* ]] || false
    run "$MAT/bin/uws" sdlc goal "A calculator" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"/uws:sdlc check <n>"* ]] || false
    no_stale_hint "$output"
    run "$MAT/bin/uws" sdlc start </dev/null
    [[ "$output" == *"Run /uws:sdlc next when complete"* ]] || false
    no_stale_hint "$output"
    run "$MAT/bin/uws" sdlc next </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"mark done with: /uws:sdlc check <n>"* ]] || false
    [[ "$output" == *"Override with: /uws:sdlc next --force"* ]] || false
    no_stale_hint "$output"
    run "$MAT/bin/uws" status </dev/null
    [[ "$output" == *"Continue work:     /uws:recover"* ]] || false
    [[ "$output" == *'/uws:checkpoint "<message>"'* ]] || false
    [[ "$output" == *'/uws:orchestrate dispatch "<task>"'* ]] || false
    no_stale_hint "$output"
    run "$MAT/bin/uws" sdlc bogus </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Run /uws:sdlc help for usage."* ]] || false
    no_stale_hint "$output"
    rm -rf "$(dirname "$MAT")"
}

@test "hints: from the CLI, an older uws earlier on PATH is not named; the right one is" {
    cd "$PROJ"
    local other bin
    other="$(mktemp -d)"; bin="$(mktemp -d)"
    printf '#!/bin/sh\necho OLD UWS\n' > "$other/uws"; chmod +x "$other/uws"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    # another uws first on PATH: hints give this install's bin/uws by absolute path
    run env -u UWS_CMD PATH="$other:$PATH" "${PROJECT_ROOT}/bin/uws" sdlc goal "A parser" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"${PROJECT_ROOT}/bin/uws sdlc check <n>"* ]] || false
    no_stale_hint "$output"
    # `uws` on PATH is this install (a symlink, as install.sh makes it): plain `uws`
    ln -s "${PROJECT_ROOT}/bin/uws" "$bin/uws"
    run env -u UWS_CMD PATH="$bin:$other:$PATH" "$bin/uws" sdlc start </dev/null
    [[ "$output" == *"Run uws sdlc next when complete"* ]] || false
    no_stale_hint "$output"
    rm -rf "$other" "$bin"
}

@test "init research: next steps name the research workflow" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true run "${PROJECT_ROOT}/bin/uws" init research </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"research start to begin the research workflow"* ]] || false
    [[ "$output" != *"to begin SDLC"* ]] || false
}

@test "kb: an approve refused inside an agent names the CLI the PI can run" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    echo "# demo project" > README.md
    local id
    id="$("${PROJECT_ROOT}/bin/uws" kb add --type fact --claim "The README names the demo project" \
        --evidence verified --source file:README.md:1 --check "grep -q 'demo project' README.md" </dev/null | grep -o 'K-[0-9]*-[0-9a-f]*' | head -1)"
    [ -n "$id" ]
    run env -u UWS_CMD CLAUDECODE=1 "${PROJECT_ROOT}/bin/uws" kb approve "$id" </dev/null
    [ "$status" -eq 6 ]
    [[ "$output" == *"own terminal, from this project:"*"/bin/uws kb approve <ID>"* || "$output" == *"own terminal, from this project: uws kb approve <ID>"* ]] || false
    run env -u UWS_CMD CLAUDECODE=1 "${PROJECT_ROOT}/bin/uws" kb pi --set pi@example.com </dev/null
    [ "$status" -eq 6 ]
    [[ "$output" == *"own terminal, from this project: "*"kb pi --set pi@example.com"* ]] || false
    # with no PI set, `kb pi` names the command too
    run env -u UWS_CMD "${PROJECT_ROOT}/bin/uws" kb pi </dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"kb pi --set <email>, in your own terminal"* ]] || false
    [[ "$output" == *"${PROJECT_ROOT}/bin/uws kb pi --set"* || "$output" == *": uws kb pi --set"* ]] || false
}

@test "hints: the plugin's session context names /uws:checkpoint and the bootstrap steps, then drops them once done" {
    materialize_plugin
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "$MAT/bin/uws" init software </dev/null >/dev/null
    run env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$MAT" "$MAT/hooks/session_start.sh"
    [ "$status" -eq 0 ]
    local ctx
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"Save progress with /uws:checkpoint <msg>."* ]] || false
    [[ "$ctx" == *'goal: (none declared; set one with /uws:sdlc goal "...")'* ]] || false
    [[ "$ctx" == *"methodology: not started (/uws:sdlc start or /uws:research start)"* ]] || false
    [[ "$ctx" != *" uws "* ]] || false
    grep -q 'next step: `/uws:sdlc goal' "$PROJ/.workflow/handoff.md"
    # Once the goal is set and SDLC started, nothing tells the model to do them again
    "$MAT/bin/uws" sdlc goal "A calculator" </dev/null >/dev/null
    "$MAT/bin/uws" sdlc start </dev/null >/dev/null
    run env CLAUDE_PROJECT_DIR="$PROJ" CLAUDE_PLUGIN_ROOT="$MAT" "$MAT/hooks/session_start.sh"
    ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" != *"none declared"* && "$ctx" != *"not started"* ]] || false
    run grep -c 'none declared\|not started\|Declare the project goal\|Start a methodology' "$PROJ/.workflow/handoff.md"
    [ "$output" = "0" ]
    run "$MAT/bin/uws" recover </dev/null
    [[ "$output" != *"Declare the project goal"* && "$output" != *"Start a methodology"* ]] || false
    rm -rf "$(dirname "$MAT")"
}

@test "orchestrate: without the plugin or agent files, dispatch warns how to get the subagent" {
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "${PROJECT_ROOT}/bin/uws" init software </dev/null >/dev/null
    "${PROJECT_ROOT}/bin/uws" sdlc start </dev/null >/dev/null
    run "${PROJECT_ROOT}/bin/uws" orchestrate dispatch "Write the requirements" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"warning: no subagent uws-researcher"* ]] || false
    [[ "$output" == *"/plugin install uws@uws"* ]] || false
    [[ "$output" == *"cp '${PROJECT_ROOT}/.claude/agents'/uws-*.md .claude/agents/"* ]] || false
    # the printed copy command works, and then the warning is gone
    mkdir -p .claude/agents && cp "${PROJECT_ROOT}"/.claude/agents/uws-*.md .claude/agents/
    run "${PROJECT_ROOT}/bin/uws" orchestrate status </dev/null
    [[ "$output" != *"warning: no subagent"* ]] || false
    [[ "$output" == *"Subagent:    uws-researcher"* ]] || false
}

@test "orchestrate: the plugin names its own subagent and ships an orchestrate command" {
    materialize_plugin
    cd "$PROJ"
    UWS_SKIP_VECTOR_MEMORY=true "$MAT/bin/uws" init software </dev/null >/dev/null
    "$MAT/bin/uws" sdlc start </dev/null >/dev/null
    run "$MAT/bin/uws" orchestrate dispatch "Write the requirements" </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *"warning: no subagent"* ]] || false
    [[ "$output" == *"run the uws:uws-researcher subagent"* ]] || false
    [[ "$output" == *'/uws:orchestrate collect "researcher: requirements artifact"'* ]] || false
    [ -f "$PLUGIN_DIR/commands/orchestrate.md" ]
    grep -q 'CLAUDE_PLUGIN_ROOT}/bin/uws orchestrate dispatch' "$PLUGIN_DIR/commands/orchestrate.md"
    rm -rf "$(dirname "$MAT")"
}
