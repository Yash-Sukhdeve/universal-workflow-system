#!/usr/bin/env bats
# Research team: the gaps a release-readiness probe found by trying to get a wrong or
# unreported result past the gates (a hand-typed number under `uws:literal` or outside the
# results sections, a cross-validation value presented as held-out, an in-place ledger
# edit two commits back, a post-hoc plan change on a bare `D-<n>` line, a made-up
# publication approval), plus the smaller usability findings. Each test breaks the
# fixture of tests/fixtures/research/project in one way.

load '../helpers/test_helper'
load '../helpers/research_helper'
source "${PROJECT_ROOT}/scripts/lib/portable.sh"   # sed_inplace (BSD and GNU sed)

setup() {
    research_fixture_setup
}

teardown() {
    teardown_test_environment
}

line_of() {
    grep -nF -- "$1" "$P/paper/main.tex" | head -1 | cut -d: -f1
}

# A second output with a cross-validation and a held-out value under keys the old pattern
# did not recognise, and a count (not from a recorded run: the `numbers` check does not need one)
extra_results() {
    printf '{"cv5_accuracy_mean": 0.761, "kfold_acc": 0.75, "cvacc": 0.76, "cv10": 0.77, "acc": 0.70, "test_accuracy": 0.7042, "n_test": 115}\n' \
        > "$P/artifacts/extra_results.json"
}

# number_row <macro> <pointer> <evaluation> [extra json fields]: a complete row on extra_results.json
number_row() {
    printf '{"macro": "%s", "output": "artifacts/extra_results.json", "pointer": "%s", "rounding": "exact", "metric": "%s", "data_origin": "synthetic-generated", "evaluation": "%s", "exp": "EXP-LEAK", "inputs": ["research/data/raw/gb_scores.csv"]%s}' \
        "$1" "$2" "${4:-accuracy}" "$3" "${5:-}"
}

refresh_review_hash() {
    local h
    h="$(check manuscript-hash)"
    sed_inplace "s/^Manuscript: .*/Manuscript: ${h}/" "$P/research/reviews/REV-001.md"
    sed_inplace "s/^PUBLICATION-APPROVAL: .*/PUBLICATION-APPROVAL: ${h} by pi@lab.example/" "$P/research/pi/decisions.md"
}

# ── uws:literal is not a way around the number ledger ────────────────────────

@test "literal: a uws:literal number close to a ledger value is still reported" {
    printf '\nThe ROC-AUC on the synthetic data was 0.921. %% uws:literal copied from the results table\n' >> "$P/paper/main.tex"
    local l
    l="$(line_of 'was 0.921.')"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l} NUM-LITERAL hand-typed 0.921 is marked uws:literal, but it is close to N-0001 (0.912)"* ]] || false
}

@test "literal: a uws:literal number in a sentence that names a ledger metric needs a PI decision" {
    printf '\nThe ROC-AUC we report for the synthetic data is 0.55. %% uws:literal copied from the results table\n' >> "$P/paper/main.tex"
    local l
    l="$(line_of 'is 0.55.')"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l} NUM-LITERAL hand-typed 0.55 is marked uws:literal in a sentence about auc, a metric of the number ledger"* ]] || false
    # a recorded PI decision accepts it, and the publication gate lists it
    sed_inplace 's/% uws:literal copied from the results table/% uws:literal D-001 the value of the cited study/' "$P/paper/main.tex"
    run check numbers
    [ "$status" -eq 0 ]
    # an unrecorded decision does not
    sed_inplace 's/% uws:literal D-001 /% uws:literal D-009 /' "$P/paper/main.tex"
    run check numbers
    [ "$status" -eq 1 ]
}

# ── hand-typed results outside the results sections ──────────────────────────

@test "scope: Findings, Analysis and Performance sections are results sections" {
    printf '\n\\section{Findings}\nGrouped splits lowered the score to 0.77.\n' >> "$P/paper/main.tex"
    local l
    l="$(line_of 'score to 0.77')"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l} NUM-LITERAL hand-typed number 0.77"* ]] || false
}

@test "scope: outside the results sections a number is reported when its sentence names a ledger metric or it is a ledger value" {
    printf '\n\\section{Method}\nIn a pilot the ROC-AUC was 0.95.\nThe pilot also gave 0.9125 for the same score.\nWe used a learning rate of 0.05.\n' >> "$P/paper/main.tex"
    local l1 l2 l3
    l1="$(line_of 'ROC-AUC was 0.95')"
    l2="$(line_of 'gave 0.9125')"
    l3="$(line_of 'learning rate of 0.05')"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l1} NUM-LITERAL hand-typed number 0.95 in a sentence about auc, a metric of the number ledger"* ]] || false
    [[ "$output" == *"paper/main.tex:${l2} NUM-LITERAL hand-typed number 0.9125 is the value of N-0001"* ]] || false
    [[ "$output" != *"main.tex:${l3} "* ]] || false
}

@test "scope: a unit-less count near a ledger count is reported where results are" {
    extra_results
    run check numbers add "$(number_row '\\NTest' /n_test n/a 'held-out test rows (count)')"
    [ "$status" -eq 0 ]
    printf '\n\\section{Results}\nOn the 120 held-out test rows the score held.\nWe used 5 folds and 2026 data.\n' >> "$P/paper/main.tex"
    local l
    l="$(line_of 'On the 120 held-out')"
    run check numbers
    [[ "$output" == *"paper/main.tex:${l} NUM-LITERAL hand-typed 120 is close to N-0002 (115, held-out test rows (count))"* ]] || false
    [[ "$output" != *"hand-typed 5 "* && "$output" != *"hand-typed 2026"* ]] || false
}

# ── cross-validation values presented as held-out ───────────────────────────

@test "split: CV keys such as cv5_, kfold, cvacc and cv10 cannot be labelled held-out" {
    extra_results
    local p
    for p in /cv5_accuracy_mean /kfold_acc /cvacc /cv10; do
        run check numbers add "$(number_row '\\HeldAcc' "$p" held-out)"
        [ "$status" -eq 1 ]
        [[ "$output" == *"NUM-SPLIT"*"evaluation is held-out, but its metric/pointer describe a cross-validation value"* ]] || false
    done
    run check numbers add "$(number_row '\\HeldAcc' /test_accuracy held-out)"
    [ "$status" -eq 0 ]
}

@test "split: a held-out row whose key names no split, in a file that also holds CV values, is a warning" {
    extra_results
    run check numbers add "$(number_row '\\HeldAcc' /acc held-out)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NUM-SPLIT [warn] N-0002: evaluation is held-out, but pointer /acc names neither a test nor a held-out split, and artifacts/extra_results.json also holds cross-validation values"* ]] || false
}

@test "split: a CV value in a sentence that says held-out blocks at peer review; a negated mention does not" {
    research_make_reproducible
    printf '\nAfter tuning by five-fold cross-validation, the ROC-AUC on the held-out test rows of the synthetic data was \\GbAucCv{}.\n' >> "$P/paper/main.tex"
    refresh_review_hash
    commit_all "cv as held-out"
    local l
    l="$(line_of 'on the held-out test rows of the synthetic data was')"
    run check gate analysis
    [ "$status" -eq 0 ]
    [[ "$output" == *"paper/main.tex:${l} NUM-SPLIT [warn]"* ]] || false
    run check gate peer_review
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l} NUM-SPLIT \\GbAucCv (N-0001) is a cross-validation value in a sentence that also says 'held-out'"* ]] || false
    # a disclaimer is not a presentation as held-out
    sed_inplace 's/After tuning by five-fold cross-validation, the ROC-AUC on the held-out test rows of the synthetic data was \\GbAucCv{}./The five-fold cross-validation mean on the synthetic data was \\GbAucCv{}; it is a cross-validation estimate, not a held-out result./' "$P/paper/main.tex"
    refresh_review_hash
    commit_all "disclaimer"
    run check gate peer_review
    [ "$status" -eq 0 ]
    [[ "$output" != *"NUM-SPLIT"* ]] || false
}

# ── append-only ledgers ──────────────────────────────────────────────────────

# ── post-hoc plan changes ────────────────────────────────────────────────────

# ── the PI's publication approval ────────────────────────────────────────────

# ── C3: disclosure of synthetic data ─────────────────────────────────────────

# ── error messages ────────────────────────────────────────────────────────────

# ── defaults ──────────────────────────────────────────────────────────────────
