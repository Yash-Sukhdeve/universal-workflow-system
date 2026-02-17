#!/usr/bin/env bats
# Tests for bin/uws CLI wrapper

load '../helpers/test_helper'

setup() {
    setup_test_environment
    # Create a minimal .workflow directory in the test env
    mkdir -p "$TEST_TMP_DIR/.workflow"
    cat > "$TEST_TMP_DIR/.workflow/state.yaml" <<'EOF'
project_type: "software"
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
last_updated: "2026-01-01T00:00:00Z"
metadata:
  version: "1.0.0"
EOF
    # Copy the uws CLI
    mkdir -p "$TEST_TMP_DIR/bin"
    cp "$PROJECT_ROOT/bin/uws" "$TEST_TMP_DIR/bin/uws"
    chmod +x "$TEST_TMP_DIR/bin/uws"
    # Create stub scripts that just echo their name and args
    for script in init_workflow.sh status.sh checkpoint.sh recover_context.sh \
                  activate_agent.sh enable_skill.sh sdlc.sh research.sh \
                  spiral.sh review.sh pm.sh submit.sh detect_and_configure.sh \
                  start_company_os.sh start_dashboard.sh; do
        cat > "$TEST_TMP_DIR/scripts/$script" <<STUB
#!/bin/bash
echo "CALLED: $script \$@"
STUB
        chmod +x "$TEST_TMP_DIR/scripts/$script"
    done
}

teardown() {
    teardown_test_environment
}

# ── Help & Version ─────────────────────────────────────────────────────────

@test "uws help exits 0 and shows usage" {
    run "$TEST_TMP_DIR/bin/uws" help
    [ "$status" -eq 0 ]
    assert_output "Universal Workflow System CLI"
}

@test "uws --help exits 0" {
    run "$TEST_TMP_DIR/bin/uws" --help
    [ "$status" -eq 0 ]
    assert_output "Universal Workflow System CLI"
}

@test "uws -h exits 0" {
    run "$TEST_TMP_DIR/bin/uws" -h
    [ "$status" -eq 0 ]
    assert_output "Universal Workflow System CLI"
}

@test "uws with no args shows help" {
    run "$TEST_TMP_DIR/bin/uws"
    [ "$status" -eq 0 ]
    assert_output "Universal Workflow System CLI"
}

@test "uws version prints version string" {
    run "$TEST_TMP_DIR/bin/uws" version
    [ "$status" -eq 0 ]
    assert_output "uws"
}

@test "uws --version prints version string" {
    run "$TEST_TMP_DIR/bin/uws" --version
    [ "$status" -eq 0 ]
    assert_output "uws"
}

# ── Unknown command ────────────────────────────────────────────────────────

@test "uws unknown-command exits non-zero" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" nonexistent-command
    [ "$status" -ne 0 ]
    assert_output "Unknown command"
}

# ── Dispatch tests ─────────────────────────────────────────────────────────

@test "uws init dispatches to init_workflow.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" init software
    [ "$status" -eq 0 ]
    assert_output "CALLED: init_workflow.sh software"
}

@test "uws status dispatches to status.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" status
    [ "$status" -eq 0 ]
    assert_output "CALLED: status.sh"
}

@test "uws status -v passes flags through" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" status -v
    [ "$status" -eq 0 ]
    assert_output "CALLED: status.sh -v"
}

@test "uws checkpoint dispatches to checkpoint.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" checkpoint create "test msg"
    [ "$status" -eq 0 ]
    assert_output "CALLED: checkpoint.sh create test msg"
}

@test "uws recover dispatches to recover_context.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" recover
    [ "$status" -eq 0 ]
    assert_output "CALLED: recover_context.sh"
}

@test "uws agent dispatches to activate_agent.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" agent researcher
    [ "$status" -eq 0 ]
    assert_output "CALLED: activate_agent.sh researcher"
}

@test "uws skill dispatches to enable_skill.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" skill testing
    [ "$status" -eq 0 ]
    assert_output "CALLED: enable_skill.sh testing"
}

@test "uws sdlc dispatches to sdlc.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" sdlc status
    [ "$status" -eq 0 ]
    assert_output "CALLED: sdlc.sh status"
}

@test "uws research dispatches to research.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" research start
    [ "$status" -eq 0 ]
    assert_output "CALLED: research.sh start"
}

@test "uws spiral dispatches to spiral.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" spiral status
    [ "$status" -eq 0 ]
    assert_output "CALLED: spiral.sh status"
}

@test "uws review dispatches to review.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" review list
    [ "$status" -eq 0 ]
    assert_output "CALLED: review.sh list"
}

@test "uws pm dispatches to pm.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" pm board
    [ "$status" -eq 0 ]
    assert_output "CALLED: pm.sh board"
}

@test "uws submit dispatches to submit.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" submit "msg" "TASK-1"
    [ "$status" -eq 0 ]
    assert_output "CALLED: submit.sh msg TASK-1"
}

@test "uws detect dispatches to detect_and_configure.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" detect
    [ "$status" -eq 0 ]
    assert_output "CALLED: detect_and_configure.sh"
}

@test "uws company-os start dispatches to start_company_os.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" company-os start
    [ "$status" -eq 0 ]
    assert_output "CALLED: start_company_os.sh"
}

@test "uws company-os dashboard dispatches to start_dashboard.sh" {
    cd "$TEST_TMP_DIR"
    run "$TEST_TMP_DIR/bin/uws" company-os dashboard
    [ "$status" -eq 0 ]
    assert_output "CALLED: start_dashboard.sh"
}

# ── Root discovery ─────────────────────────────────────────────────────────

@test "uws finds .workflow/ from subdirectory" {
    mkdir -p "$TEST_TMP_DIR/sub/deep/nested"
    cd "$TEST_TMP_DIR/sub/deep/nested"
    run "$TEST_TMP_DIR/bin/uws" status
    [ "$status" -eq 0 ]
    assert_output "CALLED: status.sh"
}

@test "UWS_ROOT env var overrides discovery" {
    local alt_root
    alt_root="$(mktemp -d)"
    mkdir -p "$alt_root/.workflow" "$alt_root/scripts"
    cat > "$alt_root/.workflow/state.yaml" <<'EOF'
current_phase: "phase_1_planning"
EOF
    cat > "$alt_root/scripts/status.sh" <<'STUB'
#!/bin/bash
echo "CALLED: alt-root status.sh"
STUB
    chmod +x "$alt_root/scripts/status.sh"

    UWS_ROOT="$alt_root" run "$TEST_TMP_DIR/bin/uws" status
    [ "$status" -eq 0 ]
    assert_output "CALLED: alt-root status.sh"

    rm -rf "$alt_root"
}

@test "uws exits with error when no .workflow/ found" {
    local empty_dir
    empty_dir="$(mktemp -d)"
    cd "$empty_dir"
    run "$TEST_TMP_DIR/bin/uws" status
    [ "$status" -ne 0 ]
    assert_output "No UWS project found"
    rm -rf "$empty_dir"
}
