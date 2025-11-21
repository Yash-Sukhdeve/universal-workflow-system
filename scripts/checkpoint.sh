#!/bin/bash

# Checkpoint Management Script
# Create, list, and restore workflow checkpoints

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND="${1:-create}"
CHECKPOINT_MSG="${2:-Manual checkpoint}"
CHECKPOINT_ID="${2:-}"

# Source utility libraries
if [[ -f "${SCRIPT_DIR}/lib/validation_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/validation_utils.sh"
fi

if [[ -f "${SCRIPT_DIR}/lib/yaml_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/yaml_utils.sh"
fi

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
    echo "  create [message]   - Create a new checkpoint"
    echo "  list              - List all checkpoints"
    echo "  restore [id]      - Restore to a checkpoint"
    echo "  status            - Show current checkpoint status"
    echo "  auto             - Enable/disable auto checkpointing"
    echo ""
    echo "Examples:"
    echo "  $0 create \"Completed model training\""
    echo "  $0 list"
    echo "  $0 restore CP_2_003"
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

# Function to create checkpoint
create_checkpoint() {
    local message="$1"
    local checkpoint_id=$(generate_checkpoint_id)
    
    echo -e "${BLUE}📍 Creating checkpoint...${NC}"

    # Update state file using YAML utilities
    local timestamp
    timestamp="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"

    if declare -f yaml_set > /dev/null 2>&1; then
        yaml_set .workflow/state.yaml "current_checkpoint" "$checkpoint_id" || {
            echo -e "${RED}Error: Failed to update state file${NC}"
            return 1
        }
        yaml_set .workflow/state.yaml "metadata.last_updated" "$timestamp"
    else
        # Fallback to sed
        sed -i.bak "s/current_checkpoint:.*/current_checkpoint: \"${checkpoint_id}\"/" .workflow/state.yaml
        sed -i.bak "s/last_updated:.*/last_updated: \"${timestamp}\"/" .workflow/state.yaml
        rm -f .workflow/state.yaml.bak
    fi
    
    # Add to checkpoint log
    echo "$(date -Iseconds) | ${checkpoint_id} | ${message}" >> .workflow/checkpoints.log
    
    # Create checkpoint snapshot
    local snapshot_dir=".workflow/checkpoints/snapshots/${checkpoint_id}"
    mkdir -p "$snapshot_dir" || {
        echo -e "${RED}Error: Failed to create snapshot directory${NC}"
        return 1
    }
    
    # Save current state
    cp .workflow/state.yaml "$snapshot_dir/state.yaml"
    cp .workflow/handoff.md "$snapshot_dir/handoff.md" 2>/dev/null || true
    
    # Save active agents and skills
    if [ -f .workflow/agents/active.yaml ]; then
        cp .workflow/agents/active.yaml "$snapshot_dir/active_agent.yaml"
    fi
    if [ -f .workflow/skills/enabled.yaml ]; then
        cp .workflow/skills/enabled.yaml "$snapshot_dir/enabled_skills.yaml"
    fi
    
    # Create checkpoint metadata
    cat > "$snapshot_dir/metadata.yaml" << EOF
checkpoint_id: "${checkpoint_id}"
created: "$(date -Iseconds)"
message: "${message}"
git_commit: "$(git rev-parse --short HEAD 2>/dev/null || echo 'uncommitted')"
git_branch: "$(git branch --show-current 2>/dev/null || echo 'unknown')"
files_changed: $(git status --porcelain | wc -l)
phase: "$(grep 'current_phase:' .workflow/state.yaml | cut -d':' -f2 | xargs)"
EOF
    
    # Git commit if enabled
    if grep -q "auto_commit_state: true" .workflow/config.yaml 2>/dev/null; then
        git add .workflow/
        git commit -m "[CHECKPOINT] ${checkpoint_id}: ${message}" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Checkpoint created: ${checkpoint_id}${NC}"
    echo -e "  Message: ${YELLOW}${message}${NC}"
    echo -e "  Snapshot: ${CYAN}${snapshot_dir}${NC}"
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

# Function to restore checkpoint
restore_checkpoint() {
    local checkpoint_id="$1"

    if [[ -z "$checkpoint_id" ]]; then
        echo -e "${RED}Error: Checkpoint ID required${NC}"
        echo "Usage: $0 restore CP_X_XXX"
        exit 1
    fi

    # Validate checkpoint ID format
    if declare -f validate_checkpoint_id > /dev/null 2>&1; then
        if ! validate_checkpoint_id "$checkpoint_id"; then
            exit 1
        fi
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

    # Show checkpoint info
    if [[ -f "$snapshot_dir/metadata.yaml" ]]; then
        echo -e "${CYAN}Checkpoint Information:${NC}"
        echo -e "  ID: ${YELLOW}${checkpoint_id}${NC}"
        grep "message:" "$snapshot_dir/metadata.yaml" | sed 's/message: /  Message: /' || true
        grep "created:" "$snapshot_dir/metadata.yaml" | sed 's/created: /  Created: /' || true
        echo ""
    fi

    # Confirm restoration
    read -p "Restore to this checkpoint? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Restoration cancelled."
        return 0
    fi

    echo -e "${BLUE}🔄 Restoring checkpoint ${checkpoint_id}...${NC}"

    # Backup current state
    local backup_dir=".workflow/checkpoints/snapshots/backup_$(date +%s)"
    mkdir -p "$backup_dir" || {
        echo -e "${RED}Error: Failed to create backup directory${NC}"
        exit 1
    }

    echo -e "  ${CYAN}Creating backup of current state...${NC}"
    cp .workflow/state.yaml "$backup_dir/state.yaml" 2>/dev/null || true
    [[ -f .workflow/handoff.md ]] && cp .workflow/handoff.md "$backup_dir/handoff.md"
    [[ -f .workflow/agents/active.yaml ]] && cp .workflow/agents/active.yaml "$backup_dir/active_agent.yaml"
    [[ -f .workflow/skills/enabled.yaml ]] && cp .workflow/skills/enabled.yaml "$backup_dir/enabled_skills.yaml"

    echo -e "  ${CYAN}Restoring files...${NC}"
    # Restore files
    cp "$snapshot_dir/state.yaml" .workflow/state.yaml || {
        echo -e "${RED}Error: Failed to restore state.yaml${NC}"
        exit 1
    }

    [[ -f "$snapshot_dir/handoff.md" ]] && cp "$snapshot_dir/handoff.md" .workflow/handoff.md
    [[ -f "$snapshot_dir/active_agent.yaml" ]] && cp "$snapshot_dir/active_agent.yaml" .workflow/agents/active.yaml
    [[ -f "$snapshot_dir/enabled_skills.yaml" ]] && cp "$snapshot_dir/enabled_skills.yaml" .workflow/skills/enabled.yaml

    # Log restoration
    local timestamp
    timestamp="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    echo "${timestamp} | RESTORED | Restored to checkpoint ${checkpoint_id}" >> .workflow/checkpoints.log
    
    echo -e "${GREEN}✓ Restored to checkpoint ${checkpoint_id}${NC}"
    
    # Show restored state
    echo ""
    echo -e "${CYAN}Restored State:${NC}"
    grep -E "current_phase|current_checkpoint" .workflow/state.yaml | while IFS=':' read -r key value; do
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
    status)
        show_checkpoint_status
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
