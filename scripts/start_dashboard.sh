#!/bin/bash
# Start the UWS Dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "Starting UWS Dashboard..."
echo "Access at: http://localhost:8080"

# Kill existing instance if any
pkill -f dashboard_server.py || true

# Start server
python3 scripts/dashboard_server.py
