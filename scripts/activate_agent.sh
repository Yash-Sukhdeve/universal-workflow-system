#!/bin/bash

# Agent Activation and Management Script
# Activate, deactivate, and manage workflow agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_NAME="${1:-}"
COMMAND="${2:-activate}"

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

# Ensure workflow is initialized
if ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -d .workflow ]]; then
        echo -e "${RED}Error: Workflow not initialized. Run ./scripts/init_workflow.sh first${NC}"
        exit 1
    fi
fi

# Validate agent name against registry
if declare -f validate_agent > /dev/null 2>&1; then
    if ! validate_agent "$AGENT_NAME" .workflow/agents/registry.yaml; then
        echo ""
        echo -e "${YELLOW}Available agents:${NC}"
        if [[ -f ".workflow/agents/registry.yaml" ]]; then
            grep "^[a-z_]*:" .workflow/agents/registry.yaml | sed 's/:$//' | while read -r agent; do
                # Get description if available
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

# Function to activate an agent
activate_agent() {
    local agent=$1
    echo -e "${BLUE}🤖 Activating ${agent} agent...${NC}"
    
    # Create active agent file
    cat > .workflow/agents/active.yaml << EOF
# Active Agent Configuration
# Generated: $(date -Iseconds)

current_agent: "${agent}"
activated_at: "$(date -Iseconds)"
agent_state:
  task: "initialized"
  progress: 0
  last_action: "Agent activated"
  next_action: "Review requirements and context"
  
context:
  phase: "$(grep 'current_phase:' .workflow/state.yaml | cut -d':' -f2 | xargs)"
  checkpoint: "$(grep 'current_checkpoint:' .workflow/state.yaml | cut -d':' -f2 | xargs)"
  
workspace:
  directory: "workspace/${agent}"
  
capabilities:
  $(case $agent in
    researcher)
      echo "- literature_review"
      echo "  - hypothesis_formation"
      echo "  - experimental_design"
      echo "  - result_analysis"
      ;;
    architect)
      echo "- system_design"
      echo "  - api_design"
      echo "  - database_schema"
      echo "  - architecture_patterns"
      ;;
    implementer)
      echo "- code_development"
      echo "  - prototype_building"
      echo "  - model_training"
      echo "  - integration"
      ;;
    experimenter)
      echo "- experiment_execution"
      echo "  - benchmarking"
      echo "  - ablation_studies"
      echo "  - performance_testing"
      ;;
    optimizer)
      echo "- model_compression"
      echo "  - quantization"
      echo "  - pruning"
      echo "  - performance_tuning"
      ;;
    deployer)
      echo "- containerization"
      echo "  - ci_cd_setup"
      echo "  - cloud_deployment"
      echo "  - monitoring"
      ;;
    documenter)
      echo "- technical_writing"
      echo "  - paper_writing"
      echo "  - api_documentation"
      echo "  - tutorial_creation"
      ;;
  esac)
EOF
    
    # Create agent workspace
    mkdir -p workspace/${agent}
    
    # Load agent-specific skills
    load_agent_skills $agent
    
    # Log activation
    echo "$(date -Iseconds) | AGENT_ACTIVATED | ${agent}" >> .workflow/checkpoints.log
    
    echo -e "${GREEN}✓ ${agent} agent activated${NC}"
    echo ""
    echo -e "Agent workspace: ${YELLOW}workspace/${agent}${NC}"
    echo -e "View status: ${BLUE}./scripts/activate_agent.sh ${agent} status${NC}"
}

# Function to load agent-specific skills
load_agent_skills() {
    local agent=$1
    
    echo -e "${BLUE}Loading skills for ${agent}...${NC}"
    
    # Create enabled skills file if it doesn't exist
    if [ ! -f .workflow/skills/enabled.yaml ]; then
        echo "enabled_skills: []" > .workflow/skills/enabled.yaml
    fi
    
    # Define skills for each agent
    case $agent in
        researcher)
            skills=("literature_review" "experimental_design" "statistical_validation")
            ;;
        architect)
            skills=("system_design" "api_design" "architecture_patterns")
            ;;
        implementer)
            skills=("code_generation" "debugging" "testing")
            ;;
        experimenter)
            skills=("experiment_execution" "benchmarking" "data_analysis")
            ;;
        optimizer)
            skills=("quantization" "pruning" "profiling")
            ;;
        deployer)
            skills=("containerization" "ci_cd" "monitoring")
            ;;
        documenter)
            skills=("technical_writing" "visualization" "presentation")
            ;;
        *)
            skills=()
            ;;
    esac
    
    # Add skills to enabled list
    for skill in "${skills[@]}"; do
        echo -e "  + Enabling skill: ${GREEN}${skill}${NC}"
        # Add to YAML file (simple append for now)
        if ! grep -q "  - ${skill}" .workflow/skills/enabled.yaml; then
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
        echo -e "${YELLOW}Specify target agent:${NC}"
        echo "  researcher, architect, implementer, experimenter,"
        echo "  optimizer, deployer, documenter"
        read -p "Target agent: " to_agent
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
        prepare_handoff $AGENT_NAME $3
        ;;
    *)
        echo -e "${RED}Unknown command: ${COMMAND}${NC}"
        show_usage
        ;;
esac
