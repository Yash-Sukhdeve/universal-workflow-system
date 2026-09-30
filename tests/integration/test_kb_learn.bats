#!/usr/bin/env bats
# Knowledge base meta-learning (docs/design/knowledge-base.md section 6):
# outcome recording in docs/kb/outcomes.tsv, `uws kb learn`, proposals, the PI
# gate on them, and revert tracking. The clock is fixed with UWS_KB_NOW.

load '../helpers/test_helper'

UWS="${PROJECT_ROOT}/bin/uws"
PI="pi@lab.example"
T0="2026-09-24T00:00:00Z"
T1="2026-09-25T00:00:00Z"

setup() {
    setup_test_environment
    # Behave like the PI's own terminal, not an agent's tool call
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_CHILD_SESSION AI_AGENT \
          UWS_AGENT GEMINI_CLI CODEX_SANDBOX UWS_KB_PI UWS_KB_DIR
    export UWS_KB_NOW="2026-09-24"
    cat > "${TEST_TMP_DIR}/.workflow/state.yaml" <<'EOF'
project_type: "software"
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
EOF
    printf '# log\n' > "${TEST_TMP_DIR}/.workflow/checkpoints.log"
    printf 'line one\n' > "${TEST_TMP_DIR}/f"
    git config user.email "$PI"
    git add -A >/dev/null
    git commit -qm "fixture" >/dev/null
    KB="${TEST_TMP_DIR}/docs/kb"
    OUT="${KB}/outcomes.tsv"
    mkdir -p "$KB"   # the project uses the KB: outcomes are recorded
}

teardown() {
    teardown_test_environment
}

# ── helpers ─────────────────────────────────────────────────────────────────

rows() { if [[ -f "$OUT" ]]; then wc -l < "$OUT" | tr -d ' '; else echo 0; fi; }
col() { sed -n "${1}p" "$OUT" | cut -f "$2"; }          # col <row> <column>
well_formed() { awk -F '\t' 'NF != 8 { bad = 1 } END { exit bad }' "$OUT"; }
row() { local IFS=$'\t'; printf '%s\n' "$*" >> "$OUT"; }  # append a fixture row
field() { grep -E "^$2:" "$1" | head -1 | sed -e "s/^$2:[[:space:]]*//" -e 's/^"//' -e 's/"$//'; }
proposal_files() { grep -l '^type: proposal$' "${KB}"/items/*.md 2>/dev/null || true; }
proposal_count() { proposal_files | grep -c . || true; }
set_pi() { "$UWS" kb pi --set "$PI" >/dev/null; }
kb_id() { KB_OUT="$("$UWS" kb "$@" 2>/dev/null)"; }

# One first-pass CR: a dispatch of <role> with <model>, then its decision
first_pass() {  # first_pass <ts> <role> <model> <result> <cr-id>
    row "$1" dispatch sdlc:implementation "$2" "$3" docs/x.md dispatched abc1234
    row "$1" cr_decision sdlc:implementation "$2" "$3" "draft" "$4" "$5"
}

# Five first-pass CRs of implementer/sonnet, three rejected (top reason "tests missing")
seed_cr_rejections() {
    first_pass "$T0" implementer sonnet "rejected: Tests missing." CR-1
    first_pass "$T0" implementer sonnet approved CR-2
    first_pass "$T0" implementer sonnet "rejected: tests  missing" CR-3
    first_pass "$T0" implementer sonnet "rejected: no docs" CR-4
    first_pass "$T0" implementer sonnet approved CR-5
}

# ── Writers: exactly one well-formed row each ───────────────────────────────

@test "writer: sdlc fail keeps the reason, tab and newline escaped, in one gate_fail row" {
    "$UWS" sdlc start >/dev/null
    "$UWS" sdlc goto verification >/dev/null
    [ "$(rows)" -eq 0 ]
    run "$UWS" sdlc fail "$(printf 'unit tests\tfail\nsee the CI log')"
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 1 ]
    well_formed
    [ "$(col 1 1)" = "$T0" ]
    [ "$(col 1 2)" = "gate_fail" ]
    [ "$(col 1 3)" = "sdlc:verification" ]
    [ "$(col 1 6)" = "sdlc:implementation" ]
    [ "$(col 1 7)" = 'unit tests\tfail\nsee the CI log' ]
    [ "$(col 1 8)" = "$(git rev-parse --short HEAD)" ]
    grep -Eq '^sdlc_phase: "?implementation"?$' .workflow/state.yaml
    # no reason given: the row still records the failure
    run "$UWS" sdlc fail
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 2 ]
    [ "$(col 2 3)" = "sdlc:implementation" ]
    [ "$(col 2 6)" = "-" ]
    [ "$(col 2 7)" = "-" ]
}

@test "writer: research reject records a gate_fail row with the refinement target" {
    "$UWS" research start >/dev/null
    "$UWS" research next >/dev/null
    [ "$(rows)" -eq 1 ]
    run "$UWS" research reject "gaps in the prior work"
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 2 ]
    well_formed
    [ "$(col 2 2)" = "gate_fail" ]
    [ "$(col 2 3)" = "research:literature_review" ]
    [ "$(col 2 6)" = "research:hypothesis" ]
    [ "$(col 2 7)" = "gaps in the prior work" ]
}

@test "writer: sdlc next records gate_pass with deliverables done/total; a blocked next records nothing" {
    "$UWS" sdlc start >/dev/null
    run "$UWS" sdlc next
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 1 ]
    [ "$(col 1 2)" = "gate_pass" ]
    [ "$(col 1 3)" = "sdlc:requirements" ]
    [ "$(col 1 6)" = "sdlc:design" ]
    [ "$(col 1 7)" = "0/3 ungated" ]
    "$UWS" sdlc goal "ship the pilot" >/dev/null
    local i
    for i in 1 2 3 4; do "$UWS" sdlc check "$i" >/dev/null; done
    run "$UWS" sdlc next
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 2 ]
    [ "$(col 2 7)" = "4/4" ]
    run "$UWS" sdlc next
    [ "$status" -eq 1 ]
    [ "$(rows)" -eq 2 ]
    run "$UWS" sdlc next --force
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 3 ]
    [ "$(col 3 3)" = "sdlc:implementation" ]
    [ "$(col 3 7)" = "0/3 forced" ]
    well_formed
}

@test "writer: orchestrate dispatch/collect and review approve/reject each append one row" {
    local model cr
    model="$(sed -n 's/^model:[[:space:]]*//p' "${PROJECT_ROOT}/.claude/agents/uws-researcher.md" | head -1 | tr -d '"')"
    [ -n "$model" ]
    "$UWS" sdlc start >/dev/null
    run "$UWS" orchestrate dispatch "Write the requirements" "docs/req.md"
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 1 ]
    [ "$(col 1 2)" = "dispatch" ]
    [ "$(col 1 3)" = "sdlc:requirements" ]
    [ "$(col 1 4)" = "researcher" ]
    [ "$(col 1 5)" = "$model" ]
    [ "$(col 1 6)" = "docs/req.md" ]
    [ "$(col 1 7)" = "dispatched" ]
    mkdir -p workspace/researcher/docs
    printf '# Requirements\n' > workspace/researcher/docs/req.md
    run "$UWS" orchestrate collect "researcher: requirements draft"
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 2 ]
    cr="$(col 2 8)"
    [[ "$cr" =~ ^CR-[0-9]{8}-[0-9]{6}$ ]]
    [ "$(col 2 2)" = "dispatch" ]
    [ "$(col 2 3)" = "sdlc:requirements" ]
    [ "$(col 2 6)" = "docs/req.md" ]
    [ "$(col 2 7)" = "collected" ]
    run "$UWS" review approve "$cr"
    [ "$status" -eq 0 ]
    [ -f docs/req.md ]
    [ "$(rows)" -eq 3 ]
    [ "$(col 3 2)" = "cr_decision" ]
    [ "$(col 3 4)" = "researcher" ]
    [ "$(col 3 5)" = "$model" ]
    [ "$(col 3 6)" = "researcher: requirements draft" ]
    [ "$(col 3 7)" = "approved" ]
    [ "$(col 3 8)" = "$cr" ]
    # A second CR, rejected with a reason that holds a tab
    "$UWS" orchestrate dispatch "Revise the requirements" "docs/req2.md" >/dev/null
    printf 'second\n' > workspace/researcher/docs/req2.md
    "$UWS" orchestrate collect "researcher: second draft" >/dev/null
    [ "$(rows)" -eq 5 ]
    cr="$(col 5 8)"
    run "$UWS" review reject "$cr" "$(printf 'missing\tfailure modes')"
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 6 ]
    [ "$(col 6 2)" = "cr_decision" ]
    [ "$(col 6 7)" = 'rejected: missing\tfailure modes' ]
    [ "$(col 6 8)" = "$cr" ]
    [ ! -d ".uws/crs/${cr}" ]
    well_formed
}

@test "writer: kb add --escaped-from records an escape row; bad phases and types are refused" {
    kb_id add --type lesson --claim "A null token crashed login after verification passed" \
        --evidence observed --source file:f:1 --escaped-from verification
    local id="$KB_OUT"
    [[ "$id" =~ ^K-20260924-[0-9a-f]{6}$ ]]
    [ "$(rows)" -eq 1 ]
    [ "$(col 1 2)" = "escape" ]
    [ "$(col 1 3)" = "sdlc:verification" ]
    [ "$(col 1 4)" = "$PI" ]
    [ "$(col 1 6)" = "$id" ]
    [ "$(col 1 7)" = "A null token crashed login after verification passed" ]
    [ "$(field "${KB}/items/${id}.md" escaped_from)" = "sdlc:verification" ]
    kb_id add --type lesson --claim "Unit mismatch slipped past the analysis gate" \
        --evidence observed --source file:f:1 --escaped-from research:analysis
    [ "$(col 2 3)" = "research:analysis" ]
    run "$UWS" kb add --type lesson --claim "x1" --evidence observed --source file:f:1 --escaped-from nowhere
    [ "$status" -eq 2 ]
    run "$UWS" kb add --type fact --claim "x2" --evidence observed --source file:f:1 --escaped-from verification
    [ "$status" -eq 2 ]
    [ "$(rows)" -eq 2 ]
    well_formed
}

@test "writer: retirements record kb_retire with reason code, evidence, captured_by and prior status" {
    kb_id add --type fact --claim "Old deployment note" --evidence observed --source file:f:1
    local a="$KB_OUT"
    run "$UWS" kb retire "$a" "replaced by ADR-7"
    [ "$status" -eq 0 ]
    [ "$(rows)" -eq 1 ]
    [ "$(col 1 2)" = "kb_retire" ]
    [ "$(col 1 4)" = "$PI" ]
    [ "$(col 1 6)" = "$a" ]
    [ "$(col 1 7)" = "manual evidence=observed captured_by=cli from=candidate type=fact" ]
    [ "$(col 1 8)" = "-" ]
    kb_id add --type fact --claim "First release checklist" --evidence observed --source file:f:1
    local b="$KB_OUT"
    kb_id add --type fact --claim "Second release checklist wording" --evidence observed --source file:f:1 --supersedes "$b"
    local c="$KB_OUT"
    [ "$(rows)" -eq 2 ]
    [ "$(col 2 6)" = "$b" ]
    [ "$(col 2 7)" = "superseded-by evidence=observed captured_by=cli from=candidate type=fact" ]
    [ "$(col 2 8)" = "$c" ]
    well_formed
}

# ── Guards on recording ─────────────────────────────────────────────────────

@test "recording is a no-op without docs/kb: no file appears and exit codes are unchanged" {
    rm -rf docs
    "$UWS" sdlc start >/dev/null
    "$UWS" sdlc goto verification >/dev/null
    run "$UWS" sdlc fail "tests fail"
    [ "$status" -eq 0 ]
    run "$UWS" sdlc next
    [ "$status" -eq 0 ]
    run "$UWS" orchestrate dispatch "Check the build"
    [ "$status" -eq 0 ]
    [ ! -e docs ]
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing to learn"* ]]
}

@test "a recording failure goes to stderr and never changes the caller's exit code" {
    mkdir -p "$OUT"   # outcomes.tsv is a directory, so every append fails
    "$UWS" sdlc start >/dev/null
    "$UWS" sdlc goto verification >/dev/null
    run "$UWS" sdlc fail "tests fail"
    [ "$status" -eq 0 ]
    [[ "$output" == *"could not record the 'gate_fail' outcome"* ]]
    grep -Eq '^sdlc_phase: "?implementation"?$' .workflow/state.yaml
    run "$UWS" sdlc next
    [ "$status" -eq 0 ]
    grep -Eq '^sdlc_phase: "?verification"?$' .workflow/state.yaml
    "$UWS" sdlc goal "ship" >/dev/null
    run "$UWS" sdlc next
    [ "$status" -eq 1 ]
    run "$UWS" review reject CR-00000000-000000 "nope"
    [ "$status" -eq 1 ]
}

# ── learn: thresholds and n >= 5 ────────────────────────────────────────────

@test "learn: n < 5 proposes nothing" {
    local i
    for i in 1 2 3 4; do first_pass "$T0" implementer sonnet "rejected: tests missing" "CR-$i"; done
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"cr-first-pass-rejection role=implementer,model=sonnet: 4 of 4 (100%) -> n < 5: no proposal"* ]]
    [ "$(proposal_count)" -eq 0 ]
    [ ! -d "${KB}/items" ]
}

@test "learn: first-pass CR rejections over 40% propose a Quality Gate item from the top reason" {
    seed_cr_rejections
    # A rework decision (no new dispatch) is not a first pass and is not counted
    row "$T0" cr_decision sdlc:implementation implementer sonnet draft "rejected: again" CR-6
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"role=implementer,model=sonnet: 3 of 5 (60%) -> over the threshold"* ]]
    [ "$(proposal_count)" -eq 1 ]
    local p
    p="$(proposal_files)"
    [ "$(field "$p" status)" = "candidate" ]
    [ "$(field "$p" metric)" = "cr-first-pass-rejection" ]
    [ "$(field "$p" metric_key)" = "role=implementer,model=sonnet" ]
    [ "$(field "$p" track_key)" = "role=implementer" ]
    [ "$(field "$p" metric_n)" = "5" ]
    [ "$(field "$p" metric_k)" = "3" ]
    [ "$(field "$p" metric_before)" = "0.60" ]
    [ "$(field "$p" target)" = "docs/personas/implementer.md" ]
    [ "$(field "$p" proposal_kind)" = "change" ]
    [[ "$(field "$p" falsifier)" == "Revert if the first-pass CR rejection rate of implementer (any model) does not fall below 60% over its next 10 first-pass CR decisions." ]]
    grep -qF -- '+- [ ] Not a repeat of a first-pass CR rejection (3 of 5 recent CRs): tests missing' "$p"
    grep -qF -- '- Rows behind the count: CR-1,CR-3,CR-4' "$p"
    grep -q '^- Small n: 5 samples' "$p"
    grep -q '^- Confounding: ' "$p"
    grep -q 'counts, not causes' "$p"
    run "$UWS" kb lint
    [ "$status" -eq 0 ]
}

@test "learn: first-pass rejections without reasons propose routing the role to another model" {
    first_pass "$T0" implementer sonnet rejected CR-1
    first_pass "$T0" implementer sonnet rejected CR-2
    first_pass "$T0" implementer sonnet rejected CR-3
    first_pass "$T0" implementer sonnet approved CR-4
    first_pass "$T0" implementer sonnet approved CR-5
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    local p
    p="$(proposal_files)"
    [ -n "$p" ]
    [[ "$(field "$p" claim)" == *"no reasons were recorded; proposal: route implementer to opus."* ]]
    grep -q '^+model: opus$' "$p"
    grep -q '^-model: ' "$p"
    grep -qF 'UWS_AGENT_MODEL_IMPLEMENTER=opus ./scripts/gen_subagents.sh' "$p"
}

@test "learn: gate escapes over 20% propose the escaped check (only PI-approved lessons count)" {
    set_pi
    "$UWS" sdlc start >/dev/null
    local i
    for i in 1 2 3 4 5; do
        "$UWS" sdlc goto verification >/dev/null
        "$UWS" sdlc next >/dev/null
    done
    [ "$(grep -c "	gate_pass	sdlc:verification	" "$OUT")" -eq 5 ]
    kb_id add --type lesson --claim "A null token crashed login after verification passed" \
        --evidence observed --source file:f:1 --escaped-from verification
    local l1="$KB_OUT"
    kb_id add --type lesson --claim "Timezone offsets broke the nightly export" \
        --evidence observed --source file:f:1 --escaped-from verification
    local l2="$KB_OUT"
    # Candidates never feed a metric
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 escape row(s) not counted"* ]]
    [[ "$output" == *"gate-escape-rate phase=sdlc:verification: 0 of 5 (0%) -> within the threshold"* ]]
    [ "$(proposal_count)" -eq 0 ]
    "$UWS" kb approve "$l1" >/dev/null
    "$UWS" kb approve "$l2" >/dev/null
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate-escape-rate phase=sdlc:verification: 2 of 5 (40%) -> over the threshold"* ]]
    local p
    p="$(proposal_files)"
    [ "$(field "$p" metric)" = "gate-escape-rate" ]
    [ "$(field "$p" metric_key)" = "phase=sdlc:verification" ]
    [ "$(field "$p" target)" = "scripts/sdlc.sh" ]
    grep -qF "+            echo \"- Escape check (${l2}): Timezone offsets broke the nightly export\"" "$p"
    grep -qF -- "- Rows behind the count: ${l1},${l2}" "$p"
    grep -q '^--- a/scripts/sdlc.sh$' "$p"
}

@test "learn: a disproven rate over 25% proposes a lower trust weight and two sources for the capture channel" {
    local codes="disproven disproven-by expired superseded-by expired" c i=0
    for c in $codes; do
        i=$((i + 1))
        row "$T0" kb_retire - uws-researcher - "K-20260924-00000${i}" "${c} evidence=observed captured_by=cli from=trusted type=fact" -
    done
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"disproven-rate evidence=observed: 2 of 5 (40%) -> over the threshold"* ]]
    [[ "$output" == *"disproven-rate captured_by=cli: 2 of 5 (40%) -> over the threshold"* ]]
    [ "$(proposal_count)" -eq 2 ]
    local p q
    p="$(grep -l '^metric_key: "evidence=observed"$' "${KB}"/items/*.md)"
    q="$(grep -l '^metric_key: "captured_by=cli"$' "${KB}"/items/*.md)"
    [[ "$(field "$p" claim)" == *"lower its search trust weight 0.6 -> 0.36."* ]]
    [ "$(field "$p" target)" = "scripts/kb.sh" ]
    grep -q '^+.*trust\["observed"\] = 0.36;' "$p"
    grep -q '^-.*trust\["observed"\] = 0.6;' "$p"
    [ "$(field "$q" target)" = ".claude/skills/uws-kb/SKILL.md" ]
    grep -qF '+- Items captured via `cli` were disproven in 2 of the last 5 retirements of trusted items' "$q"
}

@test "learn: a gate failure reason repeated 3 times proposes a check in the phase it sent work back to" {
    "$UWS" sdlc start >/dev/null
    local i
    for i in 1 2 3; do
        "$UWS" sdlc goto verification >/dev/null
        "$UWS" sdlc fail "Tests fail." >/dev/null
    done
    "$UWS" sdlc goto deployment >/dev/null
    "$UWS" sdlc fail "docker build broke" >/dev/null
    "$UWS" sdlc goto deployment >/dev/null
    "$UWS" sdlc fail "health check returned 500" >/dev/null
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"repeated-gate-fail reason=tests fail: 3 of 5 (60%) -> over the threshold"* ]]
    [[ "$output" == *"repeated-gate-fail reason=docker build broke: 1 of 5 (20%) -> within the threshold"* ]]
    [ "$(proposal_count)" -eq 1 ]
    local p
    p="$(proposal_files)"
    [ "$(field "$p" metric_key)" = "reason=tests fail" ]
    [ "$(field "$p" target)" = "scripts/sdlc.sh" ]
    grep -qF '+            echo "- Checked that this gate failure does not recur (3 of 5 recent failures): tests fail"' "$p"
    # the new line lands in the implementation checklist
    grep -A1 -F 'echo "- Dependencies declared in requirements file"' "$p" | grep -qF 'does not recur'
}

@test "learn: candidate and inferred items never feed a metric" {
    set_pi
    local i
    for i in 1 2 3 4 5; do row "$T0" gate_pass sdlc:verification - - sdlc:deployment "3/3" abc1234; done
    kb_id add --type fact --claim "The login service caches tokens" --evidence observed --source file:f:1
    local fact="$KB_OUT"
    "$UWS" kb approve "$fact" >/dev/null
    kb_id add --type lesson --claim "Token cache expiry escaped verification" --evidence inferred \
        --source "item:${fact}" --escaped-from verification --no-conflict
    local inferred="$KB_OUT"
    "$UWS" kb approve "$inferred" >/dev/null
    [ "$(field "${KB}/items/${inferred}.md" status)" = "trusted" ]
    kb_id add --type lesson --claim "Clock skew escaped verification" --evidence observed \
        --source file:f:1 --escaped-from verification --no-conflict
    local cand="$KB_OUT"
    # inferred (trusted) and candidate escapes: neither counts
    run "$UWS" kb learn
    [[ "$output" == *"gate-escape-rate phase=sdlc:verification: 0 of 5 (0%)"* ]]
    [[ "$output" == *"2 escape row(s) not counted"* ]]
    "$UWS" kb approve "$cand" >/dev/null
    run "$UWS" kb learn
    [[ "$output" == *"gate-escape-rate phase=sdlc:verification: 1 of 5 (20%) -> within the threshold"* ]]
    # retirements of inferred items or of candidates do not count either
    for i in 1 2 3 4 5; do
        row "$T0" kb_retire - a - "K-20260924-0000a${i}" "disproven evidence=inferred captured_by=cli from=trusted type=fact" -
        row "$T0" kb_retire - a - "K-20260924-0000b${i}" "rejected evidence=observed captured_by=cli from=candidate type=fact" -
    done
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"10 retirement(s) not counted"* ]]
    [[ "$output" != *"evidence=inferred"* ]]
    [[ "$output" != *"disproven-rate"* ]]
    [ "$(proposal_count)" -eq 0 ]
}

# ── learn: idempotence, dry run, human in the loop ──────────────────────────

@test "learn: --dry-run writes nothing; re-running learn on unchanged data adds no proposal" {
    seed_cr_rejections
    local events_before
    events_before="$(cat "${KB}/events.tsv" 2>/dev/null || true)"
    run "$UWS" kb learn --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would propose: First-pass CR rejections for implementer (model sonnet): 3 of 5 (60%)"* ]]
    [[ "$output" == *"| +- [ ] Not a repeat of a first-pass CR rejection"* ]]
    [[ "$output" == *"(dry run: nothing written)"* ]]
    [ "$(proposal_count)" -eq 0 ]
    [ "$(cat "${KB}/events.tsv" 2>/dev/null || true)" = "$events_before" ]
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [ "$(proposal_count)" -eq 1 ]
    local listing events
    listing="$(ls "${KB}/items")"
    events="$(cat "${KB}/events.tsv")"
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"already proposed (K-20260924-"* ]]
    [ "$(ls "${KB}/items")" = "$listing" ]
    [ "$(cat "${KB}/events.tsv")" = "$events" ]
    run "$UWS" kb learn extra
    [ "$status" -eq 2 ]
}

@test "approve records acceptance (PI only) and never modifies the proposal's target file" {
    set_pi
    local i
    for i in 1 2 3 4 5; do
        row "$T0" gate_fail sdlc:verification - - sdlc:implementation "flaky test" abc1234
    done
    "$UWS" kb learn >/dev/null
    local p id before
    p="$(proposal_files)"
    id="$(field "$p" id)"
    [ "$(field "$p" target)" = "scripts/sdlc.sh" ]
    before="$(git hash-object scripts/sdlc.sh)"
    run env CLAUDECODE=1 "$UWS" kb approve "$id"
    [ "$status" -eq 6 ]
    [ "$(field "$p" status)" = "candidate" ]
    run "$UWS" kb approve "$id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Acceptance recorded; nothing was changed in scripts/sdlc.sh."* ]]
    [[ "$output" == *"propose a revert if it does not improve"* ]]
    [ "$(git hash-object scripts/sdlc.sh)" = "$before" ]
    [ -z "$(git status --porcelain scripts)" ]
    [ "$(field "$p" status)" = "trusted" ]
    [ "$(field "$p" reviewer)" = "$PI" ]
    [ "$(field "$p" approved_ts)" = "$T0" ]
    run "$UWS" kb proposals
    [ "$status" -eq 0 ]
    [[ "$output" == *"No proposals waiting for the PI."* ]]
    [[ "$output" == *"Adopted, being measured:"*"${id} [repeated-gate-fail] approved 2026-09-24"* ]]
    run "$UWS" kb lint
    [ "$status" -eq 0 ]
}

@test "a retired and restored proposal waits for a new decision and is not measured" {
    set_pi
    seed_cr_rejections
    "$UWS" kb learn >/dev/null
    local p id
    p="$(proposal_files)"
    id="$(field "$p" id)"
    "$UWS" kb approve "$id" >/dev/null
    "$UWS" kb retire "$id" "wrong target" >/dev/null
    run "$UWS" kb restore "$id"
    [ "$status" -eq 0 ]
    p="${KB}/items/${id}.md"
    [ "$(field "$p" status)" = "candidate" ]
    [ -z "$(field "$p" approved_ts)" ]
    run "$UWS" kb proposals
    [[ "$output" == *"Waiting for the PI"*"${id}"* ]]
    [[ "$output" != *"Adopted, being measured"* ]]
    run "$UWS" status -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"KB: 1 meta-learning proposal awaits the PI"* ]]
}

@test "learn tracks an approved change and proposes a revert when the metric does not improve" {
    set_pi
    seed_cr_rejections
    "$UWS" kb learn >/dev/null
    local p id
    p="$(proposal_files)"
    id="$(field "$p" id)"
    "$UWS" kb approve "$id" >/dev/null
    export UWS_KB_NOW="2026-09-25"
    local i
    for i in 1 2 3; do first_pass "$T1" implementer sonnet "rejected: tests missing" "CR-1${i}"; done
    first_pass "$T1" implementer opus approved CR-14
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"tracking ${id} (cr-first-pass-rejection, role=implementer): 4 of 10 events since approval"* ]]
    [ "$(proposal_count)" -eq 1 ]
    for i in 5 6 7 8; do first_pass "$T1" implementer opus "rejected: tests missing" "CR-1${i}"; done
    first_pass "$T1" implementer opus approved CR-19
    first_pass "$T1" implementer opus approved CR-20
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"${id}: did not improve (60% -> 70% over 10 events)"* ]]
    [ "$(proposal_count)" -eq 2 ]
    local r rid
    r="$(grep -l '^proposal_kind: revert$' "${KB}"/items/*.md)"
    rid="$(field "$r" id)"
    [ "$(field "$r" reverts)" = "$id" ]
    [ "$(field "$r" status)" = "candidate" ]
    [ "$(field "$r" metric_before)" = "0.60" ]
    [ "$(field "$r" metric_after)" = "0.70" ]
    [[ "$(field "$r" claim)" == "Revert ${id}: cr-first-pass-rejection for role=implementer went 60% -> 70% over the 10 events after its approval (no improvement)." ]]
    # the revert is the proposal's diff reversed
    grep -qF -- '-- [ ] Not a repeat of a first-pass CR rejection (3 of 5 recent CRs): tests missing' "$r"
    grep -q '^@@ -87,7 +87,6 @@$' "$r"
    [ "$(field "$p" followup)" = "revert-proposed:${rid}" ]
    [ "$(field "$p" followup_ts)" = "$T1" ]
    [ "$(field "$p" metric_before)" = "0.60" ]
    [ "$(field "$p" metric_after)" = "0.70" ]
    # Idempotent: no second revert, no new change proposal for the same key
    run "$UWS" kb learn
    [ "$(proposal_count)" -eq 2 ]
    [[ "$output" == *"already proposed (${rid})"* ]]
    run "$UWS" kb proposals
    [[ "$output" == *"${rid} [cr-first-pass-rejection|revert]"* ]]
    [[ "$output" != *"Adopted, being measured"* ]]
}

@test "learn closes the tracking without a revert when the metric improves" {
    set_pi
    seed_cr_rejections
    "$UWS" kb learn >/dev/null
    local p id i
    p="$(proposal_files)"
    id="$(field "$p" id)"
    "$UWS" kb approve "$id" >/dev/null
    export UWS_KB_NOW="2026-09-25"
    first_pass "$T1" implementer sonnet "rejected: tests missing" CR-10
    for i in 1 2 3 4 5 6 7 8 9; do first_pass "$T1" implementer sonnet approved "CR-2${i}"; done
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"${id}: improved (60% -> 10% over 10 events); tracking closed"* ]]
    [ "$(proposal_count)" -eq 1 ]
    [ "$(field "$p" followup)" = "improved 0.60 -> 0.10 over 10 events" ]
    [ "$(field "$p" metric_after)" = "0.10" ]
    grep -q "	${id}	trusted	trusted	followup:improved" "${KB}/events.tsv"
}

# ── Surface: session line, stats, proposals ─────────────────────────────────

@test "session start shows one short line while proposals wait, inside the 1200-byte budget" {
    set_pi
    # A full handoff and checkpoint log, so the budget is actually contended
    local i
    {
        echo "# Handoff"; echo "## Next Actions"
        for i in 1 2 3 4 5; do echo "- Next action number ${i} with enough words to take real space in the context budget"; done
        echo "## Blockers"
        for i in 1 2 3; do echo "- Blocker ${i} that is long enough to matter for the byte budget of the hook"; done
    } > .workflow/handoff.md
    for i in 1 2 3; do echo "2026-09-2${i}T10:00:00 | CP_1_00${i} | checkpoint ${i} with a long description of the work done" >> .workflow/checkpoints.log; done
    run "${PROJECT_ROOT}/scripts/recover_context.sh" --hook
    [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')" != *"meta-learning"* ]]
    seed_cr_rejections
    "$UWS" kb learn >/dev/null
    git add -A >/dev/null && git commit -qm "kb" >/dev/null
    local before ctx
    before="$(git status --porcelain)"
    run "${PROJECT_ROOT}/scripts/recover_context.sh" --hook
    [ "$status" -eq 0 ]
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [[ "$ctx" == *"KB: 1 meta-learning proposal awaits the PI (uws kb proposals)."* ]]
    [ "$(printf '%s' "$ctx" | LC_ALL=C wc -c | tr -d ' ')" -le 1200 ]
    [ "$(git status --porcelain)" = "$before" ]
    run "$UWS" kb stats --short
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
    [[ "$output" == *"KB: 1 meta-learning proposal awaits the PI"* ]]
    run "$UWS" kb proposals
    [[ "$output" == *"Waiting for the PI"*"[cr-first-pass-rejection|change] First-pass CR rejections"* ]]
    run "$UWS" kb lint
    [ "$status" -eq 0 ]
}

@test "learn: malformed rows are skipped with a note; bad thresholds are refused" {
    printf 'not a row\n' >> "$OUT"
    seed_cr_rejections
    run "$UWS" kb learn --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 malformed row(s) in outcomes.tsv skipped"* ]]
    [[ "$output" == *"3 of 5 (60%)"* ]]
    run env UWS_KB_LEARN_MIN_N=0 "$UWS" kb learn
    [ "$status" -eq 2 ]
    run env UWS_KB_LEARN_CR_REJECT_RATE=2 "$UWS" kb learn
    [ "$status" -eq 2 ]
    run env UWS_KB_LEARN_MIN_N=6 "$UWS" kb learn --dry-run
    [[ "$output" == *"3 of 5 (60%) -> n < 6: no proposal"* ]]
}

@test "meta-learning scripts are ShellCheck-clean and free of GNU-only / bash 4 constructs" {
    local files=("${PROJECT_ROOT}/scripts/kb.sh" "${PROJECT_ROOT}/scripts/lib/kb_utils.sh"
                 "${PROJECT_ROOT}/scripts/review.sh" "${PROJECT_ROOT}/scripts/orchestrate.sh"
                 "${PROJECT_ROOT}/scripts/sdlc.sh" "${PROJECT_ROOT}/scripts/lib/hook_context.sh"
                 "${PROJECT_ROOT}/scripts/status.sh")
    if command -v shellcheck >/dev/null 2>&1; then
        run shellcheck -x -e SC1091 -S warning "${files[@]}"
        [ "$status" -eq 0 ]
    fi
    run grep -nE "sed -i( |$)|head -c -[0-9]|date [^|;]*%[0-9]*N" "${files[@]}"
    [ "$status" -eq 1 ]
    run grep -nE '\$\{[A-Za-z_0-9]+(,,|\^\^)\}|declare -A|local -A|mapfile|readarray|declare -n|local -n' "${files[@]}"
    [ "$status" -eq 1 ]
}
