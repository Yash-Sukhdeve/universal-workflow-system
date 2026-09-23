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
    [[ "$(echo "$ctx" | grep -A1 'Modified files:' | tail -1)" != "0" ]]
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
    grep -q 'current_checkpoint: "CP_1_002"' "$PROJ/.workflow/state.yaml"
}

@test "installer: generated commands contain no GNU-only sed -i or date -I" {
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
}

@test "plugin: every command calls the plugin's own uws, never a PATH lookup" {
    local f
    for f in "$PLUGIN_DIR"/commands/*.md; do
        if grep -qE '(^|[`!( ])uws (init|status|checkpoint|recover|sdlc|research)' "$f"; then
            echo "PATH-dependent uws call in $f" >&2
            return 1
        fi
    done
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
