#!/usr/bin/env python3
"""
Measured Ablation Study for FSE 2026 Paper

Tests contribution of each UWS component by disabling features:
- UWS-Full: Complete system
- UWS-NoCheckpoint: Without checkpoint log
- UWS-NoAgents: Without agent registry
- UWS-NoSkills: Without skill catalog
"""

import json
import os
import subprocess
import tempfile
import shutil
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple
import statistics

PROJECT_ROOT = Path(__file__).parent.parent.parent
RESULTS_DIR = PROJECT_ROOT / "artifacts" / "benchmark_results" / "ablation"

NUM_TRIALS = 30
WARMUP_TRIALS = 3


def calculate_statistics(data: List[float]) -> Dict:
    """Calculate comprehensive statistics"""
    if not data:
        return {}

    sorted_data = sorted(data)
    n = len(sorted_data)

    mean = statistics.mean(data)
    median = statistics.median(data)
    std_dev = statistics.stdev(data) if n > 1 else 0

    q1_idx = n // 4
    q3_idx = (3 * n) // 4
    q1 = sorted_data[q1_idx]
    q3 = sorted_data[q3_idx]
    iqr = q3 - q1

    # 95% CI
    se = std_dev / (n ** 0.5) if n > 1 else 0
    ci_lower = mean - 1.96 * se
    ci_upper = mean + 1.96 * se

    return {
        "n": n,
        "mean": round(mean, 3),
        "median": round(median, 3),
        "std_dev": round(std_dev, 3),
        "iqr": round(iqr, 3),
        "ci_95_lower": round(ci_lower, 3),
        "ci_95_upper": round(ci_upper, 3),
        "raw_data": [round(x, 3) for x in data]
    }


def setup_variant(tmp_dir: Path, variant: str) -> bool:
    """Setup UWS variant in test directory"""
    try:
        os.chdir(tmp_dir)

        # Initialize git
        subprocess.run(["git", "init", "--quiet"], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.email", "ablation@test.com"], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Ablation"], check=True, capture_output=True)

        # Copy base infrastructure
        workflow_src = PROJECT_ROOT / ".workflow"
        scripts_src = PROJECT_ROOT / "scripts"

        shutil.copytree(workflow_src, tmp_dir / ".workflow")
        shutil.copytree(scripts_src, tmp_dir / "scripts")

        # Apply variant modifications
        if variant == "full":
            pass  # Keep everything

        elif variant == "no_checkpoint":
            # Remove checkpoint functionality
            (tmp_dir / ".workflow" / "checkpoints.log").unlink(missing_ok=True)
            # Modify checkpoint script to be a no-op
            checkpoint_script = tmp_dir / "scripts" / "checkpoint.sh"
            checkpoint_script.write_text("#!/bin/bash\nexit 0\n")

        elif variant == "no_agents":
            # Remove agent registry
            agent_registry = tmp_dir / ".workflow" / "agents" / "registry.yaml"
            if agent_registry.exists():
                agent_registry.write_text("agents: []\n")

        elif variant == "no_skills":
            # Remove skill catalog
            skill_catalog = tmp_dir / ".workflow" / "skills" / "catalog.yaml"
            if skill_catalog.exists():
                skill_catalog.write_text("skills: []\n")

        elif variant == "minimal":
            # Minimal: no checkpoints, no agents, no skills
            (tmp_dir / ".workflow" / "checkpoints.log").unlink(missing_ok=True)
            checkpoint_script = tmp_dir / "scripts" / "checkpoint.sh"
            checkpoint_script.write_text("#!/bin/bash\nexit 0\n")

            agent_registry = tmp_dir / ".workflow" / "agents" / "registry.yaml"
            if agent_registry.exists():
                agent_registry.write_text("agents: []\n")

            skill_catalog = tmp_dir / ".workflow" / "skills" / "catalog.yaml"
            if skill_catalog.exists():
                skill_catalog.write_text("skills: []\n")

        # Create base state file
        state_file = tmp_dir / ".workflow" / "state.yaml"
        state_file.write_text(f"""
project:
  name: "ablation-test"
  type: "software"
current_phase: "phase_2_implementation"
current_checkpoint: "CP_2_5"
checkpoint_count: 5
metadata:
  created: "{datetime.now().isoformat()}"
  last_updated: "{datetime.now().isoformat()}"
""")

        # Create checkpoint log if needed
        log_file = tmp_dir / ".workflow" / "checkpoints.log"
        if not log_file.exists() and variant not in ["no_checkpoint", "minimal"]:
            log_entries = [f"2024-01-{i+1:02d}T00:00:00Z | CP_{i+1} | Checkpoint {i+1}" for i in range(5)]
            log_file.write_text("\n".join(log_entries))

        return True

    except Exception as e:
        print(f"    Setup error: {e}")
        return False


def benchmark_variant(variant: str) -> Dict:
    """Benchmark a specific UWS variant"""
    print(f"\n  Testing variant: {variant}")

    checkpoint_times = []
    recovery_times = []

    for trial in range(NUM_TRIALS + WARMUP_TRIALS):
        is_warmup = trial < WARMUP_TRIALS

        tmp_dir = Path(tempfile.mkdtemp())
        try:
            if not setup_variant(tmp_dir, variant):
                continue

            # Benchmark checkpoint (only if not disabled)
            if variant not in ["no_checkpoint", "minimal"]:
                start = time.perf_counter_ns()
                subprocess.run(
                    ["./scripts/checkpoint.sh", f"test_{trial}"],
                    capture_output=True, text=True
                )
                checkpoint_time = (time.perf_counter_ns() - start) / 1e6
            else:
                checkpoint_time = 0  # No checkpoint

            # Benchmark recovery
            start = time.perf_counter_ns()
            subprocess.run(
                ["./scripts/recover_context.sh"],
                capture_output=True, text=True
            )
            recovery_time = (time.perf_counter_ns() - start) / 1e6

            if not is_warmup:
                checkpoint_times.append(checkpoint_time)
                recovery_times.append(recovery_time)

        finally:
            os.chdir(PROJECT_ROOT)
            shutil.rmtree(tmp_dir, ignore_errors=True)

    checkpoint_stats = calculate_statistics(checkpoint_times) if checkpoint_times else {}
    recovery_stats = calculate_statistics(recovery_times)

    print(f"    Checkpoint: {checkpoint_stats.get('mean', 'N/A')}ms")
    print(f"    Recovery: {recovery_stats.get('mean', 'N/A')}ms")

    return {
        "variant": variant,
        "checkpoint": checkpoint_stats,
        "recovery": recovery_stats
    }


def run_ablation_study() -> Dict:
    """Run the full ablation study"""
    print("="*60)
    print("Ablation Study for FSE 2026")
    print("="*60)
    print(f"Trials per variant: {NUM_TRIALS}")
    print(f"Timestamp: {datetime.now().isoformat()}")

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    variants = ["full", "no_checkpoint", "no_agents", "no_skills", "minimal"]
    results = {"variants": {}, "analysis": {}}

    for variant in variants:
        results["variants"][variant] = benchmark_variant(variant)

    # Calculate relative performance
    if "full" in results["variants"]:
        full_recovery = results["variants"]["full"]["recovery"]["mean"]

        for variant in variants:
            if variant != "full" and "recovery" in results["variants"][variant]:
                variant_recovery = results["variants"][variant]["recovery"]["mean"]
                if full_recovery > 0:
                    relative = ((variant_recovery - full_recovery) / full_recovery) * 100
                    results["analysis"][f"{variant}_vs_full"] = {
                        "recovery_increase_percent": round(relative, 2),
                        "full_recovery_ms": full_recovery,
                        "variant_recovery_ms": variant_recovery
                    }

    results["metadata"] = {
        "timestamp": datetime.now().isoformat(),
        "trials": NUM_TRIALS,
        "warmup_trials": WARMUP_TRIALS
    }

    # Print summary
    print("\n" + "="*60)
    print("ABLATION STUDY SUMMARY")
    print("="*60)

    print("\nRecovery Times by Variant:")
    for variant in variants:
        if "recovery" in results["variants"][variant]:
            stats = results["variants"][variant]["recovery"]
            print(f"  {variant:15s}: {stats['mean']:6.1f}ms (95% CI: [{stats['ci_95_lower']:.1f}, {stats['ci_95_upper']:.1f}])")

    print("\nRelative to Full:")
    for key, analysis in results["analysis"].items():
        print(f"  {key}: {analysis['recovery_increase_percent']:+.1f}%")

    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = RESULTS_DIR / f"ablation_study_{timestamp}.json"
    with open(results_file, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\nResults saved to: {results_file}")

    return results


if __name__ == "__main__":
    run_ablation_study()
