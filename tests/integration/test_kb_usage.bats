#!/usr/bin/env bats
# Knowledge base increment 2 (docs/design/knowledge-base.md sections 5.3, 5.6 and 18):
# the per-machine usage log, rule R4 (unused items are proposed for retirement, never
# retired automatically), the R4-unused-share metric of `uws kb learn`, knowledge
# leads in the subagent brief (TASK.md), and the guard that keeps the test suite from
# writing into the real UWS checkout's KB.

load '../helpers/test_helper'

UWS="${PROJECT_ROOT}/bin/uws"
PI="pi@lab.example"

setup() {
    setup_test_environment
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_CHILD_SESSION AI_AGENT \
          UWS_AGENT GEMINI_CLI CODEX_SANDBOX UWS_KB_PI UWS_KB_DIR UWS_KB_ALLOW_GUARDED_WRITE
    export UWS_KB_NOW="2026-09-24" UWS_KB_SESSION="s1"
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
    USAGE="${KB}/.cache/usage.tsv"
    "$UWS" kb pi --set "$PI" >/dev/null
}

teardown() {
    teardown_test_environment
}

field() { grep -E "^$2:" "$1" | head -1 | sed -e "s/^$2:[[:space:]]*//" -e 's/^"//' -e 's/"$//'; }
proposal_files() { grep -l '^type: proposal$' "${KB}"/items/*.md 2>/dev/null || true; }
proposal_count() { proposal_files | grep -c . || true; }

# A trusted item on disk: <id> <type> <claim> [created]
seed() {
    mkdir -p "${KB}/items" "${KB}/retired"
    cat > "${KB}/items/$1.md" <<EOF
---
id: $1
type: $2
scope: project
status: trusted
claim: "$3"
evidence: observed
source: ["file:f:1"]
watch: []
watch_blob: []
author: uws-implementer
reviewer: ${PI}
captured_by: cli
created: ${4:-2026-01-01}
verified_at: 2026-09-01
status_since: 2026-09-01
review_by: 2027-03-01
supersedes: []
superseded_by:
contradicts: []
supports: []
tags: [seeded]
---
EOF
}

# Six old trusted facts about different topics, plus an old decision
seed_six() {
    local i
    for i in 1 2 3 4 5 6; do seed "K-20260101-00000${i}" fact "Topic${i} fact about the build number ${i}"; done
    seed K-20260101-0000d1 decision "Decision about topic9 layout"
}

session() {  # session <name> <words...>: one session that searches for <words>
    local s="$1"; shift
    UWS_KB_SESSION="$s" "$UWS" kb search "$@" >/dev/null 2>&1 || true
}

# ── usage log ───────────────────────────────────────────────────────────────

@test "usage: search, show and subagent briefs are logged per machine in the gitignored cache" {
    seed K-20260101-000001 fact "Topic1 fact about the release"
    seed K-20260101-000002 fact "Topic2 fact about the release"
    git add -A >/dev/null && git commit -qm kb >/dev/null
    run "$UWS" kb search topic1
    [ "$status" -eq 0 ]
    run "$UWS" kb show K-20260101-000002
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$USAGE" | tr -d ' ')" -eq 3 ]
    [ "$(sed -n 1p "$USAGE")" = "2026-09-24T00:00:00Z	s1	-	search" ]
    [ "$(sed -n 2p "$USAGE")" = "2026-09-24T00:00:00Z	s1	K-20260101-000001	search" ]
    [ "$(sed -n 3p "$USAGE")" = "2026-09-24T00:00:00Z	s1	K-20260101-000002	show" ]
    # a search that finds nothing still counts the session
    run env UWS_KB_SESSION=s2 "$UWS" kb search nothingmatches
    [ "$status" -eq 1 ]
    [ "$(tail -1 "$USAGE")" = "2026-09-24T00:00:00Z	s2	-	search" ]
    # the log never dirties the tree; the session name is sanitised
    run env UWS_KB_SESSION='a b/c;d' "$UWS" kb search topic1
    [[ "$(tail -1 "$USAGE")" == *"	a_b_c_d	K-20260101-000001	search" ]]
    [ -z "$(git status --porcelain)" ]
    run "$UWS" kb stats
    [[ "$output" == *"usage on this machine: 3 retrieval(s) of 2 item(s) in 3 session(s)"* ]]
}

@test "usage: without UWS_KB_SESSION a session is the Claude Code session, else the day" {
    seed K-20260101-000001 fact "Topic1 fact"
    run env -u UWS_KB_SESSION CLAUDE_CODE_SESSION_ID=abc-123 "$UWS" kb search topic1
    [[ "$(tail -1 "$USAGE")" == *"	abc-123	K-20260101-000001	search" ]]
    run env -u UWS_KB_SESSION -u CLAUDE_CODE_SESSION_ID "$UWS" kb search topic1
    [[ "$(tail -1 "$USAGE")" == *"	day-2026-09-24	K-20260101-000001	search" ]]
}

@test "search: function words are ignored and --min-terms asks for several matching words" {
    seed K-20260101-000001 fact "The login rate limiter uses a sliding window"
    seed K-20260101-000002 fact "Login tokens expire after one hour"
    run "$UWS" kb search -- the of and
    [ "$status" -eq 0 ]
    run "$UWS" kb search --min-terms 2 -- "Implement the login rate limiter"
    [ "$status" -eq 0 ]
    [[ "$output" == "K-20260101-000001 "* ]]
    [[ "$output" != *"K-20260101-000002"* ]]
    run "$UWS" kb search -- "Implement the login rate limiter"
    [[ "$output" == *"K-20260101-000002"* ]]
    run "$UWS" kb search --min-terms x login
    [ "$status" -eq 2 ]
}

# ── R4 ──────────────────────────────────────────────────────────────────────

@test "R4: prune proposes, and never applies, retiring old trusted items unused in the last N sessions" {
    export UWS_KB_UNUSED_SESSIONS=3
    seed_six
    seed K-20260920-0000aa fact "Topic7 young fact" 2026-09-20
    session s1 topic1
    session s2 topic1
    run "$UWS" kb prune
    [[ "$output" == *"R4 (unused) not evaluated: 2 of 3 sessions of usage recorded on this machine."* ]]
    session s3 topic1
    run "$UWS" kb prune
    [ "$status" -eq 0 ]
    local i
    for i in 2 3 4 5 6; do
        [[ "$output" == *"R4: K-20260101-00000${i} was not retrieved in the last 3 sessions on this machine; retire it only if you agree: uws kb retire K-20260101-00000${i} unused"* ]]
    done
    [[ "$output" != *"K-20260101-000001 was not"* ]]   # retrieved
    [[ "$output" != *"K-20260101-0000d1"* ]]            # decisions are excluded
    [[ "$output" != *"K-20260920-0000aa"* ]]            # younger than 90 days
    run "$UWS" kb prune --apply
    [ "$status" -eq 0 ]
    [ -f "${KB}/items/K-20260101-000002.md" ]
    [ "$(ls "${KB}/retired" | wc -l | tr -d ' ')" -eq 0 ]
    # the human confirms one; the retirement carries the reason code unused
    run "$UWS" kb retire K-20260101-000002 unused
    [ "$status" -eq 0 ]
    [ "$(field "${KB}/retired/K-20260101-000002.md" retired_reason)" = "unused" ]
    [ "$(tail -1 "${KB}/outcomes.tsv" | cut -f 7)" = "unused evidence=observed captured_by=cli from=trusted type=fact" ]
    # usage in any of the last 3 sessions saves an item
    session s4 topic3
    run "$UWS" kb prune
    [[ "$output" != *"K-20260101-000003 was not"* ]]
    run env UWS_KB_UNUSED_SESSIONS=0 "$UWS" kb prune
    [ "$status" -eq 2 ]
}

# ── learn: the R4-unused share ──────────────────────────────────────────────

@test "learn: the unused share comes from the usage log and proposes halving the review window" {
    export UWS_KB_UNUSED_SESSIONS=3
    seed_six
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"r4-unused-share trusted-items: not measured yet (0 of 3 sessions of usage recorded on this machine)"* ]]
    session s1 topic1; session s2 topic1; session s3 topic1
    run "$UWS" kb learn --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"r4-unused-share trusted-items: 5 of 6 (83%) -> over the threshold"* ]]
    [ "$(proposal_count)" -eq 0 ]
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [ "$(proposal_count)" -eq 1 ]
    local p
    p="$(proposal_files)"
    [ "$(field "$p" metric)" = "r4-unused-share" ]
    [ "$(field "$p" metric_key)" = "trusted-items" ]
    [ "$(field "$p" metric_n)" = "6" ]
    [ "$(field "$p" metric_k)" = "5" ]
    [ "$(field "$p" metric_before)" = "0.83" ]
    [ "$(field "$p" target)" = "scripts/kb.sh" ]
    [ "$(field "$p" status)" = "candidate" ]
    [[ "$(field "$p" claim)" == "Unused trusted items: 5 of 6 (83%) were not retrieved in the last 3 sessions on this machine, above 50%; proposal: halve the fact review window (180 -> 90 days)." ]]
    grep -q '^source: \["file:docs/kb/.cache/usage.tsv"\]$' "$p"
    grep -q '^-        fact) echo 180 ;;$' "$p"
    grep -q '^+        fact) echo 90 ;;$' "$p"
    grep -q 'Written by `uws kb learn` from docs/kb/.cache/usage.tsv' "$p"
    grep -q '^- Rows behind the count: K-20260101-000002,K-20260101-000003' "$p"
    grep -q 'usage is recorded on this machine only' "$p"
    # the target file is untouched and a rerun proposes nothing new
    [ -z "$(git status --porcelain scripts)" ]
    run "$UWS" kb learn
    [[ "$output" == *"r4-unused-share trusted-items: already proposed ($(basename "$p" .md))"* ]]
    [ "$(proposal_count)" -eq 1 ]
    run env UWS_KB_LEARN_UNUSED_SHARE=1.5 "$UWS" kb learn
    [ "$status" -eq 2 ]
}

@test "learn: below the threshold or with n < 5 the unused share proposes nothing" {
    export UWS_KB_UNUSED_SESSIONS=2
    seed_six
    session s1 topic1 topic2 topic3; session s2 topic4
    run "$UWS" kb learn
    [[ "$output" == *"r4-unused-share trusted-items: 2 of 6 (33%) -> within the threshold"* ]]
    rm -f "${KB}"/items/K-20260101-00000[3-6].md
    run "$UWS" kb learn
    [[ "$output" == *"r4-unused-share trusted-items: 0 of 2 (0%) -> n < 5: no proposal"* ]]
    [ "$(proposal_count)" -eq 0 ]
}

@test "learn: an approved unused-share change is measured over the next N sessions; no improvement proposes the revert" {
    export UWS_KB_UNUSED_SESSIONS=3
    seed_six
    session s1 topic1; session s2 topic1; session s3 topic1
    "$UWS" kb learn >/dev/null
    local p id
    p="$(proposal_files)"; id="$(field "$p" id)"
    run "$UWS" kb approve "$id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"measure r4-unused-share over the next 3 sessions on this machine"* ]]
    export UWS_KB_NOW="2026-09-25"
    session s4 topic1
    run "$UWS" kb learn
    [[ "$output" == *"tracking ${id} (r4-unused-share, trusted-items): 1 of 3 sessions since approval"* ]]
    session s5 topic1; session s6 topic1
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"${id}: did not improve (83% -> 83% over 3 sessions)"* ]]
    [ "$(proposal_count)" -eq 2 ]
    local r
    r="$(grep -l '^proposal_kind: revert$' "${KB}"/items/*.md)"
    [ "$(field "$r" reverts)" = "$id" ]
    [[ "$(field "$r" claim)" == "Revert ${id}: r4-unused-share for trusted-items went 83% -> 83% over the 3 sessions after its approval (no improvement)." ]]
    grep -q '^-        fact) echo 90 ;;$' "$r"
    grep -q '^+        fact) echo 180 ;;$' "$r"
    [ "$(field "$p" followup)" = "revert-proposed:$(field "$r" id)" ]
    run "$UWS" kb learn
    [[ "$output" == *"already proposed ($(field "$r" id))"* ]]
    [ "$(proposal_count)" -eq 2 ]
}

@test "learn: an approved unused-share change that improves closes its tracking" {
    export UWS_KB_UNUSED_SESSIONS=3
    seed_six
    session s1 topic1; session s2 topic1; session s3 topic1
    "$UWS" kb learn >/dev/null
    local p id
    p="$(proposal_files)"; id="$(field "$p" id)"
    "$UWS" kb approve "$id" >/dev/null
    export UWS_KB_NOW="2026-09-25"
    session s4 topic1 topic2 topic3; session s5 topic4 topic5; session s6 topic6
    run "$UWS" kb learn
    [ "$status" -eq 0 ]
    [[ "$output" == *"${id}: improved (83% -> 0% over 3 sessions); tracking closed"* ]]
    [ "$(field "$p" followup)" = "improved 0.83 -> 0.00 over 3 sessions" ]
    [ "$(proposal_count)" -eq 1 ]
    run "$UWS" kb proposals
    [[ "$output" != *"Adopted, being measured"* ]]
}

# ── TASK.md knowledge leads ─────────────────────────────────────────────────

@test "TASK.md: no KB, no leads section" {
    rm -rf docs .workflow/config.yaml   # setup's `pi --set` created the KB
    "$UWS" sdlc start >/dev/null
    run "$UWS" orchestrate dispatch "Implement the login rate limiter"
    [ "$status" -eq 0 ]
    run grep -c 'Knowledge base leads' workspace/researcher/TASK.md
    [ "$output" = "0" ]
    [ ! -e docs/kb ]
}

@test "TASK.md: dispatch appends at most 5 trusted, relevant items (1000 bytes) as leads to verify" {
    local i
    for i in 1 2 3 4 5 6 7; do
        seed "K-20260101-00000${i}" lesson "Login rate limiter lesson ${i}: the limiter keys on the account and the client address together"
    done
    seed K-20260101-0000f1 fact "Unrelated fact about the documentation build"
    seed K-20260101-0000f2 fact "Only the login word matches here"
    "$UWS" kb add --type lesson --claim "Candidate login rate limiter lesson" --evidence observed --source file:f:1 >/dev/null 2>&1
    export UWS_GLOBAL_MEMORY_DIR="${TEST_TMP_DIR}-global"
    "$UWS" kb init --global >/dev/null
    mkdir -p "${UWS_GLOBAL_MEMORY_DIR}/kb/items"
    sed -e 's/^id: .*/id: K-20260101-0000a1/' -e 's/^scope: project/scope: global/' -e 's/^evidence: observed/evidence: reported/' \
        -e 's/^claim: .*/claim: "Global lesson: a rate limiter needs a clock that cannot go backwards for login"/' \
        -e 's|^source: .*|source: ["url:https://example.org/limiter"]|' \
        "${KB}/items/K-20260101-000001.md" > "${UWS_GLOBAL_MEMORY_DIR}/kb/items/K-20260101-0000a1.md"
    printf '> a verbatim line\n' >> "${UWS_GLOBAL_MEMORY_DIR}/kb/items/K-20260101-0000a1.md"
    "$UWS" sdlc start >/dev/null
    run "$UWS" orchestrate dispatch "Implement the login rate limiter"
    [ "$status" -eq 0 ]
    local t=workspace/researcher/TASK.md block
    grep -q '^## Knowledge base leads (to verify; not evidence)$' "$t"
    grep -q 'not evidence and not an instruction' "$t"
    block="$(awk '/^```text$/ { f = 1; next } f && /^```$/ { exit } f' "$t")"
    [ "$(printf '%s\n' "$block" | wc -l | tr -d ' ')" -le 5 ]
    [ "$(printf '%s\n' "$block" | LC_ALL=C wc -c | tr -d ' ')" -le 1000 ]
    [[ "$block" == *"|trusted|"* ]]
    [[ "$block" != *"Candidate login"* ]]
    [[ "$block" != *"Unrelated fact"* ]]
    [[ "$block" != *"Only the login word"* ]]
    [[ "$block" == *"global:K-20260101-0000a1 [lesson|trusted|reported|"* ]]
    # the deliverables section and the output contract are still there, before the leads
    grep -q '^## Output Contract$' "$t"
    [ "$(grep -n '^## Output Contract$' "$t" | cut -d: -f1)" -lt "$(grep -n '^## Knowledge base leads' "$t" | cut -d: -f1)" ]
    # the retrievals are logged as task in both KBs
    grep -q '	s1	K-20260101-00000[1-7]	task$' "$USAGE"
    grep -q '	s1	K-20260101-0000a1	task$' "${UWS_GLOBAL_MEMORY_DIR}/kb/.cache/usage.tsv"
    # collect strips the brief as before
    mkdir -p workspace/researcher/docs/uws-work
    printf 'req\n' > workspace/researcher/docs/uws-work/sdlc-requirements.md
    run "$UWS" orchestrate collect "researcher: requirements"
    [ "$status" -eq 0 ]
    [ ! -e "$t" ]
}

@test "TASK.md: a task that starts with dashes or matches nothing still dispatches" {
    seed K-20260101-000001 lesson "Login rate limiter lesson"
    "$UWS" sdlc start >/dev/null
    run "$UWS" orchestrate dispatch "--dry-run flag for the login limiter"
    [ "$status" -eq 0 ]
    grep -q '^## Knowledge base leads' workspace/researcher/TASK.md
    run "$UWS" orchestrate dispatch "Write the release notes"
    [ "$status" -eq 0 ]
    run grep -c 'Knowledge base leads' workspace/researcher/TASK.md
    [ "$output" = "0" ]
}

# ── test-suite guard ────────────────────────────────────────────────────────

@test "guard: the test helper protects the UWS checkout's KB, and a test can opt in" {
    # exported for every test file, pointing at this checkout
    [ "$UWS_KB_GUARD_ROOT" = "$PROJECT_ROOT" ]
    run bash -c 'source "$1/scripts/lib/kb_utils.sh"; kb_guarded "$1/docs/kb"' _ "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    run bash -c 'source "$1/scripts/lib/kb_utils.sh"; kb_guarded "$2/docs/kb"' _ "$PROJECT_ROOT" "$TEST_TMP_DIR"
    [ "$status" -eq 1 ]
    run env UWS_KB_ALLOW_GUARDED_WRITE=1 bash -c 'source "$1/scripts/lib/kb_utils.sh"; kb_guarded "$1/docs/kb"' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
    run env -u UWS_KB_GUARD_ROOT bash -c 'source "$1/scripts/lib/kb_utils.sh"; kb_guarded "$1/docs/kb"' _ "$PROJECT_ROOT"
    [ "$status" -eq 1 ]
    # The global KB of the tests is never the user's real one
    [[ "$UWS_GLOBAL_MEMORY_DIR" != "${HOME}/uws-global-knowledge" ]]
}

@test "guard: nothing is recorded or written in a guarded checkout's KB unless the test opts in" {
    # A stand-in for the UWS checkout: a project whose KB already exists
    local fake="${TEST_TMP_DIR}/fake-uws"
    mkdir -p "$fake/.workflow" "$fake/docs/kb/items"
    cp .workflow/state.yaml .workflow/checkpoints.log "$fake/.workflow/"
    seed K-20260101-000001 fact "Topic1 fact"
    cp "${KB}/items/K-20260101-000001.md" "$fake/docs/kb/items/"
    (cd "$fake" && git init -q && git config user.email "$PI" && printf 'line one\n' > f && git add -A && git commit -qm init)
    export UWS_KB_GUARD_ROOT="$fake"
    cd "$fake"
    "$UWS" sdlc start >/dev/null
    "$UWS" sdlc goto verification >/dev/null
    run "$UWS" sdlc fail "tests fail"
    [ "$status" -eq 0 ]
    run "$UWS" kb search topic1
    [ "$status" -eq 0 ]
    run "$UWS" orchestrate dispatch "topic1 fact check"
    [ "$status" -eq 0 ]
    run "$UWS" kb add --type fact --claim "Guarded" --evidence observed --source file:f:1
    [ "$status" -eq 2 ]
    [[ "$output" == *"refusing to write the KB"*"UWS_KB_ALLOW_GUARDED_WRITE=1"* ]]
    run "$UWS" kb stats
    [ "$status" -eq 0 ]
    [ ! -e docs/kb/outcomes.tsv ]
    [ ! -e docs/kb/.cache ]
    [ ! -e docs/kb/events.tsv ]
    [ "$(ls docs/kb/items)" = "K-20260101-000001.md" ]
    # opted in: the same calls record
    export UWS_KB_ALLOW_GUARDED_WRITE=1
    run "$UWS" sdlc fail "tests fail again"
    [ "$status" -eq 0 ]
    [ "$(cut -f 2 docs/kb/outcomes.tsv)" = "gate_fail" ]
    run "$UWS" kb search topic1
    [ -s docs/kb/.cache/usage.tsv ]
    cd "$TEST_TMP_DIR"
}

# ── increment-1 regression found while building increment 2 ────────────────

@test "lists: every element of a quoted list is read without the spacing, so a two-source item can be approved" {
    printf 'watched\n' > g
    git add g && git commit -qm g >/dev/null
    local id
    id="$("$UWS" kb add --type fact --claim "Two files agree" --evidence observed --source file:f:1 --source file:g:1 2>/dev/null)"
    run "$UWS" kb approve "$id"
    [ "$status" -eq 0 ]
    [ "$(field "${KB}/items/${id}.md" status)" = "trusted" ]
    run "$UWS" kb lint
    [ "$status" -eq 0 ]
}
