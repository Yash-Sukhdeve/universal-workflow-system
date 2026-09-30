#!/usr/bin/env bats
# Research team, increment 2 (docs/design/research-team.md sections 4, 5, 8 and 11):
# methodologist, engineer and writer roles; plan freeze; data manifest; run records and
# the repro job; the red-team manuscript hash; retraction checks; metric formulas.
#
# Several fixtures reproduce failures found in the PROMISE 2026 audit, each of which must
# now be caught mechanically:
#   - the training input was chosen by newest mtime and never archived   (C5, DATA-UNMANIFESTED)
#   - the data generator was unseeded                                     (DATA-SEED)
#   - generator-rule labels were called ground truth                      (C6)
#   - cross-validation means were reported as if held-out                 (NUM-SPLIT)
#   - a false-positive rate was misreported, 5.8% for 37/88 = 42.0%        (NUM-FORMULA)
# Crossref responses in tests/fixtures/research/responses/ were captured on 2026-09-30.

load '../helpers/test_helper'
load '../helpers/research_helper'
source "${PROJECT_ROOT}/scripts/lib/portable.sh"   # sed_inplace (BSD and GNU sed)

setup() {
    research_fixture_setup
}

teardown() {
    teardown_test_environment
}

# Stub curl for Crossref: picks the body by URL and logs every URL it was asked for.
crossref_stub() {
    mkdir -p "$P/fakebin"
    cat > "$P/fakebin/curl" << 'EOF'
#!/bin/bash
out="" url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -A|-H|-w|--max-time) shift 2 ;;
        http*) url="$1"; shift ;;
        *) shift ;;
    esac
done
printf '%s\n' "$url" >> "$(dirname "$0")/urls.log"
if [[ -n "${FAKE_DOWN:-}" ]]; then
    echo "curl: (6) Could not resolve host: api.crossref.org" >&2
    exit 6
fi
case "$url" in
    *filter=updates*) cp "$FAKE_UPDATES" "$out" ;;
    *)                cp "$FAKE_WORK" "$out" ;;
esac
printf '%s' "${FAKE_CODE:-200}"
EOF
    chmod +x "$P/fakebin/curl"
}

# A new, empty research project in its own git repository (no fixture history).
fresh_project() {
    P="${TEST_TMP_DIR}/fresh"
    mkdir -p "$P"
    git -C "$P" init -q
    git -C "$P" config user.email t@example.com
    git -C "$P" config user.name t
    check init >/dev/null
}

ingest_wakefield() {
    check bib-ingest --body "${RFIX}/responses/doi_wakefield1998.bib" \
        --url "https://doi.org/10.1016/S0140-6736(97)11096-0" --id-type doi \
        --identifier "10.1016/S0140-6736(97)11096-0" --http-status 200 \
        --content-type application/x-bibtex --key wakefield1998 >/dev/null
}

# ── Gates ─────────────────────────────────────────────────────────────────────

@test "gates: the increment-2 checks run; only rules that are still unimplemented are listed as unchecked" {
    run check gate analysis
    [ "$status" -eq 1 ]
    [[ "$output" == *"REPRO N-0001 has never been reproduced"* ]]
    research_make_reproducible
    local phase
    for phase in experiment_design data_collection analysis peer_review publication; do
        run check gate "$phase"
        echo "$phase: $output"
        [ "$status" -eq 0 ]
        [[ "$output" != *"increment 2"* ]]
    done
    run check gate experiment_design
    [[ "$output" != *"not checked yet"* ]]
    run check gate analysis
    [[ "$output" == *"not checked yet: slop rules S3"* ]]
}

# ── Roles ─────────────────────────────────────────────────────────────────────

@test "orchestrate: research phases route to the methodologist, engineer and writer" {
    local pair phase agent
    for pair in experiment_design:rt-methodologist data_collection:rt-engineer \
                analysis:rt-methodologist publication:rt-writer literature_review:rt-scout; do
        phase="${pair%%:*}" agent="${pair#*:}"
        research_state "$phase"
        run "${SCRIPTS_DIR}/orchestrate.sh" status --methodology research
        [ "$status" -eq 0 ]
        [[ "$output" == *"uws-${agent}.md"* ]]
    done
    run "${SCRIPTS_DIR}/orchestrate.sh" dispatch --methodology research --agent rt-writer "Draft the results section"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DISPATCH: agent=rt-writer subagent=.claude/agents/uws-rt-writer.md"* ]]
    grep -q "research/ledger/claims.jsonl" "$P/workspace/rt-writer/TASK.md"
    run grep -q "REQ-ID" "$P/workspace/rt-writer/TASK.md"
    [ "$status" -ne 0 ]
}

@test "lead skill: both copies route to every research role and no longer defer them" {
    local f role
    for f in "${PROJECT_ROOT}/.claude/skills/uws-research-lead/SKILL.md" \
             "${PROJECT_ROOT}/plugins/uws/skills/uws-research-lead/SKILL.md"; do
        for role in rt-scout rt-verifier rt-redteam rt-methodologist rt-engineer rt-writer; do
            grep -q "$role" "$f"
        done
        run grep -q "arrive in increment 2" "$f"
        [ "$status" -ne 0 ]
        grep -q "research check repro all" "$f"
        grep -q "plan freeze" "$f"
    done
}

@test "hook: the SubagentStop matcher covers the new research roles" {
    local matcher
    matcher="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["SubagentStop"][0]["matcher"])' "${PROJECT_ROOT}/plugins/uws/hooks/hooks.json")"
    [[ "uws-rt-methodologist" =~ $matcher ]]
    [[ "uws:uws-rt-engineer" =~ $matcher ]]
    [[ "uws-rt-writer" =~ $matcher ]]
}

# ── Plan freeze (pre-registration) ───────────────────────────────────────────

@test "plan new scaffolds a template and never overwrites it; an incomplete plan cannot be frozen" {
    run check plan new EXP-NEW
    [ "$status" -eq 0 ]
    [ -f "$P/research/experiments/EXP-NEW/plan.md" ]
    run check plan new EXP-NEW
    [ "$status" -eq 1 ]
    [[ "$output" == *"never overwritten"* ]]
    run check plan freeze EXP-NEW
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-FIELDS"* ]]
    [[ "$output" == *"cannot be pre-registered"* ]]
    run grep -q "EXP-NEW" "$P/research/ledger/plans.jsonl"
    [ "$status" -ne 0 ]
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"EXP-NEW: 'hypothesis' is missing or empty"* ]]
    [[ "$output" == *"PLAN-FREEZE"* ]]
}

@test "experiment_design gate: no plan, or an unfrozen plan, blocks; freezing passes" {
    fresh_project
    run check gate experiment_design
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-FREEZE no experiment plan"* ]]
    write_plan EXP-A
    run check gate experiment_design
    [ "$status" -eq 1 ]
    [[ "$output" == *"EXP-A is not frozen"* ]]
    run check plan freeze EXP-A
    [ "$status" -eq 0 ]
    run check gate experiment_design
    [ "$status" -eq 0 ]
}

@test "plan: a plan edited before any result is re-frozen; the drift is reported until then" {
    write_plan EXP-B
    check plan freeze EXP-B >/dev/null
    printf 'Also report the fold SD.\n' >> "$P/research/experiments/EXP-B/plan.md"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-DRIFT EXP-B changed after it was frozen"* ]]
    [[ "$output" == *"no results exist yet"* ]]
    run check plan freeze EXP-B
    [ "$status" -eq 0 ]
    [[ "$output" == *"froze EXP-B rev 2"* ]]
    run check plan
    [ "$status" -eq 0 ]
}

@test "PROMISE: a plan frozen after its results were committed is not a pre-registration (PLAN-ORDER)" {
    write_plan EXP-POST
    add_number '{"id":"N-0002","exp":"EXP-POST","data_origin":"measured"}'
    commit_all "results first"
    run check plan freeze EXP-POST
    [ "$status" -eq 1 ]
    [[ "$output" == *"already exist (N-0002)"* ]]
    # An agent that writes the freeze row by hand instead of using the tool:
    python3 - "$P" << 'EOF'
import hashlib, json, os, sys
root = sys.argv[1]
plan = "research/experiments/EXP-POST/plan.md"
sha = hashlib.sha256(open(os.path.join(root, plan), "rb").read()).hexdigest()
row = {"exp": "EXP-POST", "rev": 1, "plan": plan, "sha256": sha, "frozen_at": "2026-09-30T00:00:00Z", "frozen_by": "methodologist"}
open(os.path.join(root, "research/ledger/plans.jsonl"), "a").write(json.dumps(row) + "\n")
EOF
    commit_all "freeze after results"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-ORDER EXP-POST: N-0002 was committed in"* ]]
    [[ "$output" == *"not after the plan was frozen"* ]]
}

@test "plan: results with an uncommitted freeze, or committed together with it, fail PLAN-ORDER" {
    write_plan EXP-C
    check plan freeze EXP-C >/dev/null
    add_number '{"id":"N-0002","exp":"EXP-C","data_origin":"measured"}'
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"EXP-C: the freeze is not committed, but results exist (N-0002)"* ]]
    commit_all "freeze and results together"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-ORDER EXP-C: N-0002 was committed in"* ]]
}

@test "plan: changing a frozen plan after results is a deviation that needs a recorded PI decision" {
    printf 'An extra control, added after the results were seen.\n' >> "$P/research/experiments/EXP-LEAK/plan.md"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-DRIFT EXP-LEAK changed after it was frozen"* ]]
    [[ "$output" == *"results exist (N-0001)"* ]]
    run check plan freeze EXP-LEAK --reason "added a control"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is a deviation"* ]]
    run check plan freeze EXP-LEAK --reason "added a control" --pi-decision D-099
    [ "$status" -eq 1 ]
    run check plan freeze EXP-LEAK --reason "added a control" --pi-decision D-001
    [ "$status" -eq 0 ]
    [[ "$output" == *"deviation DEV-001, D-001"* ]]
    grep -q '^| DEV-001 | .* | added a control | D-001 |$' "$P/research/experiments/EXP-LEAK/deviations.md"
    commit_all "deviation"
    run check plan
    [ "$status" -eq 0 ]
}

@test "plan: a re-freeze written by hand after results, without a PI decision, fails PLAN-DEVIATION" {
    printf 'Changed metric.\n' >> "$P/research/experiments/EXP-LEAK/plan.md"
    python3 - "$P" << 'EOF'
import hashlib, json, os, sys
root = sys.argv[1]
plan = "research/experiments/EXP-LEAK/plan.md"
path = os.path.join(root, "research/ledger/plans.jsonl")
prev = json.loads(open(path).readline())
sha = hashlib.sha256(open(os.path.join(root, plan), "rb").read()).hexdigest()
row = {"exp": "EXP-LEAK", "rev": 2, "plan": plan, "sha256": sha, "previous_sha256": prev["sha256"],
       "frozen_at": "2026-09-30T00:00:00Z", "frozen_by": "methodologist"}
open(path, "a").write(json.dumps(row) + "\n")
EOF
    commit_all "silent re-freeze"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-DEVIATION EXP-LEAK@2 re-froze the plan after results existed without a reason, a PI decision ID"* ]]
}

@test "plan: a freeze row edited in place after results counts from the edit, so it fails PLAN-ORDER" {
    printf 'Metric changed after the results.\n' >> "$P/research/experiments/EXP-LEAK/plan.md"
    python3 - "$P" << 'EOF'
import hashlib, json, os, sys
root = sys.argv[1]
path = os.path.join(root, "research/ledger/plans.jsonl")
row = json.loads(open(path).readline())
row["sha256"] = hashlib.sha256(open(os.path.join(root, row["plan"]), "rb").read()).hexdigest()
open(path, "w").write(json.dumps(row) + "\n")
EOF
    commit_all "rewrite the freeze"
    # a second commit, so the edit is no longer visible to the HEAD / HEAD~1 append-only check
    printf 'x\n' > "$P/research/lit/notes.md"
    commit_all "later work"
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" != *"PLAN-APPEND"* ]]
    [[ "$output" == *"PLAN-ORDER EXP-LEAK: N-0001 was committed in"* ]]
}

@test "plan: every result names its experiment or is labelled exploratory (PLAN-LINK)" {
    add_revision N-0001 '{"exp": null}'
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"PLAN-LINK N-0001: set exp"* ]]
    add_revision N-0001 '{"exp": "EXP-NOPE"}'
    run check plan
    [ "$status" -eq 1 ]
    [[ "$output" == *"N-0001: exp EXP-NOPE has no research/experiments/EXP-NOPE/plan.md"* ]]
    add_revision N-0001 '{"exp": "exploratory"}'
    run check plan
    [ "$status" -eq 0 ]
}

@test "run: --exp needs a frozen plan, and run records are never overwritten" {
    run check run --exp EXP-NONE -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"EXP-NONE has no frozen plan"* ]]
    research_make_reproducible
    run check run --id RUN-0001 --exp exploratory -- true
    [ "$status" -eq 1 ]
    [[ "$output" == *"never overwritten"* ]]
}

# ── Data manifest ─────────────────────────────────────────────────────────────

@test "PROMISE: generated data without a recorded seed, and an unseeded generator, fail DATA-SEED" {
    cat > "$P/research/code/gen_unseeded.py" << 'EOF'
import random
import sys


def main(path):
    with open(path, "w", encoding="utf-8") as fh:
        for _ in range(3):
            fh.write("%f\n" % random.random())


if __name__ == "__main__":
    main(sys.argv[1])
EOF
    (cd "$P" && python3 research/code/gen_unseeded.py research/data/raw/scenarios.csv)
    local args=(data add research/data/raw/scenarios.csv --source "python3 research/code/gen_unseeded.py"
                --version 1 --split "all rows; split at training time" --origin synthetic-generated
                --generator research/code/gen_unseeded.py --labels generator-rule)
    run check "${args[@]}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs --seed"* ]]
    run check "${args[@]}" --seed unrecorded
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not a recorded seed"* ]]
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-SEED research/data/raw/scenarios.csv was generated without a recorded seed"* ]]
    [[ "$output" == *"gen_unseeded.py draws random values (random.random() at line 8) but never sets a seed"* ]]
}

@test "data: a generator that builds its RNG without a seed is reported even when a seed is claimed" {
    cat > "$P/research/code/gen_rng.py" << 'EOF'
import sys

import numpy as np


def main(path):
    rng = np.random.default_rng()
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("%f\n" % rng.normal())


if __name__ == "__main__":
    main(sys.argv[1])
EOF
    printf '0.5\n' > "$P/research/data/raw/draws.csv"
    run check data add research/data/raw/draws.csv --source gen --version 1 --split none \
        --origin simulated --generator research/code/gen_rng.py --seed 3 --labels none
    [ "$status" -eq 0 ]
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"its generator research/code/gen_rng.py:7 creates np.random.default_rng() without a seed"* ]]
}

@test "data: hash drift in registered data fails DATA-HASH; a missing file fails DATA-MISSING" {
    chmod u+w "$P/research/data/raw/gb_scores.csv"
    printf 'cv,6,0.9\n' >> "$P/research/data/raw/gb_scores.csv"
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-HASH research/data/raw/gb_scores.csv changed after it was registered"* ]]
    rm -f "$P/research/data/raw/gb_scores.csv"
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-MISSING research/data/raw/gb_scores.csv is registered but missing"* ]]
}

@test "PROMISE: an input picked by modification time and never archived fails C5 and DATA-UNMANIFESTED" {
    mkdir -p "$P/research/data/processed"
    printf 'a,b\n1,2\n' > "$P/research/data/processed/training_data_20251122.csv"
    cat > "$P/research/code/train.py" << 'EOF'
import glob
import json
import os


def newest():
    return max(glob.glob("research/data/processed/training_data_*.csv"), key=os.path.getmtime)


if __name__ == "__main__":
    with open(newest(), encoding="utf-8") as fh:
        rows = sum(1 for _ in fh) - 1
    with open("artifacts/train.json", "w", encoding="utf-8") as fh:
        json.dump({"rows": rows}, fh)
EOF
    commit_all "training script"
    run check run --exp exploratory --input research/data/processed/training_data_20251122.csv \
        --output artifacts/train.json -- python3 research/code/train.py
    [ "$status" -eq 0 ]
    add_number '{"id":"N-0002","run":"RUN-0001","exp":"exploratory","data_origin":"measured"}'
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-UNMANIFESTED N-0002: input research/data/processed/training_data_20251122.csv is not in research/data/manifest.jsonl"* ]]
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"research/code/train.py:7 C5 input chosen by modification time"* ]]
}

@test "data: unregistered raw data and a number with no inputs are reported" {
    printf 'x\n' > "$P/research/data/raw/extra.csv"
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"research/data/raw/extra.csv:1 DATA-UNMANIFESTED raw data file is not in research/data/manifest.jsonl"* ]]
    rm "$P/research/data/raw/extra.csv"
    add_revision N-0001 '{"inputs": null}'
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-NOINPUT N-0001 names no run and no inputs"* ]]
}

@test "data: a hand-written run record is incomplete (RUN-SCHEMA)" {
    mkdir -p "$P/research/runs/RUN-0009"
    printf '{"id":"RUN-0009","exit_code":0,"git_commit":"abc"}\n' > "$P/research/runs/RUN-0009/run.json"
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"RUN-SCHEMA RUN-0009: missing 'command'"* ]]
}

@test "data add: a new version needs a reason, and replacing raw data needs a PI decision" {
    chmod u+w "$P/research/data/raw/gb_scores.csv"
    printf 'cv,6,0.9\n' >> "$P/research/data/raw/gb_scores.csv"
    local args=(data add research/data/raw/gb_scores.csv --source "regenerated" --version 2 --split "same"
                --origin synthetic-generated --generator research/code/gen_scores.py --seed 7 --labels none)
    run check "${args[@]}"
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs --reason"* ]]
    run check "${args[@]}" --reason "sixth fold"
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs --pi-decision"* ]]
    run check "${args[@]}" --reason "sixth fold" --pi-decision D-001
    [ "$status" -eq 0 ]
    [ ! -w "$P/research/data/raw/gb_scores.csv" ] || [ "$(id -u)" -eq 0 ]
    run check data
    [ "$status" -eq 0 ]
}

@test "data: a run that used an older version of a registered input fails DATA-RUNHASH" {
    research_make_reproducible
    chmod u+w "$P/research/data/raw/gb_scores.csv"
    printf 'cv,6,0.9\n' >> "$P/research/data/raw/gb_scores.csv"
    check data add research/data/raw/gb_scores.csv --source regenerated --version 2 --split same \
        --origin synthetic-generated --generator research/code/gen_scores.py --seed 7 --labels none \
        --reason "sixth fold" --pi-decision D-001 >/dev/null
    run check data
    [ "$status" -eq 1 ]
    [[ "$output" == *"DATA-RUNHASH N-0001: RUN-0001 used research/data/raw/gb_scores.csv version 15756d4e4a35"* ]]
}

# ── Run records and the repro job ────────────────────────────────────────────

@test "run: the wrapper records command, commit, inputs, outputs, seeds and environment; failed runs are kept" {
    run check run --exp EXP-LEAK --input research/data/raw/gb_scores.csv --output artifacts/model_results.json \
        --seed python=7 --env PYTHONHASHSEED=0 -- \
        python3 research/code/make_results.py research/data/raw/gb_scores.csv artifacts/model_results.json
    [ "$status" -eq 0 ]
    python3 - "$P" "$(git -C "$P" rev-parse HEAD)" << 'EOF'
import json, sys
root, head = sys.argv[1], sys.argv[2]
rec = json.load(open(root + "/research/runs/RUN-0001/run.json"))
assert rec["command"][:2] == ["python3", "research/code/make_results.py"], rec["command"]
assert rec["git_commit"] == head and rec["git_dirty"] is False, rec
assert rec["exit_code"] == 0 and rec["exp"] == "EXP-LEAK"
assert rec["inputs"][0]["sha256"].startswith("15756d4e4a35"), rec["inputs"]
assert rec["outputs"][0]["sha256"].startswith("0af8552eab0b"), rec["outputs"]
assert rec["seeds"] == {"python": "7"} and rec["env_vars"] == {"PYTHONHASHSEED": "0"}
assert rec["environment"]["python"]
EOF
    run check run --exp exploratory -- python3 -c 'import sys; sys.exit(3)'
    [ "$status" -eq 3 ]
    grep -q '"exit_code": 3' "$P/research/runs/RUN-0002/run.json"
}

@test "repro: re-runs the recorded command in a scratch copy, leaves the project untouched, and the gates accept it" {
    research_make_reproducible
    local reports before after
    reports="$(ls "$P"/research/repro/report-*.json | wc -l | tr -d ' ')"
    [ "$reports" -eq 1 ]
    python3 -c 'import json,glob,sys; r=json.load(open(glob.glob(sys.argv[1]+"/research/repro/report-*.json")[0]))["results"][0]; assert r["status"]=="pass" and r["observed"]==0.9125 and r["byte_identical"] is True, r' "$P"
    before="$(git -C "$P" status --porcelain)"
    local scratch_tmp
    scratch_tmp="$(mktemp -d)"
    TMPDIR="$scratch_tmp" run check repro all
    [ "$status" -eq 0 ]
    [[ "$output" == *"N-0001 pass RUN-0001: expected 0.9125, observed 0.9125 (exact)"* ]]
    # the scratch copy is removed afterwards
    [ -z "$(ls -A "$scratch_tmp")" ]
    rm -rf "$scratch_tmp"
    after="$(git -C "$P" status --porcelain)"
    # the only change in the project is the new report
    [ "$(printf '%s\n' "$after" | grep -vc '^?? research/repro/' || true)" -eq "$(printf '%s\n' "$before" | grep -vc '^?? research/repro/' || true)" ]
    run check gate publication
    [ "$status" -eq 0 ]
}

@test "repro: a value that does not reproduce fails; a declared tolerance is honoured" {
    cat > "$P/research/code/noisy.py" << 'EOF'
import json
import random
import sys

if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as fh:
        json.dump({"v": random.random()}, fh)
EOF
    commit_all "noisy"
    check run --exp exploratory --output artifacts/noisy.json -- python3 research/code/noisy.py artifacts/noisy.json >/dev/null
    local raw
    raw="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["v"])' "$P/artifacts/noisy.json")"
    add_number "{\"id\":\"N-0002\",\"run\":\"RUN-0001\",\"output\":\"artifacts/noisy.json\",\"pointer\":\"/v\",\"raw\":${raw},\"exp\":\"exploratory\",\"data_origin\":\"simulated\"}"
    commit_all "noisy number"
    run check repro N-0002
    [ "$status" -eq 1 ]
    [[ "$output" == *"REPRO N-0002: re-run gives"* ]]
    [[ "$output" == *"(tolerance exact)"* ]]
    add_revision N-0002 '{"tolerance": {"kind": "abs", "value": 1.0}}'
    commit_all "tolerance"
    run check repro N-0002
    [ "$status" -eq 0 ]
}

@test "repro: a command that does not write its output fails, even when a committed copy exists" {
    run check run --exp EXP-LEAK --output artifacts/model_results.json -- python3 -c pass
    [ "$status" -eq 0 ]
    [[ "$output" == *"were not rewritten"* ]]
    add_revision N-0001 '{"run": "RUN-0001"}'
    commit_all "run that writes nothing"
    run check repro N-0001
    [ "$status" -eq 1 ]
    [[ "$output" == *"the re-run did not write artifacts/model_results.json"* ]]
}

@test "repro: a run recorded on an uncommitted tree cannot be reproduced" {
    printf '# local edit\n' >> "$P/research/code/analysis.py"
    run check run --exp EXP-LEAK --input research/data/raw/gb_scores.csv --output artifacts/model_results.json -- \
        python3 research/code/make_results.py research/data/raw/gb_scores.csv artifacts/model_results.json
    [ "$status" -eq 0 ]
    [[ "$output" == *"uncommitted changes"* ]]
    add_revision N-0001 '{"run": "RUN-0001"}'
    run check repro N-0001
    [ "$status" -eq 1 ]
    [[ "$output" == *"was recorded on a working tree with uncommitted changes"* ]]
}

@test "repro: a re-run that writes into the original project is reported" {
    cat > "$P/research/code/mutate.py" << 'EOF'
import json
import os
import sys

if __name__ == "__main__":
    with open(sys.argv[1], "w", encoding="utf-8") as fh:
        json.dump({"v": 1}, fh)
    if os.environ.get("UWS_REPRO") == "1":
        with open(os.environ["ORIG_OUT"], "a", encoding="utf-8") as fh:
            fh.write(" ")
EOF
    commit_all "mutate"
    check run --exp exploratory --env "ORIG_OUT=$P/artifacts/mut.json" --output artifacts/mut.json -- \
        python3 research/code/mutate.py artifacts/mut.json >/dev/null
    add_number '{"id":"N-0002","run":"RUN-0001","output":"artifacts/mut.json","pointer":"/v","raw":1,"exp":"exploratory","data_origin":"measured"}'
    commit_all "mutating number"
    run check repro N-0002
    [ "$status" -eq 1 ]
    [[ "$output" == *"changed files in the original project (artifacts/mut.json)"* ]]
}

@test "repro: a number revised after its repro re-opens the analysis gate" {
    research_make_reproducible
    add_revision N-0001 '{"note": "clarified wording"}'
    commit_all "revise N-0001"
    run check gate analysis
    [ "$status" -eq 1 ]
    [[ "$output" == *"REPRO N-0001 changed after its latest repro"* ]]
    check repro all >/dev/null 2>&1
    commit_all "repro again"
    run check gate analysis
    [ "$status" -eq 0 ]
}

@test "repro: a research project in a subdirectory of its repository, driven from another directory" {
    local mono="${TEST_TMP_DIR}/mono"
    mkdir -p "$mono/sub/proj"
    cp -R "${RFIX}/project/." "$mono/sub/proj/"
    git -C "$mono" init -q
    git -C "$mono" config user.email t@example.com
    git -C "$mono" config user.name t
    git -C "$mono" add sub/proj/research/experiments sub/proj/research/ledger/plans.jsonl
    git -C "$mono" commit -q -m plan
    git -C "$mono" add -A
    git -C "$mono" commit -q -m fixture
    P="$mono/sub/proj"
    cd "$TEST_TMP_DIR"
    # relative paths are taken from the project root, where the command runs
    run check run --exp EXP-LEAK --input research/data/raw/gb_scores.csv --output artifacts/model_results.json -- \
        python3 research/code/make_results.py research/data/raw/gb_scores.csv artifacts/model_results.json
    [ "$status" -eq 0 ]
    add_revision N-0001 '{"run": "RUN-0001"}'
    git -C "$mono" add -A
    git -C "$mono" commit -q -m run
    run check repro all
    [ "$status" -eq 0 ]
    git -C "$mono" add -A
    git -C "$mono" commit -q -m repro
    run check gate publication
    [ "$status" -eq 0 ]
}

@test "repro: unknown N-IDs, no selection and no git repository are environment errors (exit 2)" {
    run check repro N-9999
    [ "$status" -eq 2 ]
    [[ "$output" == *"not in the number ledger: N-9999"* ]]
    run check repro
    [ "$status" -eq 2 ]
    rm -rf "$P/.git"
    run check repro all
    [ "$status" -eq 2 ]
    [[ "$output" == *"needs a git repository"* ]]
}

# ── Numbers: formulas and evaluation splits ──────────────────────────────────

@test "PROMISE: a false-positive rate that does not follow its formula fails (5.8% reported, 37/88 = 42.0%)" {
    printf '{"fp": 37, "tn": 51, "fpr": 0.058}\n' > "$P/artifacts/confusion.json"
    local common='"output":"artifacts/confusion.json","data_origin":"measured","evaluation":"held-out","exp":"exploratory","inputs":[]'
    add_number "{\"id\":\"N-0002\",\"macro\":\"\\\\FpCount\",\"printed\":\"37\",\"raw\":37,\"rounding\":\"exact\",\"metric\":\"false positives, held-out split\",\"pointer\":\"/fp\",${common}}"
    add_number "{\"id\":\"N-0003\",\"macro\":\"\\\\TnCount\",\"printed\":\"51\",\"raw\":51,\"rounding\":\"exact\",\"metric\":\"true negatives, held-out split\",\"pointer\":\"/tn\",${common}}"
    add_number "{\"id\":\"N-0004\",\"macro\":\"\\\\FprPct\",\"printed\":\"5.8\",\"raw\":0.058,\"rounding\":\"round:1\",\"scale\":100,\"formula\":\"N-0002/(N-0002+N-0003)\",\"metric\":\"false-positive rate FP/(FP+TN), held-out split\",\"pointer\":\"/fpr\",${common}}"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-FORMULA N-0004: formula N-0002/(N-0002+N-0003) = 0.420455 (N-0002=37, N-0003=51), but raw is 0.058"* ]]
    [[ "$output" == *"N-0004: printed '5.8', but round:1 applied to the formula's value gives 42.0"* ]]
    # The corrected output and row pass.
    printf '{"fp": 37, "tn": 51, "fpr": 0.42045454545454547}\n' > "$P/artifacts/confusion.json"
    python3 - "$P" << 'EOF'
import hashlib, json, sys
root = sys.argv[1]
sha = hashlib.sha256(open(root + "/artifacts/confusion.json", "rb").read()).hexdigest()
path = root + "/research/ledger/numbers.jsonl"
rows = [json.loads(l) for l in open(path) if l.strip()]
with open(path, "a") as fh:
    for nid in ("N-0002", "N-0003", "N-0004"):
        row = [r for r in rows if r["id"] == nid][-1]
        new = dict(row, rev=2, supersedes="%s@1" % nid, output_sha256=sha)
        if nid == "N-0004":
            new.update(raw=0.42045454545454547, printed="42.0")
        fh.write(json.dumps(new) + "\n")
EOF
    sed_inplace 's/\\newcommand{\\FprPct}{5.8}/\\newcommand{\\FprPct}{42.0}/' "$P/paper/generated/numbers.tex"
    run check numbers
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "numbers: formula errors (unknown N-ID, self-reference, unsupported syntax) are reported" {
    add_revision N-0001 '{"formula": "N-0099/2"}'
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-FORMULA N-0001: formula refers to N-0099, which is not in the number ledger"* ]]
    add_revision N-0001 '{"formula": "N-0001*1"}'
    run check numbers
    [[ "$output" == *"NUM-FORMULA N-0001: formula refers to itself"* ]]
    add_revision N-0001 '{"formula": "abs(2)"}'
    run check numbers
    [[ "$output" == *"may only use N-IDs, numbers, + - * / and parentheses"* ]]
}

@test "PROMISE: a cross-validation mean presented without saying so fails NUM-SPLIT; a held-out word is a warning" {
    printf '\n\\section{Discussion}\nThe model reaches \\GbAucCv{} on held-out scenarios.\n' >> "$P/paper/main.tex"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:25 NUM-SPLIT \\GbAucCv (N-0001) is a cross-validation value, but the sentence/caption does not say so"* ]]
    sed_inplace 's/^The model reaches .*/The 5-fold CV mean \\GbAucCv{} is not a held-out estimate./' "$P/paper/main.tex"
    run check numbers
    [ "$status" -eq 0 ]
    [[ "$output" == *"NUM-SPLIT [warn]"* ]]
}

@test "numbers: every measured or generated number says which split it comes from, consistently with its source" {
    add_revision N-0001 '{"evaluation": null}'
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-SPLIT N-0001: missing 'evaluation'"* ]]
    add_revision N-0001 '{"evaluation": "held-out"}'
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-SPLIT N-0001: evaluation is held-out, but its metric/pointer describe a cross-validation value"* ]]
}

# ── Slop C6: generator labels are not ground truth ───────────────────────────

@test "PROMISE: labels assigned by a generator are not ground truth (C6)" {
    printf '\nAgainst the ground truth labels the CV mean is \\GbAucCv{}.\n' >> "$P/paper/main.tex"
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:24 C6 'ground truth', but N-0001 is synthetic-generated data"* ]]
    sed_inplace 's/^Against the ground truth labels/Against the generator-assigned labels (not ground truth),/' "$P/paper/main.tex"
    run check slop
    [[ "$output" != *" C6 "* ]]
}

@test "C6: measured numbers whose input has generator-rule labels, and untraced ground-truth wording, are reported" {
    printf 'id,label\n1,ok\n' > "$P/research/data/raw/labels.csv"
    check data add research/data/raw/labels.csv --source "recovery runs; label by rule" --version 1 --split none \
        --origin measured --labels generator-rule >/dev/null
    printf '{"rate": 0.5}\n' > "$P/artifacts/rate.json"
    add_number '{"id":"N-0002","macro":"\\SuccessRate","printed":"0.5","raw":0.5,"rounding":"exact","metric":"success rate","output":"artifacts/rate.json","pointer":"/rate","data_origin":"measured","evaluation":"n/a","exp":"exploratory","inputs":["research/data/raw/labels.csv"]}'
    printf '\nThe annotated success rate is \\SuccessRate{}.\n\nWe compare against ground truth.\n' >> "$P/paper/main.tex"
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"C6 'annotated', but N-0002 uses research/data/raw/labels.csv, whose labels come from generator rules"* ]]
    [[ "$output" == *"C6 [warn] 'ground truth' in a sentence with no C-ID or number macro"* ]]
}

# ── Red team: the review names the current manuscript ────────────────────────

@test "red team: an edit after the review re-opens review (GATE-REVIEW-HASH); a new review of it passes" {
    research_make_reproducible
    run check gate peer_review
    [ "$status" -eq 0 ]
    printf '\nA sentence added after the review.\n' >> "$P/paper/main.tex"
    run check gate peer_review
    [ "$status" -eq 1 ]
    [[ "$output" == *"GATE-REVIEW-HASH no red-team review covers the current manuscript"* ]]
    [[ "$output" == *"REV-001.md: 56dbe6210935"* ]]
    local h
    h="$(check manuscript-hash)"
    printf '# REV-002\n\nManuscript: %s\n\n| ID | Severity | Status | Finding | Evidence | Settling check |\n|---|---|---|---|---|---|\n' "$h" \
        > "$P/research/reviews/REV-002.md"
    run check gate peer_review
    [ "$status" -eq 0 ]
}

@test "red team: a review without a Manuscript line does not count; the hash covers the number macros" {
    research_make_reproducible
    sed_inplace '/^Manuscript: /d' "$P/research/reviews/REV-001.md"
    run check gate publication
    [ "$status" -eq 1 ]
    [[ "$output" == *"REV-001.md: no Manuscript line"* ]]
    local h1 h2
    h1="$(check manuscript-hash)"
    [[ "$h1" == sha256:56dbe621093513baaf97e7be7d30a608ce2d860e18a55a29116677480ea38d29 ]]
    printf '%% regenerated\n' >> "$P/paper/generated/numbers.tex"
    h2="$(check manuscript-hash)"
    [ "$h1" != "$h2" ]
    run check manuscript-hash --files
    [[ "$output" == *"paper/generated/numbers.tex"* ]]
    [[ "$output" == *"paper/references.bib"* ]]
}

# ── Retraction checks ─────────────────────────────────────────────────────────

@test "retraction: an unchecked source is a warning, never a silent pass" {
    rm "$P/research/sources/retractions.jsonl"
    run check retraction
    [ "$status" -eq 0 ]
    [[ "$output" == *"RETRACTION [warn] sandve2013: retraction status never checked"* ]]
    run check gate literature_review
    [ "$status" -eq 0 ]
    [[ "$output" == *"retraction status never checked"* ]]
}

@test "retraction --online: Crossref's notices are cached; a verified claim or an unqualified cite of a retracted source fails" {
    crossref_stub
    ingest_wakefield
    FAKE_WORK="${RFIX}/responses/crossref_work_wakefield1998.json" \
        FAKE_UPDATES="${RFIX}/responses/crossref_updates_wakefield1998.json" \
        UWS_RESEARCH_CURL="$P/fakebin/curl" run check retraction --online --key wakefield1998
    [ "$status" -eq 0 ]
    [[ "$output" == *"wakefield1998: retracted"* ]]
    grep -q '"status": "retracted"' "$P/research/sources/retractions.jsonl"
    grep -q '10.1016/s0140-6736(10)60175-4' "$P/research/sources/retractions.jsonl"
    grep -q '^https://api.crossref.org/works/10.1016/s0140-6736(97)11096-0$' "$P/fakebin/urls.log"
    grep -q 'api.crossref.org/works?filter=updates:10.1016/s0140-6736(97)11096-0' "$P/fakebin/urls.log"
    append_claim '{"id":"C-0004","rev":1,"supersedes":null,"text":"t","category":"reported_finding","strength":"none","sources":[{"citekey":"wakefield1998","quote":"a quote that is long enough","locator":"p. 637"}],"author":"scout","status":"verified","verified_by":"verifier","verified_at":"2026-09-30T00:00:00Z","verdict":"supports"}'
    printf '\nEarly work linked the vaccine to autism \\cite{wakefield1998}.\n' >> "$P/paper/main.tex"
    run check retraction
    [ "$status" -eq 1 ]
    [[ "$output" == *"RETRACTION C-0004 rests on wakefield1998, which Crossref lists as retracted (correction 10.1016/s0140-6736(04)15715-2, retraction 10.1016/s0140-6736(10)60175-4)"* ]]
    [[ "$output" == *"paper/main.tex:24 RETRACTION \\cite{wakefield1998}: Crossref lists this source as retracted, and the sentence does not say so"* ]]
    sed_inplace 's/autism \\cite{wakefield1998}\./autism \\cite{wakefield1998}, a paper since retracted./' "$P/paper/main.tex"
    run check retraction
    [[ "$output" != *"main.tex:24 RETRACTION"* ]]
}

@test "retraction --online: unreachable Crossref exits 2, keeps the earlier answer, and never reads as clean" {
    crossref_stub
    FAKE_DOWN=1 UWS_RESEARCH_CURL="$P/fakebin/curl" run check retraction --online
    [ "$status" -eq 2 ]
    [[ "$output" == *"sandve2013: unreachable"* ]]
    tail -1 "$P/research/sources/retractions.jsonl" | grep -q '"status": "unreachable"'
    run check retraction
    [ "$status" -eq 0 ]
    [[ "$output" != *"retraction status unknown"* ]]
    rm "$P/research/sources/retractions.jsonl"
    FAKE_DOWN=1 UWS_RESEARCH_CURL="$P/fakebin/curl" run check retraction --online
    run check retraction
    [ "$status" -eq 0 ]
    [[ "$output" == *"RETRACTION [warn] sandve2013: retraction status unknown: Crossref was unreachable"* ]]
    [[ "$output" != *"no-notice"* ]]
}

@test "retraction --online: the captured Crossref answer for sandve2013 has no notice; a 404 is 'not in Crossref'" {
    crossref_stub
    FAKE_WORK="${RFIX}/responses/crossref_work_sandve2013.json" \
        FAKE_UPDATES="${RFIX}/responses/crossref_updates_sandve2013.json" \
        UWS_RESEARCH_CURL="$P/fakebin/curl" run check retraction --online
    [ "$status" -eq 0 ]
    [[ "$output" == *"sandve2013: no-notice (10.1371/journal.pcbi.1003285)"* ]]
    FAKE_CODE=404 FAKE_WORK=/dev/null FAKE_UPDATES=/dev/null UWS_RESEARCH_CURL="$P/fakebin/curl" run check retraction --online
    [ "$status" -eq 0 ]
    run check retraction
    [[ "$output" == *"RETRACTION [warn] sandve2013: retraction status unknown: its DOI 10.1371/journal.pcbi.1003285 is not registered with Crossref"* ]]
}

# ── CLI wiring ────────────────────────────────────────────────────────────────

@test "research.sh check plan|data|manuscript-hash|repro go through the checker; help lists them" {
    research_state experiment_design
    run "${SCRIPTS_DIR}/research.sh" check plan
    [ "$status" -eq 0 ]
    [[ "$output" == *"plan: PASS"* ]]
    run "${SCRIPTS_DIR}/research.sh" check data
    [ "$status" -eq 0 ]
    [[ "$output" == *"data: PASS"* ]]
    run "${SCRIPTS_DIR}/research.sh" check manuscript-hash
    [ "$status" -eq 0 ]
    [[ "$output" == *"sha256:56dbe621093513baaf97e7be7d30a608ce2d860e18a55a29116677480ea38d29"* ]]
    run "${PROJECT_ROOT}/bin/uws" research check repro N-9999
    [ "$status" -eq 2 ]
    run "${SCRIPTS_DIR}/research.sh" help
    [[ "$output" == *"check repro <N-ID ...|all>"* ]]
    [[ "$output" == *"check plan [new|freeze <EXP-ID>]"* ]]
}

@test "macros: the generated macro file is written from the number ledger" {
    rm "$P/paper/generated/numbers.tex"
    run check macros
    [ "$status" -eq 0 ]
    grep -q '^\\newcommand{\\GbAucCv}{0.912}$' "$P/paper/generated/numbers.tex"
    run check numbers
    [ "$status" -eq 0 ]
}

@test "init: scaffolds the increment-2 layout without overwriting" {
    P="${TEST_TMP_DIR}/fresh"
    mkdir -p "$P"
    run check init
    [ "$status" -eq 0 ]
    [[ "$output" == *"created research/ledger/plans.jsonl"* ]]
    printf '{"exp": "EXP-X"}\n' > "$P/research/ledger/plans.jsonl"
    run check init
    [ "$(cat "$P/research/ledger/plans.jsonl")" = '{"exp": "EXP-X"}' ]
    : > "$P/research/ledger/plans.jsonl"
    local d
    for d in research/experiments research/data/raw research/runs research/repro; do
        [ -d "$P/$d" ]
    done
    [ -f "$P/research/ledger/plans.jsonl" ]
    [ -f "$P/research/data/manifest.jsonl" ]
    run check plan
    [ "$status" -eq 0 ]
    run check data
    [ "$status" -eq 0 ]
}
