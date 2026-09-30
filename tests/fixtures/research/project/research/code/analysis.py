"""Fixture analysis script: reads the pinned results file and prints one value."""
import json
import sys

RESULTS = "artifacts/model_results.json"


def cv_auc(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)["classification"]["Gradient Boosting"]["cv_auc_mean"]


if __name__ == "__main__":
    print(cv_auc(sys.argv[1] if len(sys.argv) > 1 else RESULTS))
