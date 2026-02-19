#!/usr/bin/env bats
# Unit Tests for scripts/lib/uws_config.sh
# Tests config resolution library: read, write, resolution chains, validation

# Load test helpers
load '../helpers/test_helper'

# ============================================================================
# SETUP
# ============================================================================

setup() {
    setup_test_environment
    cd "${TEST_TMP_DIR}"

    # Point XDG_CONFIG_HOME to test-local dir so we never touch real config
    export XDG_CONFIG_HOME="${TEST_TMP_DIR}/.config"

    # Reset double-source guard
    unset _UWS_CONFIG_LOADED

    # Source the library
    source "${SCRIPTS_DIR}/lib/uws_config.sh"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# LIBRARY LOADING TESTS
# ============================================================================

@test "uws_config.sh loads without error" {
    unset _UWS_CONFIG_LOADED
    run bash -c "export XDG_CONFIG_HOME='${TEST_TMP_DIR}/.config'; source '${SCRIPTS_DIR}/lib/uws_config.sh'"
    [ "$status" -eq 0 ]
}

@test "double-source guard prevents re-loading" {
    [ "$_UWS_CONFIG_LOADED" = "true" ]
    source "${SCRIPTS_DIR}/lib/uws_config.sh"
    [ "$_UWS_CONFIG_LOADED" = "true" ]
}

# ============================================================================
# CONFIG FILE LOCATION TESTS
# ============================================================================

@test "config dir respects XDG_CONFIG_HOME" {
    [ "$UWS_CONFIG_DIR" = "${TEST_TMP_DIR}/.config/uws" ]
}

@test "config file path is under XDG_CONFIG_HOME" {
    [ "$UWS_CONFIG_FILE" = "${TEST_TMP_DIR}/.config/uws/config.yaml" ]
}

# ============================================================================
# uws_config_write TESTS
# ============================================================================

@test "uws_config_write creates directory and file" {
    [ ! -f "$UWS_CONFIG_FILE" ]

    run uws_config_write "global_memory_dir=/tmp/test-mem"
    [ "$status" -eq 0 ]
    [ -f "$UWS_CONFIG_FILE" ]
    [ -d "$UWS_CONFIG_DIR" ]
}

@test "uws_config_write writes correct key=value" {
    uws_config_write "global_memory_dir=/tmp/test-mem"

    run grep 'global_memory_dir:' "$UWS_CONFIG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *'/tmp/test-mem'* ]]
}

@test "uws_config_write handles multiple pairs" {
    uws_config_write "global_memory_dir=/tmp/mem" "uws_install_dir=/tmp/uws" "vector_memory_server=/tmp/vec"

    run grep -c ':' "$UWS_CONFIG_FILE"
    [ "$status" -eq 0 ]
    # Header comment has no colon-space-value, 3 keys do
    (( output >= 3 ))
}

@test "uws_config_write is idempotent — no duplicate keys" {
    uws_config_write "global_memory_dir=/tmp/first"
    uws_config_write "global_memory_dir=/tmp/second"

    local count
    count="$(grep -c 'global_memory_dir:' "$UWS_CONFIG_FILE")"
    [ "$count" -eq 1 ]

    # Value should be updated
    run uws_config_read_key "global_memory_dir"
    [ "$output" = "/tmp/second" ]
}

@test "uws_config_write returns 1 with no arguments" {
    run uws_config_write
    [ "$status" -eq 1 ]
}

# ============================================================================
# uws_config_read_key TESTS
# ============================================================================

@test "uws_config_read_key returns value for existing key" {
    uws_config_write "global_memory_dir=/home/user/mem"

    run uws_config_read_key "global_memory_dir"
    [ "$status" -eq 0 ]
    [ "$output" = "/home/user/mem" ]
}

@test "uws_config_read_key returns 1 for missing key" {
    uws_config_write "global_memory_dir=/tmp/mem"

    run uws_config_read_key "nonexistent_key"
    [ "$status" -eq 1 ]
}

@test "uws_config_read_key returns 1 when no config file exists" {
    run uws_config_read_key "global_memory_dir"
    [ "$status" -eq 1 ]
}

# ============================================================================
# RESOLUTION CHAIN TESTS — global_memory_dir
# ============================================================================

@test "uws_resolve_global_memory_dir: env var wins over config and default" {
    uws_config_write "global_memory_dir=/from/config"
    export UWS_GLOBAL_MEMORY_DIR="/from/env"

    run uws_resolve_global_memory_dir
    [ "$output" = "/from/env" ]

    unset UWS_GLOBAL_MEMORY_DIR
}

@test "uws_resolve_global_memory_dir: config wins over default" {
    uws_config_write "global_memory_dir=/from/config"
    unset UWS_GLOBAL_MEMORY_DIR 2>/dev/null || true

    run uws_resolve_global_memory_dir
    [ "$output" = "/from/config" ]
}

@test "uws_resolve_global_memory_dir: default when nothing set" {
    unset UWS_GLOBAL_MEMORY_DIR 2>/dev/null || true

    run uws_resolve_global_memory_dir
    [ "$output" = "${HOME}/uws-global-knowledge" ]
}

# ============================================================================
# RESOLUTION CHAIN TESTS — install_dir
# ============================================================================

@test "uws_resolve_install_dir: env var wins" {
    export UWS_INSTALL_DIR="/from/env"

    run uws_resolve_install_dir
    [ "$output" = "/from/env" ]

    unset UWS_INSTALL_DIR
}

@test "uws_resolve_install_dir: config wins over self-discovery" {
    uws_config_write "uws_install_dir=/from/config"
    unset UWS_INSTALL_DIR 2>/dev/null || true

    run uws_resolve_install_dir
    [ "$output" = "/from/config" ]
}

@test "uws_resolve_install_dir: self-discovery falls back to project root" {
    unset UWS_INSTALL_DIR 2>/dev/null || true
    # No config file exists, so it should self-discover from BASH_SOURCE

    run uws_resolve_install_dir
    [ "$status" -eq 0 ]
    # The resolved path should be the actual project root
    [ "$output" = "$PROJECT_ROOT" ]
}

# ============================================================================
# RESOLUTION CHAIN TESTS — vector_server_dir
# ============================================================================

@test "uws_resolve_vector_server_dir: env var wins" {
    export UWS_VECTOR_SERVER_DIR="/from/env"

    run uws_resolve_vector_server_dir
    [ "$output" = "/from/env" ]

    unset UWS_VECTOR_SERVER_DIR
}

@test "uws_resolve_vector_server_dir: config wins over default" {
    uws_config_write "vector_memory_server=/from/config"
    unset UWS_VECTOR_SERVER_DIR 2>/dev/null || true

    run uws_resolve_vector_server_dir
    [ "$output" = "/from/config" ]
}

@test "uws_resolve_vector_server_dir: default when nothing set" {
    unset UWS_VECTOR_SERVER_DIR 2>/dev/null || true

    run uws_resolve_vector_server_dir
    [ "$output" = "${HOME}/.uws/tools/vector-memory" ]
}

# ============================================================================
# PATH VALIDATION TESTS
# ============================================================================

@test "uws_validate_global_dir_path accepts clean paths" {
    run uws_validate_global_dir_path "/home/user/uws-global-knowledge"
    [ "$status" -eq 0 ]
}

@test "uws_validate_global_dir_path accepts paths with tilde" {
    run uws_validate_global_dir_path "~/uws-global-knowledge"
    [ "$status" -eq 0 ]
}

@test "uws_validate_global_dir_path rejects dot-prefixed components" {
    run uws_validate_global_dir_path "/home/user/.hidden/knowledge"
    [ "$status" -eq 1 ]
    [[ "$output" == *"starts with dot"* ]]
}

@test "uws_validate_global_dir_path rejects nested dot-prefixed" {
    run uws_validate_global_dir_path "/home/user/ok/.secret-dir/data"
    [ "$status" -eq 1 ]
}

@test "uws_validate_global_dir_path allows .gitkeep" {
    run uws_validate_global_dir_path "/home/user/dir/.gitkeep"
    [ "$status" -eq 0 ]
}

# ============================================================================
# uws_persist_config TESTS
# ============================================================================

@test "uws_persist_config writes all 3 keys" {
    unset UWS_GLOBAL_MEMORY_DIR UWS_INSTALL_DIR UWS_VECTOR_SERVER_DIR 2>/dev/null || true

    run uws_persist_config
    [ "$status" -eq 0 ]
    [ -f "$UWS_CONFIG_FILE" ]

    # All 3 keys should be present
    run grep -c ':' "$UWS_CONFIG_FILE"
    (( output >= 3 ))

    run uws_config_read_key "global_memory_dir"
    [ "$status" -eq 0 ]
    run uws_config_read_key "uws_install_dir"
    [ "$status" -eq 0 ]
    run uws_config_read_key "vector_memory_server"
    [ "$status" -eq 0 ]
}

@test "uws_persist_config is idempotent" {
    uws_persist_config
    local first
    first="$(cat "$UWS_CONFIG_FILE")"

    uws_persist_config
    local second
    second="$(cat "$UWS_CONFIG_FILE")"

    [ "$first" = "$second" ]
}
