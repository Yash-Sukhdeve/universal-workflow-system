#!/usr/bin/env python3
"""
Predictive Model Training for PROMISE 2026 Paper

Trains and evaluates predictive models for:
1. Recovery time prediction (regression)
2. Recovery success prediction (classification)
3. State completeness prediction (regression)

Models:
- Linear Regression / Logistic Regression (baseline)
- Random Forest (ensemble)
- Gradient Boosting (ensemble)

Evaluation:
- Cross-validation (5-fold)
- MAE, RMSE for regression
- AUC-ROC, F1, Precision, Recall for classification
- Feature importance analysis

Citation: Universal Workflow System - PROMISE 2026
"""

import json
import os
import warnings
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import csv

# Suppress sklearn warnings for cleaner output
warnings.filterwarnings('ignore')

# Try imports
try:
    import numpy as np
    import pandas as pd
    from scipy import stats
    NUMPY_AVAILABLE = True
except ImportError:
    NUMPY_AVAILABLE = False
    print("Error: numpy/pandas/scipy required. Install with: pip install numpy pandas scipy")

try:
    from sklearn.model_selection import cross_val_score, train_test_split, KFold
    from sklearn.preprocessing import StandardScaler, LabelEncoder
    from sklearn.linear_model import LinearRegression, LogisticRegression, Ridge
    from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
    from sklearn.ensemble import GradientBoostingRegressor, GradientBoostingClassifier
    from sklearn.metrics import (
        mean_absolute_error, mean_squared_error, r2_score,
        accuracy_score, precision_score, recall_score, f1_score,
        roc_auc_score, confusion_matrix, classification_report
    )
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False
    print("Error: scikit-learn required. Install with: pip install scikit-learn")

# Configuration
PROJECT_ROOT = Path(__file__).parent.parent.parent
DATASET_DIR = PROJECT_ROOT / "artifacts" / "predictive_dataset"
MODELS_DIR = PROJECT_ROOT / "artifacts" / "predictive_models"
RANDOM_SEED = 42
CV_FOLDS = 5

# Feature definitions
CATEGORICAL_FEATURES = [
    'state_complexity', 'project_type', 'agent_state',
    'handoff_size', 'interruption_type'
]

NUMERICAL_FEATURES = [
    'checkpoint_count', 'state_lines', 'corruption_level',
    'handoff_chars', 'skill_count', 'time_since_checkpoint',
    'state_file_size_bytes', 'checkpoint_log_size_bytes',
    'total_workflow_files', 'active_agent_count', 'phase_progress_percent',
    'has_blockers', 'has_pending_actions'
]

# Target variables
REGRESSION_TARGET = 'recovery_time_ms'
CLASSIFICATION_TARGET = 'recovery_success'
COMPLETENESS_TARGET = 'state_completeness_percent'


def ensure_dirs():
    """Create necessary directories"""
    MODELS_DIR.mkdir(parents=True, exist_ok=True)


def load_dataset() -> Optional[pd.DataFrame]:
    """Load the most recent dataset"""
    processed_dir = DATASET_DIR / "processed"

    if not processed_dir.exists():
        print(f"Error: Dataset directory not found: {processed_dir}")
        return None

    # Find most recent CSV file
    csv_files = list(processed_dir.glob("training_data_*.csv"))
    if not csv_files:
        print("Error: No training data files found. Run predictive_dataset_generator.py first.")
        return None

    latest_file = max(csv_files, key=lambda x: x.stat().st_mtime)
    print(f"Loading dataset: {latest_file}")

    df = pd.read_csv(latest_file)
    print(f"Loaded {len(df)} samples with {len(df.columns)} features")

    return df


def preprocess_data(df: pd.DataFrame) -> Tuple[np.ndarray, Dict]:
    """Preprocess features for model training"""
    # Copy to avoid modifying original
    df_processed = df.copy()

    # Encode categorical features
    encoders = {}
    for col in CATEGORICAL_FEATURES:
        if col in df_processed.columns:
            le = LabelEncoder()
            df_processed[col] = le.fit_transform(df_processed[col].astype(str))
            encoders[col] = le

    # Select feature columns
    feature_cols = [c for c in NUMERICAL_FEATURES + CATEGORICAL_FEATURES if c in df_processed.columns]
    X = df_processed[feature_cols].values

    # Handle missing values
    X = np.nan_to_num(X, nan=0)

    return X, {"encoders": encoders, "feature_cols": feature_cols}


def calculate_confidence_interval(scores: np.ndarray, confidence: float = 0.95) -> Tuple[float, float]:
    """Calculate confidence interval for cross-validation scores"""
    n = len(scores)
    mean = np.mean(scores)
    se = stats.sem(scores)
    t_val = stats.t.ppf((1 + confidence) / 2, n - 1)
    ci_lower = mean - t_val * se
    ci_upper = mean + t_val * se
    return ci_lower, ci_upper


def train_regression_models(X: np.ndarray, y: np.ndarray, feature_names: List[str]) -> Dict:
    """Train and evaluate regression models for recovery time prediction"""
    print("\n" + "="*70)
    print("TRAINING REGRESSION MODELS (Recovery Time Prediction)")
    print("="*70)

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_SEED
    )

    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    results = {}
    models = {
        "Linear Regression": LinearRegression(),
        "Ridge Regression": Ridge(alpha=1.0),
        "Random Forest": RandomForestRegressor(n_estimators=100, random_state=RANDOM_SEED, n_jobs=-1),
        "Gradient Boosting": GradientBoostingRegressor(n_estimators=100, random_state=RANDOM_SEED),
    }

    for name, model in models.items():
        print(f"\n{name}:")

        # Cross-validation
        cv_scores_mae = -cross_val_score(model, X_train_scaled, y_train,
                                         cv=CV_FOLDS, scoring='neg_mean_absolute_error')
        cv_scores_rmse = np.sqrt(-cross_val_score(model, X_train_scaled, y_train,
                                                   cv=CV_FOLDS, scoring='neg_mean_squared_error'))

        # Train final model
        model.fit(X_train_scaled, y_train)
        y_pred = model.predict(X_test_scaled)

        # Calculate metrics
        mae = mean_absolute_error(y_test, y_pred)
        rmse = np.sqrt(mean_squared_error(y_test, y_pred))
        r2 = r2_score(y_test, y_pred)

        # Confidence intervals
        mae_ci = calculate_confidence_interval(cv_scores_mae)
        rmse_ci = calculate_confidence_interval(cv_scores_rmse)

        print(f"  CV MAE: {np.mean(cv_scores_mae):.2f}ms (95% CI: [{mae_ci[0]:.2f}, {mae_ci[1]:.2f}])")
        print(f"  CV RMSE: {np.mean(cv_scores_rmse):.2f}ms (95% CI: [{rmse_ci[0]:.2f}, {rmse_ci[1]:.2f}])")
        print(f"  Test MAE: {mae:.2f}ms")
        print(f"  Test RMSE: {rmse:.2f}ms")
        print(f"  R-squared: {r2:.4f}")

        # Feature importance (for tree-based models)
        feature_importance = None
        if hasattr(model, 'feature_importances_'):
            importance = model.feature_importances_
            feature_importance = sorted(
                zip(feature_names, importance),
                key=lambda x: x[1],
                reverse=True
            )[:10]
            print(f"  Top 5 features: {[f[0] for f in feature_importance[:5]]}")

        results[name] = {
            "cv_mae_mean": round(float(np.mean(cv_scores_mae)), 3),
            "cv_mae_std": round(float(np.std(cv_scores_mae)), 3),
            "cv_mae_ci_95": [round(mae_ci[0], 3), round(mae_ci[1], 3)],
            "cv_rmse_mean": round(float(np.mean(cv_scores_rmse)), 3),
            "cv_rmse_std": round(float(np.std(cv_scores_rmse)), 3),
            "cv_rmse_ci_95": [round(rmse_ci[0], 3), round(rmse_ci[1], 3)],
            "test_mae": round(mae, 3),
            "test_rmse": round(rmse, 3),
            "r_squared": round(r2, 4),
            "feature_importance": [(f, round(i, 4)) for f, i in feature_importance] if feature_importance else None
        }

    return results


def train_classification_models(X: np.ndarray, y: np.ndarray, feature_names: List[str]) -> Dict:
    """Train and evaluate classification models for recovery success prediction"""
    print("\n" + "="*70)
    print("TRAINING CLASSIFICATION MODELS (Recovery Success Prediction)")
    print("="*70)

    # Ensure binary labels
    y_binary = (y > 0.5).astype(int)

    # Check class distribution
    print(f"Class distribution: Success={sum(y_binary)}, Failure={len(y_binary)-sum(y_binary)}")

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y_binary, test_size=0.2, random_state=RANDOM_SEED, stratify=y_binary
    )

    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    results = {}
    models = {
        "Logistic Regression": LogisticRegression(max_iter=1000, random_state=RANDOM_SEED),
        "Random Forest": RandomForestClassifier(n_estimators=100, random_state=RANDOM_SEED, n_jobs=-1),
        "Gradient Boosting": GradientBoostingClassifier(n_estimators=100, random_state=RANDOM_SEED),
    }

    for name, model in models.items():
        print(f"\n{name}:")

        # Cross-validation
        cv_scores_acc = cross_val_score(model, X_train_scaled, y_train, cv=CV_FOLDS, scoring='accuracy')
        cv_scores_f1 = cross_val_score(model, X_train_scaled, y_train, cv=CV_FOLDS, scoring='f1')
        cv_scores_auc = cross_val_score(model, X_train_scaled, y_train, cv=CV_FOLDS, scoring='roc_auc')

        # Train final model
        model.fit(X_train_scaled, y_train)
        y_pred = model.predict(X_test_scaled)
        y_proba = model.predict_proba(X_test_scaled)[:, 1] if hasattr(model, 'predict_proba') else y_pred

        # Calculate metrics
        accuracy = accuracy_score(y_test, y_pred)
        precision = precision_score(y_test, y_pred, zero_division=0)
        recall = recall_score(y_test, y_pred, zero_division=0)
        f1 = f1_score(y_test, y_pred, zero_division=0)
        try:
            auc = roc_auc_score(y_test, y_proba)
        except:
            auc = 0.5

        # Confidence intervals
        acc_ci = calculate_confidence_interval(cv_scores_acc)
        f1_ci = calculate_confidence_interval(cv_scores_f1)
        auc_ci = calculate_confidence_interval(cv_scores_auc)

        print(f"  CV Accuracy: {np.mean(cv_scores_acc):.3f} (95% CI: [{acc_ci[0]:.3f}, {acc_ci[1]:.3f}])")
        print(f"  CV F1 Score: {np.mean(cv_scores_f1):.3f} (95% CI: [{f1_ci[0]:.3f}, {f1_ci[1]:.3f}])")
        print(f"  CV AUC-ROC: {np.mean(cv_scores_auc):.3f} (95% CI: [{auc_ci[0]:.3f}, {auc_ci[1]:.3f}])")
        print(f"  Test Accuracy: {accuracy:.3f}")
        print(f"  Test Precision: {precision:.3f}")
        print(f"  Test Recall: {recall:.3f}")
        print(f"  Test F1: {f1:.3f}")
        print(f"  Test AUC: {auc:.3f}")

        # Feature importance
        feature_importance = None
        if hasattr(model, 'feature_importances_'):
            importance = model.feature_importances_
            feature_importance = sorted(
                zip(feature_names, importance),
                key=lambda x: x[1],
                reverse=True
            )[:10]
            print(f"  Top 5 features: {[f[0] for f in feature_importance[:5]]}")

        # Confusion matrix
        cm = confusion_matrix(y_test, y_pred)
        print(f"  Confusion Matrix: TN={cm[0,0]}, FP={cm[0,1]}, FN={cm[1,0]}, TP={cm[1,1]}")

        results[name] = {
            "cv_accuracy_mean": round(float(np.mean(cv_scores_acc)), 4),
            "cv_accuracy_ci_95": [round(acc_ci[0], 4), round(acc_ci[1], 4)],
            "cv_f1_mean": round(float(np.mean(cv_scores_f1)), 4),
            "cv_f1_ci_95": [round(f1_ci[0], 4), round(f1_ci[1], 4)],
            "cv_auc_mean": round(float(np.mean(cv_scores_auc)), 4),
            "cv_auc_ci_95": [round(auc_ci[0], 4), round(auc_ci[1], 4)],
            "test_accuracy": round(accuracy, 4),
            "test_precision": round(precision, 4),
            "test_recall": round(recall, 4),
            "test_f1": round(f1, 4),
            "test_auc": round(auc, 4),
            "confusion_matrix": cm.tolist(),
            "feature_importance": [(f, round(i, 4)) for f, i in feature_importance] if feature_importance else None
        }

    return results


def train_completeness_models(X: np.ndarray, y: np.ndarray, feature_names: List[str]) -> Dict:
    """Train models for state completeness prediction"""
    print("\n" + "="*70)
    print("TRAINING REGRESSION MODELS (State Completeness Prediction)")
    print("="*70)

    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_SEED
    )

    # Scale features
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    results = {}
    models = {
        "Random Forest": RandomForestRegressor(n_estimators=100, random_state=RANDOM_SEED, n_jobs=-1),
        "Gradient Boosting": GradientBoostingRegressor(n_estimators=100, random_state=RANDOM_SEED),
    }

    for name, model in models.items():
        print(f"\n{name}:")

        # Cross-validation
        cv_scores_mae = -cross_val_score(model, X_train_scaled, y_train,
                                         cv=CV_FOLDS, scoring='neg_mean_absolute_error')

        # Train final model
        model.fit(X_train_scaled, y_train)
        y_pred = model.predict(X_test_scaled)

        mae = mean_absolute_error(y_test, y_pred)
        rmse = np.sqrt(mean_squared_error(y_test, y_pred))
        r2 = r2_score(y_test, y_pred)

        mae_ci = calculate_confidence_interval(cv_scores_mae)

        print(f"  CV MAE: {np.mean(cv_scores_mae):.2f}% (95% CI: [{mae_ci[0]:.2f}, {mae_ci[1]:.2f}])")
        print(f"  Test MAE: {mae:.2f}%")
        print(f"  Test RMSE: {rmse:.2f}%")
        print(f"  R-squared: {r2:.4f}")

        feature_importance = None
        if hasattr(model, 'feature_importances_'):
            importance = model.feature_importances_
            feature_importance = sorted(
                zip(feature_names, importance),
                key=lambda x: x[1],
                reverse=True
            )[:10]

        results[name] = {
            "cv_mae_mean": round(float(np.mean(cv_scores_mae)), 3),
            "cv_mae_ci_95": [round(mae_ci[0], 3), round(mae_ci[1], 3)],
            "test_mae": round(mae, 3),
            "test_rmse": round(rmse, 3),
            "r_squared": round(r2, 4),
            "feature_importance": [(f, round(i, 4)) for f, i in feature_importance] if feature_importance else None
        }

    return results


def analyze_feature_importance(df: pd.DataFrame, preprocess_info: Dict) -> Dict:
    """Comprehensive feature importance analysis"""
    print("\n" + "="*70)
    print("FEATURE IMPORTANCE ANALYSIS")
    print("="*70)

    feature_names = preprocess_info["feature_cols"]

    # Correlation with targets
    correlations = {}
    for target in [REGRESSION_TARGET, CLASSIFICATION_TARGET, COMPLETENESS_TARGET]:
        if target in df.columns:
            corr_values = {}
            for feature in feature_names:
                if feature in df.columns and df[feature].dtype in ['int64', 'float64']:
                    corr, p_value = stats.spearmanr(df[feature], df[target])
                    corr_values[feature] = {
                        "correlation": round(float(corr), 4),
                        "p_value": round(float(p_value), 6),
                        "significant": bool(p_value < 0.05)
                    }
            correlations[target] = corr_values

    # Print top correlations
    print("\nTop correlations with recovery_time_ms:")
    if REGRESSION_TARGET in correlations:
        sorted_corrs = sorted(
            correlations[REGRESSION_TARGET].items(),
            key=lambda x: abs(x[1]["correlation"]),
            reverse=True
        )[:5]
        for feat, vals in sorted_corrs:
            sig = "*" if vals["significant"] else ""
            print(f"  {feat}: r={vals['correlation']:.3f}{sig}")

    print("\nTop correlations with recovery_success:")
    if CLASSIFICATION_TARGET in correlations:
        sorted_corrs = sorted(
            correlations[CLASSIFICATION_TARGET].items(),
            key=lambda x: abs(x[1]["correlation"]),
            reverse=True
        )[:5]
        for feat, vals in sorted_corrs:
            sig = "*" if vals["significant"] else ""
            print(f"  {feat}: r={vals['correlation']:.3f}{sig}")

    return correlations


def generate_latex_tables(results: Dict):
    """Generate LaTeX tables for paper"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Regression results table
    regression_tex = r"""% Auto-generated table for PROMISE 2026
\begin{table}[t]
    \centering
    \caption{Recovery Time Prediction Results (5-fold CV)}
    \label{tab:regression-results}
    \begin{tabular}{lrrr}
        \toprule
        \textbf{Model} & \textbf{MAE (ms)} & \textbf{RMSE (ms)} & \textbf{$R^2$} \\
        \midrule
"""
    for model, metrics in results.get("regression", {}).items():
        mae = metrics["cv_mae_mean"]
        mae_ci = metrics["cv_mae_ci_95"]
        rmse = metrics["cv_rmse_mean"]
        r2 = metrics["r_squared"]
        regression_tex += f"        {model} & {mae:.1f} [{mae_ci[0]:.1f}, {mae_ci[1]:.1f}] & {rmse:.1f} & {r2:.3f} \\\\\n"

    regression_tex += r"""        \bottomrule
    \end{tabular}
\end{table}
"""

    # Classification results table
    classification_tex = r"""% Auto-generated table for PROMISE 2026
\begin{table}[t]
    \centering
    \caption{Recovery Success Prediction Results (5-fold CV)}
    \label{tab:classification-results}
    \begin{tabular}{lrrr}
        \toprule
        \textbf{Model} & \textbf{Accuracy} & \textbf{F1 Score} & \textbf{AUC-ROC} \\
        \midrule
"""
    for model, metrics in results.get("classification", {}).items():
        acc = metrics["cv_accuracy_mean"]
        f1 = metrics["cv_f1_mean"]
        auc = metrics["cv_auc_mean"]
        classification_tex += f"        {model} & {acc:.3f} & {f1:.3f} & {auc:.3f} \\\\\n"

    classification_tex += r"""        \bottomrule
    \end{tabular}
\end{table}
"""

    # Save tables
    tables_dir = PROJECT_ROOT / "paper" / "tables"
    tables_dir.mkdir(parents=True, exist_ok=True)

    (tables_dir / "prediction_regression.tex").write_text(regression_tex)
    (tables_dir / "prediction_classification.tex").write_text(classification_tex)

    print(f"\nLaTeX tables saved to: {tables_dir}")


def main():
    """Main training pipeline"""
    if not NUMPY_AVAILABLE or not SKLEARN_AVAILABLE:
        print("Error: Required packages not available.")
        print("Install with: pip install numpy pandas scipy scikit-learn")
        return None

    print("="*70)
    print("PROMISE 2026 Predictive Model Training")
    print("="*70)
    print(f"Timestamp: {datetime.now().isoformat()}")
    print(f"Random seed: {RANDOM_SEED}")
    print(f"CV folds: {CV_FOLDS}")

    ensure_dirs()

    # Load dataset
    df = load_dataset()
    if df is None:
        return None

    # Preprocess
    X, preprocess_info = preprocess_data(df)
    feature_names = preprocess_info["feature_cols"]

    print(f"\nFeature matrix shape: {X.shape}")
    print(f"Features: {feature_names}")

    results = {
        "metadata": {
            "generated": datetime.now().isoformat(),
            "dataset_size": len(df),
            "features": feature_names,
            "random_seed": RANDOM_SEED,
            "cv_folds": CV_FOLDS,
            "paper": "PROMISE 2026 - Predicting Context Recovery in AI-Assisted Development"
        }
    }

    # Train regression models (recovery time)
    if REGRESSION_TARGET in df.columns:
        y_regression = df[REGRESSION_TARGET].values
        results["regression"] = train_regression_models(X, y_regression, feature_names)

    # Train classification models (recovery success)
    if CLASSIFICATION_TARGET in df.columns:
        y_classification = df[CLASSIFICATION_TARGET].values
        results["classification"] = train_classification_models(X, y_classification, feature_names)

    # Train completeness models
    if COMPLETENESS_TARGET in df.columns:
        y_completeness = df[COMPLETENESS_TARGET].values
        results["completeness"] = train_completeness_models(X, y_completeness, feature_names)

    # Feature importance analysis
    results["feature_correlations"] = analyze_feature_importance(df, preprocess_info)

    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = MODELS_DIR / f"model_results_{timestamp}.json"

    with open(results_file, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\nResults saved to: {results_file}")

    # Generate LaTeX tables
    generate_latex_tables(results)

    # Print summary
    print("\n" + "="*70)
    print("TRAINING SUMMARY")
    print("="*70)

    if "regression" in results:
        best_reg = min(results["regression"].items(), key=lambda x: x[1]["cv_mae_mean"])
        print(f"\nBest Recovery Time Model: {best_reg[0]}")
        print(f"  MAE: {best_reg[1]['cv_mae_mean']:.2f}ms")
        print(f"  RMSE: {best_reg[1]['cv_rmse_mean']:.2f}ms")

    if "classification" in results:
        best_clf = max(results["classification"].items(), key=lambda x: x[1]["cv_auc_mean"])
        print(f"\nBest Recovery Success Model: {best_clf[0]}")
        print(f"  Accuracy: {best_clf[1]['cv_accuracy_mean']:.3f}")
        print(f"  AUC-ROC: {best_clf[1]['cv_auc_mean']:.3f}")

    print("="*70)

    return results


if __name__ == "__main__":
    main()
