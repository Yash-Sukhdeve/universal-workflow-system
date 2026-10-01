#!/usr/bin/env bats
# Unit tests for scripts/gen_subagents.sh: per-role `model:` frontmatter,
# overrides, and the subagent "cannot ask the user" protocol.
#
# gen_subagents.sh writes into <its repo root>/.claude/agents, so every test
# runs a private copy of the script + personas inside TEST_TMP_DIR and never
# touches the real .claude/agents.

load '../helpers/test_helper.bash'

setup() {
    setup_test_environment
    GEN_ROOT="${TEST_TMP_DIR}/genroot"
    mkdir -p "${GEN_ROOT}/scripts" "${GEN_ROOT}/docs"
    cp "${PROJECT_ROOT}/scripts/gen_subagents.sh" "${GEN_ROOT}/scripts/"
    cp -R "${PROJECT_ROOT}/docs/personas" "${GEN_ROOT}/docs/personas"
    AGENTS="${GEN_ROOT}/.claude/agents"
    unset UWS_AGENT_MODEL
    for r in RESEARCHER ARCHITECT IMPLEMENTER EXPERIMENTER OPTIMIZER DEPLOYER DOCUMENTER \
             RT_SCOUT RT_VERIFIER RT_REDTEAM RT_METHODOLOGIST RT_ENGINEER RT_WRITER; do
        unset "UWS_AGENT_MODEL_${r}"
    done
}

teardown() {
    teardown_test_environment
}

# Print the value of the `model:` key inside the YAML frontmatter only.
frontmatter_model() {
    awk 'NR==1 && $0=="---" {infm=1; next}
         infm && $0=="---" {exit}
         infm && /^model: / {sub(/^model: /, ""); print}' "$1"
}

expected_default() {
    case "$1" in
        architect|researcher) echo opus ;;
        *)                    echo sonnet ;;
    esac
}

@test "gen_subagents: every role gets the expected default model" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success

    local role got
    for role in researcher architect implementer experimenter optimizer deployer documenter; do
        [ -f "${AGENTS}/uws-${role}.md" ]
        got="$(frontmatter_model "${AGENTS}/uws-${role}.md")"
        [ "$got" = "$(expected_default "$role")" ]
    done
}

@test "gen_subagents: model line is a valid Claude Code alias and appears once" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success

    local f n got
    for f in "${AGENTS}"/uws-*.md; do
        n="$(frontmatter_model "$f" | wc -l | tr -d ' ')"
        [ "$n" -eq 1 ]
        got="$(frontmatter_model "$f")"
        [[ "$got" =~ ^(opus|sonnet|haiku|fable|inherit)$ ]] || false
    done
}

@test "gen_subagents: UWS_AGENT_MODEL=inherit applies to every role" {
    UWS_AGENT_MODEL=inherit run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success

    local f
    for f in "${AGENTS}"/uws-*.md; do
        [ "$(frontmatter_model "$f")" = "inherit" ]
    done
}

@test "gen_subagents: per-role override beats the global override" {
    UWS_AGENT_MODEL=inherit UWS_AGENT_MODEL_IMPLEMENTER=opus \
        run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success

    [ "$(frontmatter_model "${AGENTS}/uws-implementer.md")" = "opus" ]
    [ "$(frontmatter_model "${AGENTS}/uws-architect.md")" = "inherit" ]
}

@test "gen_subagents: invalid model is rejected and existing files are untouched" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    local before
    before="$(cat "${AGENTS}/uws-deployer.md")"

    UWS_AGENT_MODEL_DEPLOYER=gpt-4 run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_failure
    [[ "$output" == *"invalid model"* ]] || false
    [ "$(cat "${AGENTS}/uws-deployer.md")" = "$before" ]
}

@test "gen_subagents: generated file documents the override" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    assert_file_contains "${AGENTS}/uws-optimizer.md" "UWS_AGENT_MODEL_OPTIMIZER="
    assert_file_contains "${AGENTS}/uws-optimizer.md" "UWS_AGENT_MODEL=inherit"
}

@test "gen_subagents: protocol routes questions to the orchestrator, not the user" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success

    local f asks cannots
    for f in "${AGENTS}"/uws-*.md; do
        assert_file_contains "$f" "Open questions for the orchestrator"
        assert_file_contains "$f" "You cannot ask the user"
        # Every "ask the user" mention must be the negated "cannot ask the user".
        asks="$(grep -ciE "ask the user" "$f" || true)"
        cannots="$(grep -ciE "cannot ask the user" "$f" || true)"
        [ "$asks" -eq "$cannots" ]
        run grep -niE "ask the architect/user|back to the user|STOP and ask\." "$f"
        [ "$status" -eq 1 ]
    done
}

# ── Research team roles (docs/design/research-team.md section 4) ─────────────

@test "gen_subagents: research roles get their model tiers (verifier, red team, methodologist on opus)" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    [ "$(frontmatter_model "${AGENTS}/uws-rt-scout.md")" = "sonnet" ]
    [ "$(frontmatter_model "${AGENTS}/uws-rt-verifier.md")" = "opus" ]
    [ "$(frontmatter_model "${AGENTS}/uws-rt-redteam.md")" = "opus" ]
    [ "$(frontmatter_model "${AGENTS}/uws-rt-methodologist.md")" = "opus" ]
    [ "$(frontmatter_model "${AGENTS}/uws-rt-engineer.md")" = "sonnet" ]
    [ "$(frontmatter_model "${AGENTS}/uws-rt-writer.md")" = "sonnet" ]
}

@test "gen_subagents: increment-2 research roles get their tools; the writer has no web access" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    grep -q '^tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, WebFetch$' "${AGENTS}/uws-rt-methodologist.md"
    grep -q '^tools: Read, Grep, Glob, Write, Edit, Bash, WebSearch, WebFetch$' "${AGENTS}/uws-rt-engineer.md"
    grep -q '^tools: Read, Grep, Glob, Write, Edit, Bash$' "${AGENTS}/uws-rt-writer.md"
    UWS_AGENT_MODEL_RT_METHODOLOGIST=sonnet run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    [ "$(frontmatter_model "${AGENTS}/uws-rt-methodologist.md")" = "sonnet" ]
}

@test "gen_subagents: UWS_AGENT_MODEL_RT_SCOUT overrides the scout (hyphen becomes underscore)" {
    UWS_AGENT_MODEL_RT_SCOUT=opus run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    [ "$(frontmatter_model "${AGENTS}/uws-rt-scout.md")" = "opus" ]
    assert_file_contains "${AGENTS}/uws-rt-scout.md" "UWS_AGENT_MODEL_RT_SCOUT="
}

@test "gen_subagents: research agents embed apocalypt.md exactly once; SDLC agents do not" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    local role n
    for role in rt-scout rt-verifier rt-redteam rt-methodologist rt-engineer rt-writer; do
        n="$(grep -c 'You are Apocalypt, pronounced' "${AGENTS}/uws-${role}.md" || true)"
        [ "$n" -eq 1 ]
        assert_file_contains "${AGENTS}/uws-${role}.md" "Research Output Contract"
        run grep -q "Trace every requirement/claim to a REQ-ID" "${AGENTS}/uws-${role}.md"
        [ "$status" -ne 0 ]
    done
    run grep -l 'You are Apocalypt, pronounced' "${AGENTS}/uws-researcher.md" "${AGENTS}/uws-implementer.md"
    [ "$status" -ne 0 ]
    # the role personas reference apocalypt.md instead of copying it
    run grep -l 'You are Apocalypt, pronounced' "${GEN_ROOT}"/docs/personas/research-*.md
    [ "$status" -ne 0 ]
}

@test "gen_subagents: committed agent files match the generator output" {
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    local role
    for role in researcher architect implementer experimenter optimizer deployer documenter \
                rt-scout rt-verifier rt-redteam rt-methodologist rt-engineer rt-writer; do
        cmp -s "${AGENTS}/uws-${role}.md" "${PROJECT_ROOT}/.claude/agents/uws-${role}.md"
    done
}

@test "gen_subagents: every generated frontmatter is valid YAML (descriptions contain ': ')" {
    # Claude Code loads an agent whose frontmatter fails to parse with ALL fields dropped
    # (model, tools, description), so an unquoted "Scout: searches ..." silently breaks it.
    run "${GEN_ROOT}/scripts/gen_subagents.sh"
    assert_success
    local f
    for f in "${AGENTS}"/uws-*.md; do
        # Dependency-free: every description is a double-quoted scalar
        grep -qE '^description: ".*"$' "$f"
    done
    python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not installed; quoting checked above"
    for f in "${AGENTS}"/uws-*.md; do
        run python3 -c 'import sys, yaml; d = yaml.safe_load(open(sys.argv[1]).read().split("---")[1]); assert d["name"] and d["description"] and d["model"] and d["tools"], d' "$f"
        [ "$status" -eq 0 ]
    done
}

@test "gen_subagents: quoting round-trips colons, quotes and backslashes" {
    source <(sed -n '/^yaml_dq()/,/^}/p' "${GEN_ROOT}/scripts/gen_subagents.sh")
    python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not installed"
    local raw='Scout: finds "primary" sources \ caches text'
    run python3 -c 'import sys, yaml; print(yaml.safe_load("d: " + sys.argv[1])["d"])' "$(yaml_dq "$raw")"
    [ "$status" -eq 0 ]
    [ "$output" = "$raw" ]
}
