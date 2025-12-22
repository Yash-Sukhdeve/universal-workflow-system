#!/bin/bash
# E2E Test Runner with Clean Server Management
# Ensures servers are in clean state before running tests

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== E2E Test Runner ===${NC}"

# Function to kill all servers
cleanup_servers() {
    echo -e "${YELLOW}Cleaning up existing servers...${NC}"
    pkill -f "mock_server.py" 2>/dev/null || true
    pkill -f "vite" 2>/dev/null || true
    sleep 2
}

# Function to check if port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || ss -tlnp 2>/dev/null | grep -q ":$port "; then
        return 0  # Port in use
    else
        return 1  # Port free
    fi
}

# Cleanup on exit
trap cleanup_servers EXIT INT TERM

# Initial cleanup
cleanup_servers

# Verify ports are free
echo -e "${YELLOW}Verifying ports 5173 and 8000 are free...${NC}"
if check_port 5173; then
    echo -e "${RED}Port 5173 still in use after cleanup!${NC}"
    exit 1
fi
if check_port 8000; then
    echo -e "${RED}Port 8000 still in use after cleanup!${NC}"
    exit 1
fi

echo -e "${GREEN}Ports are free. Starting tests...${NC}"

# Run Playwright tests
# Playwright will start the servers via webServer config
./node_modules/.bin/playwright test "$@"

# Capture exit code
EXIT_CODE=$?

# Cleanup will happen via trap
echo -e "${YELLOW}Tests completed with exit code: ${EXIT_CODE}${NC}"
exit $EXIT_CODE
