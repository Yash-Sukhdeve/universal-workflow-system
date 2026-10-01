#!/usr/bin/env bash
# Shared helpers for the research-team tests (tests/integration/test_research_team*.bats).
# Load after test_helper: it relies on setup_test_environment and PROJECT_ROOT.

RFIX="${PROJECT_ROOT}/tests/fixtures/research"
CHECK="${PROJECT_ROOT}/scripts/research_check.py"

# Copy the reference project into $P and commit it in two steps, the way a real project
# is built: the frozen plan first, then the data, ledgers and paper. The plan-freeze check
# needs the freeze to be committed before any result.
research_fixture_setup() {
    command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
    setup_test_environment
    P="${TEST_TMP_DIR}"
    cp -R "${RFIX}/project/." "$P/"
    cd "$P" || return 1
    git add research/experiments research/ledger/plans.jsonl >/dev/null
    git commit -q -m "plan: freeze EXP-LEAK" >/dev/null
    git add -A research bib_sources paper artifacts >/dev/null
    git commit -q -m "fixture" >/dev/null
}

check() {
    python3 "$CHECK" --root "$P" "$@"
}

append_claim() {
    printf '%s\n' "$1" >> "$P/research/ledger/claims.jsonl"
}

# Append a revision of a number row with extra fields: add_revision <N-ID> '<json object>'
add_revision() {
    python3 - "$P/research/ledger/numbers.jsonl" "$1" "$2" << 'EOF'
import json, sys
path, nid, extra = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
rows = [json.loads(l) for l in open(path, encoding="utf-8") if l.strip()]
latest = [r for r in rows if r["id"] == nid][-1]
new = dict(latest)
new.update({"rev": latest.get("rev", 1) + 1, "supersedes": "%s@%d" % (nid, latest.get("rev", 1))})
for k, v in extra.items():
    if v is None:
        new.pop(k, None)
    else:
        new[k] = v
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(new) + "\n")
EOF
}

# Record RUN-0001 for N-0001 with the wrapper, link it, and run the repro job, committing
# each step (what the engineer does). Afterwards every gate of the fixture passes.
research_make_reproducible() {
    python3 "$CHECK" --root "$P" run --exp EXP-LEAK --input research/data/raw/gb_scores.csv \
        --output artifacts/model_results.json -- \
        python3 research/code/make_results.py research/data/raw/gb_scores.csv artifacts/model_results.json >/dev/null
    add_revision N-0001 '{"run": "RUN-0001"}'
    git -C "$P" add -A research artifacts >/dev/null
    git -C "$P" commit -q -m "run RUN-0001" >/dev/null
    python3 "$CHECK" --root "$P" repro all >/dev/null 2>&1
    git -C "$P" add -A research >/dev/null
    git -C "$P" commit -q -m "repro" >/dev/null
}

# A state.yaml like the one init writes, with research at the given phase.
research_state() {
    cat > "$P/.workflow/state.yaml" << EOF
project_type: "research"
goal: ""
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
research_phase: "$1"

phases:
  phase_1_planning:
    status: "active"
  phase_2_implementation:
    status: "pending"
  phase_3_validation:
    status: "pending"
  phase_4_delivery:
    status: "pending"
  phase_5_maintenance:
    status: "pending"

methodology_progress:

metadata:
  created: "2026-09-26T00:00:00"
EOF
    printf '# log\n' > "$P/.workflow/checkpoints.log"
}

phase_now() {
    grep '^research_phase:' "$P/.workflow/state.yaml" | cut -d: -f2 | tr -d ' "'
}

# write_plan <EXP-ID>: a complete plan without C-ID references.
write_plan() {
    mkdir -p "$P/research/experiments/$1"
    cat > "$P/research/experiments/$1/plan.md" << 'EOF'
# Plan

## Hypothesis
Grouped splits lower the AUC.

## Unit of evaluation
Scenario.

## Baseline
Per-row cross-validation.

## Metric
ROC-AUC, mean over folds.

## Controls
Same model and seed.

## Split and grouping
GroupKFold(5) by scenario_id.

## Sample size
All scenarios; fixed dataset.

## Decision rule
Supported if the grouped AUC is lower by more than one fold SD.

## Stopping condition
One run per split scheme.
EOF
}

# add_number '<json row>': append a number row; output_sha256 is computed from `output`, and
# the row's macro is added to the generated macro file.
add_number() {
    python3 - "$P" "$1" << 'EOF'
import hashlib, json, os, sys
root, row = sys.argv[1], json.loads(sys.argv[2])
row.setdefault("rev", 1)
row.setdefault("supersedes", None)
out = row.get("output")
if out and "output_sha256" not in row and os.path.isfile(os.path.join(root, out)):
    row["output_sha256"] = hashlib.sha256(open(os.path.join(root, out), "rb").read()).hexdigest()
with open(os.path.join(root, "research/ledger/numbers.jsonl"), "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row) + "\n")
if row.get("macro"):
    with open(os.path.join(root, "paper/generated/numbers.tex"), "a", encoding="utf-8") as fh:
        fh.write("\\newcommand{%s}{%s}\n" % (row["macro"], row["printed"]))
EOF
}

commit_all() {
    git -C "$P" add -A research artifacts paper bib_sources >/dev/null
    git -C "$P" commit -q -m "$1" >/dev/null
}
