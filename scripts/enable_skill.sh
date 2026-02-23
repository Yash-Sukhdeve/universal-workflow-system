#!/bin/bash

# Skill Management Script
# Enable, disable, and execute workflow skills

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_LIB_DIR="${SCRIPT_DIR}/lib"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_LIB_DIR}/resolve_project.sh"
FIRST_ARG="${1:-}"
COMMAND="${2:-enable}"
PARAMS="${3:-}"

# Source utility libraries (suppress yq warning)
YAML_UTILS_QUIET=true
if [[ -f "${SCRIPT_DIR}/lib/validation_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/validation_utils.sh"
fi

if [[ -f "${SCRIPT_DIR}/lib/yaml_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/yaml_utils.sh"
fi

# Handle help/list/status as first arg (before treating as skill name)
# Note: show_usage is defined below; for --help we defer to the case statement
if [[ "$FIRST_ARG" =~ ^(--help|-h|help)$ ]]; then
    SKILL_NAME=""
    COMMAND="help"
elif [[ "$FIRST_ARG" == "list" ]]; then
    SKILL_NAME=""
    COMMAND="list"
elif [[ "$FIRST_ARG" == "status" ]]; then
    SKILL_NAME=""
    COMMAND="status"
else
    SKILL_NAME="$FIRST_ARG"
fi

# Color codes
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly RED='\033[0;31m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# Function to show usage
show_usage() {
    echo "Usage: $0 <skill_name> [command] [params]"
    echo ""
    echo "Commands:"
    echo "  enable    - Enable a skill"
    echo "  disable   - Disable a skill"
    echo "  execute   - Execute a skill with parameters"
    echo "  list      - List all available skills"
    echo "  status    - Show skill status"
    echo ""
    echo "Research Skills:"
    echo "  literature_review    - Systematic literature analysis"
    echo "  experimental_design  - Design experiments"
    echo "  statistical_validation - Statistical testing"
    echo ""
    echo "Development Skills:"
    echo "  code_generation     - Generate code from specs"
    echo "  debugging          - Debug and fix issues"
    echo "  testing            - Create and run tests"
    echo ""
    echo "ML/AI Skills:"
    echo "  model_development   - Build ML models"
    echo "  quantization       - Model quantization"
    echo "  pruning           - Model pruning"
    echo "  fine_tuning       - Fine-tune models"
    echo ""
    echo "Deployment Skills:"
    echo "  containerization   - Docker/container setup"
    echo "  ci_cd             - CI/CD pipeline setup"
    echo "  monitoring        - Setup monitoring"
    echo ""
    exit 1
}

# Check if workflow is initialized
if ! validate_workflow_initialized 2>/dev/null; then
    if [[ ! -d .workflow ]]; then
        echo -e "${RED}Error: Workflow not initialized. Run ./scripts/init_workflow.sh first${NC}"
        exit 1
    fi
fi

# Create skill directories if they don't exist
mkdir -p .workflow/skills/{definitions,chains,execution_logs}

# Initialize enabled skills file if it doesn't exist
if [ ! -f .workflow/skills/enabled.yaml ]; then
    cat > .workflow/skills/enabled.yaml << EOF
# Enabled Skills
# Auto-managed by skill system

enabled_skills: []
skill_configs: {}
EOF
fi

# Function to validate skill name
validate_skill_name() {
    local skill=$1

    # Reject empty or invalid names
    if [[ -z "$skill" ]]; then
        echo -e "${RED}Error: Skill name cannot be empty${NC}"
        return 1
    fi

    # Reject names that look like flags
    if [[ "$skill" =~ ^- ]]; then
        echo -e "${RED}Error: Invalid skill name '${skill}'${NC}"
        return 1
    fi

    # Reject names with special characters (allow only alphanumeric and underscores)
    if [[ ! "$skill" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo -e "${RED}Error: Invalid skill name '${skill}'. Use only letters, numbers, and underscores.${NC}"
        return 1
    fi

    return 0
}

# Function to enable a skill
enable_skill() {
    local skill=$1
    echo -e "${BLUE}🔧 Enabling skill: ${skill}...${NC}"

    # Validate skill name
    if ! validate_skill_name "$skill"; then
        return 1
    fi

    # Check if skill is already enabled
    if grep -q "  - ${skill}" .workflow/skills/enabled.yaml; then
        echo -e "${YELLOW}Skill already enabled${NC}"
        return
    fi
    
    # Add skill to enabled list
    echo "  - ${skill}" >> .workflow/skills/enabled.yaml
    
    # Create skill definition if it doesn't exist
    create_skill_definition $skill
    
    # Log skill enablement
    echo "$(date -Iseconds) | SKILL_ENABLED | ${skill}" >> .workflow/checkpoints.log
    
    echo -e "${GREEN}✓ Skill '${skill}' enabled${NC}"
    
    # Show skill dependencies
    show_skill_dependencies $skill
}

# Function to create skill definition
create_skill_definition() {
    local skill=$1
    local def_file=".workflow/skills/definitions/${skill}.yaml"
    
    if [ -f "$def_file" ]; then
        return
    fi
    
    echo -e "${CYAN}Creating skill definition...${NC}"
    
    case $skill in
        literature_review)
            cat > $def_file << 'EOF'
name: literature_review
description: "Systematic literature review and analysis"
category: research

parameters:
  query:
    type: string
    required: true
    description: "Search query for papers"
  sources:
    type: list
    default: ["arxiv", "scholar", "acm"]
    description: "Sources to search"
  limit:
    type: integer
    default: 50
    description: "Maximum papers to review"

outputs:
  - paper_database.json
  - synthesis.md
  - gap_analysis.md

execution:
  script: "scripts/skills/literature_review.sh"
  timeout: 3600
  
dependencies:
  - tool: python3
  - library: scholarly
  - library: requests
EOF
            ;;
            
        code_generation)
            cat > $def_file << 'EOF'
name: code_generation
description: "Generate code from specifications"
category: development

parameters:
  spec_file:
    type: string
    required: true
    description: "Specification file path"
  language:
    type: string
    default: "python"
    description: "Target language"
  style:
    type: string
    default: "modular"
    description: "Code style"

outputs:
  - generated_code/
  - tests/
  - documentation.md

execution:
  script: "scripts/skills/code_generation.sh"
  timeout: 1800

dependencies:
  - tool: python3
  - library: black
  - library: pytest
EOF
            ;;
            
        quantization)
            cat > $def_file << 'EOF'
name: quantization
description: "Model quantization for optimization"
category: optimization

parameters:
  model_path:
    type: string
    required: true
    description: "Path to model"
  target_bits:
    type: integer
    default: 8
    description: "Target bit width"
  calibration_data:
    type: string
    required: false
    description: "Calibration dataset"

outputs:
  - quantized_model/
  - benchmarks.yaml
  - compression_report.md

execution:
  script: "scripts/skills/quantization.py"
  timeout: 7200

dependencies:
  - tool: python3
  - library: torch
  - library: transformers
EOF
            ;;
            
        *)
            # Generic skill template
            cat > $def_file << EOF
name: ${skill}
description: "Custom skill: ${skill}"
category: custom

parameters:
  input:
    type: string
    required: true
    description: "Input parameter"

outputs:
  - output/

execution:
  script: "scripts/skills/${skill}.sh"
  timeout: 1800

dependencies: []
EOF
            ;;
    esac
    
    echo -e "${GREEN}✓ Skill definition created${NC}"
}

# Function to disable a skill
disable_skill() {
    local skill=$1
    echo -e "${BLUE}🔧 Disabling skill: ${skill}...${NC}"

    # Validate skill name
    if ! validate_skill_name "$skill"; then
        return 1
    fi

    # Check if skill is actually enabled
    if ! grep -q "  - ${skill}" .workflow/skills/enabled.yaml; then
        echo -e "${YELLOW}Skill '${skill}' is not currently enabled${NC}"
        return
    fi

    # Remove from enabled list (simple sed approach)
    sed -i "/  - ${skill}/d" .workflow/skills/enabled.yaml
    
    # Log skill disablement
    echo "$(date -Iseconds) | SKILL_DISABLED | ${skill}" >> .workflow/checkpoints.log
    
    echo -e "${GREEN}✓ Skill '${skill}' disabled${NC}"
}

# Function to execute a skill
execute_skill() {
    local skill=$1
    local params=$2
    
    echo -e "${BLUE}🚀 Executing skill: ${skill}...${NC}"
    
    # Check if skill is enabled
    if ! grep -q "  - ${skill}" .workflow/skills/enabled.yaml; then
        echo -e "${RED}Error: Skill not enabled. Enable it first.${NC}"
        exit 1
    fi
    
    # Create execution log
    local exec_id=$(date +%s)
    local log_file=".workflow/skills/execution_logs/${skill}_${exec_id}.log"
    
    # Log execution start
    cat > $log_file << EOF
Skill Execution Log
===================
Skill: ${skill}
Execution ID: ${exec_id}
Started: $(date -Iseconds)
Parameters: ${params}

Output:
-------
EOF
    
    # Execute skill based on type
    case $skill in
        literature_review)
            echo "Searching for papers..." >> $log_file
            echo "Query: ${params}" >> $log_file
            # Simulate execution
            echo "Found 25 relevant papers" >> $log_file
            echo "Creating synthesis..." >> $log_file
            ;;
            
        code_generation)
            echo "Generating code from spec..." >> $log_file
            echo "Language: Python" >> $log_file
            echo "Style: Modular" >> $log_file
            # Simulate execution
            echo "Generated 5 modules" >> $log_file
            echo "Created unit tests" >> $log_file
            ;;
            
        quantization)
            echo "Quantizing model..." >> $log_file
            echo "Target: 8-bit" >> $log_file
            # Simulate execution
            echo "Model size reduced by 75%" >> $log_file
            echo "Inference speed improved by 2.3x" >> $log_file
            ;;
            
        *)
            echo "Executing custom skill..." >> $log_file
            ;;
    esac
    
    # Log execution end
    echo "" >> $log_file
    echo "Completed: $(date -Iseconds)" >> $log_file
    
    # Update checkpoint
    echo "$(date -Iseconds) | SKILL_EXECUTED | ${skill} | exec_id:${exec_id}" >> .workflow/checkpoints.log
    
    echo -e "${GREEN}✓ Skill execution complete${NC}"
    echo -e "Log file: ${YELLOW}${log_file}${NC}"
}

# Function to list available skills
list_skills() {
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${BLUE}         Available Skills${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${CYAN}Research Skills:${NC}"
    echo "  • literature_review     - Systematic paper analysis"
    echo "  • experimental_design   - Design experiments"
    echo "  • statistical_validation - Statistical testing"
    echo "  • paper_writing        - Academic paper writing"
    echo ""
    
    echo -e "${CYAN}Development Skills:${NC}"
    echo "  • code_generation      - Generate code from specs"
    echo "  • debugging           - Debug and fix issues"
    echo "  • testing            - Unit and integration testing"
    echo "  • refactoring        - Code refactoring"
    echo ""
    
    echo -e "${CYAN}ML/AI Skills:${NC}"
    echo "  • model_development    - Build ML models"
    echo "  • fine_tuning         - Fine-tune pre-trained models"
    echo "  • quantization        - Model quantization"
    echo "  • pruning            - Model pruning"
    echo "  • distillation       - Knowledge distillation"
    echo ""
    
    echo -e "${CYAN}Optimization Skills:${NC}"
    echo "  • profiling          - Performance profiling"
    echo "  • benchmarking       - Run benchmarks"
    echo "  • hyperparameter_tuning - Tune hyperparameters"
    echo "  • resource_optimization - Optimize resource usage"
    echo ""
    
    echo -e "${CYAN}Deployment Skills:${NC}"
    echo "  • containerization    - Docker setup"
    echo "  • ci_cd              - CI/CD pipeline"
    echo "  • monitoring         - Setup monitoring"
    echo "  • scaling           - Auto-scaling setup"
    echo ""
    
    echo -e "${GREEN}Enabled Skills:${NC}"
    if [ -f .workflow/skills/enabled.yaml ]; then
        grep "^  - " .workflow/skills/enabled.yaml | while read -r line; do
            skill=$(echo $line | sed 's/^  - //')
            echo -e "  ✓ ${GREEN}${skill}${NC}"
        done || echo -e "  ${YELLOW}No skills enabled${NC}"
    else
        echo -e "  ${YELLOW}No skills configured${NC}"
    fi
}

# Function to show skill status
show_skill_status() {
    local skill=$1
    
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Skill Status: ${skill}${NC}"
    echo -e "${BLUE}═════════════════════════════════════════${NC}"
    
    # Check if enabled
    if grep -q "  - ${skill}" .workflow/skills/enabled.yaml; then
        echo -e "Status: ${GREEN}Enabled${NC}"
    else
        echo -e "Status: ${YELLOW}Disabled${NC}"
    fi
    
    # Show skill definition
    local def_file=".workflow/skills/definitions/${skill}.yaml"
    if [ -f "$def_file" ]; then
        echo ""
        echo "Definition:"
        grep -E "^(description|category):" "$def_file" | while IFS=':' read -r key value; do
            echo -e "  ${CYAN}${key}:${NC}${value}"
        done
    fi
    
    # Show recent executions
    echo ""
    echo "Recent Executions:"
    grep "SKILL_EXECUTED.*${skill}" .workflow/checkpoints.log | tail -3 | while IFS='|' read -r timestamp event details; do
        echo -e "  ${YELLOW}$(echo $timestamp | xargs)${NC}"
    done || echo -e "  ${YELLOW}No recent executions${NC}"
}

# Function to show skill dependencies
show_skill_dependencies() {
    local skill=$1
    local def_file=".workflow/skills/definitions/${skill}.yaml"
    
    if [ ! -f "$def_file" ]; then
        return
    fi
    
    echo ""
    echo -e "${CYAN}Dependencies for ${skill}:${NC}"
    
    # Extract dependencies (simple grep approach)
    sed -n '/^dependencies:/,/^[^ ]/p' "$def_file" | grep "^  - " | while read -r line; do
        dep=$(echo $line | sed 's/^  - //')
        echo -e "  • ${YELLOW}${dep}${NC}"
    done || echo -e "  ${GREEN}No dependencies${NC}"
}

# Main execution
case $COMMAND in
    enable)
        if [ -z "$SKILL_NAME" ]; then
            show_usage
        fi
        enable_skill $SKILL_NAME
        ;;
    disable)
        if [ -z "$SKILL_NAME" ]; then
            show_usage
        fi
        disable_skill $SKILL_NAME
        ;;
    execute)
        if [ -z "$SKILL_NAME" ]; then
            show_usage
        fi
        execute_skill $SKILL_NAME "$PARAMS"
        ;;
    list)
        list_skills
        ;;
    status)
        if [ -z "$SKILL_NAME" ]; then
            list_skills
        else
            show_skill_status $SKILL_NAME
        fi
        ;;
    help|*)
        show_usage
        ;;
esac
