#!/bin/bash
#
# UWS Python ML Project - Automated Walkthrough
#
# Creates a temp directory, initializes UWS, and walks through
# the full research workflow with agent handoffs and checkpoints.
#

set -euo pipefail

# Find UWS root (parent of examples/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UWS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPTS="$UWS_ROOT/scripts"

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

step() {
    echo ""
    echo -e "${BOLD}${CYAN}>> $1${NC}"
    echo ""
}

info() {
    echo -e "   ${GREEN}$1${NC}"
}

# Create temp project
DEMO_DIR="$(mktemp -d)"
trap 'rm -rf "$DEMO_DIR"' EXIT

cd "$DEMO_DIR"
git init --quiet
git config user.email "demo@example.com"
git config user.name "Demo User"

step "1. Initializing UWS for a research project"
"$SCRIPTS/init_workflow.sh" research < /dev/null 2>&1 || true
info "Project initialized in $DEMO_DIR"

step "2. Starting research workflow"
"$SCRIPTS/research.sh" start 2>&1 || true
"$SCRIPTS/research.sh" status 2>&1

step "3. Phase 1: Hypothesis - Activating researcher agent"
"$SCRIPTS/activate_agent.sh" researcher 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Hypothesis defined" 2>&1 || true
info "Checkpoint created for hypothesis phase"

step "4. Phase 2: Literature Review"
"$SCRIPTS/research.sh" next 2>&1 || true
"$SCRIPTS/research.sh" status 2>&1
"$SCRIPTS/checkpoint.sh" create "Literature review complete" 2>&1 || true

step "5. Phase 3: Experiment Design - Switching to experimenter"
"$SCRIPTS/research.sh" next 2>&1 || true
"$SCRIPTS/activate_agent.sh" experimenter 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Experiment designed" 2>&1 || true

step "6. Phase 4: Data Collection"
"$SCRIPTS/research.sh" next 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Data collected" 2>&1 || true

step "7. Phase 5: Analysis - Back to researcher"
"$SCRIPTS/research.sh" next 2>&1 || true
"$SCRIPTS/activate_agent.sh" researcher 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Analysis complete" 2>&1 || true

step "8. Phase 6: Peer Review"
"$SCRIPTS/research.sh" next 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Peer review done" 2>&1 || true

step "9. Phase 7: Publication - Switching to documenter"
"$SCRIPTS/research.sh" next 2>&1 || true
"$SCRIPTS/activate_agent.sh" documenter 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Paper submitted" 2>&1 || true

step "10. Final status"
"$SCRIPTS/status.sh" 2>&1
echo ""
"$SCRIPTS/checkpoint.sh" list 2>&1

step "Demo complete!"
info "All 7 research phases traversed with agent handoffs."
info "Temp directory will be cleaned up automatically."
