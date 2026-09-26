#!/bin/bash
#
# Start the UWS Dashboard: a local review/PM page (change-request inbox,
# issue board, active agent) for the current project.
#
# Usage: ./scripts/start_dashboard.sh      (or: uws dashboard)
#
# Environment:
#   UWS_DASHBOARD_PORT     HTTP port (default 8080; WebSocket uses port + 1)
#   UWS_PROJECT_ROOT       project to show (default: the resolved project,
#                          i.e. the directory holding .workflow/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the project: WORKFLOW_DIR (set by bin/uws) -> CWD -> git root
source "${SCRIPT_DIR}/lib/resolve_project.sh"
UWS_PROJECT_ROOT="${UWS_PROJECT_ROOT:-$(cd "$(dirname "$WORKFLOW_DIR")" && pwd)}"
export UWS_PROJECT_ROOT

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required for the UWS Dashboard." >&2
    exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/../dashboard/index.html" ]]; then
    echo "Error: dashboard files not found at ${SCRIPT_DIR}/../dashboard" >&2
    exit 1
fi

PORT="${UWS_DASHBOARD_PORT:-8080}"
echo "Starting UWS Dashboard for ${UWS_PROJECT_ROOT}..."
echo "Access at: http://localhost:${PORT}"

# Stop an earlier instance so the port is free
pkill -f "${SCRIPT_DIR}/dashboard_server.py" 2>/dev/null || true

exec python3 "${SCRIPT_DIR}/dashboard_server.py"
