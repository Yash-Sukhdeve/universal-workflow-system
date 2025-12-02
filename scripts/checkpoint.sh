#!/bin/bash

# Checkpoint Management Script - v2
# Create, list, and restore workflow checkpoints
# RWF Compliance: R3 (State Safety), R4 (Error-Free), R5 (Reproducibility)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

COMMAND="${1:-create}"
CHECKPOINT_MSG="${2:-Manual checkpoint}"
CHECKPOINT_ID="${2:-}"

# Checkpoint format version
readonly CHECKPOINT_VERSION="2.0"

# Source utility libraries in dependency order
source_lib() {
    local lib="$1"
    if [[ -f "${SCRIPT_LIB_DIR}/${lib}" ]]; then
        source "${SCRIPT_LIB_DIR}/${lib}"
        return 0
    fi
    return 1
}

# Core utilities (always required)
source_lib "yaml_utils.sh" || true
source_lib "validation_utils.sh" || true

# RWF utilities (enhanced functionality)
source_lib "atomic_utils.sh" || true
source_lib "timestamp_utils.sh" || true
source_lib "logging_utils.sh" || true
source_lib "error_utils.sh" || true
source_lib "precondition_utils.sh" || true
source_lib "checksum_utils.sh" || true
source_lib "completeness_utils.sh" || true
source_lib "decision_utils.sh" || true

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Function to show usage
show_usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  create [message]   - Create a new checkpoint (v2 format)"
    echo "  list              - List all checkpoints"
    echo "  restore [id]      - Restore to a checkpoint"
    echo "  verify [id]       - Verify checkpoint integrity"
    echo "  status            - Show current checkpoint status"
    echo "  auto              - Enable/disable auto checkpointing"
    echo "  completeness      - Show recovery completeness report"
    echo ""
    echo "Examples:"
    echo "  $0 create \"Completed model training\""
    echo "  $0 list"
    echo "  $0 restore CP_2_003"
    echo "  $0 verify CP_2_003"
    echo ""
    echo "Checkpoint Format:"
    echo "  v1.0 - Legacy format (state.yaml, handoff.md)"
    echo "  v2.0 - Enhanced format (manifest, checksums, context)"
    exit 1
}

# Check if workflow is initialized
if ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -d .workflow ]]; then
        echo -e "${RED}Error: Workflow not initialized. Run ./scripts/init_workflow.sh first${NC}"
        exit 1
    fi
fi

# Create checkpoint directories if they don't exist
mkdir -p .workflow/checkpoints/snapshots

# Function to generate checkpoint ID
generate_checkpoint_id() {
    # Get current phase number using YAML utilities
    local phase_full
    if declare -f yaml_get > /dev/null 2>&1; then
        phase_full=$(yaml_get .workflow/state.yaml "current_phase")
    else
        phase_full=$(grep 'current_phase:' .workflow/state.yaml | cut -d':' -f2 | xargs)
    fi

    # Extract phase number (e.g., "phase_1_planning" -> "1")
    local phase=$(echo "$phase_full" | cut -d'_' -f2)

    # Validate phase number
    if [[ ! "$phase" =~ ^[1-5]$ ]]; then
        echo -e "${RED}Error: Invalid phase in state file${NC}" >&2
        return 1
    fi

    # Get next checkpoint number for this phase
    local count=$(grep -c "CP_${phase}_" .workflow/checkpoints.log 2>/dev/null || echo 0)
    local next_num=$(printf "%03d" $((count + 1)))

    echo "CP_${phase}_${next_num}"
}

# Function to create checkpoint (v2 format with manifests and checksums)
create_checkpoint() {
    local message="$1"
    local checkpoint_id

    # Set error context for better diagnostics
    if declare -f set_error_context > /dev/null 2>&1; then
        set_error_context "checkpoint creation"
    fi

    # Generate checkpoint ID
    checkpoint_id=$(generate_checkpoint_id) || {
        echo -e "${RED}Error: Failed to generate checkpoint ID${NC}"
        return 1
    }

    echo -e "${BLUE}📍 Creating checkpoint ${checkpoint_id}...${NC}"

    # Log the operation
    if declare -f log_checkpoint > /dev/null 2>&1; then
        log_checkpoint "$checkpoint_id" "create" "$message"
    fi

    # Get timestamp using utility or fallback
    local timestamp
    if declare -f get_iso_timestamp > /dev/null 2>&1; then
        timestamp=$(get_iso_timestamp)
    else
        timestamp="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    fi

    # Update state file atomically
    if declare -f atomic_yaml_set > /dev/null 2>&1; then
        atomic_yaml_set .workflow/state.yaml "current_checkpoint" "$checkpoint_id" || {
            echo -e "${RED}Error: Failed to update state file atomically${NC}"
            return 1
        }
        atomic_yaml_set .workflow/state.yaml "metadata.last_updated" "$timestamp"
    elif declare -f yaml_set > /dev/null 2>&1; then
        yaml_set .workflow/state.yaml "current_checkpoint" "$checkpoint_id" || {
            echo -e "${RED}Error: Failed to update state file${NC}"
            return 1
        }
        yaml_set .workflow/state.yaml "metadata.last_updated" "$timestamp"
    else
        # Fallback to sed with backup
        cp .workflow/state.yaml .workflow/state.yaml.bak
        sed -i "s/current_checkpoint:.*/current_checkpoint: \"${checkpoint_id}\"/" .workflow/state.yaml
        sed -i "s/last_updated:.*/last_updated: \"${timestamp}\"/" .workflow/state.yaml
        rm -f .workflow/state.yaml.bak
    fi

    # Add to checkpoint log atomically
    if declare -f atomic_append > /dev/null 2>&1; then
        atomic_append .workflow/checkpoints.log "${timestamp} | ${checkpoint_id} | ${message}"
    else
        echo "${timestamp} | ${checkpoint_id} | ${message}" >> .workflow/checkpoints.log
    fi

    # Create checkpoint snapshot directory structure (v2 format)
    local snapshot_dir=".workflow/checkpoints/snapshots/${checkpoint_id}"
    mkdir -p "$snapshot_dir" || {
        echo -e "${RED}Error: Failed to create snapshot directory${NC}"
        return 1
    }

    # Create v2 subdirectories
    mkdir -p "$snapshot_dir/active_state"
    mkdir -p "$snapshot_dir/context"

    echo -e "  ${CYAN}Saving state files...${NC}"

    # Save core state files
    cp .workflow/state.yaml "$snapshot_dir/state.yaml"
    [[ -f .workflow/handoff.md ]] && cp .workflow/handoff.md "$snapshot_dir/handoff.md"

    # Save active state (v2)
    if [[ -f .workflow/agents/active.yaml ]]; then
        cp .workflow/agents/active.yaml "$snapshot_dir/active_state/agent.yaml"
        # Also copy to old location for backward compatibility
        cp .workflow/agents/active.yaml "$snapshot_dir/active_agent.yaml"
    fi
    if [[ -f .workflow/skills/enabled.yaml ]]; then
        cp .workflow/skills/enabled.yaml "$snapshot_dir/active_state/skills.yaml"
        cp .workflow/skills/enabled.yaml "$snapshot_dir/enabled_skills.yaml"
    fi

    # Create session state (v2)
    cat > "$snapshot_dir/active_state/session.yaml" << EOF
session_id: "$(date +%Y%m%d_%H%M%S)_$$"
started: "${timestamp}"
checkpoint_version: "${CHECKPOINT_VERSION}"
context_size_estimate: $(wc -c < .workflow/state.yaml 2>/dev/null || echo 0)
handoff_present: $([[ -f .workflow/handoff.md ]] && echo "true" || echo "false")
EOF

    # Save context (v2) - recent decisions and execution log
    if [[ -f .workflow/logs/decisions.log ]]; then
        # Copy last 50 entries
        tail -100 .workflow/logs/decisions.log > "$snapshot_dir/context/decisions.log" 2>/dev/null || true
    fi
    if [[ -f .workflow/logs/execution.log ]]; then
        tail -200 .workflow/logs/execution.log > "$snapshot_dir/context/execution.log" 2>/dev/null || true
    fi

    # Get git info safely
    local git_commit git_branch files_changed
    git_commit="$(git rev-parse --short HEAD 2>/dev/null || echo 'uncommitted')"
    git_branch="$(git branch --show-current 2>/dev/null || echo 'unknown')"
    files_changed="$(git status --porcelain 2>/dev/null | wc -l || echo 0)"

    # Get current phase
    local current_phase
    if declare -f yaml_get > /dev/null 2>&1; then
        current_phase=$(yaml_get .workflow/state.yaml "current_phase" 2>/dev/null || echo "unknown")
    else
        current_phase=$(grep 'current_phase:' .workflow/state.yaml 2>/dev/null | cut -d':' -f2 | xargs || echo "unknown")
    fi

    # Create enhanced metadata (v2)
    cat > "$snapshot_dir/metadata.yaml" << EOF
# Checkpoint Metadata - v2 format
version: "${CHECKPOINT_VERSION}"
checkpoint_id: "${checkpoint_id}"
created: "${timestamp}"
message: "${message}"

git:
  commit: "${git_commit}"
  branch: "${git_branch}"
  files_changed: ${files_changed}

workflow:
  phase: "${current_phase}"

recovery:
  compatible_versions: ["1.0", "2.0"]
  restore_priority: ["state.yaml", "handoff.md", "active_state/agent.yaml"]
EOF

    echo -e "  ${CYAN}Creating manifest with checksums...${NC}"

    # Create manifest with checksums (v2)
    if declare -f create_snapshot_manifest > /dev/null 2>&1; then
        create_snapshot_manifest "$snapshot_dir"
    else
        # Fallback: create basic manifest
        cat > "$snapshot_dir/manifest.yaml" << EOF
# Checkpoint Manifest - v2 format
snapshot_id: "${checkpoint_id}"
created: "${timestamp}"
version: "${CHECKPOINT_VERSION}"
files:
EOF
        # Add file entries
        for file in "$snapshot_dir"/*; do
            if [[ -f "$file" && "$(basename "$file")" != "manifest.yaml" ]]; then
                local filename=$(basename "$file")
                local checksum=""
                if command -v sha256sum &> /dev/null; then
                    checksum=$(sha256sum "$file" | cut -d' ' -f1)
                elif command -v shasum &> /dev/null; then
                    checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)
                fi
                echo "  - path: \"${filename}\"" >> "$snapshot_dir/manifest.yaml"
                echo "    checksum: \"${checksum}\"" >> "$snapshot_dir/manifest.yaml"
                echo "    required: true" >> "$snapshot_dir/manifest.yaml"
            fi
        done
    fi

    # Git commit if enabled
    if grep -q "auto_commit_state: true" .workflow/config.yaml 2>/dev/null; then
        git add .workflow/ 2>/dev/null || true
        git commit -m "[CHECKPOINT] ${checkpoint_id}: ${message}" 2>/dev/null || true
    fi

    # Log decision if decision logging available
    if declare -f log_decision > /dev/null 2>&1; then
        log_decision \
            "Created checkpoint ${checkpoint_id}" \
            "workflow" \
            "State safety checkpoint per RWF R3" \
            "" \
            "" \
            "$checkpoint_id" > /dev/null 2>&1 || true
    fi

    # Clear error context
    if declare -f clear_error_context > /dev/null 2>&1; then
        clear_error_context
    fi

    echo -e "${GREEN}✓ Checkpoint created: ${checkpoint_id}${NC}"
    echo -e "  Message: ${YELLOW}${message}${NC}"
    echo -e "  Snapshot: ${CYAN}${snapshot_dir}${NC}"
    echo -e "  Format:   ${CYAN}v${CHECKPOINT_VERSION}${NC}"
}

# Function to list checkpoints
list_checkpoints() {
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${BLUE}         Workflow Checkpoints${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo ""
    
    if [ ! -f .workflow/checkpoints.log ]; then
        echo -e "${YELLOW}No checkpoints found${NC}"
        return
    fi
    
    # Get current phase using YAML utilities
    local current_phase current_checkpoint
    if declare -f yaml_get > /dev/null 2>&1; then
        current_phase=$(yaml_get .workflow/state.yaml "current_phase")
        current_checkpoint=$(yaml_get .workflow/state.yaml "current_checkpoint")
    else
        current_phase=$(grep 'current_phase:' .workflow/state.yaml | cut -d':' -f2 | xargs)
        current_checkpoint=$(grep 'current_checkpoint:' .workflow/state.yaml | cut -d':' -f2 | xargs)
    fi
    
    echo -e "${CYAN}Current Phase:${NC} ${GREEN}${current_phase}${NC}"
    echo -e "${CYAN}Current Checkpoint:${NC} ${GREEN}${current_checkpoint}${NC}"
    echo ""
    
    # Group checkpoints by phase
    for phase in $(seq 1 5); do
        local phase_name="phase_${phase}"
        local checkpoints=$(grep "CP_${phase}_" .workflow/checkpoints.log 2>/dev/null)
        
        if [ -n "$checkpoints" ]; then
            case $phase in
                1) echo -e "${BOLD}Phase 1 - Planning:${NC}" ;;
                2) echo -e "${BOLD}Phase 2 - Implementation:${NC}" ;;
                3) echo -e "${BOLD}Phase 3 - Validation:${NC}" ;;
                4) echo -e "${BOLD}Phase 4 - Delivery:${NC}" ;;
                5) echo -e "${BOLD}Phase 5 - Maintenance:${NC}" ;;
            esac
            
            echo "$checkpoints" | while IFS='|' read -r timestamp checkpoint description; do
                checkpoint=$(echo $checkpoint | xargs)
                description=$(echo $description | xargs)
                
                if [ "$checkpoint" = "$current_checkpoint" ]; then
                    echo -e "  ${GREEN}→ ${checkpoint}${NC} - ${description}"
                else
                    echo -e "    ${YELLOW}${checkpoint}${NC} - ${description}"
                fi
                echo -e "      ${CYAN}$(echo $timestamp | xargs | cut -d'T' -f1,2)${NC}"
            done
            echo ""
        fi
    done
    
    # Show statistics
    local total=$(wc -l < .workflow/checkpoints.log)
    local today=$(grep "$(date +%Y-%m-%d)" .workflow/checkpoints.log | wc -l)
    
    echo -e "${BLUE}─────────────────────────────────────────${NC}"
    echo -e "Total checkpoints: ${GREEN}${total}${NC}"
    echo -e "Today's checkpoints: ${YELLOW}${today}${NC}"
}

# Detect checkpoint format version
# Returns: "1.0" or "2.0"
detect_checkpoint_version() {
    local snapshot_dir="$1"

    if [[ -f "$snapshot_dir/manifest.yaml" ]]; then
        echo "2.0"
    else
        echo "1.0"
    fi
}

# Function to restore checkpoint (v1/v2 compatible with verification)
restore_checkpoint() {
    local checkpoint_id="$1"

    # Set error context
    if declare -f set_error_context > /dev/null 2>&1; then
        set_error_context "checkpoint restoration"
    fi

    # Validate checkpoint ID
    if [[ -z "$checkpoint_id" ]]; then
        echo -e "${RED}Error: Checkpoint ID required${NC}"
        echo "Usage: $0 restore CP_X_XXX"
        exit 1
    fi

    # Use precondition validation if available
    if declare -f require_checkpoint_exists > /dev/null 2>&1; then
        require_checkpoint_exists "$checkpoint_id" || exit 1
    elif declare -f validate_checkpoint_id > /dev/null 2>&1; then
        validate_checkpoint_id "$checkpoint_id" || exit 1
    fi

    # Check both old and new snapshot locations for backwards compatibility
    local snapshot_dir=""
    if [[ -d ".workflow/checkpoints/snapshots/${checkpoint_id}" ]]; then
        snapshot_dir=".workflow/checkpoints/snapshots/${checkpoint_id}"
    elif [[ -d ".workflow/snapshots/${checkpoint_id}" ]]; then
        snapshot_dir=".workflow/snapshots/${checkpoint_id}"
    else
        echo -e "${RED}Error: Checkpoint ${checkpoint_id} not found${NC}"
        echo -e "${YELLOW}Available checkpoints:${NC}"
        list_checkpoints
        exit 1
    fi

    # Validate snapshot has required files
    if [[ ! -f "$snapshot_dir/state.yaml" ]]; then
        echo -e "${RED}Error: Checkpoint ${checkpoint_id} is corrupted (missing state.yaml)${NC}"
        exit 1
    fi

    # Detect checkpoint version
    local cp_version
    cp_version=$(detect_checkpoint_version "$snapshot_dir")

    echo -e "${CYAN}Checkpoint Information:${NC}"
    echo -e "  ID:      ${YELLOW}${checkpoint_id}${NC}"
    echo -e "  Format:  ${CYAN}v${cp_version}${NC}"

    # Show metadata
    if [[ -f "$snapshot_dir/metadata.yaml" ]]; then
        grep "message:" "$snapshot_dir/metadata.yaml" 2>/dev/null | sed 's/message: /  Message: /' || true
        grep "created:" "$snapshot_dir/metadata.yaml" 2>/dev/null | sed 's/created: /  Created: /' || true
    fi
    echo ""

    # For v2 checkpoints, verify checksums before restore
    if [[ "$cp_version" == "2.0" ]]; then
        echo -e "  ${CYAN}Verifying checkpoint integrity...${NC}"

        if declare -f verify_snapshot_manifest > /dev/null 2>&1; then
            if ! verify_snapshot_manifest "$snapshot_dir" 2>/dev/null; then
                echo -e "${RED}Error: Checkpoint integrity verification failed${NC}"
                echo -e "${YELLOW}The checkpoint may be corrupted. Continue anyway? [y/N]:${NC} "
                read -r force_continue
                if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
                    echo "Restoration cancelled."
                    return 1
                fi
            else
                echo -e "  ${GREEN}✓ Integrity verified${NC}"
            fi
        else
            echo -e "  ${YELLOW}(Checksum verification not available)${NC}"
        fi
    fi

    # Confirm restoration
    echo ""
    read -p "Restore to this checkpoint? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Restoration cancelled."
        return 0
    fi

    echo -e "${BLUE}🔄 Restoring checkpoint ${checkpoint_id}...${NC}"

    # Log the operation
    if declare -f log_checkpoint > /dev/null 2>&1; then
        log_checkpoint "$checkpoint_id" "restore" "Restoring from v${cp_version} checkpoint"
    fi

    # Get timestamp
    local timestamp
    if declare -f get_iso_timestamp > /dev/null 2>&1; then
        timestamp=$(get_iso_timestamp)
    else
        timestamp="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    fi

    # Backup current state before restoration
    local backup_dir=".workflow/checkpoints/snapshots/backup_${timestamp//[:-]/}"
    mkdir -p "$backup_dir" || {
        echo -e "${RED}Error: Failed to create backup directory${NC}"
        exit 1
    }

    echo -e "  ${CYAN}Creating backup of current state...${NC}"

    # Use atomic backup if available
    if declare -f safe_backup > /dev/null 2>&1; then
        safe_backup .workflow/state.yaml "$backup_dir/state.yaml"
    else
        cp .workflow/state.yaml "$backup_dir/state.yaml" 2>/dev/null || true
    fi

    [[ -f .workflow/handoff.md ]] && cp .workflow/handoff.md "$backup_dir/handoff.md"
    [[ -f .workflow/agents/active.yaml ]] && cp .workflow/agents/active.yaml "$backup_dir/active_agent.yaml"
    [[ -f .workflow/skills/enabled.yaml ]] && cp .workflow/skills/enabled.yaml "$backup_dir/enabled_skills.yaml"

    # Create backup metadata
    cat > "$backup_dir/metadata.yaml" << EOF
backup_type: "pre_restore"
restored_to: "${checkpoint_id}"
created: "${timestamp}"
EOF

    echo -e "  ${CYAN}Restoring files...${NC}"

    # Begin atomic transaction if available
    if declare -f atomic_begin > /dev/null 2>&1; then
        atomic_begin
    fi

    local restore_failed=0

    # Restore core state file
    if declare -f atomic_write > /dev/null 2>&1; then
        if ! atomic_write .workflow/state.yaml "$(cat "$snapshot_dir/state.yaml")"; then
            restore_failed=1
        fi
    else
        if ! cp "$snapshot_dir/state.yaml" .workflow/state.yaml; then
            restore_failed=1
        fi
    fi

    if [[ $restore_failed -eq 1 ]]; then
        echo -e "${RED}Error: Failed to restore state.yaml${NC}"
        # Rollback if available
        if declare -f atomic_rollback > /dev/null 2>&1; then
            atomic_rollback
        fi
        exit 1
    fi

    # Restore handoff
    [[ -f "$snapshot_dir/handoff.md" ]] && cp "$snapshot_dir/handoff.md" .workflow/handoff.md

    # Restore agent and skills - check v2 locations first, then v1
    if [[ -f "$snapshot_dir/active_state/agent.yaml" ]]; then
        mkdir -p .workflow/agents
        cp "$snapshot_dir/active_state/agent.yaml" .workflow/agents/active.yaml
    elif [[ -f "$snapshot_dir/active_agent.yaml" ]]; then
        mkdir -p .workflow/agents
        cp "$snapshot_dir/active_agent.yaml" .workflow/agents/active.yaml
    fi

    if [[ -f "$snapshot_dir/active_state/skills.yaml" ]]; then
        mkdir -p .workflow/skills
        cp "$snapshot_dir/active_state/skills.yaml" .workflow/skills/enabled.yaml
    elif [[ -f "$snapshot_dir/enabled_skills.yaml" ]]; then
        mkdir -p .workflow/skills
        cp "$snapshot_dir/enabled_skills.yaml" .workflow/skills/enabled.yaml
    fi

    # Commit atomic transaction if available
    if declare -f atomic_commit > /dev/null 2>&1; then
        atomic_commit
    fi

    # Log restoration in checkpoint log
    if declare -f atomic_append > /dev/null 2>&1; then
        atomic_append .workflow/checkpoints.log "${timestamp} | RESTORED | Restored to checkpoint ${checkpoint_id}"
    else
        echo "${timestamp} | RESTORED | Restored to checkpoint ${checkpoint_id}" >> .workflow/checkpoints.log
    fi

    # Update session recovery flag
    if declare -f yaml_set > /dev/null 2>&1; then
        yaml_set .workflow/state.yaml "session.context_recovered" "true" 2>/dev/null || true
        yaml_set .workflow/state.yaml "session.recovery_source" "$checkpoint_id" 2>/dev/null || true
    fi

    # Verify recovery completeness if available
    if declare -f calculate_completeness_score > /dev/null 2>&1; then
        local score
        score=$(calculate_completeness_score 2>/dev/null || echo "0")
        echo -e "  ${CYAN}Recovery completeness: ${score}%${NC}"
    fi

    # Clear error context
    if declare -f clear_error_context > /dev/null 2>&1; then
        clear_error_context
    fi

    echo -e "${GREEN}✓ Restored to checkpoint ${checkpoint_id}${NC}"
    echo -e "  Backup saved: ${CYAN}${backup_dir}${NC}"

    # Show restored state
    echo ""
    echo -e "${CYAN}Restored State:${NC}"
    grep -E "current_phase|current_checkpoint" .workflow/state.yaml 2>/dev/null | while IFS=':' read -r key value; do
        echo -e "  ${key}: ${GREEN}$(echo $value | xargs)${NC}"
    done
}

# Function to show checkpoint status
show_checkpoint_status() {
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${BLUE}       Checkpoint Status${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo ""
    
    # Current checkpoint
    local current_checkpoint=$(grep 'current_checkpoint:' .workflow/state.yaml | cut -d':' -f2 | xargs)
    local current_phase=$(grep 'current_phase:' .workflow/state.yaml | cut -d':' -f2 | xargs)
    
    echo -e "${CYAN}Current Position:${NC}"
    echo -e "  Phase:      ${GREEN}${current_phase}${NC}"
    echo -e "  Checkpoint: ${GREEN}${current_checkpoint}${NC}"
    echo ""
    
    # Last checkpoint details
    if [ -f .workflow/checkpoints.log ]; then
        local last_checkpoint=$(tail -1 .workflow/checkpoints.log)
        IFS='|' read -r timestamp checkpoint description <<< "$last_checkpoint"
        
        echo -e "${CYAN}Last Checkpoint:${NC}"
        echo -e "  ID:        ${YELLOW}$(echo $checkpoint | xargs)${NC}"
        echo -e "  Message:   $(echo $description | xargs)"
        echo -e "  Time:      $(echo $timestamp | xargs)"
        echo ""
    fi
    
    # Phase progress
    echo -e "${CYAN}Phase Progress:${NC}"
    for phase in $(seq 1 5); do
        local count=$(grep -c "CP_${phase}_" .workflow/checkpoints.log 2>/dev/null || echo 0)
        local phase_name=""
        case $phase in
            1) phase_name="Planning    " ;;
            2) phase_name="Implementation" ;;
            3) phase_name="Validation  " ;;
            4) phase_name="Delivery    " ;;
            5) phase_name="Maintenance " ;;
        esac
        
        # Create progress bar
        local progress=""
        for i in $(seq 1 10); do
            if [ $i -le $count ]; then
                progress="${progress}█"
            else
                progress="${progress}░"
            fi
        done
        
        if [[ "$current_phase" == "phase_${phase}"* ]]; then
            echo -e "  ${GREEN}→${NC} Phase ${phase} ${phase_name}: [${progress}] ${count} checkpoints"
        else
            echo -e "    Phase ${phase} ${phase_name}: [${progress}] ${count} checkpoints"
        fi
    done
    
    # Snapshot information
    echo ""
    echo -e "${CYAN}Snapshots:${NC}"
    if [ -d .workflow/snapshots ]; then
        local snapshot_count=$(find .workflow/snapshots -maxdepth 1 -type d | wc -l)
        local snapshot_size=$(du -sh .workflow/snapshots 2>/dev/null | cut -f1)
        echo -e "  Total snapshots: ${YELLOW}$((snapshot_count - 1))${NC}"
        echo -e "  Storage used:    ${YELLOW}${snapshot_size}${NC}"
    else
        echo -e "  ${YELLOW}No snapshots${NC}"
    fi
}

# Function to verify checkpoint integrity
verify_checkpoint() {
    local checkpoint_id="$1"

    if [[ -z "$checkpoint_id" ]]; then
        echo -e "${RED}Error: Checkpoint ID required${NC}"
        echo "Usage: $0 verify CP_X_XXX"
        exit 1
    fi

    # Find snapshot directory
    local snapshot_dir=""
    if [[ -d ".workflow/checkpoints/snapshots/${checkpoint_id}" ]]; then
        snapshot_dir=".workflow/checkpoints/snapshots/${checkpoint_id}"
    elif [[ -d ".workflow/snapshots/${checkpoint_id}" ]]; then
        snapshot_dir=".workflow/snapshots/${checkpoint_id}"
    else
        echo -e "${RED}Error: Checkpoint ${checkpoint_id} not found${NC}"
        exit 1
    fi

    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${BLUE}   Checkpoint Verification: ${checkpoint_id}${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo ""

    # Detect version
    local cp_version
    cp_version=$(detect_checkpoint_version "$snapshot_dir")
    echo -e "Format Version: ${CYAN}v${cp_version}${NC}"
    echo ""

    local errors=0
    local warnings=0

    # Check required files
    echo -e "${CYAN}Required Files:${NC}"
    if [[ -f "$snapshot_dir/state.yaml" ]]; then
        echo -e "  ${GREEN}✓${NC} state.yaml"
    else
        echo -e "  ${RED}✗${NC} state.yaml (MISSING)"
        ((errors++))
    fi

    if [[ -f "$snapshot_dir/metadata.yaml" ]]; then
        echo -e "  ${GREEN}✓${NC} metadata.yaml"
    else
        echo -e "  ${YELLOW}○${NC} metadata.yaml (optional)"
        ((warnings++))
    fi

    if [[ -f "$snapshot_dir/handoff.md" ]]; then
        echo -e "  ${GREEN}✓${NC} handoff.md"
    else
        echo -e "  ${YELLOW}○${NC} handoff.md (optional)"
    fi

    echo ""

    # For v2 checkpoints, verify manifest and checksums
    if [[ "$cp_version" == "2.0" ]]; then
        echo -e "${CYAN}V2 Enhanced Files:${NC}"

        if [[ -f "$snapshot_dir/manifest.yaml" ]]; then
            echo -e "  ${GREEN}✓${NC} manifest.yaml"
        else
            echo -e "  ${RED}✗${NC} manifest.yaml (MISSING for v2)"
            ((errors++))
        fi

        if [[ -d "$snapshot_dir/active_state" ]]; then
            echo -e "  ${GREEN}✓${NC} active_state/"
            [[ -f "$snapshot_dir/active_state/agent.yaml" ]] && echo -e "      ${GREEN}✓${NC} agent.yaml"
            [[ -f "$snapshot_dir/active_state/skills.yaml" ]] && echo -e "      ${GREEN}✓${NC} skills.yaml"
            [[ -f "$snapshot_dir/active_state/session.yaml" ]] && echo -e "      ${GREEN}✓${NC} session.yaml"
        else
            echo -e "  ${YELLOW}○${NC} active_state/ (optional)"
        fi

        if [[ -d "$snapshot_dir/context" ]]; then
            echo -e "  ${GREEN}✓${NC} context/"
        else
            echo -e "  ${YELLOW}○${NC} context/ (optional)"
        fi

        echo ""

        # Verify checksums
        echo -e "${CYAN}Checksum Verification:${NC}"
        if declare -f verify_snapshot_manifest > /dev/null 2>&1; then
            if verify_snapshot_manifest "$snapshot_dir" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} All checksums valid"
            else
                echo -e "  ${RED}✗${NC} Checksum verification failed"
                ((errors++))
            fi
        else
            echo -e "  ${YELLOW}○${NC} Checksum verification not available"
        fi
    fi

    echo ""

    # Summary
    echo -e "${BLUE}─────────────────────────────────────────${NC}"
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ Checkpoint is valid${NC}"
        if [[ $warnings -gt 0 ]]; then
            echo -e "  ${YELLOW}(${warnings} optional files missing)${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗ Checkpoint has ${errors} error(s)${NC}"
        return 1
    fi
}

# Function to show completeness report
show_completeness_report() {
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${BLUE}       Recovery Completeness Report${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo ""

    if declare -f generate_completeness_report > /dev/null 2>&1; then
        generate_completeness_report
    else
        echo -e "${YELLOW}Completeness utilities not available${NC}"
        echo ""
        echo "Manual check:"

        # Basic completeness check
        local score=0
        local max=100

        echo ""
        echo -e "${CYAN}Required Files:${NC}"
        if [[ -f .workflow/state.yaml ]]; then
            echo -e "  ${GREEN}✓${NC} state.yaml"
            ((score += 35))
        else
            echo -e "  ${RED}✗${NC} state.yaml"
        fi

        if [[ -f .workflow/checkpoints.log ]]; then
            echo -e "  ${GREEN}✓${NC} checkpoints.log"
            ((score += 35))
        else
            echo -e "  ${RED}✗${NC} checkpoints.log"
        fi

        echo ""
        echo -e "${CYAN}Optional Files:${NC}"
        if [[ -f .workflow/handoff.md ]]; then
            echo -e "  ${GREEN}✓${NC} handoff.md"
            ((score += 10))
        else
            echo -e "  ${YELLOW}○${NC} handoff.md"
        fi

        if [[ -f .workflow/config.yaml ]]; then
            echo -e "  ${GREEN}✓${NC} config.yaml"
            ((score += 10))
        else
            echo -e "  ${YELLOW}○${NC} config.yaml"
        fi

        if [[ -f .workflow/agents/registry.yaml ]]; then
            echo -e "  ${GREEN}✓${NC} agents/registry.yaml"
            ((score += 5))
        else
            echo -e "  ${YELLOW}○${NC} agents/registry.yaml"
        fi

        if [[ -f .workflow/skills/catalog.yaml ]]; then
            echo -e "  ${GREEN}✓${NC} skills/catalog.yaml"
            ((score += 5))
        else
            echo -e "  ${YELLOW}○${NC} skills/catalog.yaml"
        fi

        echo ""
        echo -e "${BLUE}─────────────────────────────────────────${NC}"

        local status_color status_text
        if (( score >= 80 )); then
            status_color="$GREEN"
            status_text="GOOD"
        elif (( score >= 50 )); then
            status_color="$YELLOW"
            status_text="PARTIAL"
        else
            status_color="$RED"
            status_text="INCOMPLETE"
        fi

        echo -e "Completeness Score: ${status_color}${score}%${NC} [${status_text}]"
    fi
}

# Function to toggle auto checkpointing
toggle_auto_checkpoint() {
    if [ ! -f .workflow/config.yaml ]; then
        echo -e "${RED}Error: Configuration file not found${NC}"
        exit 1
    fi
    
    local current=$(grep 'auto_checkpoint:' .workflow/config.yaml | cut -d':' -f2 | xargs)
    
    if [ "$current" = "true" ]; then
        sed -i 's/auto_checkpoint: true/auto_checkpoint: false/' .workflow/config.yaml
        echo -e "${YELLOW}⏸  Auto-checkpointing disabled${NC}"
    else
        sed -i 's/auto_checkpoint: false/auto_checkpoint: true/' .workflow/config.yaml
        echo -e "${GREEN}▶  Auto-checkpointing enabled${NC}"
        
        # Setup cron job for hourly checkpoints
        setup_auto_checkpoint
    fi
}

# Function to setup auto checkpoint
setup_auto_checkpoint() {
    echo -e "${CYAN}Setting up auto-checkpoint...${NC}"
    
    # Create auto-checkpoint script
    cat > .workflow/scripts/auto_checkpoint.sh << 'EOF'
#!/bin/bash
# Auto checkpoint script

cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")"

# Check if auto-checkpoint is enabled
if grep -q "auto_checkpoint: true" .workflow/config.yaml; then
    ./scripts/checkpoint.sh create "Auto checkpoint"
fi
EOF
    
    chmod +x .workflow/scripts/auto_checkpoint.sh
    
    echo -e "${GREEN}✓ Auto-checkpoint configured${NC}"
    echo -e "  Add to crontab for hourly execution:"
    echo -e "  ${CYAN}0 * * * * cd $(pwd) && ./.workflow/scripts/auto_checkpoint.sh${NC}"
}

# Main execution
case $COMMAND in
    create)
        create_checkpoint "$CHECKPOINT_MSG"
        ;;
    list)
        list_checkpoints
        ;;
    restore)
        restore_checkpoint "$CHECKPOINT_ID"
        ;;
    verify)
        verify_checkpoint "$CHECKPOINT_ID"
        ;;
    status)
        show_checkpoint_status
        ;;
    completeness)
        show_completeness_report
        ;;
    auto)
        toggle_auto_checkpoint
        ;;
    -h|--help|help)
        show_usage
        ;;
    *)
        # Default to create with the command as message
        create_checkpoint "$COMMAND $CHECKPOINT_MSG"
        ;;
esac
