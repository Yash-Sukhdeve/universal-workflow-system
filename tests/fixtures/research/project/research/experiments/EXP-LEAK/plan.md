# EXP-LEAK: pre-registered plan

<!-- Synthetic fixture for the UWS research-team tests. Frozen with
     `research_check.py plan freeze EXP-LEAK`; see research/ledger/plans.jsonl. -->

## Hypothesis
C-0003: grouped-split AUC is lower than per-row AUC by more than one CV standard deviation.

## Unit of evaluation
Scenario. Each scenario appears three times in the data, so a row is not an independent unit.

## Baseline
Per-row 5-fold cross-validation ROC-AUC of the same Gradient Boosting model (N-0001).

## Metric
ROC-AUC, mean over the five folds, and its standard deviation over folds.

## Controls
Same model, hyperparameters, preprocessing and seed under both split schemes.

## Split and grouping
Per-row KFold(5) against GroupKFold(5) grouped by scenario_id; the held-out test row is not used.

## Sample size
All scenarios of the synthetic benchmark. No power analysis: this re-analyses a fixed dataset, and
the decision rule compares the two estimates with the fold-to-fold standard deviation.

## Decision rule
Supported if grouped AUC is below per-row AUC by more than one per-row fold standard deviation;
refuted otherwise. Both values are reported either way.

## Stopping condition
One run of each split scheme; no re-tuning after the grouped result is seen.
