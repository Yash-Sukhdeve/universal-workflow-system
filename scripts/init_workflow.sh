#!/bin/bash

# Universal Workflow System - Initialization Script
# Initialize a new project with the workflow system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"

# Accept project type as argument
PROJECT_TYPE_ARG="${1:-}"

# Source utility libraries
if [[ -f "${SCRIPT_DIR}/lib/validation_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/validation_utils.sh"
fi

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════════════════════"
echo "   Universal Workflow System - Project Initialization"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if workflow is already initialized
check_existing_workflow() {
    if [[ -d ".workflow" ]] && [[ -f ".workflow/state.yaml" ]]; then
        echo -e "${YELLOW}⚠ Workflow system appears to be already initialized${NC}"
        echo ""

        # Non-interactive mode - backup and continue
        if [[ ! -t 0 ]]; then
            local backup_dir=".workflow.backup.$(date +%Y%m%d_%H%M%S)"
            echo -e "${YELLOW}Backing up existing workflow to ${backup_dir}${NC}"
            mv ".workflow" "$backup_dir"
            return 0
        fi

        read -p "Reinitialize (this will backup existing configuration)? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Initialization cancelled."
            exit 0
        fi

        # Backup existing workflow
        local backup_dir=".workflow.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Backing up existing workflow to ${backup_dir}${NC}"
        mv ".workflow" "$backup_dir"
    fi
}

# Function to detect project type
detect_project_type() {
    echo "🔍 Detecting project type..."
    
    if [ -f "requirements.txt" ] || [ -f "setup.py" ] || [ -f "pyproject.toml" ]; then
        if grep -q "torch\|tensorflow\|transformers" requirements.txt 2>/dev/null; then
            echo "  → ML/AI project detected"
            PROJECT_TYPE="ml"
        else
            echo "  → Python project detected"
            PROJECT_TYPE="software"
        fi
    elif [ -f "package.json" ]; then
        echo "  → Node.js project detected"
        PROJECT_TYPE="software"
    elif [ -d "papers" ] || [ -d "experiments" ]; then
        echo "  → Research project detected"
        PROJECT_TYPE="research"
    elif [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ]; then
        echo "  → Deployment project detected"
        PROJECT_TYPE="deployment"
    else
        echo "  → Project type unclear"
        PROJECT_TYPE="unknown"
    fi
}

# Function to prompt for project type
select_project_type() {
    # Check if non-interactive mode (stdin from pipe or file)
    if [[ ! -t 0 ]]; then
        local input
        read -r input || input=""
        # Accept either number or project type name
        case "$input" in
            1|research) PROJECT_TYPE="research";;
            2|ml) PROJECT_TYPE="ml";;
            3|software) PROJECT_TYPE="software";;
            4|llm) PROJECT_TYPE="llm";;
            5|optimization) PROJECT_TYPE="optimization";;
            6|deployment) PROJECT_TYPE="deployment";;
            7|hybrid) PROJECT_TYPE="hybrid";;
            *) PROJECT_TYPE="hybrid";;
        esac
        return 0
    fi

    echo ""
    echo "📋 Select project type:"
    echo "  1) Research Project"
    echo "  2) ML/AI Development"
    echo "  3) Software Development"
    echo "  4) LLM/Transformer Project"
    echo "  5) Model Optimization"
    echo "  6) Deployment/DevOps"
    echo "  7) Hybrid/Custom"
    echo ""
    read -p "Enter choice [1-7]: " choice

    case $choice in
        1) PROJECT_TYPE="research";;
        2) PROJECT_TYPE="ml";;
        3) PROJECT_TYPE="software";;
        4) PROJECT_TYPE="llm";;
        5) PROJECT_TYPE="optimization";;
        6) PROJECT_TYPE="deployment";;
        7) PROJECT_TYPE="hybrid";;
        *) PROJECT_TYPE="hybrid";;
    esac
}

# Create workflow structure
create_workflow_structure() {
    echo ""
    echo "🏗️  Creating workflow structure..."
    
    # Create directories
    mkdir -p .workflow/{agents,skills,knowledge,scripts,templates}
    mkdir -p .workflow/agents/{configs,memory}
    mkdir -p .workflow/skills/{definitions,chains}
    mkdir -p phases/{phase_1_planning,phase_2_implementation,phase_3_validation,phase_4_delivery,phase_5_maintenance}
    mkdir -p {artifacts,workspace,archive}
    
    echo "  ✓ Directory structure created"
}

# Initialize state file
initialize_state() {
    echo "📝 Initializing state management..."
    
    cat > .workflow/state.yaml << EOF
# Workflow State File
# Auto-generated on $(date -Iseconds)

project_type: "${PROJECT_TYPE}"
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
last_updated: "$(date -Iseconds)"

context_bridge:
  critical_info: []
  next_actions:
    - "Review project requirements"
    - "Set up development environment"
  dependencies: []

metadata:
  version: "1.1.0"
  workflow_version: "1.1.0"
  created: "$(date -Iseconds)"
EOF
    
    echo "  ✓ State file initialized"
}

# Initialize checkpoint log
initialize_checkpoints() {
    echo "📍 Setting up checkpoint system..."
    
    cat > .workflow/checkpoints.log << EOF
# Checkpoint Log
# Format: TIMESTAMP | CHECKPOINT_ID | DESCRIPTION
$(date -Iseconds) | INIT | Workflow system initialized
$(date -Iseconds) | CP_1_001 | Starting phase 1 - Planning
EOF
    
    echo "  ✓ Checkpoint system ready"
}

# Create handoff template
create_handoff_template() {
    echo "🤝 Creating handoff template..."
    
    cat > .workflow/handoff.md << EOF
# Context Handoff Document

## Last Session Summary
- **Date**: $(date -Iseconds)
- **Phase**: phase_1_planning
- **Checkpoint**: CP_1_001
- **Working on**: Initial setup

## Critical Context
1. Project type: ${PROJECT_TYPE}
2. Workflow system initialized
3. Ready to begin planning phase

## Next Actions
- [ ] Define project scope
- [ ] Document requirements
- [ ] Set up development environment

## Commands to Resume
\`\`\`bash
cd "${PROJECT_ROOT}"
./scripts/recover_context.sh
\`\`\`

## Notes
_Add session-specific notes here_
EOF
    
    echo "  ✓ Handoff template created"
}

# Setup git integration
setup_git_integration() {
    echo "🔗 Setting up git integration..."

    # Check if this is a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${YELLOW}  ⚠ Not a git repository - skipping git integration${NC}"
        echo -e "${YELLOW}    Run 'git init' to enable git features${NC}"
        return 0
    fi

    # Add workflow patterns to .gitignore if it exists
    if [ -f .gitignore ]; then
        if ! grep -q "# Workflow system" .gitignore; then
            cat >> .gitignore << EOF

# Workflow system
.workflow/agents/memory/*
.workflow/*.tmp
workspace/*
!workspace/.gitkeep
EOF
        fi
    else
        # Create .gitignore if it doesn't exist
        cat > .gitignore << EOF
# Workflow system
.workflow/agents/memory/*
.workflow/*.tmp
.workflow/*.backup
workspace/*
!workspace/.gitkeep
EOF
    fi

    # Create git hooks
    mkdir -p .git/hooks
    
    cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Update workflow state before commit

# Update timestamp in state.yaml
if [ -f .workflow/state.yaml ]; then
    TIMESTAMP="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    sed -i.bak "s/last_updated:.*/last_updated: \"${TIMESTAMP}\"/" .workflow/state.yaml
    rm -f .workflow/state.yaml.bak
    git add .workflow/state.yaml
fi

# Add checkpoint entry if workflow files changed
if git diff --cached --name-only | grep -q ".workflow/"; then
    TIMESTAMP="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    echo "${TIMESTAMP} | AUTO | Pre-commit checkpoint" >> .workflow/checkpoints.log
    git add .workflow/checkpoints.log
fi
EOF
    
    chmod +x .git/hooks/pre-commit
    echo "  ✓ Git hooks configured"
}

# Validate workflow scripts
validate_workflow_scripts() {
    echo "📦 Validating workflow scripts..."

    # Check that required scripts exist
    local required_scripts=(
        "activate_agent.sh"
        "checkpoint.sh"
        "enable_skill.sh"
        "recover_context.sh"
        "status.sh"
    )

    local all_present=true
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
            echo -e "${YELLOW}  ⚠ Warning: ${script} not found${NC}"
            all_present=false
        fi
    done

    if [[ "$all_present" == "true" ]]; then
        echo "  ✓ All workflow scripts present"
    else
        echo -e "${YELLOW}  ⚠ Some scripts missing - workflow may be incomplete${NC}"
    fi
}

# Create project-specific configuration
create_project_config() {
    echo "⚙️  Creating project configuration..."
    
    cat > .workflow/config.yaml << EOF
# Project-Specific Configuration
# Generated for: ${PROJECT_TYPE} project

project:
  name: "$(basename "${PROJECT_ROOT}")"
  type: "${PROJECT_TYPE}"
  description: ""

workflow:
  auto_checkpoint: true
  checkpoint_frequency: "hourly"
  state_backup: true
  
agents:
  auto_activate: true
  default_agent: "$([ "$PROJECT_TYPE" == "research" ] && echo "researcher" || echo "implementer")"
  
skills:
  auto_discover: true
  skill_chains_enabled: true
  
git:
  auto_commit_state: false
  branch_naming: "type/description"
  
monitoring:
  track_metrics: true
  log_level: "INFO"
EOF
    
    echo "  ✓ Configuration created"
}

# Initialize knowledge base
initialize_knowledge_base() {
    echo "🧠 Initializing knowledge base..."

    cat > .workflow/knowledge/patterns.yaml << EOF
# Knowledge Base - Learned Patterns
# This file accumulates patterns and solutions across sessions

patterns: []

solutions: []

best_practices: []
EOF

    echo "  ✓ Knowledge base initialized"
}

# Initialize agent registry
initialize_agent_registry() {
    echo "🤖 Initializing agent registry..."

    cat > .workflow/agents/registry.yaml << 'EOF'
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
EOF

    echo "  ✓ Agent registry initialized"
}

# Initialize skill catalog
initialize_skill_catalog() {
    echo "📚 Initializing skill catalog..."

    cat > .workflow/skills/catalog.yaml << 'EOF'
# Skill Catalog - Available Skills

skills:
  # Research Skills
  literature_review:
    description: "Search and analyze academic literature"
    agent: researcher

  experimental_design:
    description: "Design experiments and studies"
    agent: researcher

  statistical_validation:
    description: "Statistical analysis and validation"
    agent: researcher

  # Architecture Skills
  system_design:
    description: "High-level system architecture design"
    agent: architect

  api_design:
    description: "API design and documentation"
    agent: architect

  # Implementation Skills
  code_generation:
    description: "Generate code from specifications"
    agent: implementer

  debugging:
    description: "Debug and fix issues"
    agent: implementer

  testing:
    description: "Write and run tests"
    agent: implementer

  # Experiment Skills
  benchmarking:
    description: "Performance benchmarking"
    agent: experimenter

  data_analysis:
    description: "Analyze experimental data"
    agent: experimenter

  # Optimization Skills
  performance_profiling:
    description: "Profile and analyze performance"
    agent: optimizer

  quantization:
    description: "Model quantization for efficiency"
    agent: optimizer

  # Deployment Skills
  ci_cd:
    description: "Continuous integration and deployment"
    agent: deployer

  containerization:
    description: "Docker and container management"
    agent: deployer

  # Documentation Skills
  technical_writing:
    description: "Write technical documentation"
    agent: documenter

  api_documentation:
    description: "Generate API documentation"
    agent: documenter
EOF

    echo "  ✓ Skill catalog initialized"
}

# Main execution
main() {
    echo ""

    # Check if project type provided as argument
    if [[ -n "$PROJECT_TYPE_ARG" ]]; then
        case "$PROJECT_TYPE_ARG" in
            research|ml|software|llm|optimization|deployment|hybrid)
                PROJECT_TYPE="$PROJECT_TYPE_ARG"
                echo "📋 Using specified project type: $PROJECT_TYPE"
                ;;
            *)
                echo "⚠ Unknown project type: $PROJECT_TYPE_ARG"
                detect_project_type
                if [ "$PROJECT_TYPE" == "unknown" ]; then
                    select_project_type
                fi
                ;;
        esac
    else
        # Detect or select project type
        detect_project_type

        if [ "$PROJECT_TYPE" == "unknown" ]; then
            select_project_type
        else
            # Non-interactive mode - accept detected type
            if [[ ! -t 0 ]]; then
                local input
                read -r input || input=""
                if [[ -n "$input" ]]; then
                    # Use stdin input as override
                    case "$input" in
                        1|research) PROJECT_TYPE="research";;
                        2|ml) PROJECT_TYPE="ml";;
                        3|software) PROJECT_TYPE="software";;
                        4|llm) PROJECT_TYPE="llm";;
                        5|optimization) PROJECT_TYPE="optimization";;
                        6|deployment) PROJECT_TYPE="deployment";;
                        7|hybrid) PROJECT_TYPE="hybrid";;
                    esac
                fi
            else
                echo ""
                read -p "Detected ${PROJECT_TYPE} project. Use this type? [Y/n]: " confirm
                # Case-insensitive check
                if [[ "$confirm" =~ ^[Nn]$ ]]; then
                    select_project_type
                fi
            fi
        fi
    fi

    echo ""
    echo "🚀 Initializing ${PROJECT_TYPE} workflow..."
    echo ""

    # Check for existing workflow
    check_existing_workflow

    # Run initialization steps
    create_workflow_structure
    initialize_state
    initialize_checkpoints
    create_handoff_template
    setup_git_integration
    validate_workflow_scripts
    create_project_config
    initialize_knowledge_base
    initialize_agent_registry
    initialize_skill_catalog

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${GREEN}✅ Workflow system initialized successfully!${NC}"
    echo ""
    echo "📌 Next steps:"
    echo "  1. Review .workflow/config.yaml for customization"
    echo "  2. Run: ./scripts/status.sh to see current state"
    echo "  3. Run: ./scripts/activate_agent.sh [agent] to start"
    echo ""
    echo "💡 Useful commands:"
    echo "  ./scripts/recover_context.sh    - Recover context after break"
    echo "  ./scripts/checkpoint.sh \"msg\"   - Create checkpoint"
    echo "  ./scripts/detect_and_configure.sh - Re-detect project type"
    echo ""
    echo "📚 Documentation: README.md and CLAUDE.md"
    echo "═══════════════════════════════════════════════════════════════"
}

# Run main function
main
