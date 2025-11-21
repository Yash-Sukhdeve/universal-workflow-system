#!/bin/bash

# List Agents Script
# Display all available agents and their capabilities

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check if workflow is initialized
if [ ! -d .workflow ]; then
    echo -e "${RED}Error: Workflow not initialized. Run init_workflow.sh first${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}     Available Workflow Agents${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Check if registry exists
if [ ! -f .workflow/agents/registry.yaml ]; then
    echo -e "${YELLOW}No agent registry found${NC}"
    exit 1
fi

# List each agent
for agent in researcher architect implementer experimenter optimizer deployer documenter; do
    if grep -q "$agent:" .workflow/agents/registry.yaml; then
        echo -e "${GREEN}${BOLD}$agent${NC}"

        # Get description
        desc=$(grep -A 5 "$agent:" .workflow/agents/registry.yaml | grep "description:" | cut -d':' -f2- | xargs)
        if [ -n "$desc" ]; then
            echo -e "  ${CYAN}Description:${NC} $desc"
        fi

        # Get workspace
        workspace=$(grep -A 5 "$agent:" .workflow/agents/registry.yaml | grep "workspace:" | cut -d':' -f2- | xargs)
        if [ -n "$workspace" ]; then
            echo -e "  ${CYAN}Workspace:${NC} $workspace"
        fi

        echo ""
    fi
done

# Show active agent if any
if [ -f .workflow/agents/active.yaml ]; then
    active=$(grep "^agent:" .workflow/agents/active.yaml | cut -d':' -f2 | xargs)
    echo -e "${YELLOW}Currently active: ${GREEN}$active${NC}"
fi
