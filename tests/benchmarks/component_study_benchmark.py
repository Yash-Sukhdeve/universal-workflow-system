#!/usr/bin/env python3
"""
Component Study Benchmark: Testing UWS Design Variants

This benchmark tests different UWS design configurations to answer causal questions
about which design choices improve recovery resilience under corruption.

Variants:
  - UWS-full: YAML + handoff.md + checkpoints.log (current production design)
  - UWS-single: YAML only (no redundancy)
  - UWS-no-handoff: YAML + checkpoints.log (no human-readable fallback)
  - UWS-binary: MessagePack + checkpoints.log (binary encoding)

Hypotheses:
  H1: Redundant storage improves recovery success (full vs single)
  H2: Human-readable formats degrade more gracefully (full vs binary)
  H3: Handoff documents improve partial recovery (full vs no-handoff)
  H4: Binary formats recover faster when uncorrupted (binary vs full at 0%)

Following R1 (Truthfulness): All results are actual measurements, no simulation.
Following R5 (Reproducibility): Fixed random seed, all parameters documented.
"""

import json
import os
import random
import tempfile
import time
import statistics
from dataclasses import dataclass, asdict, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import struct

# Set random seed for reproducibility
RANDOM_SEED = 42
random.seed(RANDOM_SEED)

# Experiment parameters
CORRUPTION_LEVELS = [0, 5, 10, 25, 50, 75, 90]  # Percentages
TRIALS_PER_CONDITION = 30
VARIANTS = ["UWS-full", "UWS-single", "UWS-no-handoff", "UWS-binary"]


@dataclass
class VariantConfig:
    """Configuration for a UWS design variant."""
    name: str
    use_yaml: bool  # True for YAML, False for MessagePack
    use_handoff: bool  # Include handoff.md
    use_checkpoint_log: bool  # Include checkpoints.log
    description: str


VARIANT_CONFIGS = {
    "UWS-full": VariantConfig(
        name="UWS-full",
        use_yaml=True,
        use_handoff=True,
        use_checkpoint_log=True,
        description="Full redundancy: YAML + handoff.md + checkpoints.log"
    ),
    "UWS-single": VariantConfig(
        name="UWS-single",
        use_yaml=True,
        use_handoff=False,
        use_checkpoint_log=False,
        description="Minimal: YAML only, no redundancy"
    ),
    "UWS-no-handoff": VariantConfig(
        name="UWS-no-handoff",
        use_yaml=True,
        use_handoff=False,
        use_checkpoint_log=True,
        description="No human fallback: YAML + checkpoints.log"
    ),
    "UWS-binary": VariantConfig(
        name="UWS-binary",
        use_yaml=False,
        use_handoff=False,
        use_checkpoint_log=True,
        description="Binary encoding: MessagePack + checkpoints.log"
    ),
}


@dataclass
class RecoveryResult:
    """Result of a single recovery attempt."""
    variant: str
    corruption_level: int  # Percentage (0-100)
    trial: int
    success: bool
    recovery_time_ms: float
    state_completeness: float  # Percentage (0-100)
    fields_recovered: int
    fields_total: int
    fallback_used: str  # "primary", "handoff", "checkpoint_log", "none"
    error_message: Optional[str] = None


@dataclass
class OriginalState:
    """Original state to compare against for completeness scoring."""
    project_name: str
    project_type: str
    current_phase: str
    checkpoint_id: str
    active_agent: str
    agent_history: List[str]
    progress: Dict[str, int]
    health_status: str
    last_check: str

    def to_dict(self) -> dict:
        return {
            "version": "2.0",
            "project": {
                "name": self.project_name,
                "type": self.project_type
            },
            "current_phase": self.current_phase,
            "checkpoint": self.checkpoint_id,
            "health": {
                "status": self.health_status,
                "last_check": self.last_check
            },
            "agents": {
                "active": self.active_agent,
                "history": self.agent_history
            },
            "progress": self.progress
        }

    def field_count(self) -> int:
        """Count total recoverable fields."""
        return 10  # project_name, type, phase, checkpoint, agent, 3 history, status, last_check


class UWSVariantAdapter:
    """Adapter for testing a specific UWS design variant."""

    def __init__(self, config: VariantConfig, work_dir: Path):
        self.config = config
        self.work_dir = work_dir
        self.workflow_dir = work_dir / ".workflow"

        # State file depends on encoding
        if config.use_yaml:
            self.state_file = self.workflow_dir / "state.yaml"
        else:
            self.state_file = self.workflow_dir / "state.msgpack"

        self.handoff_file = self.workflow_dir / "handoff.md"
        self.checkpoint_log = self.workflow_dir / "checkpoints.log"

    def initialize(self) -> OriginalState:
        """Create directory structure and return original state."""
        self.workflow_dir.mkdir(parents=True, exist_ok=True)

        # Create standard test state
        state = OriginalState(
            project_name="component-study-test",
            project_type="research",
            current_phase="phase_3_validation",
            checkpoint_id="CP_3_001",
            active_agent="experimenter",
            agent_history=["researcher", "architect", "implementer"],
            progress={"phase_1": 100, "phase_2": 100, "phase_3": 75},
            health_status="healthy",
            last_check=datetime.now().isoformat()
        )

        return state

    def save_state(self, state: OriginalState) -> None:
        """Save state according to variant configuration."""
        state_dict = state.to_dict()

        # Save primary state file
        if self.config.use_yaml:
            self._save_yaml(state_dict)
        else:
            self._save_msgpack(state_dict)

        # Save handoff.md if configured
        if self.config.use_handoff:
            self._save_handoff(state)

        # Save checkpoints.log if configured
        if self.config.use_checkpoint_log:
            self._save_checkpoint_log(state)

    def _save_yaml(self, state_dict: dict) -> None:
        """Save state as YAML."""
        yaml_content = self._dict_to_yaml(state_dict)
        self.state_file.write_text(yaml_content)

    def _dict_to_yaml(self, d: dict, indent: int = 0) -> str:
        """Convert dict to YAML string."""
        lines = []
        prefix = "  " * indent
        for k, v in d.items():
            if isinstance(v, dict):
                lines.append(f"{prefix}{k}:")
                lines.append(self._dict_to_yaml(v, indent + 1))
            elif isinstance(v, list):
                lines.append(f"{prefix}{k}:")
                for item in v:
                    lines.append(f"{prefix}  - {item}")
            else:
                lines.append(f"{prefix}{k}: {v}")
        return "\n".join(lines)

    def _save_msgpack(self, state_dict: dict) -> None:
        """Save state as MessagePack (simplified binary format)."""
        # Simple binary serialization: JSON bytes with length prefix
        json_bytes = json.dumps(state_dict).encode('utf-8')
        with open(self.state_file, 'wb') as f:
            # Write length prefix (4 bytes, big-endian)
            f.write(struct.pack('>I', len(json_bytes)))
            f.write(json_bytes)

    def _save_handoff(self, state: OriginalState) -> None:
        """Save human-readable handoff document."""
        content = f"""# Workflow Handoff
## Component Study Test

**Last Updated**: {state.last_check}
**Current Phase**: {state.current_phase}
**Checkpoint**: {state.checkpoint_id}

---

## Current Status

- **Project**: {state.project_name}
- **Type**: {state.project_type}
- **Active Agent**: {state.active_agent}
- **Health**: {state.health_status}

## Progress

| Phase | Completion |
|-------|------------|
| Phase 1 | {state.progress.get('phase_1', 0)}% |
| Phase 2 | {state.progress.get('phase_2', 0)}% |
| Phase 3 | {state.progress.get('phase_3', 0)}% |

## Agent History

Previous agents: {', '.join(state.agent_history)}

## Context

This is a component study test scenario for measuring recovery resilience
under controlled corruption conditions.
"""
        self.handoff_file.write_text(content)

    def _save_checkpoint_log(self, state: OriginalState) -> None:
        """Save checkpoint log."""
        content = f"""{state.last_check} | {state.checkpoint_id} | Component study test state
{state.last_check} | CP_2_001 | Phase 2 complete
{state.last_check} | CP_1_001 | Initial setup
"""
        self.checkpoint_log.write_text(content)

    def apply_corruption(self, level: int) -> None:
        """Apply byte-level corruption to state file only."""
        if level == 0:
            return

        if not self.state_file.exists():
            return

        with open(self.state_file, 'rb') as f:
            data = bytearray(f.read())

        if len(data) == 0:
            return

        # Calculate bytes to corrupt
        num_corrupt = max(1, int(len(data) * level / 100))
        positions = random.sample(range(len(data)), min(num_corrupt, len(data)))

        for pos in positions:
            data[pos] = random.randint(0, 255)

        with open(self.state_file, 'wb') as f:
            f.write(data)

    def recover(self, original: OriginalState) -> RecoveryResult:
        """
        Attempt recovery using variant-specific fallback chain.

        Returns RecoveryResult with timing and completeness metrics.
        """
        start_time = time.perf_counter()
        recovered_fields = 0
        total_fields = original.field_count()
        fallback_used = "none"
        error_msg = None

        # Try primary state file first
        primary_result = self._try_load_primary()
        if primary_result is not None:
            recovered_fields = self._count_recovered_fields(primary_result, original)
            fallback_used = "primary"
        else:
            # Try handoff fallback (if configured)
            if self.config.use_handoff:
                handoff_result = self._try_parse_handoff(original)
                if handoff_result > 0:
                    recovered_fields = max(recovered_fields, handoff_result)
                    fallback_used = "handoff"

            # Try checkpoint log fallback (if configured)
            if self.config.use_checkpoint_log and recovered_fields < total_fields:
                log_result = self._try_parse_checkpoint_log(original)
                if log_result > 0:
                    recovered_fields = max(recovered_fields, log_result)
                    if fallback_used == "none":
                        fallback_used = "checkpoint_log"

        elapsed_ms = (time.perf_counter() - start_time) * 1000
        completeness = (recovered_fields / total_fields) * 100 if total_fields > 0 else 0
        success = completeness >= 50  # Success threshold

        return RecoveryResult(
            variant=self.config.name,
            corruption_level=0,  # Will be set by caller
            trial=0,  # Will be set by caller
            success=success,
            recovery_time_ms=elapsed_ms,
            state_completeness=completeness,
            fields_recovered=recovered_fields,
            fields_total=total_fields,
            fallback_used=fallback_used,
            error_message=error_msg
        )

    def _try_load_primary(self) -> Optional[dict]:
        """Try to load primary state file."""
        if not self.state_file.exists():
            return None

        try:
            if self.config.use_yaml:
                return self._load_yaml()
            else:
                return self._load_msgpack()
        except Exception:
            return None

    def _load_yaml(self) -> Optional[dict]:
        """Parse YAML state file."""
        content = self.state_file.read_text()
        result = {}
        stack = [(result, -1)]

        for line in content.split('\n'):
            if not line.strip() or line.strip().startswith('#'):
                continue

            indent = len(line) - len(line.lstrip())
            line = line.strip()

            while stack and stack[-1][1] >= indent:
                stack.pop()

            if ':' in line:
                key, _, value = line.partition(':')
                key = key.strip()
                value = value.strip()

                if value:
                    stack[-1][0][key] = value
                else:
                    new_dict = {}
                    stack[-1][0][key] = new_dict
                    stack.append((new_dict, indent))

        # Validate we got meaningful content
        if 'project' in result or 'current_phase' in result:
            return result
        return None

    def _load_msgpack(self) -> Optional[dict]:
        """Parse MessagePack (binary) state file."""
        with open(self.state_file, 'rb') as f:
            # Read length prefix
            length_bytes = f.read(4)
            if len(length_bytes) < 4:
                return None
            length = struct.unpack('>I', length_bytes)[0]

            # Read JSON content
            json_bytes = f.read(length)
            if len(json_bytes) < length:
                return None

            return json.loads(json_bytes.decode('utf-8'))

    def _count_recovered_fields(self, recovered: dict, original: OriginalState) -> int:
        """Count how many fields were successfully recovered."""
        count = 0

        # Check project fields
        project = recovered.get('project', {})
        if project.get('name') == original.project_name:
            count += 1
        if project.get('type') == original.project_type:
            count += 1

        # Check phase and checkpoint
        if recovered.get('current_phase') == original.current_phase:
            count += 1
        if recovered.get('checkpoint') == original.checkpoint_id:
            count += 1

        # Check agent
        agents = recovered.get('agents', {})
        if agents.get('active') == original.active_agent:
            count += 1

        # Check agent history (3 fields)
        history = agents.get('history', [])
        for i, agent in enumerate(original.agent_history):
            if i < len(history) and history[i] == agent:
                count += 1

        # Check health
        health = recovered.get('health', {})
        if health.get('status') == original.health_status:
            count += 1
        if health.get('last_check') == original.last_check:
            count += 1

        return count

    def _try_parse_handoff(self, original: OriginalState) -> int:
        """Try to extract fields from handoff.md."""
        if not self.handoff_file.exists():
            return 0

        try:
            content = self.handoff_file.read_text()
            count = 0

            # Extract what we can from handoff
            if original.current_phase in content:
                count += 1
            if original.checkpoint_id in content:
                count += 1
            if original.project_name in content:
                count += 1
            if original.active_agent in content:
                count += 1
            if original.health_status in content:
                count += 1

            return count
        except Exception:
            return 0

    def _try_parse_checkpoint_log(self, original: OriginalState) -> int:
        """Try to extract fields from checkpoints.log."""
        if not self.checkpoint_log.exists():
            return 0

        try:
            content = self.checkpoint_log.read_text()
            count = 0

            # Can only recover checkpoint ID from log
            if original.checkpoint_id in content:
                count += 1

            return count
        except Exception:
            return 0


def run_single_trial(
    variant: str,
    corruption_level: int,
    trial: int
) -> RecoveryResult:
    """Run a single recovery trial for a variant."""

    with tempfile.TemporaryDirectory() as tmpdir:
        work_dir = Path(tmpdir)
        config = VARIANT_CONFIGS[variant]
        adapter = UWSVariantAdapter(config, work_dir)

        # Initialize and save clean state
        original = adapter.initialize()
        adapter.save_state(original)

        # Apply corruption to primary state file only
        adapter.apply_corruption(corruption_level)

        # Attempt recovery
        result = adapter.recover(original)
        result.corruption_level = corruption_level
        result.trial = trial

        return result


def run_component_study() -> List[RecoveryResult]:
    """Run the full component study experiment."""
    results = []
    total_experiments = len(VARIANTS) * len(CORRUPTION_LEVELS) * TRIALS_PER_CONDITION
    completed = 0

    print("=" * 70)
    print("Component Study: Testing UWS Design Variants")
    print("=" * 70)
    print(f"Variants: {', '.join(VARIANTS)}")
    print(f"Corruption levels: {CORRUPTION_LEVELS}")
    print(f"Trials per condition: {TRIALS_PER_CONDITION}")
    print(f"Total experiments: {total_experiments}")
    print("=" * 70)

    for variant in VARIANTS:
        print(f"\n{'='*60}")
        print(f"Testing: {variant}")
        print(f"Config: {VARIANT_CONFIGS[variant].description}")
        print(f"{'='*60}")

        for corruption_level in CORRUPTION_LEVELS:
            successes = 0
            times = []
            completeness_scores = []

            for trial in range(1, TRIALS_PER_CONDITION + 1):
                result = run_single_trial(variant, corruption_level, trial)
                results.append(result)

                if result.success:
                    successes += 1
                times.append(result.recovery_time_ms)
                completeness_scores.append(result.state_completeness)

                completed += 1

            # Print summary for this condition
            success_rate = successes / TRIALS_PER_CONDITION * 100
            mean_time = statistics.mean(times)
            mean_completeness = statistics.mean(completeness_scores)

            print(f"  Corruption {corruption_level:2d}%: "
                  f"Success={success_rate:5.1f}%, "
                  f"Time={mean_time:6.2f}ms, "
                  f"Completeness={mean_completeness:5.1f}%")

    print(f"\n{'='*70}")
    print(f"Completed {completed}/{total_experiments} experiments")
    print("=" * 70)

    return results


def compute_statistics(results: List[RecoveryResult]) -> Dict:
    """Compute aggregate statistics and hypothesis test data."""
    stats = {
        "by_variant": {},
        "by_variant_corruption": {},
        "hypothesis_data": {}
    }

    # Group by variant
    for variant in VARIANTS:
        variant_results = [r for r in results if r.variant == variant]

        successes = [r.success for r in variant_results]
        times = [r.recovery_time_ms for r in variant_results]
        completeness = [r.state_completeness for r in variant_results]

        stats["by_variant"][variant] = {
            "n": len(variant_results),
            "success_rate": sum(successes) / len(successes) * 100,
            "mean_time_ms": statistics.mean(times),
            "std_time_ms": statistics.stdev(times) if len(times) > 1 else 0,
            "mean_completeness": statistics.mean(completeness),
            "std_completeness": statistics.stdev(completeness) if len(completeness) > 1 else 0,
        }

        # Group by corruption level
        stats["by_variant_corruption"][variant] = {}
        for level in CORRUPTION_LEVELS:
            level_results = [r for r in variant_results if r.corruption_level == level]
            if level_results:
                l_successes = [r.success for r in level_results]
                l_times = [r.recovery_time_ms for r in level_results]
                l_completeness = [r.state_completeness for r in level_results]

                stats["by_variant_corruption"][variant][level] = {
                    "n": len(level_results),
                    "success_rate": sum(l_successes) / len(l_successes) * 100,
                    "mean_time_ms": statistics.mean(l_times),
                    "std_time_ms": statistics.stdev(l_times) if len(l_times) > 1 else 0,
                    "mean_completeness": statistics.mean(l_completeness),
                    "std_completeness": statistics.stdev(l_completeness) if len(l_completeness) > 1 else 0,
                    "success_values": l_successes,
                    "completeness_values": l_completeness,
                    "time_values": l_times,
                }

    # Prepare hypothesis test data
    # H1: full vs single (all corruption levels)
    stats["hypothesis_data"]["H1"] = {
        "description": "Redundant storage improves recovery success",
        "comparison": "UWS-full vs UWS-single",
        "full_success": [r.success for r in results if r.variant == "UWS-full"],
        "single_success": [r.success for r in results if r.variant == "UWS-single"],
    }

    # H2: full vs binary (high corruption: 50%+)
    high_corr_full = [r for r in results if r.variant == "UWS-full" and r.corruption_level >= 50]
    high_corr_binary = [r for r in results if r.variant == "UWS-binary" and r.corruption_level >= 50]
    stats["hypothesis_data"]["H2"] = {
        "description": "Human-readable formats degrade more gracefully",
        "comparison": "UWS-full vs UWS-binary at 50%+ corruption",
        "full_completeness": [r.state_completeness for r in high_corr_full],
        "binary_completeness": [r.state_completeness for r in high_corr_binary],
    }

    # H3: full vs no-handoff (high corruption: 75%+)
    very_high_full = [r for r in results if r.variant == "UWS-full" and r.corruption_level >= 75]
    very_high_no_handoff = [r for r in results if r.variant == "UWS-no-handoff" and r.corruption_level >= 75]
    stats["hypothesis_data"]["H3"] = {
        "description": "Handoff documents improve partial recovery",
        "comparison": "UWS-full vs UWS-no-handoff at 75%+ corruption",
        "full_completeness": [r.state_completeness for r in very_high_full],
        "no_handoff_completeness": [r.state_completeness for r in very_high_no_handoff],
    }

    # H4: binary vs full (0% corruption, time comparison)
    zero_full = [r for r in results if r.variant == "UWS-full" and r.corruption_level == 0]
    zero_binary = [r for r in results if r.variant == "UWS-binary" and r.corruption_level == 0]
    stats["hypothesis_data"]["H4"] = {
        "description": "Binary formats recover faster when uncorrupted",
        "comparison": "UWS-binary vs UWS-full at 0% corruption",
        "full_time": [r.recovery_time_ms for r in zero_full],
        "binary_time": [r.recovery_time_ms for r in zero_binary],
    }

    return stats


def save_results(results: List[RecoveryResult], stats: Dict, output_dir: Path) -> Dict[str, Path]:
    """Save results to JSON files."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Save raw results
    raw_file = output_dir / f"raw_results_{timestamp}.json"
    with open(raw_file, 'w') as f:
        json.dump([asdict(r) for r in results], f, indent=2)

    # Save statistics (excluding raw values for cleaner output)
    stats_clean = {
        "by_variant": stats["by_variant"],
        "by_variant_corruption": {
            v: {
                str(k): {key: val for key, val in data.items()
                        if not key.endswith('_values')}
                for k, data in levels.items()
            }
            for v, levels in stats["by_variant_corruption"].items()
        }
    }
    stats_file = output_dir / f"statistics_{timestamp}.json"
    with open(stats_file, 'w') as f:
        json.dump(stats_clean, f, indent=2)

    # Save hypothesis test data separately
    hyp_file = output_dir / f"hypothesis_data_{timestamp}.json"
    with open(hyp_file, 'w') as f:
        json.dump(stats["hypothesis_data"], f, indent=2)

    return {
        "raw": raw_file,
        "statistics": stats_file,
        "hypothesis": hyp_file,
    }


def print_summary(stats: Dict) -> None:
    """Print summary statistics."""
    print("\n" + "=" * 70)
    print("RESULTS SUMMARY")
    print("=" * 70)

    print("\nOverall Performance by Variant:")
    print("-" * 70)
    print(f"{'Variant':<20} {'Success%':>10} {'Time(ms)':>12} {'Completeness%':>15}")
    print("-" * 70)

    for variant, data in stats["by_variant"].items():
        print(f"{variant:<20} {data['success_rate']:>9.1f}% "
              f"{data['mean_time_ms']:>11.2f} {data['mean_completeness']:>14.1f}%")

    print("\n" + "=" * 70)
    print("HYPOTHESIS PREVIEW")
    print("=" * 70)

    # H1 preview
    h1 = stats["hypothesis_data"]["H1"]
    full_rate = sum(h1["full_success"]) / len(h1["full_success"]) * 100
    single_rate = sum(h1["single_success"]) / len(h1["single_success"]) * 100
    print(f"\nH1 (Redundancy): UWS-full={full_rate:.1f}% vs UWS-single={single_rate:.1f}%")
    print(f"    Difference: {full_rate - single_rate:+.1f} percentage points")

    # H2 preview
    h2 = stats["hypothesis_data"]["H2"]
    if h2["full_completeness"] and h2["binary_completeness"]:
        full_comp = statistics.mean(h2["full_completeness"])
        binary_comp = statistics.mean(h2["binary_completeness"])
        print(f"\nH2 (Format): UWS-full={full_comp:.1f}% vs UWS-binary={binary_comp:.1f}% completeness at 50%+ corruption")
        print(f"    Difference: {full_comp - binary_comp:+.1f} percentage points")

    # H3 preview
    h3 = stats["hypothesis_data"]["H3"]
    if h3["full_completeness"] and h3["no_handoff_completeness"]:
        full_comp = statistics.mean(h3["full_completeness"])
        no_handoff_comp = statistics.mean(h3["no_handoff_completeness"])
        print(f"\nH3 (Handoff): UWS-full={full_comp:.1f}% vs UWS-no-handoff={no_handoff_comp:.1f}% completeness at 75%+ corruption")
        print(f"    Difference: {full_comp - no_handoff_comp:+.1f} percentage points")

    # H4 preview
    h4 = stats["hypothesis_data"]["H4"]
    if h4["full_time"] and h4["binary_time"]:
        full_time = statistics.mean(h4["full_time"])
        binary_time = statistics.mean(h4["binary_time"])
        print(f"\nH4 (Speed): UWS-full={full_time:.3f}ms vs UWS-binary={binary_time:.3f}ms at 0% corruption")
        print(f"    Difference: {binary_time - full_time:+.3f}ms")


def main():
    """Main entry point."""
    # Setup output directory
    script_dir = Path(__file__).parent
    uws_root = script_dir.parent.parent
    output_dir = uws_root / "artifacts" / "component_study"
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Output directory: {output_dir}")
    print(f"Random seed: {RANDOM_SEED}")

    # Run experiments
    results = run_component_study()

    # Compute statistics
    stats = compute_statistics(results)

    # Save results
    files = save_results(results, stats, output_dir)
    print(f"\nResults saved to:")
    for name, path in files.items():
        print(f"  {name}: {path}")

    # Print summary
    print_summary(stats)

    print("\n" + "=" * 70)
    print("Component study complete!")
    print("Run component_study_statistics.py for full hypothesis testing.")
    print("=" * 70)


if __name__ == "__main__":
    main()
