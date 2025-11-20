#!/bin/bash

# Test Runner Script
# Runs all BATS tests for the Universal Workflow System

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
TEST_DIR="tests"
VERBOSE=false
CATEGORY="all"
PARALLEL=false

# Show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -v, --verbose      Show verbose output"
    echo "  -c, --category     Run specific test category (unit|integration|all)"
    echo "  -p, --parallel     Run tests in parallel"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run all tests"
    echo "  $0 -v              # Run with verbose output"
    echo "  $0 -c unit         # Run only unit tests"
    echo "  $0 -c integration  # Run only integration tests"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--category)
            CATEGORY="$2"
            shift 2
            ;;
        -p|--parallel)
            PARALLEL=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            ;;
    esac
done

# Check if BATS is installed
if ! command -v bats &> /dev/null; then
    echo -e "${RED}Error: BATS is not installed${NC}"
    echo ""
    echo "Install BATS:"
    echo "  npm install -g bats"
    echo "  # or"
    echo "  git clone https://github.com/bats-core/bats-core.git"
    echo "  cd bats-core"
    echo "  sudo ./install.sh /usr/local"
    exit 1
fi

# Check if test directory exists
if [ ! -d "$TEST_DIR" ]; then
    echo -e "${RED}Error: Test directory not found: $TEST_DIR${NC}"
    exit 1
fi

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Universal Workflow System - Test Runner${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
echo ""

# Determine which tests to run
TEST_PATHS=()

case $CATEGORY in
    unit)
        echo -e "${CYAN}Running unit tests...${NC}"
        TEST_PATHS+=("$TEST_DIR/unit")
        ;;
    integration)
        echo -e "${CYAN}Running integration tests...${NC}"
        TEST_PATHS+=("$TEST_DIR/integration")
        ;;
    all)
        echo -e "${CYAN}Running all tests...${NC}"
        TEST_PATHS+=("$TEST_DIR/unit" "$TEST_DIR/integration")
        ;;
    *)
        echo -e "${RED}Unknown category: $CATEGORY${NC}"
        echo "Valid categories: unit, integration, all"
        exit 1
        ;;
esac

# Build BATS command
BATS_CMD="bats"

if [ "$VERBOSE" = true ]; then
    BATS_CMD="$BATS_CMD --verbose-run"
fi

if [ "$PARALLEL" = true ]; then
    BATS_CMD="$BATS_CMD --jobs 4"
fi

# Run tests
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

for test_path in "${TEST_PATHS[@]}"; do
    if [ -d "$test_path" ]; then
        echo -e "${YELLOW}Testing: $test_path${NC}"
        echo ""

        # Count tests
        test_files=$(find "$test_path" -name "*.bats" 2>/dev/null)

        if [ -z "$test_files" ]; then
            echo -e "${YELLOW}No test files found in $test_path${NC}"
            continue
        fi

        # Run tests and capture results
        if $BATS_CMD "$test_path"/*.bats; then
            echo -e "${GREEN}✓ Tests passed in $test_path${NC}"
            echo ""
        else
            echo -e "${RED}✗ Some tests failed in $test_path${NC}"
            echo ""
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo -e "${YELLOW}Skipping missing directory: $test_path${NC}"
    fi
done

echo -e "${BLUE}═══════════════════════════════════════════════${NC}"

if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All tests passed!${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}${BOLD}Some tests failed${NC}"
    echo ""
    exit 1
fi
