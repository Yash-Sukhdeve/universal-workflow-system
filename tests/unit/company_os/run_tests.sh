#!/bin/bash
# Test Runner Script for Company OS Unit Tests
#
# This script provides convenient commands for running the Company OS unit tests
# with various options and configurations.

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Print info
print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Default values
COVERAGE=false
VERBOSE=false
SPECIFIC_FILE=""
SPECIFIC_TEST=""
MARKERS=""
HTML_REPORT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --coverage|-c)
            COVERAGE=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --html)
            HTML_REPORT=true
            shift
            ;;
        --file|-f)
            SPECIFIC_FILE="$2"
            shift 2
            ;;
        --test|-t)
            SPECIFIC_TEST="$2"
            shift 2
            ;;
        --markers|-m)
            MARKERS="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -c, --coverage        Run with coverage report"
            echo "  -v, --verbose         Verbose output"
            echo "  --html                Generate HTML coverage report"
            echo "  -f, --file FILE       Run specific test file"
            echo "  -t, --test TEST       Run specific test"
            echo "  -m, --markers MARKER  Run tests with specific marker"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --coverage --verbose"
            echo "  $0 --file test_event_store.py"
            echo "  $0 --test test_authenticate_success"
            echo "  $0 --markers asyncio"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Run with --help to see available options"
            exit 1
            ;;
    esac
done

# Build pytest command
PYTEST_CMD="pytest tests/unit/company_os/"

# Add specific file if provided
if [ -n "$SPECIFIC_FILE" ]; then
    PYTEST_CMD="pytest tests/unit/company_os/$SPECIFIC_FILE"
fi

# Add specific test if provided
if [ -n "$SPECIFIC_TEST" ]; then
    PYTEST_CMD="$PYTEST_CMD -k $SPECIFIC_TEST"
fi

# Add markers if provided
if [ -n "$MARKERS" ]; then
    PYTEST_CMD="$PYTEST_CMD -m $MARKERS"
fi

# Add verbose flag
if [ "$VERBOSE" = true ]; then
    PYTEST_CMD="$PYTEST_CMD -v"
else
    PYTEST_CMD="$PYTEST_CMD -q"
fi

# Add coverage flags
if [ "$COVERAGE" = true ]; then
    PYTEST_CMD="$PYTEST_CMD --cov=company_os.core --cov-report=term-missing"

    if [ "$HTML_REPORT" = true ]; then
        PYTEST_CMD="$PYTEST_CMD --cov-report=html"
    fi
fi

# Print what we're running
print_header "Company OS Unit Test Runner"
print_info "Running: $PYTEST_CMD"
echo ""

# Run the tests
if $PYTEST_CMD; then
    echo ""
    print_success "All tests passed!"

    # Open HTML coverage report if generated
    if [ "$COVERAGE" = true ] && [ "$HTML_REPORT" = true ]; then
        if [ -f "htmlcov/index.html" ]; then
            print_info "Coverage report generated: htmlcov/index.html"

            # Try to open in browser (OS-specific)
            if command -v xdg-open &> /dev/null; then
                xdg-open htmlcov/index.html
            elif command -v open &> /dev/null; then
                open htmlcov/index.html
            else
                print_info "Open htmlcov/index.html in your browser to view coverage"
            fi
        fi
    fi

    exit 0
else
    echo ""
    print_error "Some tests failed!"
    exit 1
fi
