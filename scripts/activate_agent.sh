#!/bin/bash

# Agent Activation and Management Script - RWF Enhanced
# Activate, deactivate, and manage workflow agents
# RWF Compliance: R1 (Truthfulness), R3 (State Safety), R4 (Error-Free)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_LIB_DIR}/resolve_project.sh"

AGENT_NAME="${1:-}"
COMMAND="${2:-activate}"

# Source utility libraries in dependency order
source_lib() {
    local lib="$1"
    if [[ -f "${SCRIPT_LIB_DIR}/${lib}" ]]; then
        YAML_UTILS_QUIET=true source "${SCRIPT_LIB_DIR}/${lib}"
        return 0
    fi
    return 1
}

# Core utilities
source_lib "yaml_utils.sh" || true
source_lib "validation_utils.sh" || true

# RWF utilities
source_lib "timestamp_utils.sh" || true
source_lib "logging_utils.sh" || true
source_lib "error_utils.sh" || true
source_lib "precondition_utils.sh" || true
source_lib "atomic_utils.sh" || true
source_lib "decision_utils.sh" || true
source_lib "schema_utils.sh" || true

# Session manager for real-time dashboard integration
source_lib "session_manager.sh" || true

# Workflow routing for transition validation
source_lib "workflow_routing.sh" || true

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Function to show usage
show_usage() {
    echo "Usage: $0 <agent_name> [command]"
    echo ""
    echo "Agents:"
    echo "  researcher    - Literature review, hypothesis formation"
    echo "  architect     - System design, architecture planning"
    echo "  implementer   - Code development, model building"
    echo "  experimenter  - Experiments, benchmarks, testing"
    echo "  optimizer     - Performance optimization, compression"
    echo "  deployer      - Deployment, DevOps, monitoring"
    echo "  documenter    - Documentation, papers, guides"
    echo ""
    echo "Commands:"
    echo "  activate      - Activate the agent (default)"
    echo "  deactivate    - Deactivate the agent"
    echo "  status        - Show agent status"
    echo "  handoff       - Prepare handoff to another agent"
    exit 1
}

# Check arguments
if [[ -z "$AGENT_NAME" ]]; then
    show_usage
fi

# Set error context for better diagnostics (RWF R4)
if declare -f set_error_context > /dev/null 2>&1; then
    set_error_context "agent activation"
fi

# Ensure workflow is initialized using preconditions (RWF R1)
if declare -f require_workflow_initialized > /dev/null 2>&1; then
    if ! require_workflow_initialized; then
        exit 1
    fi
elif ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -d .workflow ]]; then
        echo -e "${RED}Error: Workflow not initialized. Run ./scripts/init_workflow.sh first${NC}"
        exit 1
    fi
fi

# Validate agent name using RWF preconditions (RWF R1 - Truthfulness)
if declare -f require_agent_valid > /dev/null 2>&1; then
    if ! require_agent_valid "$AGENT_NAME"; then
        echo ""
        echo -e "${YELLOW}Available agents:${NC}"
        echo "  researcher, architect, implementer, experimenter, optimizer, deployer, documenter"
        exit 1
    fi
elif declare -f validate_agent > /dev/null 2>&1; then
    if ! validate_agent "$AGENT_NAME" .workflow/agents/registry.yaml; then
        echo ""
        echo -e "${YELLOW}Available agents:${NC}"
        if [[ -f ".workflow/agents/registry.yaml" ]]; then
            grep "^[a-z_]*:" .workflow/agents/registry.yaml | sed 's/:$//' | while read -r agent; do
                desc=$(sed -n "/^${agent}:/,/^[^ ]/ {/description:/ s/.*description: //p}" .workflow/agents/registry.yaml | head -1)
                printf "  %-15s %s\n" "$agent" "${desc:-}"
            done
        else
            echo "  researcher, architect, implementer, experimenter, optimizer, deployer, documenter"
        fi
        exit 1
    fi
fi

# Create agent directories if they don't exist
mkdir -p .workflow/agents/{configs,memory}

# Create default registry if missing
if [[ ! -f ".workflow/agents/registry.yaml" ]]; then
    cat > .workflow/agents/registry.yaml << 'REGISTRY_EOF'
# Agent Registry - Default Configuration
researcher:
  description: "Literature review, hypothesis formation"
  capabilities: ["research", "analysis", "writing"]
  primary_skills: ["literature_review", "experimental_design", "statistical_validation"]

architect:
  description: "System design, architecture planning"
  capabilities: ["design", "documentation", "planning"]
  primary_skills: ["system_design", "api_design", "data_modeling"]

implementer:
  description: "Code development, model building"
  capabilities: ["coding", "testing", "debugging"]
  primary_skills: ["code_generation", "debugging", "testing"]

experimenter:
  description: "Experiments, benchmarks, testing"
  capabilities: ["testing", "analysis", "automation"]
  primary_skills: ["experiment_design", "benchmarking", "data_analysis"]

optimizer:
  description: "Performance optimization, compression"
  capabilities: ["optimization", "profiling", "tuning"]
  primary_skills: ["performance_profiling", "memory_optimization", "algorithm_optimization"]

deployer:
  description: "Deployment, DevOps, monitoring"
  capabilities: ["deployment", "automation", "monitoring"]
  primary_skills: ["ci_cd", "containerization", "monitoring"]

documenter:
  description: "Documentation, papers, guides"
  capabilities: ["writing", "documentation", "communication"]
  primary_skills: ["technical_writing", "api_documentation", "user_guides"]
REGISTRY_EOF
fi

# Function to activate an agent (RWF R3 - State Safety with atomic operations)
activate_agent() {
    local agent=$1

    # Validate transition if another agent is currently active
    if [[ -f .workflow/agents/active.yaml ]]; then
        local current_agent
        current_agent=$(grep 'current_agent:' .workflow/agents/active.yaml 2>/dev/null | cut -d'"' -f2 || echo "")
        if [[ -n "$current_agent" && "$current_agent" != "$agent" ]]; then
            if declare -f validate_agent_transition > /dev/null 2>&1; then
                if ! validate_agent_transition "$current_agent" "$agent"; then
                    echo -e "${YELLOW}⚠  Transition ${current_agent} → ${agent} is not in registry rules.${NC}"
                    echo -e "  Expected transitions from ${current_agent}: see .workflow/agents/registry.yaml"
                    echo -e "  Proceeding anyway (override).${NC}"
                fi
            fi
        fi
    fi

    echo -e "${BLUE}🤖 Activating ${agent} agent...${NC}"

    # Get timestamp using utility or fallback
    local timestamp
    if declare -f get_iso_timestamp > /dev/null 2>&1; then
        timestamp=$(get_iso_timestamp)
    else
        timestamp=$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    fi

    # Get current phase and checkpoint
    local current_phase current_checkpoint
    if declare -f yaml_get > /dev/null 2>&1; then
        current_phase=$(yaml_get .workflow/state.yaml "current_phase" 2>/dev/null || echo "unknown")
        current_checkpoint=$(yaml_get .workflow/state.yaml "current_checkpoint" 2>/dev/null || echo "unknown")
    else
        current_phase=$(grep 'current_phase:' .workflow/state.yaml 2>/dev/null | cut -d':' -f2 | xargs || echo "unknown")
        current_checkpoint=$(grep 'current_checkpoint:' .workflow/state.yaml 2>/dev/null | cut -d':' -f2 | xargs || echo "unknown")
    fi

    # Build agent config content
    local agent_config="# Active Agent Configuration
# Generated: ${timestamp}
# RWF R3: State tracked for reproducibility

current_agent: \"${agent}\"
activated_at: \"${timestamp}\"
agent_state:
  task: \"initialized\"
  progress: 0
  last_action: \"Agent activated\"
  next_action: \"Review requirements and context\"

context:
  phase: \"${current_phase}\"
  checkpoint: \"${current_checkpoint}\"

workspace:
  directory: \"workspace/${agent}\"

capabilities:"

    # Add capabilities based on agent type
    case $agent in
        researcher)
            agent_config+="
  - literature_review
  - hypothesis_formation
  - experimental_design
  - result_analysis"
            ;;
        architect)
            agent_config+="
  - system_design
  - api_design
  - database_schema
  - architecture_patterns"
            ;;
        implementer)
            agent_config+="
  - code_development
  - prototype_building
  - model_training
  - integration"
            ;;
        experimenter)
            agent_config+="
  - experiment_execution
  - benchmarking
  - ablation_studies
  - performance_testing"
            ;;
        optimizer)
            agent_config+="
  - model_compression
  - quantization
  - pruning
  - performance_tuning"
            ;;
        deployer)
            agent_config+="
  - containerization
  - ci_cd_setup
  - cloud_deployment
  - monitoring"
            ;;
        documenter)
            agent_config+="
  - technical_writing
  - paper_writing
  - api_documentation
  - tutorial_creation"
            ;;
    esac

    # Write atomically (RWF R3)
    if declare -f atomic_write > /dev/null 2>&1; then
        atomic_write .workflow/agents/active.yaml "$agent_config"
    else
        echo "$agent_config" > .workflow/agents/active.yaml
    fi

    # Create agent workspace
    mkdir -p "workspace/${agent}"

    # Load agent-specific skills
    load_agent_skills "$agent"

    # Update state file with active agent info
    if declare -f yaml_set > /dev/null 2>&1; then
        yaml_set .workflow/state.yaml "active_agent.name" "$agent" 2>/dev/null || true
        yaml_set .workflow/state.yaml "active_agent.status" "active" 2>/dev/null || true
        yaml_set .workflow/state.yaml "active_agent.activated_at" "$timestamp" 2>/dev/null || true
    fi

    # Log activation using RWF logging
    if declare -f log_agent > /dev/null 2>&1; then
        log_agent "$agent" "activated" "Agent activated in phase ${current_phase}"
    fi

    # Also log to checkpoints.log for backward compatibility
    if declare -f atomic_append > /dev/null 2>&1; then
        atomic_append .workflow/checkpoints.log "${timestamp} | AGENT_ACTIVATED | ${agent}"
    else
        echo "${timestamp} | AGENT_ACTIVATED | ${agent}" >> .workflow/checkpoints.log
    fi

    # Log decision (RWF R1 - Truthfulness, track all decisions)
    if declare -f log_decision > /dev/null 2>&1; then
        log_decision \
            "Activated ${agent} agent" \
            "workflow" \
            "Agent needed for current phase (${current_phase})" \
            "" \
            "$agent" \
            "$current_checkpoint" > /dev/null 2>&1 || true
    fi

    # Create dashboard session for real-time monitoring
    local session_id=""
    if declare -f create_agent_session > /dev/null 2>&1; then
        session_id=$(create_agent_session "$agent" "Starting work in phase ${current_phase}")
        # Store session ID in active.yaml for reference
        echo "" >> .workflow/agents/active.yaml
        echo "dashboard_session:" >> .workflow/agents/active.yaml
        echo "  id: \"${session_id}\"" >> .workflow/agents/active.yaml
        echo "  started_at: \"${timestamp}\"" >> .workflow/agents/active.yaml
        echo -e "${BLUE}📊 Dashboard session: ${session_id}${NC}"
    fi

    # G5: Append agent responsibilities to handoff.md
    local handoff_file="${WORKFLOW_DIR}/handoff.md"
    if [[ -f "$handoff_file" ]]; then
        {
            echo ""
            echo "## Agent Activated: ${agent}"
            echo "- **When**: ${timestamp}"
            echo "- **Phase**: ${current_phase}"
            echo "- **Responsibilities**:"
            case $agent in
                researcher)
                    echo "  - Review existing literature and prior art"
                    echo "  - Form and validate hypotheses"
                    echo "  - Design experiments with statistical rigor"
                    ;;
                architect)
                    echo "  - Design system architecture with component diagrams"
                    echo "  - Define all APIs, data models, and interfaces"
                    echo "  - Document technical constraints and failure modes"
                    echo "  - Produce architecture document before passing to implementer"
                    ;;
                implementer)
                    echo "  - Implement all features per design specification"
                    echo "  - Write zero placeholder/stub code"
                    echo "  - Create tests for new functionality"
                    echo "  - Update dependencies and configuration"
                    ;;
                experimenter)
                    echo "  - Execute full test suite and report results"
                    echo "  - Perform integration and system testing"
                    echo "  - Report verification coverage and gaps"
                    ;;
                optimizer)
                    echo "  - Profile performance bottlenecks"
                    echo "  - Optimize critical paths"
                    echo "  - Measure and report improvements"
                    ;;
                deployer)
                    echo "  - Containerize application"
                    echo "  - Configure health checks and monitoring"
                    echo "  - Update deployment documentation"
                    ;;
                documenter)
                    echo "  - Write/update README and API docs"
                    echo "  - Document architecture decisions"
                    echo "  - Create user guides"
                    ;;
            esac
        } >> "$handoff_file"
    fi

    echo -e "${GREEN}✓ ${agent} agent activated${NC}"
    echo ""
    echo -e "Agent workspace: ${YELLOW}workspace/${agent}${NC}"
    echo -e "View status: ${BLUE}./scripts/activate_agent.sh ${agent} status${NC}"
    if [[ -n "$session_id" ]]; then
        echo -e "Dashboard:    ${BLUE}http://localhost:8080/#agents${NC}"
    fi
}

# Function to load agent-specific skills
load_agent_skills() {
    local agent=$1
    
    echo -e "${BLUE}Loading skills for ${agent}...${NC}"

    # 1. Load Persona (The "Senior" Upgrade)
    PERSONA_FILE="docs/personas/${agent}.md"
    if [[ -f "$PERSONA_FILE" ]]; then
        echo -e "${YELLOW}📜 Loading Persona: ${agent} (Senior Mode)${NC}"
        # Inject persona into active.yaml (append)
        echo "" >> .workflow/agents/active.yaml
        echo "persona: |" >> .workflow/agents/active.yaml
        sed 's/^/  /' "$PERSONA_FILE" >> .workflow/agents/active.yaml
    fi
    
    # Create or reset enabled skills file with proper YAML structure
    mkdir -p .workflow/skills
    echo "enabled_skills:" > .workflow/skills/enabled.yaml
    
    # Define skills for each agent
    case $agent in
        researcher)
            skills=("literature_review" "experimental_design" "statistical_validation" "review_cl" "risk_analysis")
            ;;
        architect)
            skills=("system_design" "api_design" "architecture_patterns" "review_cl")
            ;;
        implementer)
            skills=("code_generation" "debugging" "testing" "submit_cl")
            ;;
        experimenter)
            skills=("experiment_execution" "benchmarking" "data_analysis" "submit_cl")
            ;;
        optimizer)
            skills=("quantization" "pruning" "profiling" "submit_cl")
            ;;
        deployer)
            skills=("containerization" "ci_cd" "monitoring" "submit_cl")
            ;;
        documenter)
            skills=("technical_writing" "visualization" "presentation" "submit_cl")
            ;;
        *)
            skills=()
            ;;
    esac
    
    # Add skills to enabled list
    for skill in "${skills[@]}"; do
        echo -e "  + Enabling skill: ${GREEN}${skill}${NC}"
        
        # Check for Expert Guide
        SKILL_DEF=".workflow/skills/definitions/${skill}.md"
        if [[ -f "$SKILL_DEF" ]]; then
            echo -e "    ${YELLOW}📘 Expert Guide Loaded${NC}"
            # You could append this to context, but for now we just notify
        fi

        # Add to YAML file under enabled_skills key
        if ! grep -q "^  - ${skill}$" .workflow/skills/enabled.yaml 2>/dev/null; then
            echo "  - ${skill}" >> .workflow/skills/enabled.yaml
        fi
    done
}

# Function to deactivate an agent
deactivate_agent() {
    local agent=$1

    if [ ! -f .workflow/agents/active.yaml ]; then
        echo -e "${YELLOW}No active agent to deactivate${NC}"
        return
    fi

    echo -e "${BLUE}🔄 Deactivating ${agent} agent...${NC}"

    # End dashboard session if exists
    local session_id=""
    session_id=$(grep -A1 "dashboard_session:" .workflow/agents/active.yaml 2>/dev/null | grep "id:" | sed 's/.*id: "\([^"]*\)".*/\1/' || true)
    if [[ -n "$session_id" ]] && declare -f end_agent_session > /dev/null 2>&1; then
        end_agent_session "$session_id" "success"
        echo -e "${BLUE}📊 Dashboard session ended: ${session_id}${NC}"
    fi

    # Save agent state to memory
    cp .workflow/agents/active.yaml .workflow/agents/memory/${agent}_$(date +%s).yaml

    # Clear active agent
    rm .workflow/agents/active.yaml

    # Log deactivation
    echo "$(date -Iseconds) | AGENT_DEACTIVATED | ${agent}" >> .workflow/checkpoints.log

    echo -e "${GREEN}✓ ${agent} agent deactivated${NC}"
}

# Function to show agent status
show_agent_status() {
    local agent=$1
    
    if [ ! -f .workflow/agents/active.yaml ]; then
        echo -e "${YELLOW}No active agent${NC}"
        return
    fi
    
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Agent Status: ${agent}${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    
    # Parse and display active agent info
    current=$(grep 'current_agent:' .workflow/agents/active.yaml | cut -d':' -f2 | xargs)
    task=$(grep 'task:' .workflow/agents/active.yaml | cut -d':' -f2 | xargs)
    progress=$(grep 'progress:' .workflow/agents/active.yaml | cut -d':' -f2 | xargs)
    
    echo -e "Active Agent: ${GREEN}${current}${NC}"
    echo -e "Current Task: ${YELLOW}${task}${NC}"
    echo -e "Progress:     ${BLUE}${progress}%${NC}"
    echo ""
    
    # Show recent agent activity
    echo "Recent Activity:"
    grep "AGENT_" .workflow/checkpoints.log | tail -3 | while IFS='|' read -r timestamp event description; do
        echo -e "  ${YELLOW}$(echo $event | xargs)${NC} - $(echo $timestamp | xargs)"
    done
}

# Function to prepare handoff
prepare_handoff() {
    local from_agent=$1
    local to_agent=${2:-""}
    
    echo -e "${BLUE}📤 Preparing handoff from ${from_agent}...${NC}"
    
    if [ -z "$to_agent" ]; then
        if [ -t 0 ]; then
            # Interactive mode - prompt for input
            echo -e "${YELLOW}Specify target agent:${NC}"
            echo "  researcher, architect, implementer, experimenter,"
            echo "  optimizer, deployer, documenter"
            read -p "Target agent: " to_agent
        else
            # Non-interactive mode - use placeholder
            to_agent="unspecified"
            echo -e "${YELLOW}Note: No target agent specified, use handoff record to set.${NC}"
        fi
    fi
    
    # Create handoff record
    cat > .workflow/agents/handoff_$(date +%s).yaml << EOF
# Agent Handoff Record
# From: ${from_agent} -> To: ${to_agent}
# Generated: $(date -Iseconds)

handoff:
  from_agent: "${from_agent}"
  to_agent: "${to_agent}"
  timestamp: "$(date -Iseconds)"
  
  deliverables:
    $(ls workspace/${from_agent}/ 2>/dev/null | sed 's/^/    - /' || echo "    - none")
  
  context_transfer:
    phase: "$(grep 'current_phase:' .workflow/state.yaml | cut -d':' -f2 | xargs)"
    checkpoint: "$(grep 'current_checkpoint:' .workflow/state.yaml | cut -d':' -f2 | xargs)"
  
  notes: |
    Add handoff notes here
    - Key decisions made
    - Blockers encountered
    - Recommendations for next agent
EOF
    
    echo -e "${GREEN}✓ Handoff prepared${NC}"
    echo -e "Edit handoff notes: ${YELLOW}vim .workflow/agents/handoff_*.yaml${NC}"
    echo -e "Activate next agent: ${BLUE}./scripts/activate_agent.sh ${to_agent}${NC}"
}

# Main execution
case $COMMAND in
    activate)
        activate_agent $AGENT_NAME
        ;;
    deactivate)
        deactivate_agent $AGENT_NAME
        ;;
    status)
        show_agent_status $AGENT_NAME
        ;;
    handoff)
        prepare_handoff $AGENT_NAME "${3:-}"
        ;;
    *)
        echo -e "${RED}Unknown command: ${COMMAND}${NC}"
        show_usage
        ;;
esac
