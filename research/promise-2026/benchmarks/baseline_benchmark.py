#!/usr/bin/env python3
"""
Real Baseline Benchmark Suite for FSE 2026 Paper

Measures actual checkpoint/restore times for:
- UWS (Universal Workflow System)
- LangGraph (checkpoint-based)
- Git-only (no workflow management)
- Manual baseline (literature-based simulation)

Requirements:
- langgraph >= 0.2.0
- scipy
- numpy
"""

import json
import os
import subprocess
import tempfile
import time
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple
import statistics

# Try to import LangGraph
try:
    from langgraph.graph import StateGraph, END
    from langgraph.checkpoint.memory import MemorySaver
    from typing import TypedDict, Annotated
    import operator
    LANGGRAPH_AVAILABLE = True
except ImportError:
    LANGGRAPH_AVAILABLE = False
    print("Warning: LangGraph not available. Install with: pip install langgraph")

# Try to import scipy for Cliff's delta
try:
    from scipy import stats
    import numpy as np
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False
    print("Warning: scipy not available. Install with: pip install scipy numpy")

# Configuration
NUM_TRIALS = 30  # Minimum 30 for statistical validity
WARMUP_TRIALS = 3
PROJECT_ROOT = Path(__file__).parent.parent.parent
RESULTS_DIR = PROJECT_ROOT / "artifacts" / "benchmark_results" / "baselines"


def ensure_results_dir():
    """Create results directory if it doesn't exist"""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)


def time_execution(func, *args, **kwargs) -> Tuple[float, any]:
    """Time function execution in milliseconds"""
    start = time.perf_counter_ns()
    result = func(*args, **kwargs)
    elapsed_ms = (time.perf_counter_ns() - start) / 1e6
    return elapsed_ms, result


def calculate_statistics(data: List[float]) -> Dict:
    """Calculate comprehensive statistics"""
    if not data:
        return {}

    sorted_data = sorted(data)
    n = len(sorted_data)

    # Basic stats
    mean = statistics.mean(data)
    median = statistics.median(data)
    std_dev = statistics.stdev(data) if n > 1 else 0

    # IQR
    q1_idx = n // 4
    q3_idx = (3 * n) // 4
    q1 = sorted_data[q1_idx]
    q3 = sorted_data[q3_idx]
    iqr = q3 - q1

    # Min/Max
    min_val = min(data)
    max_val = max(data)

    # 95% CI for mean (t-distribution)
    if SCIPY_AVAILABLE and n > 1:
        se = std_dev / np.sqrt(n)
        t_val = stats.t.ppf(0.975, n - 1)
        ci_lower = mean - t_val * se
        ci_upper = mean + t_val * se
    else:
        ci_lower = mean - 1.96 * std_dev / (n ** 0.5) if n > 1 else mean
        ci_upper = mean + 1.96 * std_dev / (n ** 0.5) if n > 1 else mean

    return {
        "n": n,
        "mean": round(mean, 3),
        "median": round(median, 3),
        "std_dev": round(std_dev, 3),
        "q1": round(q1, 3),
        "q3": round(q3, 3),
        "iqr": round(iqr, 3),
        "min": round(min_val, 3),
        "max": round(max_val, 3),
        "ci_95_lower": round(ci_lower, 3),
        "ci_95_upper": round(ci_upper, 3),
        "raw_data": [round(x, 3) for x in data]
    }


def cliffs_delta(x: List[float], y: List[float]) -> Tuple[float, str]:
    """
    Calculate Cliff's delta effect size (non-parametric)

    Returns: (delta, interpretation)

    Thresholds (Cliff, 1993):
    - |delta| < 0.147: negligible
    - |delta| < 0.33: small
    - |delta| < 0.474: medium
    - |delta| >= 0.474: large
    """
    if not x or not y:
        return 0, "undefined"

    n_x = len(x)
    n_y = len(y)

    # Count dominance
    more = 0
    less = 0
    for xi in x:
        for yi in y:
            if xi > yi:
                more += 1
            elif xi < yi:
                less += 1

    delta = (more - less) / (n_x * n_y)

    # Interpret
    abs_delta = abs(delta)
    if abs_delta < 0.147:
        interpretation = "negligible"
    elif abs_delta < 0.33:
        interpretation = "small"
    elif abs_delta < 0.474:
        interpretation = "medium"
    else:
        interpretation = "large"

    return round(delta, 4), interpretation


def wilcoxon_test(x: List[float], y: List[float]) -> Dict:
    """Perform Wilcoxon signed-rank test (paired)"""
    if not SCIPY_AVAILABLE:
        return {"statistic": None, "p_value": None, "note": "scipy not available"}

    # For independent samples, use Mann-Whitney U
    statistic, p_value = stats.mannwhitneyu(x, y, alternative='two-sided')

    return {
        "test": "Mann-Whitney U",
        "statistic": round(float(statistic), 4),
        "p_value": round(float(p_value), 6),
        "significant": bool(p_value < 0.05)
    }


# =============================================================================
# UWS BENCHMARK
# =============================================================================

def benchmark_uws() -> Dict:
    """Benchmark UWS checkpoint and recovery operations"""
    print("\n" + "="*60)
    print("Benchmarking: UWS (Universal Workflow System)")
    print("="*60)

    checkpoint_times = []
    recovery_times = []

    for trial in range(NUM_TRIALS + WARMUP_TRIALS):
        is_warmup = trial < WARMUP_TRIALS

        # Create temp directory for isolated test
        tmp_dir = tempfile.mkdtemp()
        try:
            os.chdir(tmp_dir)

            # Initialize git repo
            subprocess.run(["git", "init", "--quiet"], check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "bench@test.com"], check=True, capture_output=True)
            subprocess.run(["git", "config", "user.name", "Benchmark"], check=True, capture_output=True)

            # Copy workflow infrastructure
            workflow_src = PROJECT_ROOT / ".workflow"
            scripts_src = PROJECT_ROOT / "scripts"

            shutil.copytree(workflow_src, Path(tmp_dir) / ".workflow")
            shutil.copytree(scripts_src, Path(tmp_dir) / "scripts")

            # Create state file
            state_file = Path(tmp_dir) / ".workflow" / "state.yaml"
            state_file.write_text("""
project:
  name: "benchmark-project"
  type: "software"
current_phase: "phase_2_implementation"
current_checkpoint: "CP_2_10"
checkpoint_count: 10
context_bridge:
  critical_info:
    - "API design finalized"
    - "Database schema ready"
    - "Authentication module complete"
  next_actions:
    - "Implement user service"
    - "Write unit tests"
    - "Deploy to staging"
metadata:
  created: "2024-01-01T00:00:00Z"
  last_updated: "2024-01-15T12:00:00Z"
""")

            # Create checkpoint log
            log_file = Path(tmp_dir) / ".workflow" / "checkpoints.log"
            log_entries = []
            for i in range(10):
                log_entries.append(f"2024-01-{i+1:02d}T00:00:00Z | CP_{i+1} | Checkpoint {i+1}")
            log_file.write_text("\n".join(log_entries))

            # Create handoff file
            handoff_file = Path(tmp_dir) / ".workflow" / "handoff.md"
            handoff_file.write_text("""
# Context Handoff

## Current Status
- Phase: phase_2_implementation
- Progress: 60%
- Active Agent: implementer

## Critical Context
1. REST API design approved
2. PostgreSQL database schema finalized
3. JWT authentication working

## Next Actions
- [ ] Complete user management service
- [ ] Add role-based access control
- [ ] Write integration tests

## Blockers
None currently

## Notes
Performance optimization deferred to phase 3.
""")

            # Benchmark checkpoint creation
            start = time.perf_counter_ns()
            result = subprocess.run(
                ["./scripts/checkpoint.sh", f"benchmark_trial_{trial}"],
                capture_output=True,
                text=True
            )
            checkpoint_time = (time.perf_counter_ns() - start) / 1e6

            # Benchmark context recovery
            start = time.perf_counter_ns()
            result = subprocess.run(
                ["./scripts/recover_context.sh"],
                capture_output=True,
                text=True
            )
            recovery_time = (time.perf_counter_ns() - start) / 1e6

            if not is_warmup:
                checkpoint_times.append(checkpoint_time)
                recovery_times.append(recovery_time)
                if trial % 10 == 0:
                    print(f"  Trial {trial - WARMUP_TRIALS + 1}/{NUM_TRIALS}: "
                          f"checkpoint={checkpoint_time:.1f}ms, recovery={recovery_time:.1f}ms")

        finally:
            os.chdir(PROJECT_ROOT)
            shutil.rmtree(tmp_dir, ignore_errors=True)

    return {
        "system": "UWS",
        "version": "1.0.0",
        "checkpoint_creation": calculate_statistics(checkpoint_times),
        "context_recovery": calculate_statistics(recovery_times)
    }


# =============================================================================
# LANGGRAPH BENCHMARK
# =============================================================================

def benchmark_langgraph() -> Dict:
    """Benchmark LangGraph checkpoint and recovery operations"""
    if not LANGGRAPH_AVAILABLE:
        return {"error": "LangGraph not available"}

    print("\n" + "="*60)
    print("Benchmarking: LangGraph")
    print("="*60)

    # Define a realistic multi-step workflow
    class WorkflowState(TypedDict):
        messages: Annotated[list, operator.add]
        phase: str
        context: dict
        checkpoint_count: int

    def planning_node(state):
        return {
            "phase": "planning",
            "messages": ["Planning phase completed"],
            "context": {"plan": "defined"},
            "checkpoint_count": state.get("checkpoint_count", 0) + 1
        }

    def implementation_node(state):
        return {
            "phase": "implementation",
            "messages": ["Implementation phase completed"],
            "context": {**state.get("context", {}), "code": "written"},
            "checkpoint_count": state.get("checkpoint_count", 0) + 1
        }

    def testing_node(state):
        return {
            "phase": "testing",
            "messages": ["Testing phase completed"],
            "context": {**state.get("context", {}), "tests": "passed"},
            "checkpoint_count": state.get("checkpoint_count", 0) + 1
        }

    def deployment_node(state):
        return {
            "phase": "deployment",
            "messages": ["Deployment phase completed"],
            "context": {**state.get("context", {}), "deployed": True},
            "checkpoint_count": state.get("checkpoint_count", 0) + 1
        }

    # Build graph
    builder = StateGraph(WorkflowState)
    builder.add_node("planning", planning_node)
    builder.add_node("implementation", implementation_node)
    builder.add_node("testing", testing_node)
    builder.add_node("deployment", deployment_node)

    builder.set_entry_point("planning")
    builder.add_edge("planning", "implementation")
    builder.add_edge("implementation", "testing")
    builder.add_edge("testing", "deployment")
    builder.add_edge("deployment", END)

    checkpoint_times = []
    restore_times = []

    for trial in range(NUM_TRIALS + WARMUP_TRIALS):
        is_warmup = trial < WARMUP_TRIALS

        # Fresh checkpointer for each trial
        memory = MemorySaver()
        graph = builder.compile(checkpointer=memory)

        config = {"configurable": {"thread_id": f"trial-{trial}"}}
        initial_state = {
            "messages": [],
            "phase": "init",
            "context": {},
            "checkpoint_count": 0
        }

        # Benchmark: Execute workflow with checkpointing
        start = time.perf_counter_ns()
        result = graph.invoke(initial_state, config)
        checkpoint_time = (time.perf_counter_ns() - start) / 1e6

        # Benchmark: Restore from checkpoint
        start = time.perf_counter_ns()
        restored_state = graph.get_state(config)
        restore_time = (time.perf_counter_ns() - start) / 1e6

        if not is_warmup:
            checkpoint_times.append(checkpoint_time)
            restore_times.append(restore_time)
            if trial % 10 == 0:
                print(f"  Trial {trial - WARMUP_TRIALS + 1}/{NUM_TRIALS}: "
                      f"checkpoint={checkpoint_time:.2f}ms, restore={restore_time:.3f}ms")

    # Get LangGraph version
    try:
        import langgraph
        version = getattr(langgraph, "__version__", "unknown")
    except:
        version = "unknown"

    return {
        "system": "LangGraph",
        "version": version,
        "checkpoint_creation": calculate_statistics(checkpoint_times),
        "state_restore": calculate_statistics(restore_times)
    }


# =============================================================================
# GIT-ONLY BENCHMARK
# =============================================================================

def benchmark_git_only() -> Dict:
    """Benchmark git-only workflow (no UWS)"""
    print("\n" + "="*60)
    print("Benchmarking: Git-Only (no workflow management)")
    print("="*60)

    commit_times = []
    log_read_times = []

    for trial in range(NUM_TRIALS + WARMUP_TRIALS):
        is_warmup = trial < WARMUP_TRIALS

        tmp_dir = tempfile.mkdtemp()
        try:
            os.chdir(tmp_dir)

            # Initialize git repo
            subprocess.run(["git", "init", "--quiet"], check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "bench@test.com"], check=True, capture_output=True)
            subprocess.run(["git", "config", "user.name", "Benchmark"], check=True, capture_output=True)

            # Create some files and commits (simulate project history)
            for i in range(5):
                Path(f"file_{i}.txt").write_text(f"Content for file {i}\n" * 100)
                subprocess.run(["git", "add", "."], check=True, capture_output=True)
                subprocess.run(["git", "commit", "-m", f"Commit {i}"], check=True, capture_output=True)

            # Benchmark: Create a new commit (equivalent to "checkpoint")
            Path("new_file.txt").write_text("New content")
            subprocess.run(["git", "add", "."], check=True, capture_output=True)

            start = time.perf_counter_ns()
            subprocess.run(["git", "commit", "-m", "Benchmark commit"], check=True, capture_output=True)
            commit_time = (time.perf_counter_ns() - start) / 1e6

            # Benchmark: Read git log (part of manual context recovery)
            start = time.perf_counter_ns()
            subprocess.run(["git", "log", "--oneline", "-10"], check=True, capture_output=True)
            subprocess.run(["git", "status"], check=True, capture_output=True)
            subprocess.run(["git", "diff", "HEAD~3"], check=True, capture_output=True)
            subprocess.run(["git", "show", "--stat", "HEAD"], check=True, capture_output=True)
            log_read_time = (time.perf_counter_ns() - start) / 1e6

            if not is_warmup:
                commit_times.append(commit_time)
                log_read_times.append(log_read_time)
                if trial % 10 == 0:
                    print(f"  Trial {trial - WARMUP_TRIALS + 1}/{NUM_TRIALS}: "
                          f"commit={commit_time:.1f}ms, log_read={log_read_time:.1f}ms")

        finally:
            os.chdir(PROJECT_ROOT)
            shutil.rmtree(tmp_dir, ignore_errors=True)

    # Get git version
    result = subprocess.run(["git", "--version"], capture_output=True, text=True)
    git_version = result.stdout.strip() if result.returncode == 0 else "unknown"

    return {
        "system": "Git-Only",
        "version": git_version,
        "commit_creation": calculate_statistics(commit_times),
        "log_reading": calculate_statistics(log_read_times),
        "note": "Git-only provides mechanical operations but no structured workflow context"
    }


# =============================================================================
# MANUAL BASELINE (Literature-Based)
# =============================================================================

def get_manual_baseline() -> Dict:
    """
    Manual context recovery baseline from literature

    Sources:
    - Mark et al. (2008): "The Cost of Interrupted Work: More Speed and Stress"
      - Average 23 minutes to resume task after interruption
    - Parnin & Rugaber (2011): "Resumption strategies for interrupted programming tasks"
      - Programmers took 15-25 minutes to resume after interruption
    - Ko et al. (2006): "An Exploratory Study of How Developers Seek, Relate, and Collect Relevant Information"
      - Developers spend 35% of time on information gathering

    We use the conservative estimate of 15-25 minutes (900,000 - 1,500,000 ms)
    """
    print("\n" + "="*60)
    print("Manual Baseline (Literature-Based)")
    print("="*60)

    return {
        "system": "Manual",
        "method": "literature_estimate",
        "sources": [
            {
                "citation": "Mark et al. (2008)",
                "title": "The Cost of Interrupted Work: More Speed and Stress",
                "finding": "Average 23 minutes to resume task"
            },
            {
                "citation": "Parnin & Rugaber (2011)",
                "title": "Resumption strategies for interrupted programming tasks",
                "finding": "15-25 minutes to resume after interruption"
            }
        ],
        "estimated_recovery_time_ms": {
            "lower_bound": 900000,  # 15 minutes
            "upper_bound": 1500000,  # 25 minutes
            "point_estimate": 1200000,  # 20 minutes (midpoint)
            "note": "Human cognitive context reconstruction time"
        }
    }


# =============================================================================
# COMPARATIVE ANALYSIS
# =============================================================================

def run_comparative_analysis(results: Dict) -> Dict:
    """Run comparative statistical analysis"""
    print("\n" + "="*60)
    print("Comparative Statistical Analysis")
    print("="*60)

    analysis = {}

    # Get raw data
    uws_recovery = results.get("uws", {}).get("context_recovery", {}).get("raw_data", [])
    lg_restore = results.get("langgraph", {}).get("state_restore", {}).get("raw_data", [])
    git_read = results.get("git_only", {}).get("log_reading", {}).get("raw_data", [])

    if uws_recovery and lg_restore:
        delta, interp = cliffs_delta(lg_restore, uws_recovery)
        analysis["uws_vs_langgraph"] = {
            "cliffs_delta": delta,
            "interpretation": interp,
            "statistical_test": wilcoxon_test(uws_recovery, lg_restore),
            "note": "LangGraph restore is faster for raw state retrieval, but measures different concept"
        }
        print(f"\nUWS vs LangGraph:")
        print(f"  Cliff's delta: {delta} ({interp})")

    if uws_recovery and git_read:
        delta, interp = cliffs_delta(git_read, uws_recovery)
        analysis["uws_vs_git_only"] = {
            "cliffs_delta": delta,
            "interpretation": interp,
            "statistical_test": wilcoxon_test(uws_recovery, git_read)
        }
        print(f"\nUWS vs Git-Only:")
        print(f"  Cliff's delta: {delta} ({interp})")

    # Manual comparison (using point estimate)
    manual_estimate_ms = 1200000  # 20 minutes
    if uws_recovery:
        uws_mean = statistics.mean(uws_recovery)
        improvement_factor = manual_estimate_ms / uws_mean
        improvement_percent = (1 - uws_mean / manual_estimate_ms) * 100
        analysis["uws_vs_manual"] = {
            "uws_mean_ms": round(uws_mean, 3),
            "manual_estimate_ms": manual_estimate_ms,
            "improvement_factor": round(improvement_factor, 1),
            "improvement_percent": round(improvement_percent, 2),
            "note": "Comparison based on literature estimates; not direct measurement"
        }
        print(f"\nUWS vs Manual (literature estimate):")
        print(f"  UWS mean: {uws_mean:.1f}ms")
        print(f"  Manual estimate: {manual_estimate_ms}ms ({manual_estimate_ms/60000:.0f} min)")
        print(f"  Improvement: {improvement_percent:.1f}% faster")

    return analysis


# =============================================================================
# MAIN
# =============================================================================

def main():
    """Run all benchmarks and generate results"""
    print("="*60)
    print("FSE 2026 Baseline Benchmark Suite")
    print("="*60)
    print(f"Trials: {NUM_TRIALS}")
    print(f"Warmup: {WARMUP_TRIALS}")
    print(f"Timestamp: {datetime.now().isoformat()}")

    ensure_results_dir()

    results = {}

    # Run benchmarks
    results["uws"] = benchmark_uws()
    results["langgraph"] = benchmark_langgraph()
    results["git_only"] = benchmark_git_only()
    results["manual"] = get_manual_baseline()

    # Run comparative analysis
    results["comparative_analysis"] = run_comparative_analysis(results)

    # Add metadata
    results["metadata"] = {
        "timestamp": datetime.now().isoformat(),
        "trials": NUM_TRIALS,
        "warmup_trials": WARMUP_TRIALS,
        "platform": os.uname().sysname,
        "scipy_available": SCIPY_AVAILABLE,
        "langgraph_available": LANGGRAPH_AVAILABLE
    }

    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = RESULTS_DIR / f"baseline_comparison_{timestamp}.json"

    with open(results_file, "w") as f:
        json.dump(results, f, indent=2)

    print("\n" + "="*60)
    print("BENCHMARK SUMMARY")
    print("="*60)

    if "context_recovery" in results.get("uws", {}):
        uws_stats = results["uws"]["context_recovery"]
        print(f"\nUWS Context Recovery:")
        print(f"  Mean: {uws_stats['mean']}ms (95% CI: [{uws_stats['ci_95_lower']}, {uws_stats['ci_95_upper']}])")
        print(f"  Median: {uws_stats['median']}ms (IQR: {uws_stats['iqr']})")

    if "state_restore" in results.get("langgraph", {}):
        lg_stats = results["langgraph"]["state_restore"]
        print(f"\nLangGraph State Restore:")
        print(f"  Mean: {lg_stats['mean']}ms (95% CI: [{lg_stats['ci_95_lower']}, {lg_stats['ci_95_upper']}])")
        print(f"  Median: {lg_stats['median']}ms (IQR: {lg_stats['iqr']})")

    if "log_reading" in results.get("git_only", {}):
        git_stats = results["git_only"]["log_reading"]
        print(f"\nGit-Only Log Reading:")
        print(f"  Mean: {git_stats['mean']}ms (95% CI: [{git_stats['ci_95_lower']}, {git_stats['ci_95_upper']}])")

    print(f"\nManual Baseline (Literature):")
    print(f"  Estimate: 15-25 minutes (900,000-1,500,000ms)")

    print(f"\nResults saved to: {results_file}")
    print("="*60)

    return results


if __name__ == "__main__":
    main()
