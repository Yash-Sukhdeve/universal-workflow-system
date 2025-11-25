# Predictive Dataset for Workflow Context Recovery

**Paper**: Predicting Context Recovery Success in AI-Assisted Development
**Venue**: PROMISE 2026
**Dataset Version**: 1.0.0
**Generated**: November 2025

## Overview

This dataset contains 3,000 annotated workflow recovery scenarios for training and evaluating predictive models. Each scenario captures the outcome of recovering development context after an interruption.

## Dataset Statistics

| Metric | Value |
|--------|-------|
| Total entries | 3,000 |
| Unique scenarios | 1,000 |
| Trials per scenario | 3 |
| Features | 18 |
| Recovery time (mean) | 29.4ms |
| Recovery time (std dev) | 3.5ms |
| Success rate | 85.3% |

## Files

```
predictive_dataset/
├── README.md                    # This file
├── raw/
│   └── predictive_dataset_*.json    # Full dataset with all metadata
├── processed/
│   └── training_data_*.csv          # ML-ready CSV format
└── dataset_summary_*.json           # Summary statistics
```

## Features

### Numerical Features

| Feature | Description | Range |
|---------|-------------|-------|
| checkpoint_count | Number of checkpoints in workflow | 1-200 |
| state_lines | Lines in state.yaml file | 20-1000 |
| corruption_level | Percentage of file corruption | 0-90% |
| handoff_chars | Characters in handoff document | 500-25000 |
| skill_count | Number of enabled skills | 0-15 |
| time_since_checkpoint | Seconds since last checkpoint | 0-86400 |
| state_file_size_bytes | Size of state file | 1000-50000 |
| checkpoint_log_size_bytes | Size of checkpoint log | 80-16000 |
| total_workflow_files | Total files in .workflow/ | 5-20 |
| active_agent_count | Number of available agents | 2-5 |
| phase_progress_percent | Progress in current phase | 10-90% |
| has_blockers | Whether blockers exist | 0/1 |
| has_pending_actions | Whether pending actions exist | 0/1 |

### Categorical Features

| Feature | Values |
|---------|--------|
| state_complexity | minimal, low, medium, high, complex |
| project_type | ml_pipeline, web_dev, research, devops, data_eng, llm_app, mixed |
| agent_state | idle, active, handoff, transition |
| handoff_size | small, medium, large, very_large |
| interruption_type | clean, abrupt, crash, timeout |

### Target Variables

| Target | Type | Description |
|--------|------|-------------|
| recovery_success | Binary | Whether recovery succeeded (1) or failed (0) |
| recovery_time_ms | Continuous | Time to complete recovery in milliseconds |
| state_completeness_percent | Continuous | Percentage of context successfully recovered |

## Usage

### Loading the Dataset (Python)

```python
import pandas as pd

# Load CSV format
df = pd.read_csv('processed/training_data_YYYYMMDD_HHMMSS.csv')

# Split features and targets
feature_cols = ['checkpoint_count', 'state_lines', 'corruption_level', ...]
X = df[feature_cols]
y_time = df['recovery_time_ms']
y_success = df['recovery_success']
```

### Example: Train a Model

```python
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.model_selection import cross_val_score

# Train recovery time predictor
model = GradientBoostingRegressor(n_estimators=100, random_state=42)
scores = cross_val_score(model, X, y_time, cv=5, scoring='neg_mean_absolute_error')
print(f'MAE: {-scores.mean():.2f}ms')
```

## Benchmark Results

### Recovery Time Prediction

| Model | MAE (ms) | RMSE (ms) | R² |
|-------|----------|-----------|-----|
| Linear Regression | 2.2 | 3.1 | 0.152 |
| Ridge Regression | 2.2 | 3.1 | 0.152 |
| Random Forest | 1.2 | 1.9 | 0.718 |
| **Gradient Boosting** | **1.1** | **1.7** | **0.756** |

### Recovery Success Prediction

| Model | Accuracy | F1 Score | AUC-ROC |
|-------|----------|----------|---------|
| Logistic Regression | 0.856 | 0.917 | 0.904 |
| Random Forest | 0.845 | 0.909 | 0.907 |
| **Gradient Boosting** | **0.851** | **0.911** | **0.912** |

## Feature Importance

### Recovery Time (Top 5)
1. handoff_chars (r=0.531)
2. checkpoint_count (r=0.318)
3. checkpoint_log_size_bytes (r=0.318)
4. corruption_level (r=-0.068)
5. phase_progress_percent (r=-0.043)

### Recovery Success (Top 5)
1. corruption_level (r=-0.475)
2. interruption_type (categorical)
3. phase_progress_percent
4. time_since_checkpoint
5. project_type (categorical)

## Citation

If you use this dataset, please cite:

```bibtex
@inproceedings{uws2026promise,
  title={Predicting Context Recovery Success in AI-Assisted Development},
  author={Anonymous},
  booktitle={International Conference on Predictive Models and Data Analytics in Software Engineering (PROMISE)},
  year={2026}
}
```

## License

This dataset is released under CC BY 4.0. You may use, share, and adapt the data for any purpose, provided you give appropriate credit.

## Reproducibility

To regenerate this dataset:

```bash
# Install dependencies
pip install -r requirements.txt

# Generate dataset
python tests/benchmarks/predictive_dataset_generator.py

# Train models
python tests/benchmarks/train_predictive_models.py
```

## Contact

For questions about this dataset, please open an issue in the repository.
