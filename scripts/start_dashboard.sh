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
export UWS_DASHBOARD_PORT="$PORT"
echo "Starting UWS Dashboard for ${UWS_PROJECT_ROOT}..."
echo "Access at: http://localhost:${PORT} (WebSocket: port ${UWS_DASHBOARD_WS_PORT:-$((PORT + 1))})"
echo "It runs in the foreground: press Ctrl+C to stop it."

# Stop an earlier dashboard on this port only: dashboards of other projects may be
# running on other ports. Its PID is in a per-user, per-port file.
PIDFILE="${TMPDIR:-/tmp}/uws-dashboard-$(id -u)-${PORT}.pid"
old_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
if [[ "$old_pid" =~ ^[0-9]+$ ]] && ps -p "$old_pid" -o args= 2>/dev/null | grep -q "dashboard_server.py"; then
    kill "$old_pid" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$old_pid" 2>/dev/null || break
        sleep 0.3
    done
fi
echo "$$" > "$PIDFILE"

# -u: unbuffered, so the server's banner and errors show up at once in logs too
exec python3 -u "${SCRIPT_DIR}/dashboard_server.py"
