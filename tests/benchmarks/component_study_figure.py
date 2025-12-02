#!/usr/bin/env python3
"""
Generate degradation curve figure for component study.

Creates Figure: Recovery success rate degradation by variant across corruption levels,
with 95% CI bands from bootstrap.

Following R5 (Reproducibility): Fixed seed, all parameters documented.
"""

import json
import random
import statistics
from pathlib import Path
from typing import Dict, List, Tuple

# Reproducibility
RANDOM_SEED = 42
random.seed(RANDOM_SEED)

BOOTSTRAP_ITERATIONS = 1000
CORRUPTION_LEVELS = [0, 5, 10, 25, 50, 75, 90]
VARIANTS = ["UWS-full", "UWS-single", "UWS-no-handoff", "UWS-binary"]

# Variant display properties
VARIANT_COLORS = {
    "UWS-full": "#2ecc71",       # Green
    "UWS-single": "#e74c3c",     # Red
    "UWS-no-handoff": "#3498db", # Blue
    "UWS-binary": "#9b59b6",     # Purple
}

VARIANT_MARKERS = {
    "UWS-full": "o",
    "UWS-single": "s",
    "UWS-no-handoff": "^",
    "UWS-binary": "D",
}


def bootstrap_ci(data: List[float], n_iterations: int = 1000, ci: float = 0.95) -> Tuple[float, float]:
    """Compute bootstrap CI for mean."""
    if not data:
        return 0.0, 0.0

    means = []
    for _ in range(n_iterations):
        sample = [random.choice(data) for _ in range(len(data))]
        means.append(statistics.mean(sample))

    means.sort()
    lower_idx = int((1 - ci) / 2 * n_iterations)
    upper_idx = int((1 + ci) / 2 * n_iterations) - 1

    return means[lower_idx], means[upper_idx]


def load_raw_results(artifacts_dir: Path) -> List[Dict]:
    """Load most recent raw results."""
    files = list(artifacts_dir.glob("raw_results_*.json"))
    if not files:
        raise FileNotFoundError("No raw results found")

    latest = max(files, key=lambda p: p.stat().st_mtime)
    print(f"Loading: {latest}")

    with open(latest) as f:
        return json.load(f)


def compute_degradation_data(results: List[Dict]) -> Dict:
    """Compute success rates and CIs by variant and corruption level."""
    data = {}

    for variant in VARIANTS:
        data[variant] = {
            "corruption": [],
            "success_rate": [],
            "ci_lower": [],
            "ci_upper": [],
        }

        for level in CORRUPTION_LEVELS:
            # Filter results for this variant and level
            level_results = [
                r for r in results
                if r["variant"] == variant and r["corruption_level"] == level
            ]

            if not level_results:
                continue

            # Compute success rate
            successes = [1.0 if r["success"] else 0.0 for r in level_results]
            success_rate = statistics.mean(successes) * 100

            # Bootstrap CI
            ci_low, ci_high = bootstrap_ci(successes, BOOTSTRAP_ITERATIONS)

            data[variant]["corruption"].append(level)
            data[variant]["success_rate"].append(success_rate)
            data[variant]["ci_lower"].append(ci_low * 100)
            data[variant]["ci_upper"].append(ci_high * 100)

    return data


def generate_figure_matplotlib(data: Dict, output_path: Path) -> None:
    """Generate figure using matplotlib."""
    try:
        import matplotlib
        matplotlib.use('Agg')  # Non-interactive backend
        import matplotlib.pyplot as plt
    except ImportError:
        print("matplotlib not available, generating ASCII version")
        generate_figure_ascii(data, output_path)
        return

    fig, ax = plt.subplots(figsize=(8, 5))

    for variant in VARIANTS:
        d = data[variant]
        color = VARIANT_COLORS[variant]
        marker = VARIANT_MARKERS[variant]

        # Plot main line
        ax.plot(d["corruption"], d["success_rate"],
                color=color, marker=marker, linewidth=2,
                label=variant, markersize=6)

        # Plot CI band
        ax.fill_between(d["corruption"], d["ci_lower"], d["ci_upper"],
                       color=color, alpha=0.2)

    ax.set_xlabel("Corruption Level (%)", fontsize=11)
    ax.set_ylabel("Recovery Success Rate (%)", fontsize=11)
    ax.set_title("Recovery Resilience: UWS Design Variants", fontsize=12)
    ax.set_xlim(-2, 92)
    ax.set_ylim(-5, 105)
    ax.legend(loc="lower left", fontsize=9)
    ax.grid(True, alpha=0.3)

    # Add annotation for key finding
    ax.annotate("Full redundancy\nmaintains 100%",
                xy=(50, 100), xytext=(60, 85),
                fontsize=8, ha='left',
                arrowprops=dict(arrowstyle='->', color='gray', lw=0.5))

    ax.annotate("No redundancy\nfails at 5%",
                xy=(5, 0), xytext=(15, 25),
                fontsize=8, ha='left',
                arrowprops=dict(arrowstyle='->', color='gray', lw=0.5))

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()

    print(f"Figure saved to: {output_path}")


def generate_figure_ascii(data: Dict, output_path: Path) -> None:
    """Generate ASCII representation when matplotlib unavailable."""
    lines = [
        "Recovery Success Rate by Corruption Level",
        "=" * 60,
        "",
        "     | 0%   5%  10%  25%  50%  75%  90%",
        "-----+----------------------------------",
    ]

    for variant in VARIANTS:
        d = data[variant]
        rates = " ".join(f"{r:>4.0f}" for r in d["success_rate"])
        lines.append(f"{variant:<13}| {rates}")

    lines.extend([
        "",
        "Legend:",
        "  UWS-full: Full redundancy (YAML + handoff + log)",
        "  UWS-single: No redundancy (YAML only)",
        "  UWS-no-handoff: Partial (YAML + log)",
        "  UWS-binary: Binary encoding (MessagePack + log)",
    ])

    content = "\n".join(lines)

    # Save as text file alongside any PNG attempt
    txt_path = output_path.with_suffix('.txt')
    txt_path.write_text(content)
    print(f"ASCII table saved to: {txt_path}")


def main():
    """Main entry point."""
    script_dir = Path(__file__).parent
    uws_root = script_dir.parent.parent
    artifacts_dir = uws_root / "artifacts" / "component_study"
    figures_dir = uws_root / "paper" / "figures"

    figures_dir.mkdir(parents=True, exist_ok=True)

    # Load results
    results = load_raw_results(artifacts_dir)
    print(f"Loaded {len(results)} results")

    # Compute degradation data
    data = compute_degradation_data(results)

    # Print summary
    print("\nSuccess Rate by Variant and Corruption:")
    print("-" * 60)
    for variant in VARIANTS:
        d = data[variant]
        print(f"{variant}:")
        for i, level in enumerate(d["corruption"]):
            rate = d["success_rate"][i]
            ci_l, ci_h = d["ci_lower"][i], d["ci_upper"][i]
            print(f"  {level:2d}%: {rate:5.1f}% [{ci_l:5.1f}, {ci_h:5.1f}]")

    # Generate figure
    output_path = figures_dir / "fig_component_degradation.png"
    generate_figure_matplotlib(data, output_path)

    print("\nDone!")


if __name__ == "__main__":
    main()
