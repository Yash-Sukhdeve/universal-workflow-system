# UWS Replication Package

**Paper**: UWS: A Git-Native Workflow System for Context-Resilient AI-Assisted Development

**Venue**: FSE 2026

**DOI**: [To be assigned upon Zenodo upload]

## Contents

```
replication/
├── README.md           # This file
├── requirements.txt    # Python dependencies (pinned versions)
├── Dockerfile          # Reproducible environment
├── run_benchmarks.sh   # Main benchmark script
├── expected_outputs/   # Expected benchmark results
└── data/               # Raw benchmark data from paper
```

## System Requirements

- **OS**: Linux (Ubuntu 20.04+ recommended) or macOS 12+
- **Shell**: Bash 4.0+
- **Git**: 2.25+
- **Python**: 3.9+
- **Memory**: 4GB RAM minimum
- **Disk**: 500MB free space

## Quick Start (Docker)

The easiest way to reproduce results is using Docker:

```bash
# Build the container
docker build -t uws-replication .

# Run all benchmarks
docker run -v $(pwd)/results:/results uws-replication

# Results will be in ./results/
```

## Manual Setup

### 1. Clone Repository

```bash
git clone https://github.com/[ANONYMOUS]/universal-workflow-system.git
cd universal-workflow-system
```

### 2. Install Dependencies

```bash
# System dependencies (Ubuntu)
sudo apt-get update
sudo apt-get install -y git bash bc

# Python dependencies
pip install -r replication/requirements.txt
```

### 3. Run Benchmarks

```bash
# Run all benchmarks (30 trials each)
./replication/run_benchmarks.sh

# Run specific benchmarks
python3 tests/benchmarks/baseline_benchmark.py  # Baseline comparisons
./tests/benchmarks/benchmark_runner.sh          # UWS performance
```

### 4. Analyze Results

```bash
# Generate statistical analysis
python3 tests/benchmarks/analyze_results.py

# Results appear in:
# - artifacts/benchmark_results/baselines/
# - paper/tables/
```

## Expected Results

The benchmarks should produce results within these ranges:

| Metric | Expected | Acceptable Range |
|--------|----------|------------------|
| UWS Context Recovery | 40-50ms | 30-80ms |
| UWS Checkpoint Creation | 35-45ms | 25-60ms |
| LangGraph State Restore | 0.05-0.1ms | 0.03-0.2ms |
| Git-Only Log Reading | 5-10ms | 3-15ms |

Variance may occur due to:
- Different hardware configurations
- System load during benchmarks
- File system caching effects

## Reproducing Paper Results

### RQ1: Functionality

```bash
# Run test suite
bats tests/unit/*.bats tests/integration/*.bats tests/system/*.bats

# Expected: 164/175 tests passing (94%)
```

### RQ2: Performance

```bash
# Run baseline benchmark
python3 tests/benchmarks/baseline_benchmark.py

# Results in: artifacts/benchmark_results/baselines/
```

### RQ3: Reliability

```bash
# Run reliability tests
bats tests/benchmarks/test_performance.bats

# Expected: 100% reliability for normal operations
```

## Verification Checklist

After running benchmarks, verify:

- [ ] `artifacts/benchmark_results/baselines/baseline_comparison_*.json` exists
- [ ] UWS recovery time is under 100ms
- [ ] Statistical analysis shows Cliff's delta values
- [ ] 95% confidence intervals are reported
- [ ] At least 30 trials per condition

## Troubleshooting

### "yq not found" warning

This is non-critical. Install yq for better performance:
```bash
sudo apt-get install yq
# or
pip install yq
```

### "Permission denied" errors

```bash
chmod +x scripts/*.sh tests/benchmarks/*.sh replication/*.sh
```

### Python import errors

```bash
pip install --upgrade -r replication/requirements.txt
```

## Hardware Used in Paper

- **CPU**: Intel Core i7-10700 (8 cores)
- **RAM**: 32GB DDR4
- **Storage**: NVMe SSD
- **OS**: Ubuntu 22.04 LTS
- **Git**: 2.49.0
- **Bash**: 5.1.16

## Contact

For questions about replication, open an issue on the repository or contact the authors via the conference submission system.

## License

This replication package is released under the MIT License.
