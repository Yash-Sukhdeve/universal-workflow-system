#!/usr/bin/env bats
# Research team, field-test fixes (docs/design/research-team.md section 11b).
#
# The first real use of the research checks was an audit of the PROMISE 2026 paper
# (github.com/Yash-Sukhdeve/uws-promise-2026 at 778ab9a). Each test here reproduces one
# integrity gap, miss, false positive or friction point that audit found. Lines quoted
# from the paper are verbatim copies in tests/fixtures/research/promise/.

load '../helpers/test_helper'
load '../helpers/research_helper'
source "${PROJECT_ROOT}/scripts/lib/portable.sh"   # sed_inplace (BSD and GNU sed)

PROMISE="${RFIX}/promise"

setup() {
    research_fixture_setup
}

teardown() {
    if [[ -n "${NOSTATE:-}" && -d "${NOSTATE}" ]]; then
        rm -rf "${NOSTATE}"
    fi
    teardown_test_environment
}

# line_of <fixed text>: the line of paper/main.tex that contains it.
line_of() {
    grep -nF -- "$1" "$P/paper/main.tex" | head -1 | cut -d: -f1
}

# ── P0: pre-registration order ───────────────────────────────────────────────

@test "P0 PLAN-ORDER: a results file committed before the freeze fails, even when its ledger row comes later" {
    write_plan EXP-LATE
    printf '{"auc": 0.95}\n' > "$P/artifacts/results.json"
    commit_all "results written and committed first"
    run check plan freeze EXP-LATE
    [ "$status" -eq 0 ]
    commit_all "plan frozen after the results existed"
    add_number '{"id":"N-0002","macro":"\\LateAuc","printed":"0.95","raw":0.95,"rounding":"exact","metric":"held-out AUC","output":"artifacts/results.json","pointer":"/auc","data_origin":"measured","evaluation":"held-out","exp":"EXP-LATE","inputs":[]}'
    commit_all "ledger row added after the freeze"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-ORDER EXP-LATE: N-0002"* ]]
    [[ "$output" == *"artifacts/results.json was first committed in"* ]]
}

@test "P0 PLAN-ORDER: a run executed before the freeze fails, even when its record is committed after it" {
    write_plan EXP-EARLY
    commit_all "plan written, not frozen"
    check run --exp exploratory --input research/data/raw/gb_scores.csv --output artifacts/early.json -- \
        python3 research/code/make_results.py research/data/raw/gb_scores.csv artifacts/early.json >/dev/null
    check plan freeze EXP-EARLY >/dev/null
    git -C "$P" add research/ledger/plans.jsonl
    git -C "$P" commit -q -m "freeze only"
    add_number '{"id":"N-0002","macro":"\\EarlyAuc","printed":"0.912","raw":0.9125,"rounding":"floor:3","metric":"5-fold CV mean ROC-AUC","output":"artifacts/early.json","pointer":"/classification/Gradient Boosting/cv_auc_mean","data_origin":"synthetic-generated","evaluation":"cross-validation","exp":"EXP-EARLY","run":"RUN-0001"}'
    commit_all "run record and row committed after the freeze"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-ORDER EXP-EARLY: RUN-0001 (N-0002) ran on commit"* ]]
    [[ "$output" == *"which does not contain the freeze"* ]]
}

@test "P0 PLAN-ORDER: a run on a tree that contains the committed freeze passes" {
    write_plan EXP-OK
    check plan freeze EXP-OK >/dev/null
    commit_all "plan frozen"
    check run --exp EXP-OK --input research/data/raw/gb_scores.csv --output artifacts/ok.json -- \
        python3 research/code/make_results.py research/data/raw/gb_scores.csv artifacts/ok.json >/dev/null
    add_number '{"id":"N-0002","macro":"\\OkAuc","printed":"0.912","raw":0.9125,"rounding":"floor:3","metric":"5-fold CV mean ROC-AUC","output":"artifacts/ok.json","pointer":"/classification/Gradient Boosting/cv_auc_mean","data_origin":"synthetic-generated","evaluation":"cross-validation","exp":"EXP-OK","run":"RUN-0001"}'
    commit_all "results"
    run check plan
    echo "$output"
    [ "$status" -eq 0 ]
}

# ── P0: C6 on real PROMISE sentences ────────────────────────────────────────

@test "P0 C6: 'ground truth' next to LaTeX commands in the real PROMISE lines is caught" {
    printf 'id,label\n1,ok\n' > "$P/research/data/raw/labels.csv"
    check data add research/data/raw/labels.csv --source "generator" --version 1 --split none \
        --origin measured --labels generator-rule >/dev/null
    { printf '\n\\section{Introduction}\n'; cat "$PROMISE/intro-contribution.tex"; printf '\n'; cat "$PROMISE/approach-platform.tex"; } >> "$P/paper/main.tex"
    local l1 l2
    l1="$(line_of 'our benchmark provides ground-truth')"
    l2="$(line_of 'Why UWS as Platform')"
    run check slop
    echo "$output"
    [[ "$output" == *"paper/main.tex:${l1} C6 [warn] 'ground-truth'"* ]]
    [[ "$output" == *"paper/main.tex:${l1} C6 [warn] 'annotated'"* ]]
    [[ "$output" == *"paper/main.tex:${l2} C6 [warn] 'ground-truth'"* ]]
}

@test "P0 C6: a claim row that records the sentence as resting on generator data makes C6 block" {
    printf 'id,label\n1,ok\n' > "$P/research/data/raw/labels.csv"
    check data add research/data/raw/labels.csv --source "generator" --version 1 --split none \
        --origin measured --labels generator-rule >/dev/null
    { printf '\n'; cat "$PROMISE/approach-dataset.tex"; } >> "$P/paper/main.tex"
    local l
    l="$(line_of 'records ground-truth outcomes')"
    run check slop
    [[ "$output" == *"paper/main.tex:${l} C6 [warn] 'ground-truth'"* ]]
    append_claim "{\"id\":\"C-0004\",\"rev\":1,\"supersedes\":null,\"text\":\"Each trial records ground-truth outcomes.\",\"where\":\"paper/main.tex:${l}\",\"category\":\"own_observation\",\"strength\":\"empirical\",\"data_origin\":\"synthetic-generated\",\"labels\":\"generator-rule\",\"numbers\":[],\"depends_on\":[],\"sources\":[],\"author\":\"engineer\",\"status\":\"unverified\"}"
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l} C6 'ground-truth', but C-0004"* ]]
}

@test "P0 sentences: a dot inside a file name neither ends the sentence nor drops its start" {
    printf '\nAs \\cite{sandve2013} notes, running \\texttt{recover\\_context.sh} helps; studies show it.\n' >> "$P/paper/main.tex"
    run check slop
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *" S2 "* ]]
}

# ── P0: hand-typed numbers are linked to their rows through `where` ──────────

@test "P0 NUM-SPLIT: a hand-typed number located by its row's where is judged like a macro use" {
    printf '\n\\section{Discussion}\nGradient Boosting reaches 0.912 on unseen scenarios. %% uws:literal typed by the authors\n' >> "$P/paper/main.tex"
    local l
    l="$(line_of 'reaches 0.912 on unseen')"
    add_revision N-0001 "{\"where\": \"paper/main.tex:${l}\"}"
    run check numbers
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l} NUM-SPLIT hand-typed 0.912 (N-0001) is a cross-validation value"* ]]
}

@test "P0 NUM-LITERAL: a hand-typed number at its row's where names the row and its macro; a missing value warns" {
    printf '\n\\section{Discussion}\nThe 5-fold CV mean ROC-AUC is 0.912.\n' >> "$P/paper/main.tex"
    local l
    l="$(line_of 'mean ROC-AUC is 0.912')"
    add_revision N-0001 "{\"where\": \"paper/main.tex:${l}; paper/main.tex:9\"}"
    run check numbers
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:${l} NUM-LITERAL hand-typed number 0.912 is N-0001: use its macro \\GbAucCv"* ]]
    [[ "$output" == *"NUM-WHERE [warn] N-0001: where names paper/main.tex:9, but its printed value 0.912 is not there"* ]]
}

# ── P1: coverage and false positives ─────────────────────────────────────────

@test "P1 NUM-LITERAL: numbers with units (1.1ms, 1.1\\,ms, 30\\%) are caught, in the introduction too" {
    printf '\n\\section{Introduction}\nRecovery takes 1.1ms (or 1.1\\,ms) and fails in 30\\%% of runs; see Section 3.2, the 1990s and 3 trials.\n' >> "$P/paper/main.tex"
    local l
    l="$(line_of 'Recovery takes 1.1ms')"
    run check numbers
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"main.tex:${l} NUM-LITERAL hand-typed number 1.1ms:"* ]]
    [[ "$output" == *"main.tex:${l} NUM-LITERAL hand-typed number 1.1\\,ms:"* ]]
    [[ "$output" == *"main.tex:${l} NUM-LITERAL hand-typed number 30\\%:"* ]]
    [[ "$output" != *"number 3.2"* ]]
    [[ "$output" != *"number 1990"* ]]
    [[ "$output" != *"number 3:"* ]]
}

@test "P1 NUM-LITERAL: the real PROMISE abstract and introduction numbers are all caught" {
    { printf '\n\\section{Introduction}\n'; cat "$PROMISE/intro-findings.tex"; printf '\n'; cat "$PROMISE/abstract.tex"; } >> "$P/paper/main.tex"
    local li la
    li="$(line_of 'achieves MAE of 1.1ms using Gradient Boosting')"
    la="$(line_of 'Gradient Boosting achieves MAE of 1.1ms for recovery time')"
    run check numbers
    [ "$status" -eq 1 ]
    local want
    for want in "${li} NUM-LITERAL hand-typed number 1.1ms" "${li} NUM-LITERAL hand-typed number 0.756" \
                "$((li + 1)) NUM-LITERAL hand-typed number 0.912" "$((li + 1)) NUM-LITERAL hand-typed number 0.911" \
                "${la} NUM-LITERAL hand-typed number 1.1ms" "${la} NUM-LITERAL hand-typed number -0.475"; do
        [[ "$output" == *"main.tex:${want}"* ]] || { echo "missing: $want"; echo "$output"; false; }
    done
}

@test "P1 NUM-ROUND: a pre-rounded stored value warns; an unrounded value from a run decides" {
    add_revision N-0001 '{"rounding": "round:3"}'
    run check numbers
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"NUM-ROUND [warn] N-0001"* ]]
    [[ "$output" == *"pre-rounded"* ]]
    printf 'import json\njson.dump({"cv_auc_mean": 0.9124501829991217}, open("artifacts/full.json", "w"))\n' > "$P/research/code/full.py"
    printf 'import json\njson.dump({"cv_auc_mean": 0.91251}, open("artifacts/other.json", "w"))\n' > "$P/research/code/other.py"
    commit_all "full-precision scripts"
    check run --exp exploratory --code research/code/full.py --output artifacts/full.json -- python3 research/code/full.py >/dev/null
    check run --exp exploratory --code research/code/other.py --output artifacts/other.json -- python3 research/code/other.py >/dev/null
    add_revision N-0001 '{"unrounded": {"run": "RUN-0001", "output": "artifacts/full.json", "pointer": "/cv_auc_mean"}}'
    run check numbers
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *"NUM-ROUND"* ]]
    add_revision N-0001 '{"unrounded": {"run": "RUN-0002", "output": "artifacts/other.json", "pointer": "/cv_auc_mean"}}'
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-ROUND N-0001: printed '0.912' is not round:3 applied to the unrounded value 0.91251 (expected 0.913"* ]]
}

@test "P1 NUM-ROUND: an unrounded value that does not round to raw is a different quantity" {
    printf 'import json\njson.dump({"v": 0.7}, open("artifacts/wrong.json", "w"))\n' > "$P/research/code/wrong.py"
    commit_all "wrong script"
    check run --exp exploratory --code research/code/wrong.py --output artifacts/wrong.json -- python3 research/code/wrong.py >/dev/null
    add_revision N-0001 '{"unrounded": {"run": "RUN-0001", "output": "artifacts/wrong.json", "pointer": "/v"}}'
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-ROUND N-0001: the unrounded value 0.7"* ]]
    [[ "$output" == *"does not round to raw 0.9125"* ]]
}

@test "P1 gate: a number-ledger schema error is reported once, not once per check" {
    add_number '{"id":"N-0002","macro":"\\Typed","printed":"5.8","raw":0.058,"rounding":"round:1","scale":100,"metric":"FPR as printed","data_origin":"measured","evaluation":"held-out","exp":"exploratory","inputs":[]}'
    run check gate analysis
    [ "$(printf '%s\n' "$output" | grep -c "NUM-SCHEMA N-0002: missing 'output'$" || true)" -eq 1 ]
}

@test "P1 S1: 'best practices' is an idiom, not a superlative; 'the best model' still needs a claim" {
    { printf '\n'; cat "$PROMISE/background-insight.tex"; } >> "$P/paper/main.tex"
    run check slop
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *" S1 "* ]]
    printf '\nOurs is the best model for recovery.\n' >> "$P/paper/main.tex"
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"S1 'best' needs a verified claim"* ]]
}

@test "P1 DATA-UNMANIFESTED: code given as --input or --code is not data; uncommitted code is RUN-CODE" {
    check run --exp EXP-LEAK --input research/data/raw/gb_scores.csv --input research/code/make_results.py \
        --output artifacts/model_results.json -- \
        python3 research/code/make_results.py research/data/raw/gb_scores.csv artifacts/model_results.json >/dev/null
    add_revision N-0001 '{"run": "RUN-0001"}'
    run check data
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *"DATA-UNMANIFESTED"* ]]
    python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); assert [c["path"] for c in r["code"]] == ["research/code/make_results.py"], r; assert [i["path"] for i in r["inputs"]] == ["research/data/raw/gb_scores.csv"], r' \
        "$P/research/runs/RUN-0001/run.json"
    printf 'print(1)\n' > "$P/research/code/untracked.py"
    run check run --exp exploratory --code research/code/untracked.py -- python3 research/code/untracked.py
    [ "$status" -eq 0 ]
    [[ "$output" == *"research/code/untracked.py is not committed"* ]]
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"RUN-CODE RUN-0002: code research/code/untracked.py is not in commit"* ]]
}

@test "P1 BIB-UNDEFINED: a \\cite key that references.bib does not define is its own finding" {
    printf 'See \\cite{autogen2023}.\n' >> "$P/paper/main.tex"
    run check bib
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:23 BIB-UNDEFINED \\cite{autogen2023} is not defined"* ]]
    [[ "$output" != *"BIB-MISSING \\cite{autogen2023}"* ]]
    printf '\n@misc{handwritten,\n  title = {Typed from memory}\n}\n' >> "$P/paper/references.bib"
    printf 'And \\cite{handwritten}.\n' >> "$P/paper/main.tex"
    run check bib
    [[ "$output" == *"paper/main.tex:24 BIB-MISSING \\cite{handwritten} has no bib_sources/handwritten.bib"* ]]
}

@test "P1 run/repro: --output takes a glob for timestamped names; the concrete file is recorded and re-found" {
    cat > "$P/research/code/stamped.py" << 'EOF'
import json
import time

with open("artifacts/stamped_%d.json" % time.time_ns(), "w", encoding="utf-8") as fh:
    json.dump({"v": 3}, fh)
EOF
    commit_all "timestamped writer"
    run check run --exp exploratory --code research/code/stamped.py --output 'artifacts/stamped_*.json' -- python3 research/code/stamped.py
    echo "$output"
    [ "$status" -eq 0 ]
    local concrete
    concrete="$(cd "$P" && ls artifacts/stamped_*.json)"
    python3 -c 'import json,sys; o=json.load(open(sys.argv[1]))["outputs"]; assert o == [dict(o[0], path=sys.argv[2], pattern="artifacts/stamped_*.json")] and o[0]["sha256"], o' \
        "$P/research/runs/RUN-0001/run.json" "$concrete"
    add_number "{\"id\":\"N-0002\",\"macro\":\"\\\\Stamped\",\"printed\":\"3\",\"raw\":3,\"rounding\":\"exact\",\"metric\":\"count\",\"output\":\"${concrete}\",\"pointer\":\"/v\",\"data_origin\":\"measured\",\"evaluation\":\"n/a\",\"exp\":\"exploratory\",\"run\":\"RUN-0001\"}"
    commit_all "stamped number"
    run check repro N-0002
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"N-0002 pass RUN-0001"* ]]
}

@test "P1 run: a glob that matches no file the command wrote is an error" {
    run check run --exp exploratory --output 'artifacts/none_*.json' -- python3 -c pass
    [ "$status" -eq 1 ]
    [[ "$output" == *"artifacts/none_*.json matched no file the command wrote"* ]]
}

@test "P1 DATA-LEAK: a structured split with a group in train and test fails; free text warns" {
    mkdir -p "$P/research/data/derived"
    printf 'scenario_id,x\n1,a\n2,b\n3,c\n' > "$P/research/data/derived/train.csv"
    printf 'scenario_id,x\n3,c\n4,d\n' > "$P/research/data/derived/test.csv"
    printf 'scenario_id,x\n1,a\n2,b\n3,c\n3,c\n4,d\n' > "$P/research/data/derived/all.csv"
    local f
    for f in train test; do
        check data add "research/data/derived/${f}.csv" --source split --version 1 --split none --origin measured >/dev/null
    done
    run check data add research/data/derived/all.csv --source runs --version 1 --origin measured \
        --split '{"train": "research/data/derived/train.csv", "test": "research/data/derived/test.csv", "group_key": "scenario_id"}'
    [ "$status" -eq 0 ]
    run check data
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-LEAK research/data/derived/all.csv: 1 scenario_id value(s) appear in both train and test (3)"* ]]
    [[ "$output" == *"DATA-LEAK [warn] research/data/raw/gb_scores.csv: the split is free text"* ]]
    printf 'x\n' > "$P/research/data/derived/x.csv"
    run check data add research/data/derived/x.csv --source s --version 1 --origin measured --split '{"train": 1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"--split looks like JSON but does not parse"* ]]
    run check data add research/data/derived/x.csv --source s --version 1 --origin measured --split '{"train": "nope.csv", "group_key": "id"}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"--split: train file nope.csv is not a file inside the project"* ]]
}

@test "P1 DATA-LEAK: disjoint groups pass; a missing group column is reported" {
    mkdir -p "$P/research/data/derived"
    printf 'scenario_id,x\n1,a\n2,b\n' > "$P/research/data/derived/train.csv"
    printf 'scenario_id,x\n3,c\n' > "$P/research/data/derived/test.csv"
    printf '{"id": 9}\n' > "$P/research/data/derived/valid.jsonl"
    printf 'scenario_id,x\n1,a\n2,b\n3,c\n' > "$P/research/data/derived/all.csv"
    local f
    for f in train.csv test.csv valid.jsonl; do
        check data add "research/data/derived/${f}" --source split --version 1 --split none --origin measured >/dev/null
    done
    check data add research/data/derived/all.csv --source runs --version 1 --origin measured \
        --split '{"train": "research/data/derived/train.csv", "test": "research/data/derived/test.csv", "group_key": "scenario_id"}' >/dev/null
    run check data
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" != *"DATA-LEAK research/data/derived/all.csv"* ]]
    printf 'scenario_id,x\n1,a\n2,b\n3,c\n5,e\n' > "$P/research/data/derived/all.csv"
    check data add research/data/derived/all.csv --source runs --version 2 --origin measured --reason "validation split" \
        --split '{"train": "research/data/derived/train.csv", "validation": "research/data/derived/valid.jsonl", "test": "research/data/derived/test.csv", "group_key": "scenario_id"}' >/dev/null
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-SPLIT research/data/derived/all.csv: research/data/derived/valid.jsonl has no scenario_id"* ]]
}

# ── P2: friction ─────────────────────────────────────────────────────────────

# A copy of the UWS scripts with its own .workflow, like an installed UWS, and a project
# that has no .workflow of its own.
nostate_setup() {
    INST="${TEST_TMP_DIR}/uws-install"
    mkdir -p "$INST/.workflow"
    cp -R "${PROJECT_ROOT}/bin" "${PROJECT_ROOT}/scripts" "$INST/"
    printf 'project_type: "software"\n' > "$INST/.workflow/state.yaml"
    NOSTATE="$(mktemp -d)"
    git -C "$NOSTATE" init -q
}

@test "P2 init: research check init needs no .workflow (uws and research.sh), and never writes into UWS itself" {
    nostate_setup
    cd "$NOSTATE"
    run env -u WORKFLOW_DIR -u UWS_ROOT "$INST/bin/uws" research check init
    echo "$output"
    [ "$status" -eq 0 ]
    [ -f "$NOSTATE/research/ledger/claims.jsonl" ]
    [ ! -e "$INST/research" ]
    rm -rf "$NOSTATE/research" "$NOSTATE/bib_sources"
    run env -u WORKFLOW_DIR -u UWS_ROOT "$INST/scripts/research.sh" check init
    echo "$output"
    [ "$status" -eq 0 ]
    [ -f "$NOSTATE/research/ledger/numbers.jsonl" ]
    [ ! -e "$INST/research" ]
    run env -u WORKFLOW_DIR -u UWS_ROOT "$INST/scripts/research.sh" check ledger
    [ "$status" -eq 0 ]
    [[ "$output" == *"ledger: PASS"* ]]
}

@test "P2 research.sh: an action that needs workflow state says so" {
    nostate_setup
    rm -rf "$INST/.workflow"
    cd "$NOSTATE"
    run env -u WORKFLOW_DIR -u UWS_ROOT "$INST/scripts/research.sh" next
    [ "$status" -eq 1 ]
    [[ "$output" == *"research.sh next needs .workflow/state.yaml"* ]]
    [[ "$output" == *"research.sh check"* ]]
}

@test "P2 numbers add / claims add append validated rows and never edit existing ones" {
    local before
    before="$(cat "$P/research/ledger/numbers.jsonl")"
    run check numbers add '{"macro":"\\GbAucTest","rounding":"round:3","metric":"held-out ROC-AUC","output":"artifacts/model_results.json","pointer":"/classification/Gradient Boosting/test_auc","data_origin":"synthetic-generated","evaluation":"held-out","exp":"EXP-LEAK","inputs":["research/data/raw/gb_scores.csv"]}'
    echo "$output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"appended N-0002 rev 1"* ]]
    [ "$(head -1 "$P/research/ledger/numbers.jsonl")" = "$before" ]
    python3 -c 'import json,sys; r=json.loads(open(sys.argv[1]).read().splitlines()[-1]); assert r["id"]=="N-0002" and r["raw"]==0.9199 and r["printed"]=="0.920" and r["rev"]==1 and r["supersedes"] is None and len(r["output_sha256"])==64, r' \
        "$P/research/ledger/numbers.jsonl"
    local n
    n="$(wc -l < "$P/research/ledger/numbers.jsonl")"
    run check numbers add '{"macro":"\\NoMetric","output":"artifacts/model_results.json","pointer":"/classification/Gradient Boosting/test_auc","rounding":"exact","data_origin":"measured","evaluation":"held-out","exp":"exploratory","inputs":[]}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing 'metric'"* ]]
    run check numbers add '{"macro":"\\WrongRaw","raw":0.95,"rounding":"round:2","metric":"m","output":"artifacts/model_results.json","pointer":"/classification/Gradient Boosting/test_auc","data_origin":"measured","evaluation":"held-out","exp":"exploratory","inputs":[]}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-VALUE"* ]]
    run check numbers add '{"id":"N-0001","rev":1,"macro":"\\GbAucCv"}'
    [ "$status" -eq 1 ]
    [ "$(wc -l < "$P/research/ledger/numbers.jsonl")" -eq "$n" ]
    run check claims add '{"text":"t","category":"own_observation","status":"verified","author":"writer","verified_by":"writer","verified_at":"2026-09-30T00:00:00Z","verdict":"supports","numbers":["N-0002"]}'
    [ "$status" -eq 1 ]
    [[ "$output" == *"LEDGER-SELFVERIFY"* ]]
    run check claims add '{"text":"GB reaches a held-out AUC of 0.920.","category":"own_observation","strength":"empirical","data_origin":"synthetic-generated","status":"unverified","author":"writer","numbers":["N-0002"]}'
    [ "$status" -eq 0 ]
    [[ "$output" == *"appended C-0004 rev 1"* ]]
    run check ledger
    [ "$status" -eq 0 ]
}

@test "P2 macros: valid rows are written, invalid rows are reported and skipped" {
    add_number '{"id":"N-0002","macro":"\\Bad","printed":"5.8","raw":0.058,"rounding":"round:1","metric":"m","data_origin":"measured","evaluation":"held-out","exp":"exploratory","inputs":[]}'
    rm "$P/paper/generated/numbers.tex"
    run check macros
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"skipped N-0002"* ]]
    grep -q '^\\newcommand{\\GbAucCv}{0.912}$' "$P/paper/generated/numbers.tex"
    run grep -q 'Bad' "$P/paper/generated/numbers.tex"
    [ "$status" -ne 0 ]
}

@test "P2 run: records the command's interpreter and the environment-lock hash" {
    mkdir -p "$P/research/env" "$P/fakebin"
    printf 'numpy==2.2.6\n' > "$P/research/env/requirements.lock"
    printf '#!/bin/sh\nexec python3 "$@"\n' > "$P/fakebin/python3.99"
    chmod +x "$P/fakebin/python3.99"
    run check run --exp exploratory -- "$P/fakebin/python3.99" -c 'print(1)'
    [ "$status" -eq 0 ]
    local want_ver
    want_ver="$(python3 -c 'import platform; print(platform.python_version())')"
    python3 - "$P" "$want_ver" << 'EOF'
import hashlib, json, os, sys
root, ver = sys.argv[1], sys.argv[2]
rec = json.load(open(os.path.join(root, "research/runs/RUN-0001/run.json")))
it = rec["interpreter"]
assert it["path"] == os.path.realpath(os.path.join(root, "fakebin/python3.99")), it
assert it["kind"] == "python" and it["version"] == ver and it["executable"], it
lock = hashlib.sha256(open(os.path.join(root, "research/env/requirements.lock"), "rb").read()).hexdigest()
assert rec["env_lock"] == [{"path": "research/env/requirements.lock", "sha256": lock}], rec["env_lock"]
EOF
    PATH="$P/fakebin:$PATH" run check run --exp exploratory -- python3.99 -c 'print(2)'
    [ "$status" -eq 0 ]
    python3 -c 'import json,os,sys; it=json.load(open(sys.argv[1]))["interpreter"]; assert it["command"]=="python3.99" and it["path"]==os.path.realpath(sys.argv[2]), it' \
        "$P/research/runs/RUN-0002/run.json" "$P/fakebin/python3.99"
}

@test "P2 gate note: the KB note agrees with uws kb stats" {
    local stats
    stats="$(cd "$P" && "${PROJECT_ROOT}/bin/uws" kb stats)"
    [[ "$stats" == "No KB yet"* ]]
    run check gate literature_review
    echo "$output"
    [[ "$output" == *"note: No KB yet"* ]]
    [[ "$output" != *"KB available"* ]]
}

@test "P2 init: empty scaffold directories get .gitkeep so they are committed" {
    P="${TEST_TMP_DIR}/fresh"
    mkdir -p "$P"
    git -C "$P" init -q
    run check init
    [ "$status" -eq 0 ]
    local d
    for d in research/lit research/reviews research/experiments research/data/raw research/runs research/repro bib_sources; do
        [ -f "$P/$d/.gitkeep" ] || { echo "no .gitkeep in $d"; false; }
    done
    [ ! -e "$P/research/sources/cache/.gitkeep" ]
    git -C "$P" add -A
    git -C "$P" ls-files | grep -q '^research/runs/.gitkeep$'
    run check data
    [ "$status" -eq 0 ]
    run check init
    [[ "$output" == *"nothing changed"* ]]
}
