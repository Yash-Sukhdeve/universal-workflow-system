#!/usr/bin/env bats
# Knowledge base, increment 1 (docs/design/knowledge-base.md section 12).
# Tests 1-14 are the design's acceptance tests, with test 6 adapted to the PI
# decision (only the PI promotes); test 15 (real Claude Code) is run by hand.
# The rest cover the research-team interface (docs/design/research-team.md
# section 9) and the PI gate.

load '../helpers/test_helper'

UWS="${PROJECT_ROOT}/bin/uws"
PI="pi@lab.example"

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
    printf 'line one\nUWS_HOOK_MAX_BYTES:-1200\n' > "${TEST_TMP_DIR}/f"
    printf 'watched\n' > "${TEST_TMP_DIR}/g"
    git config user.email "$PI"
    git add -A >/dev/null
    git commit -qm "fixture" >/dev/null
    KB="${TEST_TMP_DIR}/docs/kb"
}

teardown() {
    teardown_test_environment
}

# Run `uws kb` and keep only stdout (the new ID) in $KB_OUT
kb_id() {
    KB_OUT="$("$UWS" kb "$@" 2>/dev/null)"
}

set_pi() {
    "$UWS" kb pi --set "$PI" >/dev/null
}

item_count() {
    local n=0 f
    for f in "${KB}"/items/*.md; do [[ -f "$f" ]] && n=$((n + 1)); done
    echo "$n"
}

field() {  # field <file> <key>
    grep -E "^$2:" "$1" | head -1 | sed -e "s/^$2:[[:space:]]*//" -e 's/^"//' -e 's/"$//'
}

# Seed N trusted items (plus 1 disputed, 1 stale and 1 retired decoy that
# also match "test") directly on disk, reviewed by the PI.
seed_items() {
    local n="$1" i id
    mkdir -p "${KB}/items" "${KB}/retired"
    for i in $(seq 1 "$n"); do
        id="K-20260924-$(printf '%06x' "$i")"
        cat > "${KB}/items/${id}.md" <<EOF
---
id: ${id}
type: fact
scope: project
status: trusted
claim: "Seeded fact number ${i} says the test suite covers module ${i} with a long explanation that pads the claim to be quite long indeed"
evidence: observed
source: ["file:f:1"]
watch: [f]
watch_blob: [x]
author: uws-implementer
reviewer: ${PI}
captured_by: cli
created: 2026-09-24
verified_at: 2026-09-24
status_since: 2026-09-24
review_by: 2027-03-23
supersedes: []
superseded_by:
contradicts: []
supports: []
tags: [test, seeded]
---
Body for item ${i}.
EOF
    done
    local st
    for st in disputed stale; do
        id="K-20260924-dec0$([[ $st == disputed ]] && echo 01 || echo 02)"
        sed -e "s/^status: trusted/status: ${st}/" -e "s/^id: .*/id: ${id}/" \
            "${KB}/items/K-20260924-000001.md" > "${KB}/items/${id}.md"
    done
    id="K-20260924-dec003"
    sed -e "s/^status: trusted/status: retired/" -e "s/^id: .*/id: ${id}/" \
        "${KB}/items/K-20260924-000001.md" > "${KB}/retired/${id}.md"
}

# ── Acceptance tests 1-14 (design section 12) ───────────────────────────────

@test "1: add without --source exits 2 and writes nothing" {
    run "$UWS" kb add --type fact --claim X --evidence observed
    [ "$status" -eq 2 ]
    [[ "$output" == *"--source"* ]]
    [ "$(item_count)" -eq 0 ]
}

@test "2: add with a file source creates one candidate pinned to HEAD and logs one event" {
    local head
    head="$(git rev-parse --short HEAD)"
    kb_id add --type fact --claim "The hook budget default is 1200 bytes" --evidence observed \
        --source file:scripts/lib/hook_context.sh:30
    [[ "$KB_OUT" =~ ^K-20260924-[0-9a-f]{6}$ ]]
    [ "$(item_count)" -eq 1 ]
    local f="${KB}/items/${KB_OUT}.md"
    [ "$(field "$f" status)" = "candidate" ]
    grep -q "^source: \[\"file:scripts/lib/hook_context.sh:30@${head}\"\]" "$f"
    [ "$(wc -l < "${KB}/events.tsv" | tr -d ' ')" -eq 1 ]
    grep -q "${KB_OUT}.*candidate.*add" "${KB}/events.tsv"
}

@test "3: a source file that does not exist exits 2" {
    run "$UWS" kb add --type fact --claim "Something" --evidence observed --source file:does/not/exist:1
    [ "$status" -eq 2 ]
    [[ "$output" == *"does not exist"* ]]
    [ "$(item_count)" -eq 0 ]
}

@test "4: adding the same claim twice exits 3 and prints the first ID" {
    kb_id add --type fact --claim "Checkpoints live in .workflow" --evidence observed --source file:f:1
    local first="$KB_OUT"
    run "$UWS" kb add --type fact --claim "  checkpoints LIVE in .workflow.  " --evidence observed --source file:f:1
    [ "$status" -eq 3 ]
    [[ "$output" == *"$first"* ]]
    [ "$(item_count)" -eq 1 ]
}

@test "5: verified item: check passes (still candidate), PI approves, then a failing check disputes it" {
    set_pi
    kb_id add --type fact --claim "f holds the 1200 byte budget" --evidence verified \
        --source file:f:2 --check 'grep -q 1200 f' --tags budget
    local id="$KB_OUT" f="${KB}/items/${KB_OUT}.md"
    run "$UWS" kb verify "$id"
    [ "$status" -eq 0 ]
    [ "$(field "$f" status)" = "candidate" ]
    [ "$(field "$f" check_status)" = "pass" ]
    export UWS_KB_NOW="2026-09-25"
    run "$UWS" kb approve "$id"
    [ "$status" -eq 0 ]
    [ "$(field "$f" status)" = "trusted" ]
    [ "$(field "$f" verified_at)" = "2026-09-25" ]
    [ "$(field "$f" reviewer)" = "$PI" ]
    run "$UWS" kb search budget
    [ "$status" -eq 0 ]
    [[ "$output" == *"$id"* ]]
    printf 'no longer\n' > f
    run "$UWS" kb verify --changed
    [ "$status" -eq 5 ]
    [ "$(field "$f" status)" = "disputed" ]
    run "$UWS" kb search budget
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "6: approve by a non-PI actor is refused (exit 6); by the PI -> trusted; watched edit -> stale" {
    set_pi
    kb_id add --type lesson --claim "g is watched for changes" --evidence observed --source file:f:1 --watch g
    local id="$KB_OUT" f="${KB}/items/${KB_OUT}.md"
    git config user.email "reviewer@lab.example"
    run "$UWS" kb approve "$id"
    [ "$status" -eq 6 ]
    [[ "$output" == *"not the PI"* ]]
    [ "$(field "$f" status)" = "candidate" ]
    git config user.email "$PI"
    run "$UWS" kb approve "$id"
    [ "$status" -eq 0 ]
    [ "$(field "$f" status)" = "trusted" ]
    printf 'edited\n' > g
    run "$UWS" kb verify --changed
    [ "$status" -eq 0 ]
    [ "$(field "$f" status)" = "stale" ]
    grep -q "trusted	stale	watch-changed:g" "${KB}/events.tsv"
}

@test "7: supersedes retires the old item; restore brings it back; git log --follow shows both moves" {
    kb_id add --type fact --claim "Old claim about the release flow" --evidence observed --source file:f:1
    local a="$KB_OUT"
    git add -A >/dev/null && git commit -qm "add A"
    kb_id add --type fact --claim "New claim about the release process" --evidence observed --source file:f:1 --supersedes "$a"
    local b="$KB_OUT"
    [ -f "${KB}/retired/${a}.md" ]
    [ ! -f "${KB}/items/${a}.md" ]
    [ "$(field "${KB}/retired/${a}.md" retired_reason)" = "superseded-by:${b}" ]
    git add -A >/dev/null && git commit -qm "supersede A"
    run "$UWS" kb restore "$a"
    [ "$status" -eq 0 ]
    [ -f "${KB}/items/${a}.md" ]
    [ "$(field "${KB}/items/${a}.md" status)" = "candidate" ]
    git add -A >/dev/null && git commit -qm "restore A"
    run git log --follow --format=%s -- "docs/kb/items/${a}.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"restore A"* ]]
    [[ "$output" == *"supersede A"* ]]
    [[ "$output" == *"add A"* ]]
    # Restore also removed A from B's supersedes, so prune will not retire it again
    run "$UWS" kb prune
    [[ "$output" != *"$a"* ]]
}

@test "8: prune is a dry run by default; --apply marks expired items stale, then retires them" {
    set_pi
    export UWS_KB_NOW="2026-01-01"
    kb_id add --type fact --claim "A fact that will expire" --evidence observed --source file:f:1
    local id="$KB_OUT"
    "$UWS" kb approve "$id" >/dev/null
    git add -A >/dev/null && git commit -qm "kb"
    export UWS_KB_NOW="2026-07-15"   # past review_by (2026-06-30)
    local before
    before="$(git status --porcelain)"
    run "$UWS" kb prune
    [ "$status" -eq 0 ]
    [[ "$output" == *"would stale ${id}"* ]]
    [ "$(git status --porcelain)" = "$before" ]
    run "$UWS" kb prune --apply
    [ "$status" -eq 0 ]
    [ "$(field "${KB}/items/${id}.md" status)" = "stale" ]
    export UWS_KB_NOW="2026-08-15"   # 31 days later
    run "$UWS" kb prune --apply
    [ "$status" -eq 0 ]
    [ -f "${KB}/retired/${id}.md" ]
    [ "$(field "${KB}/retired/${id}.md" retired_reason)" = "expired" ]
}

@test "9: search over 50 trusted items stays within 5 lines, 200 bytes each, 1000 total" {
    set_pi
    seed_items 50
    run "$UWS" kb search test
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -le 5 ]
    local line
    while IFS= read -r line; do
        [ "$(printf '%s' "$line" | LC_ALL=C wc -c | tr -d ' ')" -le 200 ]
        [[ "$line" == *"|trusted|"* ]]
    done <<< "$output"
    [ "$(printf '%s\n' "$output" | LC_ALL=C wc -c | tr -d ' ')" -le 1000 ]
    [[ "$output" != *"dec00"* ]]
}

@test "10: SessionStart hook with 50 items stays within 1200 bytes, shows the KB line, writes nothing" {
    set_pi
    seed_items 50
    git add -A >/dev/null && git commit -qm "seed"
    local before
    before="$(git status --porcelain)"
    run "${PROJECT_ROOT}/scripts/recover_context.sh" --hook
    [ "$status" -eq 0 ]
    local ctx
    ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
    [ "$(printf '%s' "$ctx" | LC_ALL=C wc -c | tr -d ' ')" -le 1200 ]
    [[ "$ctx" == *"KB: 50 trusted"* ]]
    [ "$(git status --porcelain)" = "$before" ]
}

@test "11: two trusted items linked by contradicts fail lint, naming both" {
    set_pi
    seed_items 2
    local a="K-20260924-000001" b="K-20260924-000002"
    sed -e "s/^contradicts: \[\]/contradicts: [${b}]/" "${KB}/items/${a}.md" > x && mv x "${KB}/items/${a}.md"
    sed -e "s/^contradicts: \[\]/contradicts: [${a}]/" "${KB}/items/${b}.md" > x && mv x "${KB}/items/${b}.md"
    run "$UWS" kb lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"I3"*"$a"*"$b"* ]]
}

@test "12: a claim containing an AWS access key shape exits 2" {
    run "$UWS" kb add --type fact --claim "key AKIAABCDEFGHIJKLMNOP leaked" --evidence observed --source file:f:1
    [ "$status" -eq 2 ]
    [[ "$output" == *"secret"* ]]
    [ "$(item_count)" -eq 0 ]
}

@test "13: deleting .cache does not change stats or search output (I5)" {
    set_pi
    seed_items 8
    run "$UWS" kb stats
    local stats1="$output"
    run "$UWS" kb search test
    local search1="$output"
    [ -f "${KB}/.cache/stats" ]
    rm -rf "${KB}/.cache"
    run "$UWS" kb stats
    [ "$output" = "$stats1" ]
    run "$UWS" kb search test
    [ "$output" = "$search1" ]
}

@test "14: KB scripts are ShellCheck-clean and free of GNU-only / bash 4 constructs" {
    command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
    run shellcheck -x -e SC1091 -S warning "${PROJECT_ROOT}/scripts/kb.sh" "${PROJECT_ROOT}/scripts/lib/kb_utils.sh"
    [ "$status" -eq 0 ]
    run grep -nE "sed -i( |$)|head -c -[0-9]|date [^|;]*%[0-9]*N" "${PROJECT_ROOT}/scripts/kb.sh" "${PROJECT_ROOT}/scripts/lib/kb_utils.sh"
    [ "$status" -eq 1 ]
    run grep -nE '\$\{[A-Za-z_0-9]+(,,|\^\^)\}|declare -A|local -A|mapfile|readarray|declare -n|local -n' \
        "${PROJECT_ROOT}/scripts/kb.sh" "${PROJECT_ROOT}/scripts/lib/kb_utils.sh"
    [ "$status" -eq 1 ]
}

# ── PI-only promotion ───────────────────────────────────────────────────────

@test "PI gate: approve is refused inside an AI agent even with the PI's identity" {
    set_pi
    kb_id add --type fact --claim "Agent context cannot promote" --evidence observed --source file:f:1
    run env CLAUDECODE=1 "$UWS" kb approve "$KB_OUT"
    [ "$status" -eq 6 ]
    [[ "$output" == *"AI agent"* ]]
    run env UWS_AGENT=uws-implementer "$UWS" kb approve "$KB_OUT"
    [ "$status" -eq 6 ]
    [ "$(field "${KB}/items/${KB_OUT}.md" status)" = "candidate" ]
}

@test "PI gate: no PI configured refuses approve; --as must equal the PI and the git identity" {
    kb_id add --type fact --claim "Needs a PI" --evidence observed --source file:f:1
    run "$UWS" kb approve "$KB_OUT"
    [ "$status" -eq 6 ]
    [[ "$output" == *"no PI configured"* ]]
    set_pi
    run "$UWS" kb approve "$KB_OUT" --as someone@else.example
    [ "$status" -eq 6 ]
    git config user.email "other@lab.example"
    run "$UWS" kb approve "$KB_OUT" --as "$PI"
    [ "$status" -eq 6 ]
    git config user.email "$PI"
    run "$UWS" kb approve "$KB_OUT" --as "$PI"
    [ "$status" -eq 0 ]
}

@test "PI gate: config kb.pi wins over UWS_KB_PI; pi --set is refused inside an agent" {
    set_pi
    run env UWS_KB_PI=agent@evil.example "$UWS" kb pi
    [ "$output" = "$PI" ]
    run env CLAUDECODE=1 "$UWS" kb pi --set agent@evil.example
    [ "$status" -eq 6 ]
    grep -q "pi: \"${PI}\"" "${TEST_TMP_DIR}/.workflow/config.yaml"
}

@test "PI gate: an agent can recommend but the item stays a candidate" {
    set_pi
    kb_id add --type fact --claim "Recommended by an agent" --evidence observed --source file:f:1
    run env CLAUDECODE=1 "$UWS" kb recommend "$KB_OUT" "sources checked"
    [ "$status" -eq 0 ]
    local f="${KB}/items/${KB_OUT}.md"
    [ "$(field "$f" status)" = "candidate" ]
    grep -q "^recommended_by: \[agent:" "$f"
    run "$UWS" kb review
    [[ "$output" == *"$KB_OUT"*"recommended:agent:"* ]]
}

@test "PI gate: approve refuses when a verified item's check fails" {
    set_pi
    kb_id add --type fact --claim "Check must pass at approval" --evidence verified --source file:f:1 --check 'grep -q absent-text f'
    run "$UWS" kb approve "$KB_OUT"
    [ "$status" -eq 5 ]
    [ "$(field "${KB}/items/${KB_OUT}.md" status)" = "candidate" ]
}

@test "lint I7: a hand-edited trusted status (no PI review) is reported" {
    set_pi
    kb_id add --type fact --claim "Edited by hand" --evidence observed --source file:f:1
    local f="${KB}/items/${KB_OUT}.md"
    sed -e 's/^status: candidate/status: trusted/' "$f" > x && mv x "$f"
    run "$UWS" kb lint
    [ "$status" -eq 1 ]
    [[ "$output" == *"I7 ${KB_OUT}"* ]]
}

@test "reject (PI only) retires a candidate as rejected" {
    set_pi
    kb_id add --type fact --claim "To be rejected" --evidence observed --source file:f:1
    run env CLAUDECODE=1 "$UWS" kb reject "$KB_OUT" "wrong"
    [ "$status" -eq 6 ]
    run "$UWS" kb reject "$KB_OUT" "wrong"
    [ "$status" -eq 0 ]
    [ "$(field "${KB}/retired/${KB_OUT}.md" retired_reason)" = "rejected:wrong" ]
}

# ── Research-team interface (research-team.md section 9) ────────────────────

@test "interface: add is non-interactive and prints only the ID on stdout" {
    local out
    out="$("$UWS" kb add --type lesson --claim "Pinned numpy breaks opencv wheels" --evidence observed \
        --source file:f:1 --author uws-researcher --tags numpy,opencv </dev/null 2>/dev/null)"
    [[ "$out" =~ ^K-20260924-[0-9a-f]{6}$ ]]
    [ "$(field "${KB}/items/${out}.md" author)" = "uws-researcher" ]
    grep -q '^tags: \[numpy, opencv\]' "${KB}/items/${out}.md"
}

@test "interface: validation failures give a one-line reason on stderr" {
    local err
    err="$("$UWS" kb add --type fact --claim "x" --evidence guessed --source file:f:1 2>&1 >/dev/null || true)"
    [ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" -eq 1 ]
    [[ "$err" == *"unknown evidence"* ]]
    run "$UWS" kb add --type fact --claim "x" --evidence observed --source file:f:1 --reviewer bob
    [ "$status" -eq 2 ]
}

@test "interface: claims over 240 bytes are refused; 240 is accepted" {
    local long ok
    long="$(printf 'a%.0s' $(seq 1 241))"
    ok="$(printf 'b%.0s' $(seq 1 240))"
    run "$UWS" kb add --type fact --claim "$long" --evidence observed --source file:f:1
    [ "$status" -eq 2 ]
    [[ "$output" == *"241 bytes"* ]]
    run "$UWS" kb add --type fact --claim "$ok" --evidence observed --source file:f:1
    [ "$status" -eq 0 ]
}

@test "interface: search --status disputed and links --type contradicts find disputes" {
    set_pi
    kb_id add --type fact --claim "git stash pop drops changes on conflict" --evidence observed --source file:f:1
    local a="$KB_OUT"
    "$UWS" kb approve "$a" >/dev/null
    kb_id add --type fact --claim "A conflicting stash pop keeps the stash entry" --evidence reported \
        --source url:https://git-scm.com/docs/git-stash \
        --quote "Applying the state can fail with conflicts; in this case, it is not removed from the stash list" \
        --contradicts "$a"
    local b="$KB_OUT"
    run "$UWS" kb links --type contradicts "$a"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$b"* ]]
    run "$UWS" kb links --type contradicts stash
    [ "$status" -eq 0 ]
    [[ "$output" == *"$a"* && "$output" == *"$b"* ]]
    [[ "$output" == *"{contradicts "* ]]
    # The PI settles it: approving B retires A as disproven
    run "$UWS" kb approve "$b"
    [ "$status" -eq 0 ]
    [ "$(field "${KB}/retired/${a}.md" retired_reason)" = "disproven-by:${b}" ]
    run "$UWS" kb lint
    [ "$status" -eq 0 ]
    # A disputed item is visible only through --status disputed
    kb_id add --type fact --claim "stash entries are kept in refs/stash" --evidence verified \
        --source file:f:1 --check 'grep -q "line one" f' --no-conflict
    "$UWS" kb approve "$KB_OUT" >/dev/null
    printf 'changed\n' > f
    "$UWS" kb verify --changed >/dev/null || true
    run "$UWS" kb search --status disputed stash
    [ "$status" -eq 0 ]
    [[ "$output" == *"$KB_OUT [fact|disputed|verified|"* ]]
}

@test "interface: search lines carry status and evidence; candidates show check-passed" {
    set_pi
    kb_id add --type fact --claim "f contains line one" --evidence verified --source file:f:1 --check 'grep -q "line one" f'
    "$UWS" kb verify "$KB_OUT" >/dev/null
    run "$UWS" kb search --all line
    [ "$status" -eq 0 ]
    [[ "$output" == "$KB_OUT [fact|candidate|verified|check-passed|2026-09-24] f contains line one (file:f:1@"* ]]
}

# ── Other rules ─────────────────────────────────────────────────────────────

@test "add: undeclared overlap with a trusted item exits 4; --no-conflict accepts" {
    set_pi
    kb_id add --type fact --claim "Checkpoint snapshots are gitignored locally" --evidence observed --source file:f:1
    "$UWS" kb approve "$KB_OUT" >/dev/null
    run "$UWS" kb add --type fact --claim "Checkpoint snapshots gitignored locally always" --evidence observed --source file:g:1
    [ "$status" -eq 4 ]
    run "$UWS" kb add --type fact --claim "Checkpoint snapshots gitignored locally always" --evidence observed --source file:g:1 --no-conflict
    [ "$status" -eq 0 ]
}

@test "add: provenance rules per evidence level and type" {
    run "$UWS" kb add --type fact --claim "r" --evidence reported --source url:https://example.org
    [ "$status" -eq 2 ]
    [[ "$output" == *"verbatim quote"* ]]
    run "$UWS" kb add --type fact --claim "i" --evidence inferred --source file:f:1
    [ "$status" -eq 2 ]
    run "$UWS" kb add --type hypothesis --claim "h" --evidence inferred --source file:f:1
    [ "$status" -eq 2 ]
    [[ "$output" == *"falsifier"* ]]
    run "$UWS" kb add --type fact --claim "v" --evidence verified --source file:f:1
    [ "$status" -eq 2 ]
    run "$UWS" kb add --type fact --claim "d" --evidence verified --source file:f:1 --check 'rm -rf /tmp/x'
    [ "$status" -eq 2 ]
    [[ "$output" == *"destructive"* ]]
    run "$UWS" kb add --type question --claim "Why did the design gate fail?"
    [ "$status" -eq 0 ]
    # increment 2: global items need the global KB repository (uws kb init --global)
    run "$UWS" kb add --type fact --claim "global" --evidence observed --source file:f:1 --scope global
    [ "$status" -eq 2 ]
    [[ "$output" == *"not its own git repository"* ]]
}

@test "verify: a check that times out marks a trusted item stale, not disputed" {
    set_pi
    kb_id add --type fact --claim "Slow check item" --evidence verified --source file:f:1 --check 'sleep 5'
    local f="${KB}/items/${KB_OUT}.md"
    sed -e 's/^check: .*/check: "true"/' "$f" > x && mv x "$f"
    "$UWS" kb approve "$KB_OUT" >/dev/null
    sed -e 's/^check: .*/check: "sleep 5"/' "$f" > x && mv x "$f"
    run env UWS_KB_CHECK_TIMEOUT=1 "$UWS" kb verify "$KB_OUT"
    [ "$status" -eq 0 ]
    [ "$(field "$f" status)" = "stale" ]
    [ "$(field "$f" check_status)" = "timeout" ]
}

@test "prune: candidates retire as unpromoted after 30 days; disputed as disproven after 14" {
    set_pi
    kb_id add --type fact --claim "Never promoted" --evidence observed --source file:f:1
    local c="$KB_OUT"
    kb_id add --type fact --claim "f has line one" --evidence verified --source file:f:1 --check 'grep -q "line one" f'
    local d="$KB_OUT"
    "$UWS" kb approve "$d" >/dev/null
    printf 'x\n' > f
    "$UWS" kb verify --changed >/dev/null || true
    export UWS_KB_NOW="2026-10-24"
    run "$UWS" kb prune --apply
    [ "$status" -eq 0 ]
    [ "$(field "${KB}/retired/${c}.md" retired_reason)" = "unpromoted" ]
    [ "$(field "${KB}/retired/${d}.md" retired_reason)" = "disproven" ]
}

@test "retire, show and stats: manual retirement is logged and reversible" {
    kb_id add --type decision --claim "Use plain files for the KB" --evidence observed --source file:f:1
    run "$UWS" kb show "$KB_OUT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"review_by: never"* ]]
    run "$UWS" kb retire "$KB_OUT" "replaced by ADR-7"
    [ "$status" -eq 0 ]
    grep -q "candidate	retired	replaced by ADR-7" "${KB}/events.tsv"
    run "$UWS" kb stats
    [[ "$output" == *"0 active"*"1 retired"* ]]
    run "$UWS" kb show K-20260101-abcdef
    [ "$status" -eq 1 ]
}

@test "uws help lists kb; the KB gitignores its cache" {
    run "$UWS" help
    [[ "$output" == *"kb <verb>"* ]]
    kb_id add --type fact --claim "Cache is local" --evidence observed --source file:f:1
    grep -qx '.cache/' "${KB}/.gitignore"
    "$UWS" kb stats >/dev/null
    [ -z "$(git status --porcelain docs/kb/.cache)" ]
}
