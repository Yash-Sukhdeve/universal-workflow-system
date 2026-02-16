#!/bin/bash
# Universal Workflow System - Test Runner
# Runs all BATS tests and generates reports

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Test categories
CATEGORIES=("unit" "integration" "system")

# Results directory
RESULTS_DIR="${PROJECT_ROOT}/test-results"
mkdir -p "${RESULTS_DIR}"

# ============================================================================
# FUNCTIONS
# ============================================================================

print_header() {
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}        Universal Workflow System - Test Suite                   ${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

check_bats() {
    if ! command -v bats &> /dev/null; then
        echo -e "${RED}Error: BATS (Bash Automated Testing System) is not installed.${NC}"
        echo ""
        echo "Install BATS using one of these methods:"
        echo ""
        echo "  Ubuntu/Debian:"
        echo "    sudo apt-get install bats"
        echo ""
        echo "  macOS (Homebrew):"
        echo "    brew install bats-core"
        echo ""
        echo "  npm (cross-platform):"
        echo "    npm install -g bats"
        echo ""
        echo "  From source:"
        echo "    git clone https://github.com/bats-core/bats-core.git"
        echo "    cd bats-core && sudo ./install.sh /usr/local"
        echo ""
        exit 1
    fi
    echo -e "${GREEN}✓${NC} BATS installed: $(bats --version)"
}

check_shellcheck() {
    if command -v shellcheck &> /dev/null; then
        echo -e "${GREEN}✓${NC} ShellCheck installed: $(shellcheck --version | head -2 | tail -1)"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} ShellCheck not installed (optional, for linting)"
        return 1
    fi
}

run_shellcheck() {
    echo -e "${BLUE}Running ShellCheck on scripts...${NC}"

    local errors=0
    local checked=0

    while IFS= read -r -d '' script; do
        checked=$((checked + 1))
        if ! shellcheck -x -e SC1091 "${script}" > "${RESULTS_DIR}/shellcheck.log" 2>&1; then
            echo -e "  ${RED}✗${NC} ${script}"
            errors=$((errors + 1))
        else
            echo -e "  ${GREEN}✓${NC} ${script}"
        fi
    done < <(find "${PROJECT_ROOT}/scripts" -name "*.sh" -print0)

    echo ""
    if [[ ${errors} -eq 0 ]]; then
        echo -e "${GREEN}ShellCheck: All ${checked} scripts passed${NC}"
    else
        echo -e "${YELLOW}ShellCheck: ${errors}/${checked} scripts have warnings${NC}"
    fi
    echo ""
}

run_test_category() {
    local category="$1"
    local test_dir="${SCRIPT_DIR}/${category}"

    if [[ ! -d "${test_dir}" ]]; then
        echo -e "${YELLOW}⚠${NC} No ${category} tests found"
        return 0
    fi

    local test_files
    test_files=$(find "${test_dir}" -name "*.bats" 2>/dev/null | wc -l)

    if [[ ${test_files} -eq 0 ]]; then
        echo -e "${YELLOW}⚠${NC} No test files in ${category}/"
        return 0
    fi

    echo -e "${BLUE}Running ${category} tests (${test_files} files)...${NC}"
    echo ""

    local output_file="${RESULTS_DIR}/${category}_results.tap"

    if bats --tap "${test_dir}"/*.bats > "${output_file}" 2>&1; then
        echo -e "${GREEN}✓${NC} ${category} tests passed"
        return 0
    else
        echo -e "${RED}✗${NC} ${category} tests failed"
        cat "${output_file}"
        return 1
    fi
}

count_tests() {
    local category="$1"
    local test_dir="${SCRIPT_DIR}/${category}"

    if [[ ! -d "${test_dir}" ]]; then
        echo "0"
        return
    fi

    grep -r "^@test" "${test_dir}"/*.bats 2>/dev/null | wc -l || echo "0"
}

generate_summary() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}                        Test Summary                             ${NC}"
    echo -e "${BOLD}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    local total=0
    local passed=0
    local failed=0

    for category in "${CATEGORIES[@]}"; do
        local count
        count=$(count_tests "${category}")
        total=$((total + count))

        local result_file="${RESULTS_DIR}/${category}_results.tap"
        if [[ -f "${result_file}" ]]; then
            local cat_passed
            cat_passed=$(grep -c "^ok" "${result_file}" 2>/dev/null) || cat_passed=0
            local cat_failed
            cat_failed=$(grep -c "^not ok" "${result_file}" 2>/dev/null) || cat_failed=0
            passed=$((passed + cat_passed))
            failed=$((failed + cat_failed))

            if [[ ${cat_failed} -eq 0 ]]; then
                echo -e "  ${GREEN}✓${NC} ${category}: ${cat_passed} passed"
            else
                echo -e "  ${RED}✗${NC} ${category}: ${cat_passed} passed, ${cat_failed} failed"
            fi
        else
            echo -e "  ${YELLOW}-${NC} ${category}: not run"
        fi
    done

    echo ""
    echo -e "${BOLD}────────────────────────────────────────────────────────────────${NC}"

    if [[ ${failed} -eq 0 && ${passed} -gt 0 ]]; then
        echo -e "  ${GREEN}${BOLD}All tests passed: ${passed}/${total}${NC}"
    elif [[ ${passed} -eq 0 && ${failed} -eq 0 ]]; then
        echo -e "  ${YELLOW}No tests were run${NC}"
    else
        echo -e "  ${RED}${BOLD}Tests failed: ${failed}/${total}${NC}"
    fi

    echo ""
    echo -e "Results saved to: ${RESULTS_DIR}/"
    echo ""
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    local run_lint=false
    local category_filter=""
    local verbose=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--lint)
                run_lint=true
                shift
                ;;
            -c|--category)
                category_filter="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  -l, --lint        Run ShellCheck linting"
                echo "  -c, --category    Run specific category (unit, integration, system)"
                echo "  -v, --verbose     Verbose output"
                echo "  -h, --help        Show this help"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    print_header

    # Check dependencies
    check_bats
    local has_shellcheck=false
    if check_shellcheck; then
        has_shellcheck=true
    fi
    echo ""

    # Run linting if requested
    if [[ "${run_lint}" == "true" && "${has_shellcheck}" == "true" ]]; then
        run_shellcheck
    fi

    # Run tests
    local exit_code=0

    if [[ -n "${category_filter}" ]]; then
        # Run specific category
        if ! run_test_category "${category_filter}"; then
            exit_code=1
        fi
    else
        # Run all categories
        for category in "${CATEGORIES[@]}"; do
            if ! run_test_category "${category}"; then
                exit_code=1
            fi
            echo ""
        done
    fi

    # Generate summary
    generate_summary

    exit ${exit_code}
}

main "$@"
