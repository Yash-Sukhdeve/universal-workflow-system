#!/usr/bin/env bats
# Knowledge base increment 2: the global (cross-project) KB (docs/design/knowledge-base.md
# sections 4.5, 10 risk 13 and 18). It lives at $UWS_GLOBAL_MEMORY_DIR/kb, must be its own
# git repository before anything is written there, keeps its own PI, holds no project
# paths in claims, and is searched together with the project KB.

load '../helpers/test_helper'

UWS="${PROJECT_ROOT}/bin/uws"
PI="pi@lab.example"

setup() {
    setup_test_environment
    unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_CHILD_SESSION AI_AGENT \
          UWS_AGENT GEMINI_CLI CODEX_SANDBOX UWS_KB_PI UWS_KB_DIR
    export UWS_KB_NOW="2026-09-24" UWS_KB_SESSION="s1"
    cat > "${TEST_TMP_DIR}/.workflow/state.yaml" <<'EOF'
project_type: "software"
current_phase: "phase_1_planning"
current_checkpoint: "CP_1_001"
EOF
    printf 'line one\n' > "${TEST_TMP_DIR}/f"
    git config user.email "$PI"
    git add -A >/dev/null
    git commit -qm "fixture" >/dev/null
    KB="${TEST_TMP_DIR}/docs/kb"
    GKB="${UWS_GLOBAL_MEMORY_DIR}/kb"
}

teardown() {
    teardown_test_environment
}

field() { grep -E "^$2:" "$1" | head -1 | sed -e "s/^$2:[[:space:]]*//" -e 's/^"//' -e 's/"$//'; }
gid() { KB_OUT="$("$UWS" kb "$@" 2>/dev/null)"; }

init_global() {
    "$UWS" kb init --global >/dev/null
    git -C "$GKB" config user.email "$PI"
    git -C "$GKB" config user.name "PI"
    "$UWS" kb pi --set "$PI" --global >/dev/null
}

add_global_lesson() {  # add_global_lesson <claim>
    gid add --global --type lesson --claim "$1" --evidence reported \
        --source url:https://example.org/doc --quote "a verbatim line"
}

# Trusted items written straight to disk: <dir> <id> <claim> <evidence> <scope>
seed_item() {
    mkdir -p "$1/items" "$1/retired"
    cat > "$1/items/$2.md" <<EOF
---
id: $2
type: lesson
scope: $5
status: trusted
claim: "$3"
evidence: $4
source: ["url:https://example.org/$2"]
check: "true"
watch: []
watch_blob: []
author: human
reviewer: ${PI}
captured_by: cli
created: 2026-09-24
verified_at: 2026-09-24
status_since: 2026-09-24
review_by: 2027-09-24
supersedes: []
superseded_by:
contradicts: []
supports: []
tags: [test]
---
> a verbatim line
EOF
}

@test "global: every write is refused until init --global makes the KB its own git repository" {
    run "$UWS" kb add --global --type lesson --claim "Pin tool versions" --evidence reported \
        --source url:https://example.org --quote "pin"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not its own git repository"*"uws kb init --global"* ]]
    # a plain directory (for example a copied KB) is not enough
    mkdir -p "$GKB"
    run "$UWS" kb add --global --type lesson --claim "Pin tool versions" --evidence reported \
        --source url:https://example.org --quote "pin"
    [ "$status" -eq 2 ]
    run "$UWS" kb init --global
    [ "$status" -eq 0 ]
    [[ "$output" == *"as its own git repository"* ]]
    [ "$(cd "$(git -C "$GKB" rev-parse --show-toplevel)" && pwd -P)" = "$(cd "$GKB" && pwd -P)" ]
    grep -qx '.cache/' "$GKB/.gitignore"
    run "$UWS" kb init --global
    [[ "$output" == *"already initialised"* ]]
    gid add --global --type lesson --claim "Pin tool versions" --evidence reported \
        --source url:https://example.org --quote "pin"
    [[ "$KB_OUT" =~ ^K-20260924-[0-9a-f]{6}$ ]]
    [ "$(field "$GKB/items/${KB_OUT}.md" scope)" = "global" ]
    grep -q "	${KB_OUT}	-	candidate	add	" "$GKB/events.tsv"
    # nothing went to the project KB, and nothing was committed for the user
    [ ! -e "$KB" ]
    [ -z "$(git -C "$GKB" log --oneline 2>/dev/null)" ]
}

@test "global: claims naming a project or home path are refused; lint I8 reports a hand-edited one" {
    init_global
    run "$UWS" kb add --global --type fact --claim "The checker lives in scripts/kb.sh" --evidence reported \
        --source url:https://example.org --quote "q"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must not name a project or home path (scripts/kb.sh)"* ]]
    run "$UWS" kb add --global --type fact --claim "Notes are in /home/alice/notes.md" --evidence reported \
        --source url:https://example.org --quote "q"
    [ "$status" -eq 2 ]
    run "$UWS" kb add --global --type fact --claim "Keep a copy in ~/backup" --evidence reported \
        --source url:https://example.org --quote "q"
    [ "$status" -eq 2 ]
    run "$UWS" kb add --global --type fact --claim "It is in ${TEST_TMP_DIR}/f" --evidence reported \
        --source url:https://example.org --quote "q"
    [ "$status" -eq 2 ]
    # URLs and generic words with slashes are not project paths
    add_global_lesson "Read the manual at https://git-scm.com/docs/git-stash before and/or after a pop"
    [ -n "$KB_OUT" ]
    local f="$GKB/items/${KB_OUT}.md"
    sed -e 's|^claim: .*|claim: "See /home/alice/x"|' "$f" > "$f.new" && mv "$f.new" "$f"
    run "$UWS" kb lint --global
    [ "$status" -eq 1 ]
    [[ "$output" == *"I8 ${KB_OUT}: global claim names a project or home path (/home/alice/x)"* ]]
    # --escaped-from is project-only
    run "$UWS" kb add --global --type lesson --claim "Escaped" --evidence reported \
        --source url:https://example.org --quote "q" --escaped-from verification
    [ "$status" -eq 2 ]
}

@test "global: only the global KB's PI promotes, never from inside an agent; global:ID reaches it from a project" {
    "$UWS" kb init --global >/dev/null
    git -C "$GKB" config user.email "$PI"
    add_global_lesson "Retries need jitter"
    local id="$KB_OUT"
    # the project's PI is not the global KB's PI
    "$UWS" kb pi --set "$PI" >/dev/null
    run "$UWS" kb approve "global:${id}"
    [ "$status" -eq 6 ]
    [[ "$output" == *"no PI configured"* ]]
    run env CLAUDECODE=1 "$UWS" kb pi --set "$PI" --global
    [ "$status" -eq 6 ]
    "$UWS" kb pi --set "$PI" --global >/dev/null
    grep -q "pi: \"${PI}\"" "$GKB/config.yaml"
    run env CLAUDECODE=1 "$UWS" kb approve "global:${id}"
    [ "$status" -eq 6 ]
    [ "$(field "$GKB/items/${id}.md" status)" = "candidate" ]
    git -C "$GKB" config user.email "someone@else.example"
    run "$UWS" kb approve "global:${id}"
    [ "$status" -eq 6 ]
    git -C "$GKB" config user.email "$PI"
    run "$UWS" kb approve "global:${id}"
    [ "$status" -eq 0 ]
    [[ "$output" == "global:${id}: candidate -> trusted (approved by ${PI})" ]]
    [ "$(field "$GKB/items/${id}.md" reviewer)" = "$PI" ]
    # show finds a global item with or without the prefix
    run "$UWS" kb show "global:${id}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"id: ${id}"* ]]
    run "$UWS" kb show "$id"
    [ "$status" -eq 0 ]
    run "$UWS" kb lint --global
    [ "$status" -eq 0 ]
}

@test "search: project and global items are ranked together in one budget; global hits are marked" {
    init_global
    local i
    for i in $(seq 1 20); do
        seed_item "$KB" "K-20260924-$(printf '%06x' "$i")" "Project test note ${i} with enough words to make the line long enough to be cut" observed project
    done
    for i in 1 2 3; do
        seed_item "$GKB" "K-20260924-$(printf 'aa%04x' "$i")" "Global test lesson ${i} that applies to every project" verified global
    done
    run "$UWS" kb search test
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -le 5 ]
    [ "$(printf '%s\n' "$output" | LC_ALL=C wc -c | tr -d ' ')" -le 1000 ]
    local line
    while IFS= read -r line; do [ "$(printf '%s' "$line" | LC_ALL=C wc -c | tr -d ' ')" -le 200 ]; done <<< "$output"
    # verified global lessons outrank observed project notes, and are marked
    [[ "$(printf '%s\n' "$output" | head -1)" == "global:K-20260924-aa"*" [lesson|trusted|verified|2026-09-24] Global test lesson"* ]]
    [[ "$output" == *$'\n'"K-20260924-0000"* ]]
    run "$UWS" kb search --scope project test
    [[ "$output" != *"global:"* ]]
    run "$UWS" kb search --scope global test
    [ "$(printf '%s\n' "$output" | grep -c '^global:K-' || true)" -eq 3 ]
    [[ "$output" != *"Project test note"* ]]
    run "$UWS" kb search --scope everywhere test
    [ "$status" -eq 2 ]
    run "$UWS" kb learn --global
    [ "$status" -eq 2 ]
}

@test "global: retire, restore and prune use git mv in the global repository, never commit, and record no project outcomes" {
    init_global
    mkdir -p "$KB"   # the project records outcomes
    add_global_lesson "Timeouts need a budget"
    local id="$KB_OUT"
    git -C "$GKB" add -A && git -C "$GKB" commit -qm "kb" >/dev/null
    run "$UWS" kb retire "global:${id}" "replaced"
    [ "$status" -eq 0 ]
    [ -f "$GKB/retired/${id}.md" ]
    # staged as a rename (git mv), then edited (status and retired_reason)
    git -C "$GKB" status --porcelain | grep -Eq "^R. items/${id}\.md -> retired/${id}\.md$"
    [ "$(git -C "$GKB" log --oneline | wc -l | tr -d ' ')" -eq 1 ]
    run "$UWS" kb restore "global:${id}"
    [ "$status" -eq 0 ]
    [ -f "$GKB/items/${id}.md" ]
    [ ! -e "$KB/outcomes.tsv" ]
    export UWS_KB_NOW="2026-11-24"
    run "$UWS" kb prune --global --apply
    [ "$status" -eq 0 ]
    [ "$(field "$GKB/retired/${id}.md" retired_reason)" = "unpromoted" ]
    [ ! -e "$KB/outcomes.tsv" ]
    run "$UWS" kb stats --global
    [[ "$output" == "Global KB ${GKB}: 0 active"*"1 retired"* ]]
}

@test "uws kb --global works outside any UWS project; project verbs still need one" {
    local elsewhere="${TEST_TMP_DIR}-elsewhere"
    mkdir -p "$elsewhere"
    cd "$elsewhere"
    run "$UWS" kb init --global
    [ "$status" -eq 0 ]
    git -C "$GKB" config user.email "$PI"
    run "$UWS" kb add --global --type lesson --claim "Outside a project" --evidence reported \
        --source url:https://example.org --quote "q"
    [ "$status" -eq 0 ]
    run "$UWS" kb stats --global
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 active"* ]]
    run "$UWS" kb stats
    [ "$status" -eq 1 ]
    [[ "$output" == *"No UWS project found"* ]]
    cd "$TEST_TMP_DIR"
    rm -rf "$elsewhere"
}

@test "--scope global selects the global KB for add, search and show, as --global does" {
    init_global
    gid add --scope global --type lesson --claim "Scoped lesson about retry jitter" --evidence reported \
        --source url:https://example.org/doc --quote "a verbatim line"
    local id="$KB_OUT"
    [[ "$id" =~ ^K-20260924-[0-9a-f]{6}$ ]]
    [ -f "$GKB/items/${id}.md" ]
    [ "$(field "$GKB/items/${id}.md" scope)" = "global" ]
    [ ! -e "$KB/items/${id}.md" ]
    run "$UWS" kb show --scope global "$id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"id: ${id}"* ]]
    [[ "$output" == *"scope: global"* ]]
    run "$UWS" kb show --scope=global "$id"
    [ "$status" -eq 0 ]
    # candidates are searched with --status; the hit is marked global
    run "$UWS" kb search --scope global --status candidate jitter
    [ "$status" -eq 0 ]
    [[ "$output" == "global:${id} [lesson|candidate|reported|"* ]]
    run "$UWS" kb search --scope project --status candidate jitter
    [ "$status" -eq 1 ]
    # a project-only verb is refused with the global scope
    run "$UWS" kb proposals --scope global
    [ "$status" -eq 2 ]
}

@test "stats lists the global KB next to the project KB" {
    init_global
    add_global_lesson "Caches must be rebuildable"
    "$UWS" kb add --type fact --claim "f has one line" --evidence observed --source file:f:1 >/dev/null 2>&1
    run "$UWS" kb stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"KB docs/kb: 1 active"* ]]
    [[ "$output" == *"global KB ${GKB}: 0 trusted, 0 stale, 0 disputed, 1 candidate, 0 retired"* ]]
    run "$UWS" kb stats --short --global
    [[ "$output" == "Global KB: 0 trusted, 0 stale, 0 disputed, 1 to review."* ]]
}
