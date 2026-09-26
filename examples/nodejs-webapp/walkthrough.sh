#!/bin/bash
#
# UWS Node.js Webapp - Automated Walkthrough
#
# Creates a temp directory, initializes UWS, and walks through
# the full SDLC workflow with agent handoffs and checkpoints.
#
# Each handoff is `orchestrate.sh dispatch`: it picks the subagent that owns
# the current phase, writes its brief to workspace/<role>/TASK.md and records
# it as the active agent. In Claude Code the uws-<role> subagent then does the
# work; this demo only shows the bookkeeping.
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

step "1. Initializing UWS for a software project"
"$SCRIPTS/init_workflow.sh" software < /dev/null 2>&1 || true
info "Project initialized in $DEMO_DIR"

step "2. Starting SDLC workflow"
"$SCRIPTS/sdlc.sh" start 2>&1 || true
"$SCRIPTS/sdlc.sh" status 2>&1

step "3. Phase 1: Requirements - Dispatching to the researcher subagent"
"$SCRIPTS/orchestrate.sh" dispatch "Gather requirements and user stories" 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Requirements gathered" 2>&1 || true
info "Checkpoint created for requirements phase"

step "4. Phase 2: Design - Dispatching to the architect subagent"
"$SCRIPTS/sdlc.sh" next 2>&1 || true
"$SCRIPTS/sdlc.sh" status 2>&1
"$SCRIPTS/orchestrate.sh" dispatch "Design the API, data model and components" 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "System design complete" 2>&1 || true

step "5. Phase 3: Implementation - Dispatching to the implementer subagent"
"$SCRIPTS/sdlc.sh" next 2>&1 || true
"$SCRIPTS/orchestrate.sh" dispatch "Implement auth service and dashboard UI" 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Core features implemented" 2>&1 || true

step "6. Phase 4: Verification - Dispatching to the experimenter subagent"
"$SCRIPTS/sdlc.sh" next 2>&1 || true
"$SCRIPTS/orchestrate.sh" dispatch "Verify requirements end to end" 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "All tests passing" 2>&1 || true

step "7. Phase 5: Deployment - Dispatching to the deployer subagent"
"$SCRIPTS/sdlc.sh" next 2>&1 || true
"$SCRIPTS/orchestrate.sh" dispatch "Deploy to staging, then production" 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Deployed to production" 2>&1 || true

step "8. Phase 6: Maintenance - Deployer subagent keeps watch"
"$SCRIPTS/sdlc.sh" next 2>&1 || true
"$SCRIPTS/orchestrate.sh" dispatch "Monitor production and triage issues" 2>&1 || true
"$SCRIPTS/checkpoint.sh" create "Maintenance mode active" 2>&1 || true

step "9. Final status"
"$SCRIPTS/status.sh" 2>&1
echo ""
"$SCRIPTS/checkpoint.sh" list 2>&1

step "Demo complete!"
info "All 6 SDLC phases traversed with agent handoffs."
info "Temp directory will be cleaned up automatically."
