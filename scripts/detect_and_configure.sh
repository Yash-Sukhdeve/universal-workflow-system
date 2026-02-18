#!/bin/bash

# Universal Workflow System - Project Detection and Configuration
# Automatically detect project type and configure workflow accordingly
# Can be run on existing projects or to reconfigure current setup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve WORKFLOW_DIR: CWD first, then git root, then UWS fallback
source "${SCRIPT_DIR}/lib/resolve_project.sh"

PROJECT_ROOT="$(dirname "$WORKFLOW_DIR")"

# Source utility libraries if available (suppress yq warning)
YAML_UTILS_QUIET=true
if [[ -f "${SCRIPT_DIR}/lib/yaml_utils.sh" ]]; then
    source "${SCRIPT_DIR}/lib/yaml_utils.sh"
fi

if [[ -f "${SCRIPT_DIR}/lib/workflow_routing.sh" ]]; then
    source "${SCRIPT_DIR}/lib/workflow_routing.sh"
fi

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Configuration
DETECTED_TYPE=""
CONFIDENCE="unknown"
AUTO_MODE=false
FORCE_UPDATE=false
VERBOSE=false

#######################################
# Print usage information
#######################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Detect project type and configure workflow system automatically.

Options:
    -a, --auto          Auto-configure without prompting
    -f, --force         Force reconfiguration even if already configured
    -v, --verbose       Verbose output showing detection details
    -h, --help          Show this help message

Project Types:
    research        Academic research projects
    ml              ML/AI development
    software        Production software development
    llm             LLM/transformer projects
    optimization    Model optimization work
    deployment      DevOps and deployment
    hybrid          Mixed projects

Examples:
    # Detect and configure with prompts
    $0

    # Auto-configure without prompts
    $0 --auto

    # Force reconfiguration
    $0 --force

    # Verbose detection
    $0 --verbose
EOF
}

#######################################
# Parse command line arguments
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--auto)
                AUTO_MODE=true
                shift
                ;;
            -f|--force)
                FORCE_UPDATE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}Error: Unknown option: $1${NC}" >&2
                usage
                exit 1
                ;;
        esac
    done
}

#######################################
# Print verbose message
#######################################
verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
    fi
}

#######################################
# Check if workflow is already configured
#######################################
check_existing_config() {
    if [[ -f ".workflow/config.yaml" ]] && [[ "$FORCE_UPDATE" != "true" ]]; then
        local existing_type
        if command -v yq &> /dev/null; then
            existing_type=$(yq eval '.project.type' .workflow/config.yaml 2>/dev/null || echo "unknown")
        else
            existing_type=$(grep "^  type:" .workflow/config.yaml 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")
        fi

        if [[ -n "$existing_type" ]] && [[ "$existing_type" != "null" ]]; then
            echo -e "${YELLOW}⚠ Workflow already configured as '${existing_type}'${NC}"
            echo ""
            read -p "Reconfigure? [y/N]: " confirm
            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                echo "Configuration unchanged."
                exit 0
            fi
        fi
    fi
}

#######################################
# Detect Python/ML project
#######################################
detect_python_ml() {
    local score=0
    local indicators=()

    # Check for Python files
    if [[ -n "$(find . -maxdepth 2 -name "*.py" -type f 2>/dev/null | head -1)" ]]; then
        score=$((score + 10))
        indicators+=("Python files found")
        verbose "Found Python files"
    fi

    # Check for requirements.txt
    if [[ -f "requirements.txt" ]]; then
        score=$((score + 15))
        indicators+=("requirements.txt")
        verbose "Found requirements.txt"

        # Check for ML/AI libraries
        if grep -qiE "torch|tensorflow|keras|sklearn|scikit-learn|transformers|jax" requirements.txt 2>/dev/null; then
            score=$((score + 30))
            indicators+=("ML/AI libraries detected")
            verbose "Detected ML/AI libraries in requirements.txt"
        fi
    fi

    # Check for setup.py or pyproject.toml
    if [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]]; then
        score=$((score + 10))
        indicators+=("Python package configuration")
        verbose "Found Python package configuration"
    fi

    # Check for Jupyter notebooks
    if [[ -n "$(find . -maxdepth 2 -name "*.ipynb" -type f 2>/dev/null | head -1)" ]]; then
        score=$((score + 15))
        indicators+=("Jupyter notebooks")
        verbose "Found Jupyter notebooks"
    fi

    # Check for ML-specific directories
    for dir in models data datasets experiments notebooks; do
        if [[ -d "$dir" ]]; then
            score=$((score + 5))
            indicators+=("$dir/ directory")
            verbose "Found $dir/ directory"
        fi
    done

    # Determine type based on indicators
    if [[ $score -ge 40 ]]; then
        if grep -qiE "torch|tensorflow|keras|sklearn|transformers" requirements.txt 2>/dev/null || \
           [[ -d "models" ]] || [[ -d "experiments" ]]; then
            DETECTED_TYPE="ml"
            CONFIDENCE="high"
        fi
    elif [[ $score -ge 20 ]]; then
        DETECTED_TYPE="software"
        CONFIDENCE="medium"
    fi

    verbose "Python/ML detection score: $score"
    if [[ ${#indicators[@]} -gt 0 ]] && [[ "$VERBOSE" == "true" ]]; then
        printf "  Indicators: %s\n" "${indicators[*]}"
    fi
}

#######################################
# Detect Research project
#######################################
detect_research() {
    local score=0
    local indicators=()

    # Check for research-specific directories
    for dir in papers literature experiments results analysis docs publications; do
        if [[ -d "$dir" ]]; then
            score=$((score + 15))
            indicators+=("$dir/ directory")
            verbose "Found $dir/ directory"
        fi
    done

    # Check for LaTeX files
    if [[ -n "$(find . -maxdepth 2 -name "*.tex" -type f 2>/dev/null | head -1)" ]]; then
        score=$((score + 20))
        indicators+=("LaTeX files")
        verbose "Found LaTeX files"
    fi

    # Check for citation files
    if [[ -f "references.bib" ]] || [[ -f "bibliography.bib" ]]; then
        score=$((score + 15))
        indicators+=("Bibliography files")
        verbose "Found bibliography files"
    fi

    # Check for data analysis scripts
    if [[ -n "$(find . -maxdepth 2 -name "*analysis*.py" -o -name "*experiment*.py" 2>/dev/null | head -1)" ]]; then
        score=$((score + 10))
        indicators+=("Analysis scripts")
        verbose "Found analysis scripts"
    fi

    if [[ $score -ge 30 ]]; then
        DETECTED_TYPE="research"
        CONFIDENCE="high"
    fi

    verbose "Research detection score: $score"
}

#######################################
# Detect LLM/Transformer project
#######################################
detect_llm() {
    local score=0
    local indicators=()

    # Check for transformer/LLM libraries
    if [[ -f "requirements.txt" ]]; then
        if grep -qiE "transformers|openai|anthropic|langchain|llama|gpt" requirements.txt 2>/dev/null; then
            score=$((score + 40))
            indicators+=("LLM libraries")
            verbose "Detected LLM-specific libraries"
        fi
    fi

    # Check for LLM-specific files/directories
    for item in prompts models/llm fine-tuning tokenizer; do
        if [[ -d "$item" ]] || [[ -f "$item" ]]; then
            score=$((score + 10))
            indicators+=("$item")
            verbose "Found $item"
        fi
    done

    # Check for config files with model names
    if grep -qriE "gpt-|claude-|llama|mistral|falcon" . --include="*.yaml" --include="*.json" --include="*.py" 2>/dev/null; then
        score=$((score + 15))
        indicators+=("LLM model references")
        verbose "Found LLM model references"
    fi

    if [[ $score -ge 40 ]]; then
        DETECTED_TYPE="llm"
        CONFIDENCE="high"
    fi

    verbose "LLM detection score: $score"
}

#######################################
# Detect Deployment/DevOps project
#######################################
detect_deployment() {
    local score=0
    local indicators=()

    # Check for Docker
    if [[ -f "Dockerfile" ]] || [[ -f "docker-compose.yml" ]]; then
        score=$((score + 25))
        indicators+=("Docker configuration")
        verbose "Found Docker configuration"
    fi

    # Check for Kubernetes
    if [[ -d "k8s" ]] || [[ -d "kubernetes" ]] || [[ -n "$(find . -maxdepth 2 -name "*.yaml" -exec grep -l "kind: Deployment" {} \; 2>/dev/null | head -1)" ]]; then
        score=$((score + 20))
        indicators+=("Kubernetes configuration")
        verbose "Found Kubernetes configuration"
    fi

    # Check for CI/CD
    if [[ -d ".github/workflows" ]] || [[ -f ".gitlab-ci.yml" ]] || [[ -f "Jenkinsfile" ]]; then
        score=$((score + 15))
        indicators+=("CI/CD configuration")
        verbose "Found CI/CD configuration"
    fi

    # Check for IaC tools
    if [[ -d "terraform" ]] || [[ -f "terraform.tf" ]] || [[ -d "ansible" ]]; then
        score=$((score + 20))
        indicators+=("Infrastructure as Code")
        verbose "Found IaC configuration"
    fi

    if [[ $score -ge 35 ]]; then
        DETECTED_TYPE="deployment"
        CONFIDENCE="high"
    fi

    verbose "Deployment detection score: $score"
}

#######################################
# Detect Software Development project
#######################################
detect_software() {
    local score=0
    local indicators=()

    # Check for Node.js
    if [[ -f "package.json" ]]; then
        score=$((score + 20))
        indicators+=("Node.js project")
        verbose "Found package.json"
    fi

    # Check for various language markers
    if [[ -f "Cargo.toml" ]]; then
        score=$((score + 20))
        indicators+=("Rust project")
        verbose "Found Cargo.toml"
    fi

    if [[ -f "go.mod" ]]; then
        score=$((score + 20))
        indicators+=("Go project")
        verbose "Found go.mod"
    fi

    if [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]]; then
        score=$((score + 20))
        indicators+=("Java project")
        verbose "Found Java build configuration"
    fi

    # Check for source directories
    for dir in src lib app source; do
        if [[ -d "$dir" ]]; then
            score=$((score + 5))
            indicators+=("$dir/ directory")
            verbose "Found $dir/ directory"
        fi
    done

    # Check for test directories
    if [[ -d "tests" ]] || [[ -d "test" ]]; then
        score=$((score + 10))
        indicators+=("Test directory")
        verbose "Found test directory"
    fi

    if [[ $score -ge 25 ]]; then
        DETECTED_TYPE="software"
        CONFIDENCE="medium"
    fi

    verbose "Software detection score: $score"
}

#######################################
# Run all detection heuristics
#######################################
run_detection() {
    echo -e "${BOLD}🔍 Analyzing project structure...${NC}"
    echo ""

    # Run all detectors (order matters - more specific first)
    detect_llm
    [[ -z "$DETECTED_TYPE" ]] && detect_research
    [[ -z "$DETECTED_TYPE" ]] && detect_python_ml
    [[ -z "$DETECTED_TYPE" ]] && detect_deployment
    [[ -z "$DETECTED_TYPE" ]] && detect_software

    # Default to hybrid if nothing detected
    if [[ -z "$DETECTED_TYPE" ]]; then
        DETECTED_TYPE="hybrid"
        CONFIDENCE="low"
        verbose "No specific project type detected, defaulting to hybrid"
    fi
}

#######################################
# Prompt user to confirm or change detection
#######################################
confirm_detection() {
    if [[ "$AUTO_MODE" == "true" ]]; then
        echo -e "${GREEN}✓${NC} Auto-detected: ${BOLD}${DETECTED_TYPE}${NC} (confidence: ${CONFIDENCE})"
        return 0
    fi

    echo -e "${GREEN}✓${NC} Detected project type: ${BOLD}${DETECTED_TYPE}${NC}"
    echo -e "   Confidence: ${CONFIDENCE}"
    echo ""
    echo "Is this correct? [Y/n/change]"
    read -p "> " response

    case "$response" in
        [Nn]*)
            echo ""
            select_project_type
            ;;
        [Cc]*)
            echo ""
            select_project_type
            ;;
        *)
            # Accept detection
            ;;
    esac
}

#######################################
# Manual project type selection
#######################################
select_project_type() {
    echo ""
    echo -e "${BOLD}📋 Select project type:${NC}"
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
        1) DETECTED_TYPE="research";;
        2) DETECTED_TYPE="ml";;
        3) DETECTED_TYPE="software";;
        4) DETECTED_TYPE="llm";;
        5) DETECTED_TYPE="optimization";;
        6) DETECTED_TYPE="deployment";;
        7) DETECTED_TYPE="hybrid";;
        *) DETECTED_TYPE="hybrid";;
    esac

    CONFIDENCE="user_selected"
}

#######################################
# Update configuration files
#######################################
update_configuration() {
    echo ""
    echo -e "${BOLD}⚙️  Updating configuration...${NC}"

    # Update config.yaml if it exists
    if [[ -f ".workflow/config.yaml" ]]; then
        if command -v yq &> /dev/null; then
            yq eval ".project.type = \"${DETECTED_TYPE}\"" -i .workflow/config.yaml
            echo -e "${GREEN}✓${NC} Updated .workflow/config.yaml"
        else
            # Fallback: sed replacement
            sed -i.bak "s/^  type: .*/  type: \"${DETECTED_TYPE}\"/" .workflow/config.yaml
            rm -f .workflow/config.yaml.bak
            echo -e "${GREEN}✓${NC} Updated .workflow/config.yaml"
        fi
    else
        echo -e "${YELLOW}⚠${NC} .workflow/config.yaml not found (run init_workflow.sh first)"
    fi

    # Update state.yaml if it exists
    if [[ -f ".workflow/state.yaml" ]]; then
        if command -v yq &> /dev/null; then
            yq eval ".project.type = \"${DETECTED_TYPE}\"" -i .workflow/state.yaml
            yq eval ".metadata.last_updated = \"$(date -Iseconds 2>/dev/null || date)\"" -i .workflow/state.yaml
            echo -e "${GREEN}✓${NC} Updated .workflow/state.yaml"
        else
            # Fallback: sed replacement
            sed -i.bak "s/^  type: .*/  type: \"${DETECTED_TYPE}\"/" .workflow/state.yaml
            rm -f .workflow/state.yaml.bak
            echo -e "${GREEN}✓${NC} Updated .workflow/state.yaml"
        fi
    else
        echo -e "${YELLOW}⚠${NC} .workflow/state.yaml not found (run init_workflow.sh first)"
    fi
}

#######################################
# Apply methodology and default agent based on detected type
#######################################
apply_configuration() {
    local project_type="$DETECTED_TYPE"

    # Set active_methodology in state.yaml
    if [[ -f ".workflow/state.yaml" ]]; then
        local methodology="both"
        if declare -f get_active_methodology > /dev/null 2>&1; then
            methodology=$(get_active_methodology "$project_type")
        else
            case "$project_type" in
                research)       methodology="research" ;;
                software|deployment|optimization) methodology="sdlc" ;;
                *)              methodology="both" ;;
            esac
        fi

        if command -v yq &> /dev/null; then
            yq eval ".active_methodology = \"${methodology}\"" -i .workflow/state.yaml 2>/dev/null || true
        else
            if grep -q "^active_methodology:" .workflow/state.yaml 2>/dev/null; then
                sed -i "s|^active_methodology:.*|active_methodology: \"${methodology}\"|" .workflow/state.yaml
            else
                echo "active_methodology: \"${methodology}\"" >> .workflow/state.yaml
            fi
        fi
        echo -e "${GREEN}✓${NC} Set active methodology: ${methodology}"
    fi

    # Set default_agent in config.yaml
    if [[ -f ".workflow/config.yaml" ]]; then
        local default_agent
        if declare -f get_default_agent > /dev/null 2>&1; then
            default_agent=$(get_default_agent "$project_type")
        else
            case "$project_type" in
                research|ml|llm) default_agent="researcher" ;;
                software)        default_agent="architect" ;;
                deployment)      default_agent="deployer" ;;
                optimization)    default_agent="optimizer" ;;
                *)               default_agent="architect" ;;
            esac
        fi

        if command -v yq &> /dev/null; then
            yq eval ".agents.default_agent = \"${default_agent}\"" -i .workflow/config.yaml 2>/dev/null || true
        else
            if grep -q "default_agent:" .workflow/config.yaml 2>/dev/null; then
                sed -i "s|default_agent:.*|default_agent: \"${default_agent}\"|" .workflow/config.yaml
            else
                # Insert after auto_select line
                sed -i "/auto_select:/a\\  default_agent: \"${default_agent}\"" .workflow/config.yaml
            fi
        fi
        echo -e "${GREEN}✓${NC} Set default agent: ${default_agent}"
    fi
}

#######################################
# Recommend initial agent and skills
#######################################
recommend_setup() {
    echo ""
    echo -e "${BOLD}💡 Recommendations for '${DETECTED_TYPE}' project:${NC}"
    echo ""

    case "$DETECTED_TYPE" in
        research)
            echo "  📚 Suggested first agent: ${BOLD}researcher${NC}"
            echo "  🛠️  Useful skills: literature_review, experimental_design, statistical_validation"
            echo "  📖 Next steps:"
            echo "     1. ./scripts/activate_agent.sh researcher"
            echo "     2. ./scripts/enable_skill.sh literature_review"
            echo "     3. Define research questions and methodology"
            ;;
        ml|llm)
            echo "  🤖 Suggested first agent: ${BOLD}researcher${NC} → ${BOLD}implementer${NC}"
            echo "  🛠️  Useful skills: model_development, training_pipeline, evaluation"
            echo "  📖 Next steps:"
            echo "     1. ./scripts/activate_agent.sh researcher"
            echo "     2. Define ML problem and success metrics"
            echo "     3. Transition to implementer for model development"
            ;;
        software)
            echo "  🏗️  Suggested first agent: ${BOLD}architect${NC}"
            echo "  🛠️  Useful skills: api_design, code_review, testing"
            echo "  📖 Next steps:"
            echo "     1. ./scripts/activate_agent.sh architect"
            echo "     2. Design system architecture"
            echo "     3. Transition to implementer for development"
            ;;
        deployment)
            echo "  🚀 Suggested first agent: ${BOLD}deployer${NC}"
            echo "  🛠️  Useful skills: containerization, ci_cd, monitoring"
            echo "  📖 Next steps:"
            echo "     1. ./scripts/activate_agent.sh deployer"
            echo "     2. ./scripts/enable_skill.sh containerization ci_cd"
            echo "     3. Set up deployment pipeline"
            ;;
        optimization)
            echo "  ⚡ Suggested first agent: ${BOLD}optimizer${NC}"
            echo "  🛠️  Useful skills: profiling, quantization, pruning"
            echo "  📖 Next steps:"
            echo "     1. ./scripts/activate_agent.sh optimizer"
            echo "     2. Profile baseline performance"
            echo "     3. Apply optimization techniques"
            ;;
        hybrid|*)
            echo "  🔄 Suggested first agent: ${BOLD}architect${NC}"
            echo "  🛠️  Useful skills: Depends on your specific needs"
            echo "  📖 Next steps:"
            echo "     1. Review project requirements"
            echo "     2. Choose appropriate workflow template"
            echo "     3. Activate relevant agent"
            ;;
    esac

    echo ""
    echo -e "${GREEN}✓${NC} Configuration complete!"
}

#######################################
# Main execution
#######################################
main() {
    parse_args "$@"

    echo "═══════════════════════════════════════════════════════════════"
    echo "   Universal Workflow System - Project Detection"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Change to project root if we're in scripts directory
    cd "$PROJECT_ROOT"

    # Check existing configuration
    if [[ "$AUTO_MODE" != "true" ]] && [[ "$FORCE_UPDATE" != "true" ]]; then
        check_existing_config
    fi

    # Run detection
    run_detection

    # Confirm with user (unless auto mode)
    confirm_detection

    # Update configuration files
    update_configuration

    # Apply methodology routing and default agent
    apply_configuration

    # Show recommendations
    recommend_setup
}

# Run main function
main "$@"
