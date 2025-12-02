#!/usr/bin/env python3
"""
Baseline Computation for PROMISE 2026 Paper

Computes baseline model performance to demonstrate that ML models
add value beyond simple heuristics.

Baselines:
1. Random Baseline: Predict mean (regression) / majority class (classification)
2. Single-Feature Heuristic: "Predict failure if corruption_level > 50%"
3. Linear Models: Already computed in train_predictive_models.py

Output: baseline_results.json with metrics for each baseline
"""

import json
import warnings
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

warnings.filterwarnings('ignore')

try:
    import numpy as np
    import pandas as pd
    from scipy import stats
    from sklearn.model_selection import train_test_split, cross_val_score
    from sklearn.metrics import (
        mean_absolute_error, mean_squared_error, r2_score,
        accuracy_score, precision_score, recall_score, f1_score,
        roc_auc_score, confusion_matrix
    )
    DEPS_AVAILABLE = True
except ImportError as e:
    DEPS_AVAILABLE = False
    print(f"Error: Missing dependency - {e}")
    print("Install with: pip install numpy pandas scipy scikit-learn")

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent.parent
DATASET_DIR = PROJECT_ROOT / "artifacts" / "predictive_dataset"
OUTPUT_DIR = PROJECT_ROOT / "artifacts" / "baseline_results"
RANDOM_SEED = 42


def load_dataset() -> Optional[pd.DataFrame]:
    """Load the predictive dataset"""
    processed_dir = DATASET_DIR / "processed"

    if not processed_dir.exists():
        print(f"Error: Dataset directory not found: {processed_dir}")
        return None

    csv_files = list(processed_dir.glob("training_data_*.csv"))
    if not csv_files:
        print(f"Error: No CSV files found in {processed_dir}")
        return None

    latest_file = max(csv_files, key=lambda p: p.stat().st_mtime)
    print(f"Loading dataset: {latest_file.name}")

    return pd.read_csv(latest_file)


def compute_random_baseline(y_true: np.ndarray, task: str) -> Dict:
    """
    Compute random baseline metrics.

    For regression: predict mean value
    For classification: predict majority class
    """
    if task == "regression":
        y_pred = np.full_like(y_true, y_true.mean(), dtype=float)
        return {
            "strategy": "predict_mean",
            "predicted_value": float(y_true.mean()),
            "mae": float(mean_absolute_error(y_true, y_pred)),
            "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
            "r_squared": 0.0  # By definition, predicting mean gives R²=0
        }
    else:  # classification
        majority_class = int(np.bincount(y_true.astype(int)).argmax())
        y_pred = np.full_like(y_true, majority_class)

        # For AUC, we need probabilities - use majority class proportion
        majority_prob = (y_true == majority_class).mean()
        y_proba = np.full(len(y_true), majority_prob)

        return {
            "strategy": "predict_majority_class",
            "majority_class": majority_class,
            "class_distribution": {
                "class_0": int((y_true == 0).sum()),
                "class_1": int((y_true == 1).sum())
            },
            "accuracy": float(accuracy_score(y_true, y_pred)),
            "precision": float(precision_score(y_true, y_pred, zero_division=0)),
            "recall": float(recall_score(y_true, y_pred, zero_division=0)),
            "f1_score": float(f1_score(y_true, y_pred, zero_division=0)),
            "auc_roc": 0.5  # Random baseline by definition
        }


def compute_single_feature_heuristic(
    X: pd.DataFrame,
    y_true: np.ndarray,
    feature: str = "corruption_level",
    threshold: float = 0.5
) -> Dict:
    """
    Compute single-feature heuristic baseline.

    Rule: Predict failure (0) if corruption_level > threshold, else success (1)
    """
    corruption = X[feature].values
    y_pred = (corruption <= threshold).astype(int)

    # For AUC, use corruption level as "probability" of failure
    # Higher corruption = lower success probability
    y_proba = 1 - corruption  # Invert: low corruption = high success prob

    try:
        auc = float(roc_auc_score(y_true, y_proba))
    except ValueError:
        auc = 0.5

    cm = confusion_matrix(y_true, y_pred)

    return {
        "strategy": f"predict_success_if_{feature}_<=_{threshold}",
        "feature": feature,
        "threshold": threshold,
        "confusion_matrix": cm.tolist(),
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "f1_score": float(f1_score(y_true, y_pred, zero_division=0)),
        "auc_roc": auc
    }


def compute_corruption_regression_baseline(
    X: pd.DataFrame,
    y_true: np.ndarray,
    target_name: str
) -> Dict:
    """
    Simple baseline: Use corruption_level alone to predict recovery metrics.

    For completeness: predict (1 - corruption_level) * 100
    """
    corruption = X["corruption_level"].values

    if target_name == "state_completeness_percent":
        # Simple inverse relationship
        y_pred = (1 - corruption) * 100
    else:
        # For recovery time, use mean (no clear single-feature relationship)
        y_pred = np.full_like(y_true, y_true.mean(), dtype=float)

    return {
        "strategy": f"corruption_based_prediction",
        "target": target_name,
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "r_squared": float(r2_score(y_true, y_pred))
    }


def main():
    """Compute all baselines and save results"""
    if not DEPS_AVAILABLE:
        return 1

    # Load dataset
    df = load_dataset()
    if df is None:
        return 1

    print(f"Dataset loaded: {len(df)} samples")

    # Prepare features and targets
    feature_cols = [c for c in df.columns if c not in [
        'recovery_time_ms', 'recovery_success', 'state_completeness_percent',
        'scenario_id', 'trial'
    ]]

    X = df[feature_cols]
    y_time = df['recovery_time_ms'].values
    y_success = df['recovery_success'].values
    y_completeness = df['state_completeness_percent'].values

    # Convert recovery_success to binary
    y_success_binary = (y_success > 0.5).astype(int)

    print(f"\nClass distribution:")
    print(f"  Success (1): {y_success_binary.sum()} ({y_success_binary.mean()*100:.1f}%)")
    print(f"  Failure (0): {(1-y_success_binary).sum()} ({(1-y_success_binary.mean())*100:.1f}%)")

    # Compute baselines
    results = {
        "metadata": {
            "generated": datetime.now().isoformat(),
            "dataset_size": len(df),
            "random_seed": RANDOM_SEED
        },
        "classification_baselines": {},
        "regression_baselines": {}
    }

    # === Classification Baselines (Recovery Success) ===
    print("\n=== Classification Baselines (Recovery Success) ===")

    # 1. Random baseline (majority class)
    random_clf = compute_random_baseline(y_success_binary, "classification")
    results["classification_baselines"]["random_majority_class"] = random_clf
    print(f"\nRandom (Majority Class):")
    print(f"  Accuracy: {random_clf['accuracy']:.3f}")
    print(f"  F1 Score: {random_clf['f1_score']:.3f}")
    print(f"  AUC-ROC: {random_clf['auc_roc']:.3f}")

    # 2. Single-feature heuristic (corruption > 50%)
    for threshold in [0.3, 0.5, 0.7]:
        heuristic = compute_single_feature_heuristic(
            X, y_success_binary, "corruption_level", threshold
        )
        key = f"corruption_threshold_{int(threshold*100)}"
        results["classification_baselines"][key] = heuristic
        print(f"\nHeuristic (corruption <= {threshold}):")
        print(f"  Accuracy: {heuristic['accuracy']:.3f}")
        print(f"  F1 Score: {heuristic['f1_score']:.3f}")
        print(f"  AUC-ROC: {heuristic['auc_roc']:.3f}")

    # === Regression Baselines ===
    print("\n=== Regression Baselines (Recovery Time) ===")

    # 1. Random baseline (predict mean)
    random_reg = compute_random_baseline(y_time, "regression")
    results["regression_baselines"]["random_mean"] = random_reg
    print(f"\nRandom (Predict Mean):")
    print(f"  MAE: {random_reg['mae']:.2f} ms")
    print(f"  RMSE: {random_reg['rmse']:.2f} ms")
    print(f"  R²: {random_reg['r_squared']:.3f}")

    # 2. Corruption-based baseline for completeness
    print("\n=== Regression Baselines (State Completeness) ===")
    corruption_baseline = compute_corruption_regression_baseline(
        X, y_completeness, "state_completeness_percent"
    )
    results["regression_baselines"]["corruption_completeness"] = corruption_baseline
    print(f"\nCorruption-Based (completeness = 100 * (1 - corruption)):")
    print(f"  MAE: {corruption_baseline['mae']:.2f}%")
    print(f"  RMSE: {corruption_baseline['rmse']:.2f}%")
    print(f"  R²: {corruption_baseline['r_squared']:.3f}")

    # === Summary Table for Paper ===
    print("\n" + "="*60)
    print("SUMMARY FOR PAPER (Table: Baseline Comparison)")
    print("="*60)

    print("\nRecovery Success Classification:")
    print("-" * 50)
    print(f"{'Model':<30} {'AUC-ROC':>10} {'F1':>10}")
    print("-" * 50)
    print(f"{'Random (Majority Class)':<30} {0.500:>10.3f} {random_clf['f1_score']:>10.3f}")

    best_heuristic = results["classification_baselines"]["corruption_threshold_50"]
    print(f"{'Single-Feature (corr<=0.5)':<30} {best_heuristic['auc_roc']:>10.3f} {best_heuristic['f1_score']:>10.3f}")

    # Reference values from model_results (already computed)
    print(f"{'Logistic Regression':<30} {'0.904':>10} {'0.917':>10}")
    print(f"{'Gradient Boosting':<30} {'0.912':>10} {'0.911':>10}")

    print("\nRecovery Time Regression:")
    print("-" * 50)
    print(f"{'Model':<30} {'MAE (ms)':>10} {'R²':>10}")
    print("-" * 50)
    print(f"{'Random (Predict Mean)':<30} {random_reg['mae']:>10.2f} {0.000:>10.3f}")
    print(f"{'Linear Regression':<30} {'2.21':>10} {'0.152':>10}")
    print(f"{'Gradient Boosting':<30} {'1.10':>10} {'0.756':>10}")

    # Save results
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_file = OUTPUT_DIR / f"baseline_results_{timestamp}.json"

    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\nResults saved to: {output_file}")

    # Also save a simple version for the paper table
    paper_table = {
        "classification": [
            {"model": "Random Baseline", "auc_roc": 0.500, "f1_score": random_clf['f1_score']},
            {"model": "Single-Feature Heuristic", "auc_roc": best_heuristic['auc_roc'], "f1_score": best_heuristic['f1_score']},
            {"model": "Logistic Regression", "auc_roc": 0.904, "f1_score": 0.917},
            {"model": "Gradient Boosting", "auc_roc": 0.912, "f1_score": 0.911}
        ],
        "regression": [
            {"model": "Random Baseline", "mae_ms": random_reg['mae'], "r_squared": 0.0},
            {"model": "Linear Regression", "mae_ms": 2.21, "r_squared": 0.152},
            {"model": "Gradient Boosting", "mae_ms": 1.10, "r_squared": 0.756}
        ]
    }

    paper_file = OUTPUT_DIR / "paper_baseline_table.json"
    with open(paper_file, 'w') as f:
        json.dump(paper_table, f, indent=2)

    print(f"Paper table data saved to: {paper_file}")

    return 0


if __name__ == "__main__":
    exit(main())
