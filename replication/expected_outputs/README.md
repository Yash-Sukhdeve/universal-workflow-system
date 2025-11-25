# Expected Outputs for Replication Verification

This directory contains reference values for validating replication results.

## Benchmark Expected Results

### 1. Baseline Benchmark (`baseline_benchmark.py`)

| Metric | Expected | Acceptable Range |
|--------|----------|------------------|
| UWS Context Recovery | 44ms | 30-80ms |
| LangGraph State Restore | 0.06ms | 0.03-0.2ms |
| Git-Only Log Reading | 6.6ms | 3-15ms |

**Statistical Requirements:**
- 30 trials minimum
- 95% confidence intervals reported
- Cliff's delta for effect sizes

### 2. Repository Mining Study (`repository_mining_study.py`)

| Metric | Expected | Acceptable |
|--------|----------|------------|
| Projects Tested | 10 | 10 |
| Setup Success Rate | 80% | 70-100% |
| Checkpoint Success | 100%* | 95-100% |
| Recovery Success | 100%* | 95-100% |

*For successfully setup projects

### 3. Ablation Study (`ablation_study.py`)

| Variant | Expected Recovery | Acceptable Range |
|---------|-------------------|------------------|
| UWS-Full | 26.5ms | 20-40ms |
| UWS-NoCheckpoint | 18.3ms | 15-25ms |
| UWS-NoAgents | 26.4ms | 20-40ms |
| UWS-NoSkills | 26.3ms | 20-40ms |
| UWS-Minimal | 18.4ms | 15-25ms |

### 4. Sensitivity Analysis (`sensitivity_analysis.py`)

| Checkpoints | Expected | Acceptable Range |
|-------------|----------|------------------|
| 5 | 28.9ms | 20-40ms |
| 25 | 28.7ms | 20-40ms |
| 50 | 29.0ms | 20-40ms |
| 100 | 28.8ms | 20-40ms |

**Expected Variation:** < 5% across checkpoint counts

### 5. Test Suite (`bats tests/`)

| Category | Expected Pass Rate |
|----------|-------------------|
| Unit Tests | > 85% |
| Integration Tests | > 95% |
| End-to-End Tests | > 95% |
| **Overall** | **> 90%** |

## Verification Checklist

After running benchmarks, verify:

- [ ] All JSON result files created in `artifacts/benchmark_results/`
- [ ] Mean values within acceptable ranges
- [ ] 95% confidence intervals reported
- [ ] Cliff's delta effect sizes calculated
- [ ] No errors in benchmark scripts
- [ ] Test suite passes > 90%

## Variance Factors

Results may vary due to:
- **Hardware**: Different CPU speeds affect timing
- **System Load**: Background processes add variance
- **File System**: SSD vs HDD affects I/O times
- **OS Caching**: Cold vs warm runs differ

For best results:
1. Run on idle system
2. Close unnecessary applications
3. Use Docker container for consistency
4. Run multiple trials (30+)

## Troubleshooting

### Results significantly different?

1. Check system load: `top` or `htop`
2. Verify no background processes
3. Run warmup trials before measurement
4. Increase trial count to 50+

### Benchmark script fails?

1. Check dependencies: `pip install -r requirements.txt`
2. Verify git is installed: `git --version`
3. Ensure scripts are executable: `chmod +x scripts/*.sh`
