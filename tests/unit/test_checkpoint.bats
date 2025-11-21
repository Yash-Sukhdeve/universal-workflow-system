#!/usr/bin/env bats

# Unit tests for checkpoint management functionality
# Tests checkpoint creation, restoration, and ID generation

load '../helpers/test_helper'

setup() {
    common_setup
    create_test_state "phase_2_implementation" "CP_2_001"
    create_test_config

    # Define checkpoint functions (extracted from checkpoint.sh)
    generate_checkpoint_id() {
        local phase=$(grep 'current_phase:' "$WORKFLOW_DIR/state.yaml" | cut -d'_' -f2 | cut -d' ' -f1)
        local count=$(grep -c "CP_${phase}_" "$WORKFLOW_DIR/checkpoints.log" 2>/dev/null || echo 0)
        local next_num=$(printf "%03d" $((count + 1)))
        echo "CP_${phase}_${next_num}"
    }

    simple_create_checkpoint() {
        local message="$1"
        local checkpoint_id=$(generate_checkpoint_id)

        # Update state file
        sed -i "s/last_checkpoint:.*/last_checkpoint: ${checkpoint_id}/" "$WORKFLOW_DIR/state.yaml"
        sed -i "s/last_updated:.*/last_updated: $(date -u +\"%Y-%m-%dT%H:%M:%SZ\")/" "$WORKFLOW_DIR/state.yaml"

        # Add to checkpoint log
        echo "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\") | ${checkpoint_id} | ${message}" >> "$WORKFLOW_DIR/checkpoints.log"

        # Create checkpoint snapshot
        local snapshot_dir="$WORKFLOW_DIR/snapshots/${checkpoint_id}"
        mkdir -p "$snapshot_dir"
        cp "$WORKFLOW_DIR/state.yaml" "$snapshot_dir/state.yaml"

        echo "$checkpoint_id"
    }
}

teardown() {
    common_teardown
}

# Checkpoint ID Generation Tests

@test "generate_checkpoint_id creates correct format for phase 1" {
    create_test_state "phase_1_planning" "CP_1_001"

    result=$(generate_checkpoint_id)
    [[ "$result" =~ ^CP_1_[0-9]{3}$ ]]
}

@test "generate_checkpoint_id creates correct format for phase 2" {
    create_test_state "phase_2_implementation" "CP_2_001"

    result=$(generate_checkpoint_id)
    [[ "$result" =~ ^CP_2_[0-9]{3}$ ]]
}

@test "generate_checkpoint_id creates correct format for phase 3" {
    create_test_state "phase_3_validation" "CP_3_001"

    result=$(generate_checkpoint_id)
    [[ "$result" =~ ^CP_3_[0-9]{3}$ ]]
}

@test "generate_checkpoint_id creates correct format for phase 4" {
    create_test_state "phase_4_delivery" "CP_4_001"

    result=$(generate_checkpoint_id)
    [[ "$result" =~ ^CP_4_[0-9]{3}$ ]]
}

@test "generate_checkpoint_id creates correct format for phase 5" {
    create_test_state "phase_5_maintenance" "CP_5_001"

    result=$(generate_checkpoint_id)
    [[ "$result" =~ ^CP_5_[0-9]{3}$ ]]
}

@test "generate_checkpoint_id starts at 001 for empty log" {
    result=$(generate_checkpoint_id)
    [ "$result" = "CP_2_001" ]
}

@test "generate_checkpoint_id increments correctly" {
    echo "2024-01-01T10:00:00Z | CP_2_001 | First checkpoint" > "$WORKFLOW_DIR/checkpoints.log"

    result=$(generate_checkpoint_id)
    [ "$result" = "CP_2_002" ]
}

@test "generate_checkpoint_id increments to 003" {
    echo "2024-01-01T10:00:00Z | CP_2_001 | First" > "$WORKFLOW_DIR/checkpoints.log"
    echo "2024-01-02T10:00:00Z | CP_2_002 | Second" >> "$WORKFLOW_DIR/checkpoints.log"

    result=$(generate_checkpoint_id)
    [ "$result" = "CP_2_003" ]
}

@test "generate_checkpoint_id handles double digits" {
    # Create 10 checkpoints
    for i in {1..10}; do
        local num=$(printf "%03d" $i)
        echo "2024-01-${i}T10:00:00Z | CP_2_${num} | Checkpoint $i" >> "$WORKFLOW_DIR/checkpoints.log"
    done

    result=$(generate_checkpoint_id)
    [ "$result" = "CP_2_011" ]
}

@test "generate_checkpoint_id only counts current phase" {
    # Mix of phase 1 and phase 2 checkpoints
    echo "2024-01-01T10:00:00Z | CP_1_001 | Phase 1" > "$WORKFLOW_DIR/checkpoints.log"
    echo "2024-01-02T10:00:00Z | CP_1_002 | Phase 1" >> "$WORKFLOW_DIR/checkpoints.log"
    echo "2024-01-03T10:00:00Z | CP_2_001 | Phase 2" >> "$WORKFLOW_DIR/checkpoints.log"

    result=$(generate_checkpoint_id)
    [ "$result" = "CP_2_002" ]  # Only counts phase 2 checkpoints
}

# Checkpoint Creation Tests

@test "simple_create_checkpoint creates checkpoint log entry" {
    checkpoint_id=$(simple_create_checkpoint "Test checkpoint")

    assert_file_exists "$WORKFLOW_DIR/checkpoints.log"
    grep -q "Test checkpoint" "$WORKFLOW_DIR/checkpoints.log"
}

@test "simple_create_checkpoint updates state file with new checkpoint" {
    checkpoint_id=$(simple_create_checkpoint "Test checkpoint")

    result=$(grep "last_checkpoint:" "$WORKFLOW_DIR/state.yaml" | cut -d':' -f2 | xargs)
    [ "$result" = "$checkpoint_id" ]
}

@test "simple_create_checkpoint updates timestamp" {
    old_timestamp=$(grep "last_updated:" "$WORKFLOW_DIR/state.yaml" | cut -d':' -f2- | xargs)
    sleep 1

    simple_create_checkpoint "Test checkpoint"

    new_timestamp=$(grep "last_updated:" "$WORKFLOW_DIR/state.yaml" | cut -d':' -f2- | xargs)
    [ "$old_timestamp" != "$new_timestamp" ]
}

@test "simple_create_checkpoint creates snapshot directory" {
    checkpoint_id=$(simple_create_checkpoint "Test checkpoint")

    assert_dir_exists "$WORKFLOW_DIR/snapshots/$checkpoint_id"
}

@test "simple_create_checkpoint saves state snapshot" {
    checkpoint_id=$(simple_create_checkpoint "Test checkpoint")

    assert_file_exists "$WORKFLOW_DIR/snapshots/$checkpoint_id/state.yaml"
}

@test "simple_create_checkpoint snapshot contains correct data" {
    checkpoint_id=$(simple_create_checkpoint "Test checkpoint")

    grep -q "project_name: test_project" "$WORKFLOW_DIR/snapshots/$checkpoint_id/state.yaml"
    grep -q "current_phase: phase_2_implementation" "$WORKFLOW_DIR/snapshots/$checkpoint_id/state.yaml"
}

@test "simple_create_checkpoint returns checkpoint ID" {
    checkpoint_id=$(simple_create_checkpoint "Test checkpoint")

    [[ "$checkpoint_id" =~ ^CP_2_[0-9]{3}$ ]]
}

@test "simple_create_checkpoint creates multiple checkpoints" {
    checkpoint_1=$(simple_create_checkpoint "First")
    checkpoint_2=$(simple_create_checkpoint "Second")
    checkpoint_3=$(simple_create_checkpoint "Third")

    [ "$checkpoint_1" = "CP_2_001" ]
    [ "$checkpoint_2" = "CP_2_002" ]
    [ "$checkpoint_3" = "CP_2_003" ]
}

# Checkpoint Log Format Tests

@test "checkpoint log entry has correct format" {
    simple_create_checkpoint "Test message"

    last_line=$(tail -n 1 "$WORKFLOW_DIR/checkpoints.log")
    [[ "$last_line" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\ \|\ CP_[0-9]_[0-9]{3}\ \|\ .*$ ]]
}

@test "checkpoint log preserves message with special characters" {
    simple_create_checkpoint "Test: with-special_chars & symbols!"

    grep -q "Test: with-special_chars & symbols!" "$WORKFLOW_DIR/checkpoints.log"
}

@test "checkpoint log handles empty message" {
    simple_create_checkpoint ""

    assert_file_exists "$WORKFLOW_DIR/checkpoints.log"
    [ $(wc -l < "$WORKFLOW_DIR/checkpoints.log") -eq 1 ]
}

@test "checkpoint log handles multi-word message" {
    simple_create_checkpoint "This is a long checkpoint message with many words"

    grep -q "This is a long checkpoint message with many words" "$WORKFLOW_DIR/checkpoints.log"
}

# Checkpoint Snapshot Tests

@test "checkpoint snapshot directory naming" {
    checkpoint_id=$(simple_create_checkpoint "Test")

    [ -d "$WORKFLOW_DIR/snapshots/$checkpoint_id" ]
    [[ "$checkpoint_id" =~ ^CP_2_[0-9]{3}$ ]]
}

@test "multiple checkpoints create separate snapshots" {
    cp1=$(simple_create_checkpoint "First")
    cp2=$(simple_create_checkpoint "Second")
    cp3=$(simple_create_checkpoint "Third")

    assert_dir_exists "$WORKFLOW_DIR/snapshots/$cp1"
    assert_dir_exists "$WORKFLOW_DIR/snapshots/$cp2"
    assert_dir_exists "$WORKFLOW_DIR/snapshots/$cp3"
}

@test "checkpoint snapshots are independent" {
    cp1=$(simple_create_checkpoint "First")

    # Modify state
    sed -i "s/test_project/modified_project/" "$WORKFLOW_DIR/state.yaml"

    cp2=$(simple_create_checkpoint "Second")

    # First snapshot should have original name
    grep -q "test_project" "$WORKFLOW_DIR/snapshots/$cp1/state.yaml"
    # Second snapshot should have modified name
    grep -q "modified_project" "$WORKFLOW_DIR/snapshots/$cp2/state.yaml"
}

# Phase Transition Checkpoint Tests

@test "checkpoint IDs change when phase changes" {
    create_test_state "phase_1_planning" "CP_1_001"
    cp1=$(simple_create_checkpoint "Phase 1 checkpoint")
    [ "$cp1" = "CP_1_001" ]

    # Change to phase 2
    sed -i "s/phase_1_planning/phase_2_implementation/" "$WORKFLOW_DIR/state.yaml"
    cp2=$(simple_create_checkpoint "Phase 2 checkpoint")
    [ "$cp2" = "CP_2_001" ]
}

@test "checkpoint numbering resets for new phase" {
    create_test_state "phase_1_planning" "CP_1_005"

    # Add some phase 1 checkpoints
    for i in {1..5}; do
        echo "2024-01-0${i}T10:00:00Z | CP_1_$(printf '%03d' $i) | Phase 1 checkpoint $i" >> "$WORKFLOW_DIR/checkpoints.log"
    done

    # Move to phase 2
    sed -i "s/phase_1_planning/phase_2_implementation/" "$WORKFLOW_DIR/state.yaml"

    # First phase 2 checkpoint should be 001
    cp2=$(simple_create_checkpoint "First phase 2 checkpoint")
    [ "$cp2" = "CP_2_001" ]
}

# Error Handling Tests

@test "checkpoint creation works with missing checkpoints.log" {
    rm -f "$WORKFLOW_DIR/checkpoints.log"

    checkpoint_id=$(simple_create_checkpoint "Test")

    assert_file_exists "$WORKFLOW_DIR/checkpoints.log"
    [ "$checkpoint_id" = "CP_2_001" ]
}

@test "checkpoint creation works with empty checkpoints.log" {
    touch "$WORKFLOW_DIR/checkpoints.log"

    checkpoint_id=$(simple_create_checkpoint "Test")
    [ "$checkpoint_id" = "CP_2_001" ]
}

# Checkpoint Querying Tests

@test "can query checkpoint count" {
    simple_create_checkpoint "One"
    simple_create_checkpoint "Two"
    simple_create_checkpoint "Three"

    count=$(wc -l < "$WORKFLOW_DIR/checkpoints.log")
    [ "$count" -eq 3 ]
}

@test "can find latest checkpoint" {
    simple_create_checkpoint "First"
    simple_create_checkpoint "Second"
    cp3=$(simple_create_checkpoint "Third")

    latest=$(tail -n 1 "$WORKFLOW_DIR/checkpoints.log" | cut -d'|' -f2 | xargs)
    [ "$latest" = "$cp3" ]
}

@test "can filter checkpoints by phase" {
    create_test_state "phase_1_planning" "CP_1_001"
    simple_create_checkpoint "Phase 1 A"
    simple_create_checkpoint "Phase 1 B"

    sed -i "s/phase_1_planning/phase_2_implementation/" "$WORKFLOW_DIR/state.yaml"
    simple_create_checkpoint "Phase 2 A"

    phase_1_count=$(grep -c "CP_1_" "$WORKFLOW_DIR/checkpoints.log")
    phase_2_count=$(grep -c "CP_2_" "$WORKFLOW_DIR/checkpoints.log")

    [ "$phase_1_count" -eq 2 ]
    [ "$phase_2_count" -eq 1 ]
}

# Performance Tests

@test "checkpoint creation handles many checkpoints" {
    # Create 50 checkpoints
    for i in {1..50}; do
        simple_create_checkpoint "Checkpoint $i"
    done

    count=$(wc -l < "$WORKFLOW_DIR/checkpoints.log")
    [ "$count" -eq 50 ]

    # Verify last checkpoint is CP_2_050
    latest=$(generate_checkpoint_id)
    [ "$latest" = "CP_2_051" ]
}

@test "checkpoint ID generation is fast" {
    # Create 100 entries in log
    for i in {1..100}; do
        echo "2024-01-01T10:00:00Z | CP_2_$(printf '%03d' $i) | Test $i" >> "$WORKFLOW_DIR/checkpoints.log"
    done

    # Generate next ID (should be quick even with 100 entries)
    start=$(date +%s%N)
    result=$(generate_checkpoint_id)
    end=$(date +%s%N)

    [ "$result" = "CP_2_101" ]

    # Should complete in less than 100ms (100,000,000 nanoseconds)
    elapsed=$((end - start))
    [ "$elapsed" -lt 100000000 ]
}
