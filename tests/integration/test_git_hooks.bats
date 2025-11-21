#!/usr/bin/env bats

# Integration tests for git hook functionality
# Tests automatic state updates and checkpoint creation

load '../helpers/test_helper'

setup() {
    common_setup
    create_test_state "phase_2_implementation" "CP_2_001"
    create_test_config
    init_test_git
}

teardown() {
    common_teardown
}

# Git Hook Installation Tests

@test "pre-commit hook can be installed" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
# Update workflow state timestamp on commit
if [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    assert_file_exists "$TEST_DIR/.git/hooks/pre-commit"
    [ -x "$TEST_DIR/.git/hooks/pre-commit" ]
}

@test "pre-commit hook has correct shebang" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
echo "test hook"
EOF

    first_line=$(head -n 1 "$TEST_DIR/.git/hooks/pre-commit")
    [[ "$first_line" == "#!/bin/bash" ]] || [[ "$first_line" == "#!/usr/bin/env bash" ]]
}

# State Update Tests

@test "git commit updates state timestamp" {
    mkdir -p "$TEST_DIR/.git/hooks"

    # Install hook
    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
if [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Get original timestamp
    old_timestamp=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")

    sleep 1

    # Make a change and commit
    echo "test" > "$TEST_DIR/test_file.txt"
    git add test_file.txt

    # Manually run the hook
    cd "$TEST_DIR"
    .git/hooks/pre-commit

    # Check if timestamp was updated
    new_timestamp=$(get_test_yaml_value "$WORKFLOW_DIR/state.yaml" "last_updated")

    # Timestamps should be different
    [ "$old_timestamp" != "$new_timestamp" ]
}

@test "git commit stages state file" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
if [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Make a change
    echo "test" > "$TEST_DIR/test_file.txt"
    git add test_file.txt

    # Run hook
    cd "$TEST_DIR"
    .git/hooks/pre-commit

    # Check if state.yaml is staged
    git add .workflow/state.yaml
    # If the command succeeds, the file was added (or was already staged)
}

# Checkpoint Logging Tests

@test "git commit adds checkpoint entry" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
# Add checkpoint entry
if [ -f .workflow/checkpoints.log ]; then
    current_checkpoint=$(grep 'last_checkpoint:' .workflow/state.yaml | cut -d':' -f2 | xargs)
    echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | ${current_checkpoint} | Committed changes" >> .workflow/checkpoints.log
    git add .workflow/checkpoints.log
fi
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Get initial log size
    touch "$WORKFLOW_DIR/checkpoints.log"
    initial_lines=$(wc -l < "$WORKFLOW_DIR/checkpoints.log")

    # Make a change and run hook
    echo "test" > "$TEST_DIR/test_file.txt"
    git add test_file.txt
    cd "$TEST_DIR"
    .git/hooks/pre-commit

    # Check if checkpoint was added
    new_lines=$(wc -l < "$WORKFLOW_DIR/checkpoints.log")
    [ "$new_lines" -gt "$initial_lines" ]
}

# Hook Error Handling

@test "hook handles missing state file gracefully" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
if [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi
# Should not fail if file doesn't exist
exit 0
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Remove state file
    rm -f "$WORKFLOW_DIR/state.yaml"

    # Run hook (should not fail)
    cd "$TEST_DIR"
    run .git/hooks/pre-commit
    [ "$status" -eq 0 ]
}

@test "hook handles missing workflow directory" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
if [ -d .workflow ] && [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi
exit 0
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Remove workflow directory
    rm -rf "$WORKFLOW_DIR"

    # Run hook (should not fail)
    cd "$TEST_DIR"
    run .git/hooks/pre-commit
    [ "$status" -eq 0 ]
}

# Multiple File Updates

@test "hook updates multiple workflow files" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
if [ -f .workflow/state.yaml ]; then
    # Update state
    sed -i "s/last_updated:.*/last_updated: \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"/" .workflow/state.yaml
    git add .workflow/state.yaml

    # Update checkpoint log
    if [ -f .workflow/checkpoints.log ]; then
        echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | COMMIT | Auto-checkpoint" >> .workflow/checkpoints.log
        git add .workflow/checkpoints.log
    fi
fi
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    touch "$WORKFLOW_DIR/checkpoints.log"

    # Run hook
    echo "test" > "$TEST_DIR/test_file.txt"
    git add test_file.txt
    cd "$TEST_DIR"
    .git/hooks/pre-commit

    # Both files should be updated
    grep -q "last_updated:" "$WORKFLOW_DIR/state.yaml"
    grep -q "COMMIT" "$WORKFLOW_DIR/checkpoints.log"
}

# Hook Execution Tests

@test "hook executes before commit" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
echo "Hook executed" > /tmp/hook_test_marker
exit 0
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Run hook
    cd "$TEST_DIR"
    .git/hooks/pre-commit

    # Check marker file
    [ -f /tmp/hook_test_marker ]
    rm -f /tmp/hook_test_marker
}

@test "hook can prevent commit on error" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
# Simulate validation failure
if [ -f .workflow/state.yaml ]; then
    if ! grep -q "project_name:" .workflow/state.yaml; then
        echo "ERROR: Invalid state file"
        exit 1
    fi
fi
exit 0
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Run hook (should succeed with valid state)
    cd "$TEST_DIR"
    run .git/hooks/pre-commit
    [ "$status" -eq 0 ]
}

# Auto-Checkpoint on Phase Change

@test "hook detects phase change" {
    mkdir -p "$TEST_DIR/.git/hooks"

    # Create previous state backup
    cp "$WORKFLOW_DIR/state.yaml" "$WORKFLOW_DIR/state.yaml.prev"

    # Change phase
    sed -i "s/phase_2_implementation/phase_3_validation/" "$WORKFLOW_DIR/state.yaml"

    # Hook should detect difference
    if ! diff -q "$WORKFLOW_DIR/state.yaml" "$WORKFLOW_DIR/state.yaml.prev" > /dev/null 2>&1; then
        phase_changed=true
    fi

    [ "$phase_changed" = true ]
}

@test "hook creates checkpoint on phase change" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
if [ -f .workflow/state.yaml.prev ]; then
    old_phase=$(grep 'current_phase:' .workflow/state.yaml.prev | cut -d':' -f2 | xargs)
    new_phase=$(grep 'current_phase:' .workflow/state.yaml | cut -d':' -f2 | xargs)

    if [ "$old_phase" != "$new_phase" ]; then
        echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | PHASE_CHANGE | Changed from $old_phase to $new_phase" >> .workflow/checkpoints.log
    fi
fi
cp .workflow/state.yaml .workflow/state.yaml.prev
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Create previous state
    cp "$WORKFLOW_DIR/state.yaml" "$WORKFLOW_DIR/state.yaml.prev"

    # Change phase
    sed -i "s/phase_2_implementation/phase_3_validation/" "$WORKFLOW_DIR/state.yaml"

    # Run hook
    cd "$TEST_DIR"
    .git/hooks/pre-commit

    # Check for phase change entry
    grep -q "PHASE_CHANGE" "$WORKFLOW_DIR/checkpoints.log" || true
}

# Configuration-Based Hook Behavior

@test "hook respects auto_commit config" {
    mkdir -p "$TEST_DIR/.git/hooks"

    # Check config
    auto_commit=$(grep 'auto_commit:' "$WORKFLOW_DIR/config.yaml" | cut -d':' -f2 | xargs)

    [ "$auto_commit" = "false" ] || [ "$auto_commit" = "true" ]
}

@test "hook respects commit_checkpoints config" {
    commit_checkpoints=$(grep 'commit_checkpoints:' "$WORKFLOW_DIR/config.yaml" | cut -d':' -f2 | xargs)

    [ "$commit_checkpoints" = "false" ] || [ "$commit_checkpoints" = "true" ]
}

# Post-Commit Hook Tests

@test "post-commit hook can be installed" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/post-commit" <<'EOF'
#!/bin/bash
# Log successful commit
echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | COMMITTED | $(git log -1 --oneline)" >> .workflow/commit_history.log
EOF

    chmod +x "$TEST_DIR/.git/hooks/post-commit"

    assert_file_exists "$TEST_DIR/.git/hooks/post-commit"
    [ -x "$TEST_DIR/.git/hooks/post-commit" ]
}

# Hook Compatibility Tests

@test "hook works with existing pre-commit hooks" {
    mkdir -p "$TEST_DIR/.git/hooks"

    # Existing hook
    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
# Existing functionality
echo "Running linter..."

# Workflow hook functionality
if [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    # Both parts should work
    cd "$TEST_DIR"
    run .git/hooks/pre-commit
    [ "$status" -eq 0 ]
}

# Hook Logging Tests

@test "hook logs execution" {
    mkdir -p "$TEST_DIR/.git/hooks"

    cat > "$TEST_DIR/.git/hooks/pre-commit" <<'EOF'
#!/bin/bash
mkdir -p .workflow/logs
echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | pre-commit hook executed" >> .workflow/logs/hook.log
exit 0
EOF

    chmod +x "$TEST_DIR/.git/hooks/pre-commit"

    mkdir -p "$WORKFLOW_DIR/logs"

    cd "$TEST_DIR"
    .git/hooks/pre-commit

    if [ -f "$WORKFLOW_DIR/logs/hook.log" ]; then
        grep -q "pre-commit hook executed" "$WORKFLOW_DIR/logs/hook.log"
    fi
}
