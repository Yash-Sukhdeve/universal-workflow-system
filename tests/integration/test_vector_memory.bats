#!/usr/bin/env bats
# Integration tests for vector memory MCP servers
# Requires: vector_memory_local and vector_memory_global configured in .mcp.json

load '../helpers/test_helper.bash'

# Use actual project root (not temp dir) -- these test real project config
setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export PROJECT_ROOT
}

@test "vector memory local server is configured in .mcp.json" {
    run grep -c "vector_memory_local" "${PROJECT_ROOT}/.mcp.json"
    assert_success
    [ "$output" -ge 1 ]
}

@test "vector memory global server is configured in .mcp.json" {
    run grep -c "vector_memory_global" "${PROJECT_ROOT}/.mcp.json"
    assert_success
    [ "$output" -ge 1 ]
}

@test "vector memory venv exists" {
    [ -f "${HOME}/.uws/tools/vector-memory/.venv/bin/python" ]
}

@test "memory directory is gitignored" {
    run grep -c "^memory/" "${PROJECT_ROOT}/.gitignore"
    assert_success
}

@test "CLAUDE.md contains Vector Memory Protocol section" {
    run grep -c "Vector Memory Protocol" "${PROJECT_ROOT}/CLAUDE.md"
    assert_success
    [ "$output" -ge 1 ]
}

@test "settings.json contains memory hooks" {
    run grep -c "additionalContext" "${PROJECT_ROOT}/.claude/settings.json"
    assert_success
}

@test "memory-gate skill exists" {
    [ -f "${PROJECT_ROOT}/.claude/skills/memory-gate/SKILL.md" ]
}

@test "phase-distillation skill exists" {
    [ -f "${PROJECT_ROOT}/.claude/skills/phase-distillation/SKILL.md" ]
}

@test "memory-retrospective skill exists" {
    [ -f "${PROJECT_ROOT}/.claude/skills/memory-retrospective/SKILL.md" ]
}

@test "memory-gate skill is auto-invocable (no disable-model-invocation)" {
    # memory-gate should NOT have disable-model-invocation: true
    run grep -c "disable-model-invocation: true" "${PROJECT_ROOT}/.claude/skills/memory-gate/SKILL.md"
    [ "$output" -eq 0 ] || [ "$status" -ne 0 ]
}

@test "memory-gate skill has user-invocable: false" {
    run grep -c "user-invocable: false" "${PROJECT_ROOT}/.claude/skills/memory-gate/SKILL.md"
    assert_success
    [ "$output" -ge 1 ]
}

@test "phase-distillation skill is manual-only" {
    run grep -c "disable-model-invocation: true" "${PROJECT_ROOT}/.claude/skills/phase-distillation/SKILL.md"
    assert_success
    [ "$output" -ge 1 ]
}
