#!/bin/bash
# UWS Replication Package - Benchmark Runner
#
# This script runs all benchmarks and generates results for paper verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================================"
echo "UWS Replication Benchmark Suite"
echo "============================================================"
echo "Timestamp: $(date -Iseconds)"
echo "Project Root: ${PROJECT_ROOT}"
echo ""

# Check dependencies
echo "Checking dependencies..."
command -v git >/dev/null 2>&1 || { echo "Error: git not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found"; exit 1; }
command -v bash >/dev/null 2>&1 || { echo "Error: bash not found"; exit 1; }
echo "All dependencies found."
echo ""

# Run baseline benchmark
echo "============================================================"
echo "Running Baseline Benchmark (30 trials)"
echo "============================================================"
cd "${PROJECT_ROOT}"
python3 tests/benchmarks/baseline_benchmark.py

# Run UWS benchmark
echo ""
echo "============================================================"
echo "Running UWS Performance Benchmark"
echo "============================================================"
./tests/benchmarks/benchmark_runner.sh

# Generate analysis
echo ""
echo "============================================================"
echo "Generating Statistical Analysis"
echo "============================================================"
python3 tests/benchmarks/analyze_results.py

# Summary
echo ""
echo "============================================================"
echo "REPLICATION COMPLETE"
echo "============================================================"
echo ""
echo "Results saved to:"
echo "  - artifacts/benchmark_results/baselines/"
echo "  - artifacts/benchmark_results/raw/"
echo "  - artifacts/benchmark_results/processed/"
echo "  - paper/tables/"
echo ""
echo "Verify results match expected ranges in replication/README.md"
