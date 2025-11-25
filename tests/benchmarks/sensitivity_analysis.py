#!/usr/bin/env python3
"""
Sensitivity Analysis for FSE 2026 Paper

Tests UWS performance stability across:
1. Different checkpoint counts (5, 25, 100)
2. Different state file sizes
"""

import json
import os
import subprocess
import tempfile
import shutil
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List
import statistics

PROJECT_ROOT = Path(__file__).parent.parent.parent
RESULTS_DIR = PROJECT_ROOT / "artifacts" / "benchmark_results" / "sensitivity"

NUM_TRIALS = 15  # Fewer trials for sensitivity


def calculate_statistics(data: List[float]) -> Dict:
    if not data:
        return {}
    n = len(data)
    mean = statistics.mean(data)
    median = statistics.median(data)
    std_dev = statistics.stdev(data) if n > 1 else 0
    se = std_dev / (n ** 0.5) if n > 1 else 0
    return {
        "n": n,
        "mean": round(mean, 3),
        "median": round(median, 3),
        "std_dev": round(std_dev, 3),
        "ci_95_lower": round(mean - 1.96 * se, 3),
        "ci_95_upper": round(mean + 1.96 * se, 3)
    }


def test_checkpoint_count(count: int) -> Dict:
    """Test recovery with different checkpoint counts"""
    recovery_times = []

    for trial in range(NUM_TRIALS):
        tmp_dir = Path(tempfile.mkdtemp())
        try:
            os.chdir(tmp_dir)

            subprocess.run(["git", "init", "--quiet"], check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "sens@test.com"], check=True, capture_output=True)
            subprocess.run(["git", "config", "user.name", "Sensitivity"], check=True, capture_output=True)

            shutil.copytree(PROJECT_ROOT / ".workflow", tmp_dir / ".workflow")
            shutil.copytree(PROJECT_ROOT / "scripts", tmp_dir / "scripts")

            # Create state
            state_file = tmp_dir / ".workflow" / "state.yaml"
            state_file.write_text(f"""
project:
  name: "sensitivity-test"
  type: "software"
current_phase: "phase_2_implementation"
current_checkpoint: "CP_{count}"
checkpoint_count: {count}
""")

            # Create checkpoint log with specified count
            log_file = tmp_dir / ".workflow" / "checkpoints.log"
            entries = [f"2024-01-{(i%28)+1:02d}T{(i%24):02d}:00:00Z | CP_{i+1} | Checkpoint {i+1}" for i in range(count)]
            log_file.write_text("\n".join(entries))

            # Benchmark recovery
            start = time.perf_counter_ns()
            subprocess.run(["./scripts/recover_context.sh"], capture_output=True, text=True)
            recovery_times.append((time.perf_counter_ns() - start) / 1e6)

        finally:
            os.chdir(PROJECT_ROOT)
            shutil.rmtree(tmp_dir, ignore_errors=True)

    return calculate_statistics(recovery_times)


def run_sensitivity_analysis() -> Dict:
    """Run the sensitivity analysis"""
    print("="*60)
    print("Sensitivity Analysis for FSE 2026")
    print("="*60)
    print(f"Trials per condition: {NUM_TRIALS}")
    print(f"Timestamp: {datetime.now().isoformat()}")

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    results = {"checkpoint_counts": {}, "metadata": {}}

    # Test different checkpoint counts
    print("\nTesting checkpoint count sensitivity...")
    for count in [5, 25, 50, 100]:
        print(f"  {count} checkpoints...", end=" ", flush=True)
        stats = test_checkpoint_count(count)
        results["checkpoint_counts"][count] = stats
        print(f"{stats['mean']:.1f}ms (95% CI: [{stats['ci_95_lower']:.1f}, {stats['ci_95_upper']:.1f}])")

    results["metadata"] = {
        "timestamp": datetime.now().isoformat(),
        "trials": NUM_TRIALS
    }

    # Print summary
    print("\n" + "="*60)
    print("SENSITIVITY ANALYSIS SUMMARY")
    print("="*60)
    print("\nRecovery Time vs Checkpoint Count:")
    for count, stats in results["checkpoint_counts"].items():
        print(f"  {count:3d} checkpoints: {stats['mean']:6.1f}ms ± {stats['std_dev']:.1f}")

    # Check if performance is stable
    means = [stats['mean'] for stats in results["checkpoint_counts"].values()]
    variation = (max(means) - min(means)) / statistics.mean(means) * 100
    print(f"\nVariation across checkpoint counts: {variation:.1f}%")
    print(f"Stability: {'STABLE' if variation < 20 else 'VARIABLE'} (threshold: 20%)")

    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = RESULTS_DIR / f"sensitivity_analysis_{timestamp}.json"
    with open(results_file, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\nResults saved to: {results_file}")

    return results


if __name__ == "__main__":
    run_sensitivity_analysis()
