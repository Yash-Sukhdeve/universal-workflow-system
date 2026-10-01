#!/bin/bash

# Universal Workflow System - Initialization Script
# Initialize a new project with the workflow system

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"

# Accept project type as argument
PROJECT_TYPE_ARG="${1:-}"

# The UWS release (VERSION at the install's root), recorded in state.yaml metadata
UWS_RELEASE="$(tr -d '[:space:]' 2>/dev/null < "${SCRIPT_DIR}/../VERSION" || true)"
UWS_RELEASE="${UWS_RELEASE:-unknown}"

# Source utility libraries
if [[ -f "${SCRIPT_DIR}/lib/uws_config.sh" ]]; then
    source "${SCRIPT_DIR}/lib/uws_config.sh"
fi
if [[ -f "${SCRIPT_DIR}/lib/validation_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/validation_utils.sh"
fi
if [[ -f "${SCRIPT_DIR}/lib/vector_memory_setup.sh" ]]; then
    source "${SCRIPT_DIR}/lib/vector_memory_setup.sh"
fi
# uws_hint: how to spell the next command (`uws ...`, `./uws ...`, `/uws:...`)
source "${SCRIPT_DIR}/lib/uws_ui.sh"

# Color codes for output (guard matching validation_utils.sh:14-19)
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
fi
# No colour unless stdout is a terminal (and NO_COLOR or TERM=dumb is not set): output an
# agent or a slash command captures must not carry raw ANSI escapes.
[[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]] || { RED=''; GREEN=''; YELLOW=''; NC=''; }

echo "═══════════════════════════════════════════════════════════════"
echo "   Universal Workflow System - Project Initialization"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Check if workflow is already initialized
check_existing_workflow() {
    if [[ -d ".workflow" ]] && [[ -f ".workflow/state.yaml" ]]; then
        echo -e "${YELLOW}⚠ Workflow system appears to be already initialized${NC}"
        echo ""

        # Non-interactive mode: never move existing state aside unless explicitly asked,
        # so re-running init from an agent, CI or a hook is a safe no-op.
        if [[ ! -t 0 ]]; then
            if [[ "${UWS_FORCE_REINIT:-false}" != "true" ]]; then
                upgrade_uws_hook
                echo "UWS is already initialized here; leaving .workflow/ unchanged."
                echo "To back it up and start over: UWS_FORCE_REINIT=true $0"
                exit 0
            fi
            local backup_dir
            backup_dir=".workflow.backup.$(date +%Y%m%d_%H%M%S)"
            echo -e "${YELLOW}Backing up existing workflow to ${backup_dir}${NC}"
            mv ".workflow" "$backup_dir"
            return 0
        fi

        read -p "Reinitialize (this will backup existing configuration)? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            upgrade_uws_hook
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
    
    # Create directories. Only .workflow/: nothing else goes into the project's top level
    # (workspace/<role>/ is made by `uws orchestrate dispatch`; the knowledge base,
    # docs/kb/, by the first `uws kb add`)
    mkdir -p .workflow/{agents,scripts,templates}
    
    echo "  ✓ Directory structure created"
}

# Initialize state file
initialize_state() {
    echo "📝 Initializing state management..."
    
    cat > .workflow/state.yaml << EOF
# Workflow State File
# Auto-generated on $(date -Iseconds)

project_type: "${PROJECT_TYPE}"
goal: ""
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
last_updated: "$(date -Iseconds)"

context_bridge:
  critical_info: []
  next_actions:
    - "Review project requirements"
    - "Set up development environment"
  dependencies: []

phases:
  phase_1_planning:
    status: "active"
  phase_2_implementation:
    status: "pending"
  phase_3_validation:
    status: "pending"
  phase_4_delivery:
    status: "pending"
  phase_5_maintenance:
    status: "pending"

methodology_progress:

metadata:
  version: "${UWS_RELEASE}"
  workflow_version: "${UWS_RELEASE}"
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
    
    # The summary block is rendered from state.yaml and refreshed by UWS on
    # every checkpoint and phase change; every other section belongs to the
    # people and agents working on the project and is never rewritten.
    local summary_block
    if [[ -f "${SCRIPT_DIR}/lib/handoff_utils.sh" ]]; then
        source "${SCRIPT_DIR}/lib/handoff_utils.sh"
        summary_block="$(uws_handoff_render_block .workflow/state.yaml .workflow/checkpoints.log)"
    else
        summary_block="<!-- uws:managed:start -->
## Last Session Summary
- **Phase**: phase_1_planning
- **Checkpoint**: CP_1_001
<!-- uws:managed:end -->"
    fi
    local init_date
    init_date="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)"

    cat > .workflow/handoff.md << EOF
# Context Handoff Document

${summary_block}

## Critical Context
<!-- Durable facts the next session must know: decisions, constraints, gotchas. -->
1. Project type: ${PROJECT_TYPE}
2. UWS initialized: ${init_date}

## Next Actions
<!-- Keep this list current; open items are shown to Claude at session start.
     Declaring the goal and starting a methodology are listed in the summary above
     until state.yaml shows they are done. -->

## Blockers
- None

## Commands to Resume
\`\`\`bash
uws recover          # or ./uws recover; in Claude Code: /uws:recover
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
.workflow/checkpoints/snapshots/
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
.workflow/checkpoints/snapshots/
workspace/*
!workspace/.gitkeep
EOF
    fi

    # Create git hooks — never clobber a project's existing pre-commit hook
    # (husky, pre-commit framework, custom scripts).
    local hooks_dir
    hooks_dir="$(git rev-parse --git-path hooks 2>/dev/null || echo .git/hooks)"
    if [[ -e "${hooks_dir}/pre-commit" ]] && ! grep -q "Update workflow state before commit" "${hooks_dir}/pre-commit" 2>/dev/null; then
        echo -e "${YELLOW}  ⚠ Existing pre-commit hook found; leaving it untouched (UWS hook skipped)${NC}"
        return 0
    fi
    mkdir -p "${hooks_dir}"

    write_uws_hook "${hooks_dir}"
    echo "  ✓ Git hooks configured"
}

# write_uws_hook <hooks dir>: the UWS pre-commit hook. It touches a commit only when
# the commit already stages .workflow/state.yaml: it then refreshes last_updated in
# that file. It never stages files the commit did not include and never writes
# checkpoints.log. Delete .git/hooks/pre-commit to opt out.
write_uws_hook() {
    local hooks_dir="$1"
    mkdir -p "${hooks_dir}"
    cat > "${hooks_dir}/pre-commit" << 'EOF'
#!/bin/sh
# Update workflow state before commit (installed by UWS init, v2)
# Only when this commit already stages .workflow/state.yaml and the file has no
# unstaged changes: refresh its last_updated and re-stage it. Nothing else.
if git diff --cached --name-only -- .workflow/state.yaml | grep -q . \
    && git diff --quiet -- .workflow/state.yaml; then
    TIMESTAMP="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S%z)"
    sed -i.uwsbak "s/^last_updated:.*/last_updated: \"${TIMESTAMP}\"/" .workflow/state.yaml
    rm -f .workflow/state.yaml.uwsbak
    git add .workflow/state.yaml
fi
exit 0
EOF
    chmod +x "${hooks_dir}/pre-commit"
}

# The hook earlier versions installed staged .workflow/state.yaml into every commit and
# appended "AUTO | Pre-commit checkpoint" to checkpoints.log. Re-running init replaces
# it (only a UWS hook: its first comment line says so).
upgrade_uws_hook() {
    local hooks_dir hook
    git rev-parse --git-dir > /dev/null 2>&1 || return 0
    hooks_dir="$(git rev-parse --git-path hooks 2>/dev/null || echo .git/hooks)"
    hook="${hooks_dir}/pre-commit"
    [[ -f "$hook" ]] || return 0
    grep -q "Update workflow state before commit" "$hook" 2>/dev/null || return 0
    grep -q "installed by UWS init, v2" "$hook" 2>/dev/null && return 0
    write_uws_hook "$hooks_dir"
    echo "Updated the UWS pre-commit hook: it no longer stages .workflow/state.yaml into every commit."
}

# Validate workflow scripts
validate_workflow_scripts() {
    echo "📦 Validating workflow scripts..."

    # Check that required scripts exist
    local required_scripts=(
        "checkpoint.sh"
        "orchestrate.sh"
        "recover_context.sh"
        "research.sh"
        "sdlc.sh"
        "status.sh"
    )

    local all_present=true
    for script in ${required_scripts[@]+"${required_scripts[@]}"}; do
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
  default_agent: "$([ "$PROJECT_TYPE" == "research" ] && echo "researcher" || echo "implementer")"

git:
  auto_commit_state: false
  branch_naming: "type/description"
  
monitoring:
  track_metrics: true
  log_level: "INFO"
EOF
    
    echo "  ✓ Configuration created"
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

# Create uws CLI wrapper in the project root
create_uws_wrapper() {
    echo "Creating uws CLI wrapper..."

    cat > "${PROJECT_ROOT}/uws" << WRAPPER_EOF
#!/bin/bash
# UWS CLI — routes commands to Universal Workflow System scripts.
# Generated by init_workflow.sh on $(date -Iseconds)

set -euo pipefail

# Resolve UWS install dir: config file → baked-in fallback
_UWS_CONFIG_FILE="\${XDG_CONFIG_HOME:-\${HOME}/.config}/uws/config.yaml"
_UWS_BAKED_DIR="${SCRIPT_DIR}"
if [[ -f "\$_UWS_CONFIG_FILE" ]]; then
    _UWS_CFG_DIR="\$(grep -E '^uws_install_dir:' "\$_UWS_CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//;s/"$//' | sed "s/^'//;s/'$//")" || true
fi
UWS_SCRIPTS="\${_UWS_CFG_DIR:-\$_UWS_BAKED_DIR}"
# Validate resolved dir exists; fall back if not
if [[ ! -d "\$UWS_SCRIPTS" ]]; then
    UWS_SCRIPTS="\$_UWS_BAKED_DIR"
fi

export WORKFLOW_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)/.workflow"
export STATE_FILE="\${WORKFLOW_DIR}/state.yaml"
# The scripts' "run ... next" hints name this wrapper
export UWS_CMD="\${UWS_CMD:-./uws}"

CMD="\${1:-help}"
shift 2>/dev/null || true

case "\$CMD" in
    status)       "\$UWS_SCRIPTS/status.sh" "\$@" ;;
    checkpoint)   "\$UWS_SCRIPTS/checkpoint.sh" "\$@" ;;
    sdlc)         "\$UWS_SCRIPTS/sdlc.sh" "\$@" ;;
    research)     "\$UWS_SCRIPTS/research.sh" "\$@" ;;
    orchestrate)  "\$UWS_SCRIPTS/orchestrate.sh" "\$@" ;;
    kb)           "\$UWS_SCRIPTS/kb.sh" "\$@" ;;
    dashboard)    "\$UWS_SCRIPTS/start_dashboard.sh" "\$@" ;;
    agent|skill)
        echo "uws \$CMD: retired. Agents are Claude Code subagents: run './uws orchestrate dispatch \"<task>\"' or use /agents. Skills are native Claude Code skills." >&2
        exit 2
        ;;
    recover)      "\$UWS_SCRIPTS/recover_context.sh" "\$@" ;;
    init)         "\$UWS_SCRIPTS/init_workflow.sh" "\$@" ;;
    spiral)       "\$UWS_SCRIPTS/spiral.sh" "\$@" ;;
    submit)       "\$UWS_SCRIPTS/submit.sh" "\$@" ;;
    review)       "\$UWS_SCRIPTS/review.sh" "\$@" ;;
    pm)           "\$UWS_SCRIPTS/pm.sh" "\$@" ;;
    detect)       "\$UWS_SCRIPTS/detect_and_configure.sh" "\$@" ;;
    help|--help|-h)
        echo "UWS — Universal Workflow System"
        echo ""
        echo "Usage: ./uws <command> [args...]"
        echo ""
        echo "Workflow:"
        echo "  status                Show workflow status"
        echo "  sdlc [action]         SDLC phases (status|start|next|goto|fail|reset|goal|check|deliverables)"
        echo "  research [action]     Research phases (status|start|next|reject|reset|goal|check|deliverables)"
        echo "  checkpoint create [msg]  Create checkpoint (also: list, restore <ID>)"
        echo "  kb <verb>             Project knowledge base (docs/kb/)"
        echo "  recover               Recover context after break"
        echo ""
        echo "Agents:"
        echo "  orchestrate dispatch \"<task>\"  Route the current phase to its subagent"
        echo ""
        echo "Other:"
        echo "  pm [cmd]              Project management"
        echo "  submit [msg]          Submit changes"
        echo "  review [cmd]          Review changes"
        echo "  detect                Re-detect project type"
        echo "  spiral [action]       Spiral model"
        echo "  dashboard             Start the review/PM dashboard (http://localhost:8080)"
        ;;
    *)
        echo "Unknown command: \$CMD"
        echo "Run ./uws help for usage."
        exit 1
        ;;
esac
WRAPPER_EOF

    chmod +x "${PROJECT_ROOT}/uws"
    echo "  Created ./uws CLI wrapper"
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
    initialize_agent_registry

    # Create uws CLI wrapper (the Claude Code plugin sets UWS_NO_WRAPPER: its
    # scripts live in a versioned cache dir that a baked-in path would outlive)
    if [[ "${UWS_NO_WRAPPER:-false}" != "true" ]]; then
        create_uws_wrapper
    fi

    # Vector memory setup (optional, graceful failure)
    if declare -f setup_vector_memory > /dev/null 2>&1; then
        if ! setup_vector_memory "${PROJECT_ROOT}"; then
            echo -e "${YELLOW}  Vector memory setup skipped (optional)${NC}"
        fi
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo -e "${GREEN}Workflow system initialized successfully!${NC}"
    echo ""
    # Hints name the per-project ./uws wrapper when this run created it
    if [[ "${UWS_NO_WRAPPER:-false}" != "true" && -z "${UWS_CMD:-}" ]] && ! uws_in_plugin; then
        UWS_CMD="./uws"
    fi
    local m="sdlc" m_name="SDLC"
    [[ "$PROJECT_TYPE" == "research" ]] && { m="research"; m_name="the research workflow"; }
    echo "Next steps:"
    echo "  1. Review .workflow/config.yaml for customization"
    echo -e "  2. Declare the goal: ${GREEN}$(uws_hint "$m" goal '"<what you are building>"')${NC} (optional; turns on deliverable gating)"
    echo -e "  3. Run: ${GREEN}$(uws_hint "$m" start)${NC} to begin ${m_name}"
    echo ""
    echo "Commands (run from this project directory):"
    echo "  $(uws_hint status)              - Show workflow status"
    echo "  $(uws_hint sdlc '[action]')       - SDLC workflow"
    echo "  $(uws_hint research '[action]')   - Research workflow"
    echo "  $(uws_hint checkpoint create '[msg]') - Create checkpoint"
    echo "  $(uws_hint orchestrate dispatch '"<task>"') - Hand the current phase to its subagent"
    echo "  $(uws_hint recover)             - Recover context"
    echo "═══════════════════════════════════════════════════════════════"
}

# Run main function
main
