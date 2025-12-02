# Research Archive

This directory contains research materials and academic paper submissions related to the Universal Workflow System.

## PROMISE 2026 Submission

**Title**: "Predicting Workflow Recovery in AI-Assisted Development: A Synthetic Benchmark and Empirical Study"

**Status**: Draft (under review iterations)

### Contents

```
promise-2026/
├── paper/              # LaTeX paper source
├── artifacts/          # Research artifacts and results
│   ├── component_study/     # 840 experiments data
│   ├── predictive_dataset/  # 3,000 scenario dataset
│   └── predictive_models/   # Trained ML models
├── benchmarks/         # Experiment scripts
├── replication/        # Docker replication package
└── docs/              # Research documentation
```

### Key Results

- Recovery time prediction: MAE = 1.1ms (R² = 0.756)
- Recovery success prediction: AUC-ROC = 0.912
- Component study: 4/4 hypotheses supported (p < 0.0001)

### Running Experiments

```bash
cd promise-2026

# Generate predictive dataset
python benchmarks/predictive_dataset_generator.py

# Train models
python benchmarks/train_predictive_models.py

# Run component study
python benchmarks/component_study_benchmark.py
```

### Citation

If you use this research, please cite:
```bibtex
@inproceedings{uws2026,
  title={Predicting Workflow Recovery in AI-Assisted Development},
  author={Anonymous},
  booktitle={PROMISE 2026},
  year={2026}
}
```

---

*Note: This research validates UWS design decisions but is separate from the production workflow system. Users should use the main UWS installation, not these research scripts.*
