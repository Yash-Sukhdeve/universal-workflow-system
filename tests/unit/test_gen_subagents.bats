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
    for r in RESEARCHER ARCHITECT IMPLEMENTER EXPERIMENTER OPTIMIZER DEPLOYER DOCUMENTER; do
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
        [[ "$got" =~ ^(opus|sonnet|haiku|fable|inherit)$ ]]
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
    [[ "$output" == *"invalid model"* ]]
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
