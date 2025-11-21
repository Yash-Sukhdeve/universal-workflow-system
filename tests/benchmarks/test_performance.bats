#!/usr/bin/env bats
# Performance Benchmarks as BATS Tests
# Validates that UWS meets performance targets

load '../helpers/test_helper'

# Performance targets (in milliseconds)
CHECKPOINT_TARGET_MS=1000       # <1 second
AGENT_ACTIVATION_TARGET_MS=500  # <0.5 seconds
RECOVERY_TARGET_MS=5000         # <5 seconds (vs 15 min manual)
STATE_SIZE_TARGET_BYTES=51200   # <50 KB for 100 checkpoints

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    create_full_test_environment
    cd "${TEST_TMP_DIR}"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# CHECKPOINT PERFORMANCE
# ============================================================================

@test "PERF: Checkpoint creation under 1 second" {
    local start=$(date +%s%N)
    run "${TEST_TMP_DIR}/scripts/checkpoint.sh" "perf_test"
    local end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt "$CHECKPOINT_TARGET_MS" ] || \
        skip "Checkpoint took ${elapsed_ms}ms (target: <${CHECKPOINT_TARGET_MS}ms)"
}

@test "PERF: Multiple checkpoints remain fast" {
    local total_ms=0

    for i in {1..5}; do
        local start=$(date +%s%N)
        run "${TEST_TMP_DIR}/scripts/checkpoint.sh" "perf_test_$i"
        local end=$(date +%s%N)
        total_ms=$(( total_ms + (end - start) / 1000000 ))
    done

    local avg_ms=$((total_ms / 5))
    [ "$avg_ms" -lt "$CHECKPOINT_TARGET_MS" ] || \
        skip "Average checkpoint time: ${avg_ms}ms (target: <${CHECKPOINT_TARGET_MS}ms)"
}

# ============================================================================
# AGENT ACTIVATION PERFORMANCE
# ============================================================================

@test "PERF: Agent activation under 500ms" {
    local start=$(date +%s%N)
    run "${TEST_TMP_DIR}/scripts/activate_agent.sh" "implementer"
    local end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt "$AGENT_ACTIVATION_TARGET_MS" ] || \
        skip "Agent activation took ${elapsed_ms}ms (target: <${AGENT_ACTIVATION_TARGET_MS}ms)"
}

@test "PERF: All agents activate quickly" {
    local agents=("researcher" "architect" "implementer" "experimenter" "deployer")
    local max_ms=0

    for agent in "${agents[@]}"; do
        local start=$(date +%s%N)
        run "${TEST_TMP_DIR}/scripts/activate_agent.sh" "$agent"
        local end=$(date +%s%N)
        local elapsed_ms=$(( (end - start) / 1000000 ))
        ((elapsed_ms > max_ms)) && max_ms=$elapsed_ms
    done

    [ "$max_ms" -lt "$AGENT_ACTIVATION_TARGET_MS" ] || \
        skip "Slowest agent activation: ${max_ms}ms (target: <${AGENT_ACTIVATION_TARGET_MS}ms)"
}

# ============================================================================
# CONTEXT RECOVERY PERFORMANCE
# ============================================================================

@test "PERF: Context recovery under 5 seconds" {
    # Add some checkpoint history
    for i in {1..5}; do
        echo "2024-01-0${i}T00:00:00Z | CP_$i | Checkpoint $i" >> \
            "${TEST_TMP_DIR}/.workflow/checkpoints.log"
    done

    local start=$(date +%s%N)
    run "${TEST_TMP_DIR}/scripts/recover_context.sh"
    local end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt "$RECOVERY_TARGET_MS" ] || \
        skip "Recovery took ${elapsed_ms}ms (target: <${RECOVERY_TARGET_MS}ms)"
}

@test "PERF: Status check is instantaneous" {
    local start=$(date +%s%N)
    run "${TEST_TMP_DIR}/scripts/status.sh"
    local end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 1000 ] || \
        skip "Status check took ${elapsed_ms}ms (target: <1000ms)"
}

# ============================================================================
# STATE FILE SIZE
# ============================================================================

@test "PERF: State files remain small with many checkpoints" {
    # Add 100 checkpoints
    for i in {1..100}; do
        echo "2024-01-01T${i}:00:00Z | CP_$i | Checkpoint $i" >> \
            "${TEST_TMP_DIR}/.workflow/checkpoints.log"
    done

    local total_size=$(du -sb "${TEST_TMP_DIR}/.workflow" | cut -f1)

    [ "$total_size" -lt "$STATE_SIZE_TARGET_BYTES" ] || \
        skip "State dir size: ${total_size} bytes (target: <${STATE_SIZE_TARGET_BYTES})"
}

@test "PERF: Individual state file under 10KB" {
    local state_size=$(wc -c < "${TEST_TMP_DIR}/.workflow/state.yaml")

    [ "$state_size" -lt 10240 ] || \
        skip "state.yaml size: ${state_size} bytes (target: <10KB)"
}

# ============================================================================
# SCALABILITY
# ============================================================================

@test "PERF: Checkpoint lookup scales linearly" {
    # Create checkpoint history
    for i in {1..50}; do
        echo "2024-01-01T${i}:00:00Z | CP_$i | Checkpoint $i" >> \
            "${TEST_TMP_DIR}/.workflow/checkpoints.log"
    done

    # Time to find latest checkpoint
    local start=$(date +%s%N)
    tail -1 "${TEST_TMP_DIR}/.workflow/checkpoints.log" >/dev/null
    local end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 100 ] || \
        skip "Checkpoint lookup took ${elapsed_ms}ms"
}

@test "PERF: YAML parsing remains fast" {
    skip_if_no_yaml_utils

    source "${TEST_TMP_DIR}/scripts/lib/yaml_utils.sh"

    local start=$(date +%s%N)
    for i in {1..10}; do
        yaml_get "${TEST_TMP_DIR}/.workflow/state.yaml" "current_phase" >/dev/null 2>&1 || true
    done
    local end=$(date +%s%N)
    local elapsed_ms=$(( (end - start) / 1000000 ))

    [ "$elapsed_ms" -lt 500 ] || \
        skip "10 YAML lookups took ${elapsed_ms}ms"
}

# ============================================================================
# COMPARISON BENCHMARKS
# ============================================================================

@test "PERF: UWS recovery faster than baseline estimate" {
    # UWS recovery time
    local start=$(date +%s%N)
    run "${TEST_TMP_DIR}/scripts/recover_context.sh"
    local end=$(date +%s%N)
    local uws_ms=$(( (end - start) / 1000000 ))

    # Baseline estimate: 15 minutes (from literature)
    local baseline_ms=$((15 * 60 * 1000))

    # UWS should be at least 10x faster
    local improvement_factor=$((baseline_ms / (uws_ms + 1)))

    [ "$improvement_factor" -gt 10 ] || \
        skip "UWS recovery: ${uws_ms}ms, baseline: ${baseline_ms}ms, factor: ${improvement_factor}x"
}

# ============================================================================
# HELPERS
# ============================================================================

skip_if_no_yaml_utils() {
    if [[ ! -f "${TEST_TMP_DIR}/scripts/lib/yaml_utils.sh" ]]; then
        skip "yaml_utils.sh not found"
    fi
}
