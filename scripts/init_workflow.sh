#!/bin/bash

# Universal Workflow System - Initialization Script
# Initialize a new project with the workflow system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"

echo "═══════════════════════════════════════════════════════════════"
echo "   Universal Workflow System - Project Initialization"
echo "═══════════════════════════════════════════════════════════════"
echo ""

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
  version: "1.0.0"
  workflow_version: "1.0.0"
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
cd ${PROJECT_ROOT}
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
    fi
    
    # Create git hooks
    mkdir -p .git/hooks
    
    cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Update workflow state before commit

# Update timestamp in state.yaml
if [ -f .workflow/state.yaml ]; then
    sed -i "s/last_updated:.*/last_updated: \"$(date -Iseconds)\"/" .workflow/state.yaml
    git add .workflow/state.yaml
fi

# Add checkpoint entry if message contains [CHECKPOINT]
if git diff --cached --name-only | grep -q ".workflow/"; then
    echo "$(date -Iseconds) | AUTO | Pre-commit checkpoint" >> .workflow/checkpoints.log
    git add .workflow/checkpoints.log
fi
EOF
    
    chmod +x .git/hooks/pre-commit
    echo "  ✓ Git hooks configured"
}

# Copy workflow scripts
copy_workflow_scripts() {
    echo "📦 Installing workflow scripts..."
    
    # Copy all scripts from the repository
    if [ -d "${SCRIPT_DIR}" ]; then
        cp -r ${SCRIPT_DIR}/*.sh .workflow/scripts/
        chmod +x .workflow/scripts/*.sh
        echo "  ✓ Scripts installed"
    fi
}

# Create project-specific configuration
create_project_config() {
    echo "⚙️  Creating project configuration..."
    
    cat > .workflow/config.yaml << EOF
# Project-Specific Configuration
# Generated for: ${PROJECT_TYPE} project

project:
  name: "$(basename ${PROJECT_ROOT})"
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

# Main execution
main() {
    echo ""
    
    # Detect or select project type
    detect_project_type
    
    if [ "$PROJECT_TYPE" == "unknown" ]; then
        select_project_type
    else
        echo ""
        read -p "Detected ${PROJECT_TYPE} project. Use this type? [Y/n]: " confirm
        if [ "$confirm" == "n" ] || [ "$confirm" == "N" ]; then
            select_project_type
        fi
    fi
    
    echo ""
    echo "🚀 Initializing ${PROJECT_TYPE} workflow..."
    echo ""
    
    # Run initialization steps
    create_workflow_structure
    initialize_state
    initialize_checkpoints
    create_handoff_template
    setup_git_integration
    copy_workflow_scripts
    create_project_config
    initialize_knowledge_base
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "✅ Workflow system initialized successfully!"
    echo ""
    echo "📌 Next steps:"
    echo "  1. Review .workflow/config.yaml for customization"
    echo "  2. Run: ./workflow/scripts/status.sh to see current state"
    echo "  3. Run: ./workflow/scripts/activate_agent.sh [agent] to start"
    echo ""
    echo "📚 Documentation: .workflow/README.md"
    echo "═══════════════════════════════════════════════════════════════"
}

# Run main function
main
