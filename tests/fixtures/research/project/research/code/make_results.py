"""Fixture analysis: summarise per-fold scores into artifacts/model_results.json.

Usage: python3 research/code/make_results.py <scores.csv> <results.json>
"""
import csv
import json
import sys
from decimal import Decimal

NOTE = ("Synthetic test fixture for tests/integration/test_research_team.bats. "
        "These values are not a measurement.")


def summarise(scores_path):
    with open(scores_path, encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    folds = [Decimal(r["auc"]) for r in rows if r["split"] == "cv"]
    tests = [Decimal(r["auc"]) for r in rows if r["split"] == "test"]
    if not folds or len(tests) != 1:
        raise SystemExit("expected cross-validation folds and exactly one test row in %s" % scores_path)
    return {
        "_note": NOTE,
        "classification": {
            "Gradient Boosting": {
                "cv_auc_mean": float(sum(folds) / len(folds)),
                "test_auc": float(tests[0]),
            }
        },
    }


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: make_results.py <scores.csv> <results.json>")
    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        fh.write(json.dumps(summarise(sys.argv[1]), indent=2) + "\n")


if __name__ == "__main__":
    main()
