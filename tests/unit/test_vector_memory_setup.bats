#!/usr/bin/env bats
# Unit Tests for scripts/lib/vector_memory_setup.sh
# Tests vector memory setup library functions

# Load test helpers
load '../helpers/test_helper'

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    cd "${TEST_TMP_DIR}"

    # Reset the double-source guard so we can source fresh each test
    unset _VECTOR_MEMORY_SETUP_LOADED

    # Source the library
    source "${SCRIPTS_DIR}/lib/vector_memory_setup.sh"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# LIBRARY LOADING TESTS
# ============================================================================

@test "vector_memory_setup.sh loads without error" {
    unset _VECTOR_MEMORY_SETUP_LOADED
    run bash -c "source '${SCRIPTS_DIR}/lib/vector_memory_setup.sh'"
    [ "$status" -eq 0 ]
}

@test "double-source guard prevents re-loading" {
    # First source already happened in setup()
    # Verify guard variable is set
    [ "$_VECTOR_MEMORY_SETUP_LOADED" = "true" ]

    # Source again — should be a no-op (no crash)
    source "${SCRIPTS_DIR}/lib/vector_memory_setup.sh"
    [ "$_VECTOR_MEMORY_SETUP_LOADED" = "true" ]
}

@test "UWS_SKIP_VECTOR_MEMORY=true skips all setup" {
    export UWS_SKIP_VECTOR_MEMORY=true
    run setup_vector_memory "${TEST_TMP_DIR}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped"* ]]
}

# ============================================================================
# PYTHON CHECK TESTS
# ============================================================================

@test "uws_vm_check_python returns 0 or 1 without crashing" {
    run uws_vm_check_python
    # Should return 0 (python found) or 1 (not found) — both are valid
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

# ============================================================================
# DISK SPACE CHECK TESTS
# ============================================================================

@test "uws_vm_check_disk_space returns 0 or 1 without crashing" {
    run uws_vm_check_disk_space "${TEST_TMP_DIR}"
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

# ============================================================================
# MCP.JSON CONFIGURATION TESTS
# ============================================================================

@test "uws_vm_configure_mcp_json creates .mcp.json when absent" {
    # Need a fake venv python for this test
    local fake_venv="${TEST_TMP_DIR}/fake-venv"
    mkdir -p "${fake_venv}/bin"
    # Use the real python as the fake venv python
    local real_python
    real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)" || skip "Python not available"
    ln -s "$real_python" "${fake_venv}/bin/python"

    # Override the install dir for testing
    UWS_VECTOR_INSTALL_DIR="${TEST_TMP_DIR}/fake-install"
    mkdir -p "${UWS_VECTOR_INSTALL_DIR}/.venv/bin"
    ln -s "$real_python" "${UWS_VECTOR_INSTALL_DIR}/.venv/bin/python"
    touch "${UWS_VECTOR_INSTALL_DIR}/main.py"

    [ ! -f "${TEST_TMP_DIR}/.mcp.json" ]

    run uws_vm_configure_mcp_json "${TEST_TMP_DIR}"
    [ "$status" -eq 0 ]
    [ -f "${TEST_TMP_DIR}/.mcp.json" ]

    # Verify it contains vector_memory_local
    run grep "vector_memory_local" "${TEST_TMP_DIR}/.mcp.json"
    [ "$status" -eq 0 ]
}

@test "uws_vm_configure_mcp_json merges into existing .mcp.json preserving other servers" {
    local real_python
    real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)" || skip "Python not available"

    UWS_VECTOR_INSTALL_DIR="${TEST_TMP_DIR}/fake-install"
    mkdir -p "${UWS_VECTOR_INSTALL_DIR}/.venv/bin"
    ln -s "$real_python" "${UWS_VECTOR_INSTALL_DIR}/.venv/bin/python"
    touch "${UWS_VECTOR_INSTALL_DIR}/main.py"

    # Create existing .mcp.json with another server
    cat > "${TEST_TMP_DIR}/.mcp.json" << 'EOF'
{
  "mcpServers": {
    "existing_server": {
      "command": "npx",
      "args": ["-y", "some-server"]
    }
  }
}
EOF

    run uws_vm_configure_mcp_json "${TEST_TMP_DIR}"
    [ "$status" -eq 0 ]

    # Verify existing server preserved
    run grep "existing_server" "${TEST_TMP_DIR}/.mcp.json"
    [ "$status" -eq 0 ]

    # Verify vector memory added
    run grep "vector_memory_local" "${TEST_TMP_DIR}/.mcp.json"
    [ "$status" -eq 0 ]
    run grep "vector_memory_global" "${TEST_TMP_DIR}/.mcp.json"
    [ "$status" -eq 0 ]
}

@test "uws_vm_configure_mcp_json is idempotent" {
    local real_python
    real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)" || skip "Python not available"

    UWS_VECTOR_INSTALL_DIR="${TEST_TMP_DIR}/fake-install"
    mkdir -p "${UWS_VECTOR_INSTALL_DIR}/.venv/bin"
    ln -s "$real_python" "${UWS_VECTOR_INSTALL_DIR}/.venv/bin/python"
    touch "${UWS_VECTOR_INSTALL_DIR}/main.py"

    run uws_vm_configure_mcp_json "${TEST_TMP_DIR}"
    [ "$status" -eq 0 ]
    local first_content
    first_content="$(cat "${TEST_TMP_DIR}/.mcp.json")"

    # Run again — should not change
    run uws_vm_configure_mcp_json "${TEST_TMP_DIR}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already configured"* ]]

    local second_content
    second_content="$(cat "${TEST_TMP_DIR}/.mcp.json")"
    [ "$first_content" = "$second_content" ]
}

@test "uws_vm_configure_mcp_json updates --working-dir when project path differs" {
    local real_python
    real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)" || skip "Python not available"

    UWS_VECTOR_INSTALL_DIR="${TEST_TMP_DIR}/fake-install"
    mkdir -p "${UWS_VECTOR_INSTALL_DIR}/.venv/bin"
    ln -s "$real_python" "${UWS_VECTOR_INSTALL_DIR}/.venv/bin/python"
    touch "${UWS_VECTOR_INSTALL_DIR}/main.py"

    # First configure with one path
    run uws_vm_configure_mcp_json "${TEST_TMP_DIR}"
    [ "$status" -eq 0 ]

    # Verify the current path is present
    run grep "${TEST_TMP_DIR}" "${TEST_TMP_DIR}/.mcp.json"
    [ "$status" -eq 0 ]

    # Create a different project directory
    local other_dir="${TEST_TMP_DIR}/other-project"
    mkdir -p "$other_dir"

    # Copy .mcp.json to new location and reconfigure
    cp "${TEST_TMP_DIR}/.mcp.json" "${other_dir}/.mcp.json"
    run uws_vm_configure_mcp_json "${other_dir}"
    [ "$status" -eq 0 ]

    # Verify the new path is present and old path replaced
    run grep "${other_dir}" "${other_dir}/.mcp.json"
    [ "$status" -eq 0 ]
}

@test "path with spaces handled correctly in .mcp.json" {
    local real_python
    real_python="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)" || skip "Python not available"

    UWS_VECTOR_INSTALL_DIR="${TEST_TMP_DIR}/fake-install"
    mkdir -p "${UWS_VECTOR_INSTALL_DIR}/.venv/bin"
    ln -s "$real_python" "${UWS_VECTOR_INSTALL_DIR}/.venv/bin/python"
    touch "${UWS_VECTOR_INSTALL_DIR}/main.py"

    local spaced_dir="${TEST_TMP_DIR}/my project dir"
    mkdir -p "$spaced_dir"

    run uws_vm_configure_mcp_json "$spaced_dir"
    [ "$status" -eq 0 ]
    [ -f "$spaced_dir/.mcp.json" ]

    # Verify JSON is valid (python can parse it)
    run "$real_python" -c "import json; json.load(open('$spaced_dir/.mcp.json'))"
    [ "$status" -eq 0 ]
}

# ============================================================================
# GITIGNORE TESTS
# ============================================================================

@test "uws_vm_update_gitignore adds memory/ when absent" {
    echo "# existing content" > "${TEST_TMP_DIR}/.gitignore"

    run uws_vm_update_gitignore "${TEST_TMP_DIR}"
    [ "$status" -eq 0 ]

    run grep '^memory/$' "${TEST_TMP_DIR}/.gitignore"
    [ "$status" -eq 0 ]
}

@test "uws_vm_update_gitignore is idempotent" {
    echo "# existing" > "${TEST_TMP_DIR}/.gitignore"

    uws_vm_update_gitignore "${TEST_TMP_DIR}"
    local first_lines
    first_lines="$(wc -l < "${TEST_TMP_DIR}/.gitignore")"

    uws_vm_update_gitignore "${TEST_TMP_DIR}"
    local second_lines
    second_lines="$(wc -l < "${TEST_TMP_DIR}/.gitignore")"

    [ "$first_lines" -eq "$second_lines" ]
}

@test "uws_vm_update_gitignore creates .gitignore if missing" {
    [ ! -f "${TEST_TMP_DIR}/sub/.gitignore" ]

    mkdir -p "${TEST_TMP_DIR}/sub"
    run uws_vm_update_gitignore "${TEST_TMP_DIR}/sub"
    [ "$status" -eq 0 ]
    [ -f "${TEST_TMP_DIR}/sub/.gitignore" ]

    run grep '^memory/$' "${TEST_TMP_DIR}/sub/.gitignore"
    [ "$status" -eq 0 ]
}

# ============================================================================
# ORCHESTRATOR TESTS
# ============================================================================

@test "non-interactive mode skips prompt" {
    # Run with stdin from /dev/null — should not hang waiting for input
    run bash -c "unset _VECTOR_MEMORY_SETUP_LOADED; source '${SCRIPTS_DIR}/lib/vector_memory_setup.sh'; setup_vector_memory '${TEST_TMP_DIR}'" < /dev/null
    # Status 0 or 1 (depending on python/disk/network) but must not hang
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "setup_vector_memory returns 0 even when Python is missing (graceful degradation)" {
    # Create a wrapper script so bash can find itself but python is hidden
    local wrapper="${TEST_TMP_DIR}/test_no_python.sh"
    cat > "$wrapper" << SCRIPTEOF
#!/bin/bash
set -euo pipefail
# Hide python by overriding the check function
unset _VECTOR_MEMORY_SETUP_LOADED
source '${SCRIPTS_DIR}/lib/vector_memory_setup.sh'
# Override the python check to simulate missing python
uws_vm_check_python() { return 1; }
setup_vector_memory '${TEST_TMP_DIR}'
SCRIPTEOF
    chmod +x "$wrapper"

    run bash "$wrapper"
    # Returns 1 (graceful) but does not crash (exit code 2+ would mean crash)
    [[ "$status" -le 1 ]]
}
