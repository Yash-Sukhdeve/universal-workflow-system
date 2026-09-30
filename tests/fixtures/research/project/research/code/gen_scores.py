"""Fixture generator: synthetic per-fold ROC-AUC values for the research-team tests.

The values are synthetic by construction: five cross-validation folds whose mean is exactly
0.9125, plus one held-out test value of 0.9199. They are not measurements.

Usage: python3 research/code/gen_scores.py --seed 7 --out research/data/raw/gb_scores.csv
"""
import argparse
import csv
import random
from decimal import Decimal

CV_CENTRE = Decimal("0.9125")
TEST_AUC = Decimal("0.9199")


def fold_scores(seed):
    rng = random.Random(seed)
    offsets = [Decimal(rng.randint(-60, 60)) / Decimal(10000) for _ in range(4)]
    offsets.append(-sum(offsets))
    return [CV_CENTRE + off for off in offsets]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    with open(args.out, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(["split", "fold", "auc"])
        for i, auc in enumerate(fold_scores(args.seed), 1):
            writer.writerow(["cv", i, auc])
        writer.writerow(["test", "", TEST_AUC])


if __name__ == "__main__":
    main()
