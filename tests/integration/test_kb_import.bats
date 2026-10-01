#!/usr/bin/env bats
# Knowledge base increment 2: imports (docs/design/knowledge-base.md sections 7 and 18).
# `uws kb import vector|automemory` reads a vector-memory database or Claude Code
# auto-memory files and writes candidates only; the sources are never written, and
# the PI triages every imported item. The databases are synthetic fixtures built by
# tests/fixtures/kb/make_vector_db.py with the real server's schema; no test reads a
# real memory store.

load '../helpers/test_helper'

UWS="${PROJECT_ROOT}/bin/uws"
PI="pi@lab.example"
MAKE_DB="${PROJECT_ROOT}/tests/fixtures/kb/make_vector_db.py"

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
    # Sources live outside the project, read-only
    SRC="${TEST_TMP_DIR}-src"
    mkdir -p "$SRC"
    python3 "$MAKE_DB" local "${SRC}/local.db"
    python3 "$MAKE_DB" global "${SRC}/global.db"
    chmod 444 "${SRC}/local.db" "${SRC}/global.db"
    chmod 555 "$SRC"
}

teardown() {
    chmod -R u+w "${TEST_TMP_DIR}-src" 2>/dev/null || true
    rm -rf "${TEST_TMP_DIR}-src"
    teardown_test_environment
}

field() { grep -E "^$2:" "$1" | head -1 | sed -e "s/^$2:[[:space:]]*//" -e 's/^"//' -e 's/"$//'; }
item_count() { local n=0 f; for f in "$1"/items/*.md; do [[ -f "$f" ]] && n=$((n + 1)); done; echo "$n"; }
item_with() { grep -l -F -- "$2" "$1"/items/*.md | head -1; }        # item_with <kb> <text>
id_of() { basename "$1" .md; }
src_state() { (cd "$SRC" && ls -la && cat local.db global.db | git hash-object --stdin); }

init_global() {
    "$UWS" kb init --global >/dev/null
    git -C "$GKB" config user.email "$PI"
    git -C "$GKB" config user.name "PI"
    "$UWS" kb pi --set "$PI" --global >/dev/null
}

@test "import vector: rows become inferred candidates with import sources; the database is only read" {
    local before
    before="$(src_state)"
    run "$UWS" kb import vector --db "${SRC}/local.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"added 5 candidate(s) (1 flagged suspected-fixture), 1 duplicate(s) collapsed (R7), 0 already retired, 1 skipped."* ]]
    [[ "$output" == *"uws kb review --imported"* ]]
    [ "$(src_state)" = "$before" ]
    [ "$(item_count "$KB")" -eq 5 ]
    local f
    for f in "$KB"/items/*.md; do
        [ "$(field "$f" status)" = "candidate" ]
        [ "$(field "$f" evidence)" = "inferred" ]
        [ "$(field "$f" captured_by)" = "import" ]
        [ "$(field "$f" scope)" = "project" ]
        grep -Eq '^source: \["import:vector-local#[0-9]+"' "$f"
        grep -q '^> ' "$f"
    done
    # the prefix is not part of the claim; the category picks the type
    f="$(item_with "$KB" 'grep -c with')"
    [ "$(field "$f" type)" = "lesson" ]
    [[ "$(field "$f" claim)" == "BUG: grep -c with"* ]]
    grep -q '^tags: \[import, vector-local, phase-2, implementation, tooling, bug\]$' "$f"
    [ "$(grep -c '	candidate	import:import:vector-local#' "$KB/events.tsv")" -eq 5 ]
    run "$UWS" kb lint
    [ "$status" -eq 0 ]
}

@test "import vector: duplicate rows collapse by R7 into one item; a rerun changes nothing" {
    "$UWS" kb import vector --db "${SRC}/local.db" >/dev/null
    local f listing events
    f="$(item_with "$KB" 'keeps one Markdown file per item')"
    grep -q '^source: \["import:vector-local#1", "import:vector-local#4"\]$' "$f"
    listing="$(ls "$KB/items")"
    events="$(cat "$KB/events.tsv")"
    run "$UWS" kb import vector --db "${SRC}/local.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"added 0 candidate(s)"* ]]
    [[ "$output" == *"import:vector-local#4: same claim as $(id_of "$f") (R7); not imported"* ]]
    [ "$(ls "$KB/items")" = "$listing" ]
    [ "$(cat "$KB/events.tsv")" = "$events" ]
}

@test "import vector: a row naming nothing in the project is flagged for the PI and never retired automatically" {
    "$UWS" kb import vector --db "${SRC}/local.db" >/dev/null
    local fx real
    fx="$(item_with "$KB" 'batch_size')"
    grep -q '^flags: \[suspected-fixture\]$' "$fx"
    [[ "$(field "$fx" flag_detail)" == "names things absent from this project: deploy/Dockerfile, docker/compose.gpu.yml, configs/train_resnet.yaml, batch_size" ]]
    # a row that names a file the project has is not flagged
    real="$(item_with "$KB" 'scripts/kb.sh')"
    run grep -q '^flags:' "$real"
    [ "$status" -eq 1 ]
    run "$UWS" kb review --imported
    [ "$status" -eq 0 ]
    [[ "$output" == *"$(id_of "$fx") [candidate|inferred|check:none|recommended:none|flags:suspected-fixture]"* ]]
    [[ "$output" == *"from import:vector-local#5; names things absent from this project"* ]]
    [[ "$output" == *"refute:"*"uws kb dispute <ID> --by <new ID>"* ]]
    # R5 would retire a 30-day-old candidate; imports wait for the PI (decision D6)
    export UWS_KB_NOW="2026-12-24"
    run "$UWS" kb prune --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"5 imported candidate(s) wait for the PI's triage"* ]]
    [ -f "$fx" ]
    [ "$(item_count "$KB")" -eq 5 ]
}

@test "import vector: a row that looks like a secret is skipped; long rows are cut to 240 bytes" {
    run "$UWS" kb import vector --db "${SRC}/local.db"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip import:vector-local#6: text looks like a secret (aws-key)"* ]]
    run grep -rl 'AKIA' "$KB"
    [ "$status" -eq 1 ]
    local long claim
    long="$(item_with "$KB" 'A long lesson about checkpoints')"
    claim="$(field "$long" claim)"
    [ "$(printf '%s' "$claim" | LC_ALL=C wc -c | tr -d ' ')" -le 240 ]
    [[ "$claim" == *"checkpoints." ]]
    # the full text stays in the body
    [ "$(grep -o 'A long lesson about checkpoints' "$long" | wc -l | tr -d ' ')" -ge 13 ]
}

@test "import vector --dry-run writes nothing, not even the KB directory" {
    run "$UWS" kb import vector --db "${SRC}/local.db" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would add K-20260924-"*"[fact|flag:suspected-fixture] from import:vector-local#5"* ]]
    [[ "$output" == *"would be collapsed into it"* ]]
    [[ "$output" == *"would add 5 candidate(s)"* ]]
    [ ! -e "$KB" ]
    [ -z "$(git status --porcelain)" ]
}

@test "import vector: bad input is refused with exit 2" {
    run "$UWS" kb import vector --db "${SRC}/missing.db"
    [ "$status" -eq 2 ]
    python3 -c 'import sqlite3, sys; c = sqlite3.connect(sys.argv[1]); c.execute("create table t (x)"); c.commit()' "${TEST_TMP_DIR}/other.db"
    run "$UWS" kb import vector --db "${TEST_TMP_DIR}/other.db"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not a vector-memory database"* ]]
    run "$UWS" kb import vectors --db "${SRC}/local.db"
    [ "$status" -eq 2 ]
    run "$UWS" kb import vector
    [ "$status" -eq 2 ]
    run "$UWS" kb import automemory --dir "$SRC" --global
    [ "$status" -eq 2 ]
    [ ! -e "$KB/items" ]
}

@test "import vector --scope global: needs the global KB repository; home paths are skipped" {
    run "$UWS" kb import vector --db "${SRC}/global.db" --scope global
    [ "$status" -eq 2 ]
    [[ "$output" == *"not its own git repository"* ]]
    init_global
    run "$UWS" kb import vector --db "${SRC}/global.db" --scope global
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip import:vector-global#4: names a project or home path (/home/someone/project/notes.md)"* ]]
    [[ "$output" == *"suspected-fixture rule not applied: a global import has no project to compare with"* ]]
    [ "$(item_count "$GKB")" -eq 3 ]
    local f
    f="$(item_with "$GKB" 'git stash pop')"
    [ "$(field "$f" scope)" = "global" ]
    grep -q '^source: \["import:vector-global#1"\]$' "$f"
    [ ! -e "$KB" ]
    run "$UWS" kb lint --global
    [ "$status" -eq 0 ]
}

@test "triage: approve refuses an import; refute (dispute, then approve the counter-evidence), correct and drop" {
    init_global
    "$UWS" kb import vector --db "${SRC}/global.db" --scope global >/dev/null
    local stash memdb bash_row c n
    stash="$(id_of "$(item_with "$GKB" 'git stash pop')")"
    memdb="$(id_of "$(item_with "$GKB" 'memories.db')")"
    bash_row="$(id_of "$(item_with "$GKB" 'macOS ships bash 3.2')")"
    run "$UWS" kb approve "global:${stash}"
    [ "$status" -eq 2 ]
    [[ "$output" == *"rests on an import (import:vector-global#1)"*"--supersedes global:${stash}"* ]]
    # refute: counter-evidence with a verbatim quote from the git manual
    c="$("$UWS" kb add --global --type fact --claim "A git stash pop that hits conflicts keeps the stash entry" \
        --evidence reported --source url:https://git-scm.com/docs/git-stash \
        --quote "Applying the state can fail with conflicts; in this case, it is not removed from the stash list" \
        --contradicts "$stash" 2>/dev/null)"
    run env CLAUDECODE=1 "$UWS" kb dispute "global:${stash}" --by "$c" "the git manual says the opposite"
    [ "$status" -eq 0 ]
    [ "$(field "${GKB}/items/${stash}.md" status)" = "disputed" ]
    run "$UWS" kb search --scope global --status disputed stash
    [[ "$output" == "global:${stash} [lesson|disputed|inferred|"*"{contradicts ${c}}" ]]
    run "$UWS" kb approve "global:${c}"
    [ "$status" -eq 0 ]
    [ "$(field "${GKB}/retired/${stash}.md" retired_reason)" = "disproven-by:${c}" ]
    [ "$(field "${GKB}/items/${c}.md" status)" = "trusted" ]
    # correct: restate with the right file name and a resolvable source
    n="$("$UWS" kb add --global --type fact --claim "The vector-memory server stores memories in vector_memory.db" \
        --evidence reported --source url:https://github.com/cornebidouil/vector-memory-mcp \
        --quote 'DB_NAME = "vector_memory.db"' --supersedes "$memdb" 2>/dev/null)"
    [ "$(field "${GKB}/retired/${memdb}.md" retired_reason)" = "superseded-by:${n}" ]
    # drop
    run "$UWS" kb reject "global:${bash_row}" "a lint enforces it already"
    [ "$status" -eq 0 ]
    [ "$(field "${GKB}/retired/${bash_row}.md" retired_reason)" = "rejected:a lint enforces it already" ]
    run "$UWS" kb review --imported --global
    [[ "$output" == *"No imported items wait for triage."* ]]
    # a re-import does not bring triaged rows back
    run "$UWS" kb import vector --db "${SRC}/global.db" --scope global
    [ "$status" -eq 0 ]
    [[ "$output" == *"added 0 candidate(s)"*"3 already retired"* ]]
    [[ "$output" == *"already retired as global:${stash} (disproven-by:${c})"* ]]
    run "$UWS" kb lint --global
    [ "$status" -eq 0 ]
    # nothing was committed for the PI
    [ -z "$(git -C "$GKB" log --oneline 2>/dev/null)" ]
}

@test "dispute: needs non-inferred counter-evidence; a trusted item is disputed only by a trusted one" {
    "$UWS" kb pi --set "$PI" >/dev/null
    local a b q
    a="$("$UWS" kb add --type fact --claim "The build uses make" --evidence observed --source file:f:1 2>/dev/null)"
    "$UWS" kb approve "$a" >/dev/null
    b="$("$UWS" kb add --type fact --claim "The build uses a shell script only" --evidence observed --source file:f:1 --no-conflict 2>/dev/null)"
    run "$UWS" kb dispute "$a" --by "$b"
    [ "$status" -eq 2 ]
    [[ "$output" == *"only a trusted item disputes it"* ]]
    [ "$(field "${KB}/items/${a}.md" status)" = "trusted" ]
    q="$("$UWS" kb add --type fact --claim "Reasoned from the build item" --evidence inferred --source "item:${b}" 2>/dev/null)"
    run "$UWS" kb dispute "$b" --by "$q"
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be verified, observed or reported"* ]]
    run "$UWS" kb dispute "$b" --by "$b"
    [ "$status" -eq 2 ]
    run "$UWS" kb dispute "$b"
    [ "$status" -eq 2 ]
    run "$UWS" kb dispute "$b" --by "$a"
    [ "$status" -eq 0 ]
    [ "$(field "${KB}/items/${b}.md" status)" = "disputed" ]
    grep -q "^contradicts: \[${b}\]$" "${KB}/items/${a}.md"
    grep -q "	${b}	candidate	disputed	disputed-by:${a}	" "${KB}/events.tsv"
}

@test "import automemory: project facts become candidates; preferences, feedback and MEMORY.md are not imported or edited" {
    local mem="${TEST_TMP_DIR}-src/automem"
    chmod 755 "$SRC"
    mkdir -p "$mem"
    printf -- '- [x](x.md) index line\n' > "$mem/MEMORY.md"
    cat > "$mem/deploy-notes.md" <<'EOF'
---
name: deploy-notes
description: "The release job runs scripts/kb.sh lint before tagging"
metadata:
  node_type: memory
  type: project
---
Body of the project memory.
EOF
    cat > "$mem/dashboards.md" <<'EOF'
---
name: dashboards
description: The latency dashboard lives in grafana_board_eu under ops/grafana/latency.json
type: reference
---
Reference body.
EOF
    cat > "$mem/prefers-short.md" <<'EOF'
---
name: prefers-short
description: The user prefers short answers
type: user
---
EOF
    cat > "$mem/no-emoji.md" <<'EOF'
---
name: no-emoji
description: Do not use emoji
metadata:
  type: feedback
---
EOF
    printf 'no front matter\n' > "$mem/loose.md"
    chmod 444 "$mem"/*.md
    chmod 555 "$mem" "$SRC"
    local before
    before="$(cd "$mem" && ls -la && cat ./*.md | git hash-object --stdin)"
    run "$UWS" kb import automemory --dir "$mem"
    [ "$status" -eq 0 ]
    [ "$(cd "$mem" && ls -la && cat ./*.md | git hash-object --stdin)" = "$before" ]
    [[ "$output" == *"skip automemory#MEMORY.md: the auto-memory index: not read (--include-index imports its entries; UWS never edits it)"* ]]
    [[ "$output" == *"skip automemory#prefers-short.md: a user memory (preference or correction): it stays in auto-memory"* ]]
    [[ "$output" == *"skip automemory#no-emoji.md: a feedback memory"* ]]
    [[ "$output" == *"skip automemory#loose.md: no front matter"* ]]
    [[ "$output" == *"added 2 candidate(s) (1 flagged suspected-fixture)"* ]]
    local p r
    p="$(item_with "$KB" 'release job runs')"
    [ "$(field "$p" claim)" = "The release job runs scripts/kb.sh lint before tagging" ]
    grep -q '^source: \["import:automemory#deploy-notes.md"\]$' "$p"
    [ "$(field "$p" captured_by)" = "import" ]
    grep -q '^> Body of the project memory.$' "$p"
    run grep -q '^flags:' "$p"
    [ "$status" -eq 1 ]
    r="$(item_with "$KB" 'latency dashboard')"
    grep -q '^flags: \[suspected-fixture\]$' "$r"
    chmod 755 "$mem"
}

@test "import automemory --include-index: MEMORY.md entries become candidates; the file is only read" {
    local mem="${TEST_TMP_DIR}-src/automem"
    chmod 755 "$SRC"
    mkdir -p "$mem"
    # Line numbers matter: each entry's source is import:automemory#MEMORY.md:L<first line>
    cat > "$mem/MEMORY.md" <<'EOF'
# Project Memory

> **RELEASE PROCESS (2026-09-01):** The release job runs `scripts/kb.sh lint`
> before tagging, and a failed lint blocks the tag.

## Tooling
- [deploy notes](deploy-notes.md) — the release checklist
- ok
- The release job runs scripts/kb.sh lint before tagging
- Training reads configs/train_resnet.yaml and sets batch_size from it
  - the GPU nodes need the cuda_visible_devices list
- The CI token = Zq7xYp3Lm9Rt2Wv8Ab

## Commands
Check the KB before a release:
```
./scripts/kb.sh lint

# exit 1 lists the violations
```
EOF
    cat > "$mem/deploy-notes.md" <<'EOF'
---
name: deploy-notes
description: "The release job runs scripts/kb.sh lint before tagging"
type: project
---
Body of the project memory.
EOF
    chmod 444 "$mem"/*.md
    chmod 555 "$mem" "$SRC"
    local before
    before="$(cd "$mem" && ls -la && cat ./*.md | git hash-object --stdin)"
    # a dry run lists the entries and writes nothing
    run "$UWS" kb import automemory --dir "$mem" --include-index --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"would add K-20260924-"*"[fact] from import:automemory#MEMORY.md:L3: RELEASE PROCESS (2026-09-01): The release job runs"* ]]
    [ ! -e "$KB" ]
    run "$UWS" kb import automemory --dir "$mem" --include-index
    [ "$status" -eq 0 ]
    [ "$(cd "$mem" && ls -la && cat ./*.md | git hash-object --stdin)" = "$before" ]
    [[ "$output" == *"skip automemory#MEMORY.md:L7: an index line pointing to the topic file deploy-notes.md"* ]]
    [[ "$output" == *"skip automemory#MEMORY.md:L8: too short to be a fact"* ]]
    [[ "$output" == *"skip import:automemory#MEMORY.md:L12: text looks like a secret (assignment)"* ]]
    [[ "$output" == *"import:automemory#deploy-notes.md: same claim as "*" (R7); collapsed into it (source added)"* ]]
    [[ "$output" == *"Summary: 6 record(s); added 4 candidate(s) (1 flagged suspected-fixture), 1 duplicate(s) collapsed (R7), 0 already retired, 3 skipped."* ]]
    run grep -rl 'Zq7xYp3Lm9Rt2Wv8Ab' "$KB"
    [ "$status" -eq 1 ]
    local q d fx cmd
    # a quoted, bold, two-line entry is one claim; the section names a tag
    q="$(item_with "$KB" 'RELEASE PROCESS')"
    [ "$(field "$q" claim)" = 'RELEASE PROCESS (2026-09-01): The release job runs `scripts/kb.sh lint` before tagging, and a failed lint blocks the tag.' ]
    grep -q '^source: \["import:automemory#MEMORY.md:L3"\]$' "$q"
    grep -q '^tags: \[import, automemory, index, project-memory\]$' "$q"
    [ "$(field "$q" captured_by)" = "import" ]
    [ "$(field "$q" evidence)" = "inferred" ]
    grep -q '(file=MEMORY.md; line=3; section=Project Memory); the source was only read.' "$q"
    grep -q '^> > \*\*RELEASE PROCESS (2026-09-01):\*\* The release job runs `scripts/kb.sh lint`$' "$q"
    # the index entry and the topic file say the same thing: one item, both sources
    d="$(item_with "$KB" 'claim: "The release job runs scripts/kb.sh lint before tagging"')"
    grep -q '^source: \["import:automemory#MEMORY.md:L9", "import:automemory#deploy-notes.md"\]$' "$d"
    # a nested item joins its parent; names absent from the project raise the flag
    fx="$(item_with "$KB" 'train_resnet')"
    [ "$(field "$fx" claim)" = "Training reads configs/train_resnet.yaml and sets batch_size from it; the GPU nodes need the cuda_visible_devices list" ]
    grep -q '^flags: \[suspected-fixture\]$' "$fx"
    # a fenced block stays inside its entry
    cmd="$(item_with "$KB" 'Check the KB before a release')"
    [ "$(field "$cmd" claim)" = "Check the KB before a release: ./scripts/kb.sh lint # exit 1 lists the violations" ]
    grep -q '^tags: \[import, automemory, index, commands\]$' "$cmd"
    # imports are leads: the PI restates them before anything is trusted
    "$UWS" kb pi --set "$PI" >/dev/null
    run "$UWS" kb approve "$(id_of "$q")"
    [ "$status" -eq 2 ]
    [[ "$output" == *"rests on an import (import:automemory#MEMORY.md:L3)"* ]]
    run "$UWS" kb lint
    [ "$status" -eq 0 ]
    # a rerun changes nothing
    local listing events
    listing="$(ls "$KB/items")"; events="$(cat "$KB/events.tsv")"
    run "$UWS" kb import automemory --dir "$mem" --include-index
    [ "$status" -eq 0 ]
    [[ "$output" == *"added 0 candidate(s)"* ]]
    [ "$(ls "$KB/items")" = "$listing" ]
    [ "$(cat "$KB/events.tsv")" = "$events" ]
    # the flag belongs to the auto-memory import only
    run "$UWS" kb import vector --db "${SRC}/local.db" --include-index
    [ "$status" -eq 2 ]
    [[ "$output" == *"--include-index is for 'import automemory'"* ]]
    chmod 755 "$mem"
}

@test "import: the reader and fixture builder use the Python standard library only" {
    # parse only (py_compile would write __pycache__ into the checkout)
    run python3 -c 'import ast, sys; [ast.parse(open(p).read(), p) for p in sys.argv[1:]]' \
        "${PROJECT_ROOT}/scripts/kb_import.py" "$MAKE_DB"
    [ "$status" -eq 0 ]
    run grep -nE '^\s*(import|from)\s+(yaml|numpy|pandas|requests|sqlite_vec)\b' \
        "${PROJECT_ROOT}/scripts/kb_import.py" "$MAKE_DB"
    [ "$status" -eq 1 ]
}
