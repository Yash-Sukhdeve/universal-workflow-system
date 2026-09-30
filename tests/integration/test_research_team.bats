#!/usr/bin/env bats
# Research team, increment 1 (docs/design/research-team.md section 11).
# Acceptance tests AT1-AT10 against tests/fixtures/research/project, which passes every
# gate; each test breaks one thing and expects the named check to fail on it.
# AT11 (headless Claude, SubagentStop) and AT12 (PROMISE audit) run outside BATS.

load '../helpers/test_helper'
source "${PROJECT_ROOT}/scripts/lib/portable.sh"   # sed_inplace (BSD and GNU sed)

RFIX="${PROJECT_ROOT}/tests/fixtures/research"
CHECK="${PROJECT_ROOT}/scripts/research_check.py"
HOOK="${PROJECT_ROOT}/plugins/uws/hooks/research_subagent_stop.sh"

setup() {
    command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
    setup_test_environment
    P="${TEST_TMP_DIR}"
    cp -R "${RFIX}/project/." "$P/"
    cd "$P"
    git add -A research bib_sources paper artifacts >/dev/null
    git commit -q -m "fixture" >/dev/null
}

teardown() {
    teardown_test_environment
}

check() {
    python3 "$CHECK" --root "$P" "$@"
}

append_claim() {
    printf '%s\n' "$1" >> "$P/research/ledger/claims.jsonl"
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

# Stub curl for the fetcher: copies $FAKE_BODY to the -o file and prints the -w line.
fake_curl() {
    mkdir -p "$P/fakebin"
    cat > "$P/fakebin/curl" << 'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cp "$FAKE_BODY" "$out"
printf '%s' "$FAKE_STATUS"
EOF
    chmod +x "$P/fakebin/curl"
}

# ── The reference project passes ──────────────────────────────────────────────

@test "research fixture: every phase gate passes on the reference project" {
    local phase
    for phase in hypothesis literature_review experiment_design data_collection analysis peer_review publication; do
        run check gate "$phase"
        echo "$phase: $output"
        [ "$status" -eq 0 ]
    done
}

@test "research check: without research/ledger the checker exits 2 (fails closed)" {
    rm -rf "$P/research/ledger"
    run check gate analysis
    [ "$status" -eq 2 ]
    [[ "$output" == *"research/ledger/ not found"* ]]
}

@test "research check: --json output is machine-readable" {
    append_claim '{"id":"C-0009","rev":1,"supersedes":null,"text":"x","category":"reported_finding","status":"verified","author":"verifier","verified_by":"verifier","verified_at":"2026-09-26T00:00:00Z","verdict":"supports"}'
    run python3 "$CHECK" --root "$P" --json ledger
    [ "$status" -eq 1 ]
    echo "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert any(f["rule"]=="LEDGER-SELFVERIFY" for f in d["findings"])'
}

# ── AT1: separation of duties ─────────────────────────────────────────────────

@test "AT1: a claim verified by its own author fails the ledger check and names the C-ID" {
    append_claim '{"id":"C-0003","rev":2,"supersedes":"C-0003@1","text":"t","category":"reported_finding","strength":"none","sources":[{"citekey":"sandve2013","quote":"keep track of how it was produced","locator":"Rule 1"}],"author":"scout","status":"verified","verified_by":"scout","verified_at":"2026-09-26T00:00:00Z","verdict":"supports"}'
    run check ledger
    [ "$status" -eq 1 ]
    [[ "$output" == *"LEDGER-SELFVERIFY"* ]]
    [[ "$output" == *"C-0003"* ]]
    [[ "$output" == *"research/ledger/claims.jsonl:6 "* ]]
}

@test "ledger: category rules (hypothesis never verified, inference needs dependencies)" {
    append_claim '{"id":"C-0004","rev":1,"supersedes":null,"text":"h","category":"hypothesis","status":"verified","author":"lead","verified_by":"verifier","verified_at":"2026-09-26T00:00:00Z","verdict":"supports","mechanism":"m","distinguishing_prediction":"d","strongest_alternative":"a","undermining_observation":"u"}'
    append_claim '{"id":"C-0005","rev":1,"supersedes":null,"text":"i","category":"inference","strength":"causal","status":"unverified","author":"lead","depends_on":["C-0002"]}'
    run check ledger
    [ "$status" -eq 1 ]
    [[ "$output" == *"LEDGER-HYPOTHESIS C-0004"* ]]
    [[ "$output" == *"LEDGER-STRENGTH C-0005"* ]]
}

@test "ledger: a revision must name the revision it supersedes" {
    append_claim '{"id":"C-0003","rev":2,"text":"t","category":"open_question","status":"unverified","author":"lead"}'
    run check ledger
    [ "$status" -eq 1 ]
    [[ "$output" == *"LEDGER-REV"* ]]
}

@test "ledger: a line that is not JSON is reported with its line number" {
    printf '{not json\n' >> "$P/research/ledger/claims.jsonl"
    run check ledger
    [ "$status" -eq 1 ]
    [[ "$output" == *"claims.jsonl:6 LEDGER-PARSE"* ]]
}

# ── AT2: references.bib comes only from bib_sources ──────────────────────────

@test "AT2: a hand-edited references.bib entry fails the bib check" {
    sed_inplace 's/Ten Simple Rules/Eleven Simple Rules/' "$P/paper/references.bib"
    run check bib
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/references.bib:3 BIB-REFS entry sandve2013 is not byte-equal"* ]]
}

@test "AT2: an entry missing its .meta.json fails the bib check" {
    rm "$P/bib_sources/sandve2013.meta.json"
    run check bib
    [ "$status" -eq 1 ]
    [[ "$output" == *"BIB-META"* ]]
}

@test "bib: editing a fetched file is detected by its recorded hash" {
    sed_inplace 's/year={2013}/year={2014}/' "$P/bib_sources/sandve2013.bib"
    run check bib
    [ "$status" -eq 1 ]
    [[ "$output" == *"bib_sources/sandve2013.bib:1 BIB-HASH"* ]]
}

@test "bib: a \\cite with no bib_sources entry is reported at its line" {
    printf 'See \\cite{nobody2099}.\n' >> "$P/paper/main.tex"
    run check bib
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:23 BIB-MISSING"* ]]
}

@test "bib build: references.bib is rebuilt from bib_sources and then passes" {
    printf 'garbage\n' > "$P/paper/references.bib"
    run check bib
    [ "$status" -eq 1 ]
    run check bib-build --out paper/references.bib
    [ "$status" -eq 0 ]
    run check bib
    [ "$status" -eq 0 ]
}

# ── AT3: the fetcher never writes a file from an HTML page ───────────────────

@test "AT3: the DBLP bot-check page is refused and nothing is written" {
    fake_curl
    local before
    before="$(ls "$P/bib_sources")"
    FAKE_BODY="${RFIX}/responses/dblp_bot_check.html" FAKE_STATUS="200 text/html; charset=utf-8" \
        UWS_BIB_CURL="$P/fakebin/curl" UWS_RESEARCH_ROOT="$P" \
        run "${PROJECT_ROOT}/scripts/research_bib.sh" fetch dblp:journals/corr/abs-2309-11495
    [ "$status" -eq 1 ]
    [[ "$output" == *"refused"* ]]
    [ "$(ls "$P/bib_sources")" = "$before" ]
}

@test "AT3: an HTML body is refused even when the server labels it text/plain" {
    fake_curl
    local before
    before="$(ls "$P/bib_sources")"
    FAKE_BODY="${RFIX}/responses/dblp_bot_check.html" FAKE_STATUS="200 text/plain" \
        UWS_BIB_CURL="$P/fakebin/curl" UWS_RESEARCH_ROOT="$P" \
        run "${PROJECT_ROOT}/scripts/research_bib.sh" fetch dblp:journals/corr/abs-2309-11495
    [ "$status" -eq 1 ]
    [[ "$output" == *"HTML"* ]]
    [ "$(ls "$P/bib_sources")" = "$before" ]
}

@test "bib fetch: a real arXiv response is stored with provenance and passes the bib check" {
    fake_curl
    FAKE_BODY="${RFIX}/responses/arxiv_2309.11495.bib" FAKE_STATUS="200 text/plain; charset=utf-8" \
        UWS_BIB_CURL="$P/fakebin/curl" UWS_RESEARCH_ROOT="$P" \
        run "${PROJECT_ROOT}/scripts/research_bib.sh" fetch 2309.11495 --key dhuliawala2023
    [ "$status" -eq 0 ]
    [ -f "$P/bib_sources/dhuliawala2023.bib" ]
    grep -q '"source_url": "https://arxiv.org/bibtex/2309.11495"' "$P/bib_sources/dhuliawala2023.meta.json"
    grep -q $'^dhuliawala2023\tdhuliawala2023chainofverificationreduceshallucinationlarge$' "$P/bib_sources/KEYMAP.tsv"
    UWS_RESEARCH_ROOT="$P" run "${PROJECT_ROOT}/scripts/research_bib.sh" build --out paper/references.bib
    [ "$status" -eq 0 ]
    grep -q '@misc{dhuliawala2023,' "$P/paper/references.bib"
    run check bib
    [ "$status" -eq 0 ]
    # a second fetch of the same key is refused rather than silently replacing it
    FAKE_BODY="${RFIX}/responses/arxiv_2309.11495.bib" FAKE_STATUS="200 text/plain" \
        UWS_BIB_CURL="$P/fakebin/curl" UWS_RESEARCH_ROOT="$P" \
        run "${PROJECT_ROOT}/scripts/research_bib.sh" fetch 2309.11495 --key dhuliawala2023
    [ "$status" -eq 1 ]
}

@test "bib fetch: a PI-supplied file needs a PI decision ID" {
    UWS_RESEARCH_ROOT="$P" run "${PROJECT_ROOT}/scripts/research_bib.sh" fetch doi:10.1/x --from-file "${RFIX}/responses/arxiv_2309.11495.bib"
    [ "$status" -eq 1 ]
    [[ "$output" == *"--pi-decision"* ]]
    UWS_RESEARCH_ROOT="$P" run "${PROJECT_ROOT}/scripts/research_bib.sh" fetch doi:10.1/x --from-file "${RFIX}/responses/arxiv_2309.11495.bib" --pi-decision D-001 --key pisupplied
    [ "$status" -eq 0 ]
    grep -q '"pi_decision": "D-001"' "$P/bib_sources/pisupplied.meta.json"
}

@test "bib fetch: a network failure is an environment error (exit 2) and writes nothing" {
    mkdir -p "$P/fakebin"
    printf '#!/bin/bash\necho "Could not resolve host" >&2\nexit 6\n' > "$P/fakebin/curl"
    chmod +x "$P/fakebin/curl"
    local before
    before="$(ls "$P/bib_sources")"
    UWS_BIB_CURL="$P/fakebin/curl" UWS_RESEARCH_ROOT="$P" run "${PROJECT_ROOT}/scripts/research_bib.sh" fetch 2309.11495
    [ "$status" -eq 2 ]
    [ "$(ls "$P/bib_sources")" = "$before" ]
}

# ── AT4: quotes must be verbatim ──────────────────────────────────────────────

@test "AT4: a quote that is not in the cached text fails the quotes check" {
    append_claim '{"id":"C-0001","rev":3,"supersedes":"C-0001@2","text":"t","category":"reported_finding","strength":"none","sources":[{"citekey":"sandve2013","quote":"Every result must always be reproduced by an independent laboratory.","locator":"Rule 1"}],"author":"scout","status":"verified","verified_by":"verifier","verified_at":"2026-09-26T00:00:00Z","verdict":"supports"}'
    run check quotes
    [ "$status" -eq 1 ]
    [[ "$output" == *"claims.jsonl:6 QUOTE-MISMATCH C-0001 cites sandve2013"* ]]
}

@test "quotes: typographic quotes and whitespace do not cause false failures; a missing cache does" {
    append_claim '{"id":"C-0001","rev":3,"supersedes":"C-0001@2","text":"t","category":"reported_finding","strength":"none","sources":[{"citekey":"sandve2013","quote":"Whenever  a result may be of potential   interest, keep track","locator":"Rule 1"}],"author":"scout","status":"verified","verified_by":"verifier","verified_at":"2026-09-26T00:00:00Z","verdict":"supports"}'
    run check quotes
    [ "$status" -eq 0 ]
    rm "$P/research/sources/cache/sandve2013.txt"
    run check quotes
    [ "$status" -eq 1 ]
    [[ "$output" == *"QUOTE-NOCACHE"* ]]
    run check quotes --allow-missing-cache
    [ "$status" -eq 0 ]
}

# ── AT5: numbers come from traced macros ──────────────────────────────────────

@test "AT5: the macro with raw 0.9125 and floor:3 passes the numbers check" {
    run check numbers
    [ "$status" -eq 0 ]
}

@test "AT5: a hand-typed 0.913 in the abstract fails the numbers check" {
    sed_inplace 's/ROC-AUC of \\GbAucCv{}/ROC-AUC of 0.913/' "$P/paper/main.tex"
    grep -q 'ROC-AUC of 0.913' "$P/paper/main.tex"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:5 NUM-LITERAL hand-typed number 0.913"* ]]
}

@test "AT5: changing one byte of the output file gives a hash mismatch" {
    sed_inplace 's/0.9199/0.9198/' "$P/artifacts/model_results.json"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-HASH"* ]]
}

@test "numbers: a printed value that the rounding rule does not produce fails" {
    sed_inplace 's/\\newcommand{\\GbAucCv}{0.912}/\\newcommand{\\GbAucCv}{0.913}/' "$P/paper/generated/numbers.tex"
    python3 - "$P/research/ledger/numbers.jsonl" << 'EOF'
import json, sys
p = sys.argv[1]
row = json.loads(open(p).readline())
row.update({"rev": 2, "supersedes": "N-0001@1", "printed": "0.913"})
open(p, "a").write(json.dumps(row) + "\n")
EOF
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"NUM-ROUND"* ]]
    [[ "$output" == *"expected 0.912"* ]]
}

@test "numbers: a literal with a reason is allowed, one without a reason is not" {
    printf '\\section{Results}\nWe ran 2.5 hours. %% uws:literal wall-clock note, not a result\nAnd 3.25 more. %% uws:literal\n' >> "$P/paper/main.tex"
    run check numbers
    [ "$status" -eq 1 ]
    [[ "$output" == *"main.tex:25 NUM-LITERAL uws:literal needs a reason"* ]]
    [[ "$output" != *"main.tex:24 "* ]]
}

# ── AT6 / AT7 and the other slop rules ───────────────────────────────────────

@test "AT6: 'the first predictive models' with no C-ID fails slop rule S1" {
    printf '\nWe present the first predictive models for workflow recovery.\n' >> "$P/paper/main.tex"
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:24 S1"* ]]
    [[ "$output" == *"the first"* ]]
}

@test "S1: a novelty word is allowed as a candidate contribution" {
    printf '\nA candidate contribution is the first grouped-split audit.\n' >> "$P/paper/main.tex"
    run check slop
    [ "$status" -eq 0 ]
}

@test "AT7: a simulated number used without a disclosure word fails C3" {
    python3 - "$P/research/ledger/numbers.jsonl" << 'EOF'
import json, sys
p = sys.argv[1]
row = json.loads(open(p).readline())
row.update({"rev": 2, "supersedes": "N-0001@1", "data_origin": "simulated"})
open(p, "a").write(json.dumps(row) + "\n")
EOF
    printf '\nThe framework finishes in \\GbAucCv{} seconds.\n' >> "$P/paper/main.tex"
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"paper/main.tex:24 C3"* ]]
    [[ "$output" == *"simulated"* ]]
}

@test "C3: a number labelled measured whose script draws random values fails" {
    mkdir -p "$P/research/code"
    printf 'import random\n\ndef timing():\n    return random.uniform(1.0, 2.0)\n' > "$P/research/code/bench.py"
    python3 - "$P/research/ledger/numbers.jsonl" << 'EOF'
import json, sys
p = sys.argv[1]
row = json.loads(open(p).readline())
row.update({"rev": 2, "supersedes": "N-0001@1", "data_origin": "measured", "script": "research/code/bench.py"})
open(p, "a").write(json.dumps(row) + "\n")
EOF
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"C3 N-0001 is labelled measured, but research/code/bench.py:4 draws random.uniform()"* ]]
}

@test "slop: S2 vague attribution, S4 placeholder and S6 strength drift are blocked" {
    printf '\nStudies show that checkpoints help.\n\nTODO add the ablation.\n\nThis proves that checkpoints cause faster recovery. %% C-0002\n' >> "$P/paper/main.tex"
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"main.tex:24 S2"* ]]
    [[ "$output" == *"main.tex:26 S4"* ]]
    [[ "$output" == *"main.tex:28 S6"* ]]
}

@test "slop: C1 placeholders and C5 mtime-selected inputs in research code are blocked" {
    cat > "$P/research/code/train.py" << 'EOF'
import glob
import os


def pick():
    return max(glob.glob("data/*.csv"), key=os.path.getmtime)


def evaluate():
    raise NotImplementedError


def later():
    pass
EOF
    run check slop
    [ "$status" -eq 1 ]
    [[ "$output" == *"research/code/train.py:6 C5"* ]]
    [[ "$output" == *"research/code/train.py:10 C1"* ]]
    [[ "$output" == *"research/code/train.py:13 C1"* ]]
}

# ── AT9: ledgers are append-only ─────────────────────────────────────────────

@test "AT9: deleting a committed ledger line fails, before and after it is committed" {
    sed_inplace '/"id":"C-0003"/d' "$P/research/ledger/claims.jsonl"
    run check ledger
    [ "$status" -eq 1 ]
    [[ "$output" == *"LEDGER-APPEND C-0003@1 was removed or edited compared with HEAD"* ]]
    git -C "$P" commit -q -am "drop C-0003"
    run check ledger
    [ "$status" -eq 1 ]
    [[ "$output" == *"compared with HEAD~1"* ]]
}

@test "AT9: editing a committed ledger line in place fails" {
    sed_inplace 's/"author":"lead"/"author":"writer"/' "$P/research/ledger/claims.jsonl"
    run check ledger
    [ "$status" -eq 1 ]
    [[ "$output" == *"LEDGER-APPEND C-0003@1"* ]]
}

# ── AT8 / AT10: research.sh next runs the gate ───────────────────────────────

@test "research.sh next advances through passing gates" {
    research_state hypothesis
    run "${SCRIPTS_DIR}/research.sh" next
    [ "$status" -eq 0 ]
    [ "$(phase_now)" = "literature_review" ]
}

@test "AT8: next in analysis with a failing check is blocked; --force with a reason advances and is logged" {
    research_state analysis
    printf '\nWe present the first predictive models.\n' >> "$P/paper/main.tex"
    run "${SCRIPTS_DIR}/research.sh" next
    [ "$status" -eq 1 ]
    [[ "$output" == *"S1"* ]]
    [[ "$output" == *"Blocked"* ]]
    [ "$(phase_now)" = "analysis" ]

    run "${SCRIPTS_DIR}/research.sh" next --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"needs a reason"* ]]
    [ "$(phase_now)" = "analysis" ]

    run "${SCRIPTS_DIR}/research.sh" next --force "PI D-001: accept the wording for the internal draft"
    [ "$status" -eq 0 ]
    [ "$(phase_now)" = "peer_review" ]
    grep -q 'category: "research-gate-force"' "$P/.workflow/logs/decisions.log"
    grep -q 'summary: "Research evidence gate forced at analysis"' "$P/.workflow/logs/decisions.log"
    grep -q 'PI D-001: accept the wording' "$P/.workflow/logs/decisions.log"
}

@test "AT10: next --force at publication is refused" {
    research_state publication
    run "${SCRIPTS_DIR}/research.sh" next --force "ship it"
    [ "$status" -eq 1 ]
    [[ "$output" == *"never accepted at the publication gate"* ]]
    [ "$(phase_now)" = "publication" ]
    if [ -f "$P/.workflow/logs/decisions.log" ]; then
        run grep -q "research-gate-force" "$P/.workflow/logs/decisions.log"
        [ "$status" -ne 0 ]
    fi
}

@test "research.sh: the gate stays inactive without research/ledger" {
    research_state analysis
    rm -rf "$P/research"
    run "${SCRIPTS_DIR}/research.sh" next
    [ "$status" -eq 0 ]
    [ "$(phase_now)" = "peer_review" ]
}

@test "research.sh check <name> runs the checker; check <n> still ticks deliverables" {
    research_state analysis
    run "${SCRIPTS_DIR}/research.sh" check ledger
    [ "$status" -eq 0 ]
    [[ "$output" == *"ledger: PASS"* ]]
    run "${SCRIPTS_DIR}/research.sh" check 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"Marked [1]"* ]]
}

@test "uws research check gate goes through bin/uws" {
    research_state literature_review
    run "${PROJECT_ROOT}/bin/uws" research check gate literature_review
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate literature_review: PASS"* ]]
}

@test "research check init scaffolds a project without overwriting files" {
    rm -rf "$P/research" "$P/bib_sources"
    run check init
    [ "$status" -eq 0 ]
    [ -f "$P/research/ledger/claims.jsonl" ]
    [ -f "$P/research/QUESTION.md" ]
    grep -q '^research/sources/cache/$' "$P/.gitignore"
    printf 'mine\n' > "$P/research/QUESTION.md"
    run check init
    [ "$(cat "$P/research/QUESTION.md")" = "mine" ]
    run check gate hypothesis
    [ "$status" -eq 1 ]
    [[ "$output" == *"GATE-QUESTION"* ]]
}

@test "gate peer_review: an open blocking red-team finding blocks" {
    printf '| F-003 | blocking | open | split leaks | train.py:157 | GroupKFold |\n' >> "$P/research/reviews/REV-001.md"
    run check gate peer_review
    [ "$status" -eq 1 ]
    [[ "$output" == *"research/reviews/REV-001.md:7 GATE-REVIEW F-003"* ]]
}

@test "gate publication: needs the PI approval line" {
    sed_inplace '/PUBLICATION-APPROVAL/d' "$P/research/pi/decisions.md"
    run check gate publication
    [ "$status" -eq 1 ]
    [[ "$output" == *"GATE-PI"* ]]
}

# ── SubagentStop hook (L2) ────────────────────────────────────────────────────

hook_input() {
    python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SubagentStop","agent_type":sys.argv[1],"agent_id":"a1","stop_hook_active":False,"last_assistant_message":sys.argv[2]}))' "$1" "$2"
}

@test "hook: a research agent that verified its own claim is sent back (exit 2)" {
    append_claim '{"id":"C-0003","rev":2,"supersedes":"C-0003@1","text":"t","category":"open_question","status":"verified","author":"scout","verified_by":"scout","verified_at":"2026-09-26T00:00:00Z","verdict":"supports"}'
    run bash -c "$(declare -f hook_input); hook_input uws:uws-rt-scout 'Done. Open questions for the orchestrator: None' | CLAUDE_PROJECT_DIR='$P' CLAUDE_PLUGIN_ROOT='${PROJECT_ROOT}/plugins/uws' '$HOOK'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"C-0003 is marked verified by its own author"* ]]
}

@test "hook: after 2 retries the agent may stop and a blocker is recorded" {
    append_claim '{"id":"C-0003","rev":2,"supersedes":"C-0003@1","text":"t","category":"open_question","status":"verified","author":"scout","verified_by":"scout","verified_at":"2026-09-26T00:00:00Z","verdict":"supports"}'
    local i
    for i in 1 2; do
        run bash -c "$(declare -f hook_input); hook_input uws-rt-scout 'Open questions for the orchestrator: None' | CLAUDE_PROJECT_DIR='$P' CLAUDE_PLUGIN_ROOT='${PROJECT_ROOT}/plugins/uws' '$HOOK'"
        [ "$status" -eq 2 ]
    done
    run bash -c "$(declare -f hook_input); hook_input uws-rt-scout 'Open questions for the orchestrator: None' | CLAUDE_PROJECT_DIR='$P' CLAUDE_PLUGIN_ROOT='${PROJECT_ROOT}/plugins/uws' '$HOOK'"
    [ "$status" -eq 0 ]
    echo "$output" | python3 -c 'import json,sys; assert "systemMessage" in json.loads(sys.stdin.read())'
    grep -q 'category: "research-exit-check"' "$P/.workflow/logs/decisions.log"
    grep -q 'type: "blocker"' "$P/.workflow/logs/decisions.log"
}

@test "hook: a missing 'Open questions' section is sent back; a clean stop passes" {
    run bash -c "$(declare -f hook_input); hook_input uws-rt-verifier 'All verified.' | CLAUDE_PROJECT_DIR='$P' CLAUDE_PLUGIN_ROOT='${PROJECT_ROOT}/plugins/uws' '$HOOK'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Open questions for the orchestrator"* ]]
    run bash -c "$(declare -f hook_input); hook_input uws-rt-verifier 'Report. Open questions for the orchestrator: None' | CLAUDE_PROJECT_DIR='$P' CLAUDE_PLUGIN_ROOT='${PROJECT_ROOT}/plugins/uws' '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "hook: other agents and projects without research/ledger are ignored" {
    append_claim '{"id":"C-0003","rev":2,"supersedes":"C-0003@1","text":"t","category":"open_question","status":"verified","author":"scout","verified_by":"scout","verified_at":"2026-09-26T00:00:00Z","verdict":"supports"}'
    run bash -c "$(declare -f hook_input); hook_input Explore 'done' | CLAUDE_PROJECT_DIR='$P' CLAUDE_PLUGIN_ROOT='${PROJECT_ROOT}/plugins/uws' '$HOOK'"
    [ "$status" -eq 0 ]
    rm -rf "$P/research"
    run bash -c "$(declare -f hook_input); hook_input uws-rt-scout 'done' | CLAUDE_PROJECT_DIR='$P' CLAUDE_PLUGIN_ROOT='${PROJECT_ROOT}/plugins/uws' '$HOOK'"
    [ "$status" -eq 0 ]
}

@test "hook: hooks.json routes SubagentStop for plain and plugin-scoped research agents only" {
    local matcher
    matcher="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["SubagentStop"][0]["matcher"])' "${PROJECT_ROOT}/plugins/uws/hooks/hooks.json")"
    [[ "uws-rt-verifier" =~ $matcher ]]
    [[ "uws:uws-rt-scout" =~ $matcher ]]
    run bash -c "[[ 'uws-researcher' =~ $matcher ]]"
    [ "$status" -ne 0 ]
    run bash -c "[[ 'Explore' =~ $matcher ]]"
    [ "$status" -ne 0 ]
}

# ── orchestrate.sh --methodology / --agent ───────────────────────────────────

@test "orchestrate: --methodology research dispatches research work when sdlc is also active" {
    research_state literature_review
    printf 'sdlc_phase: "design"\n' >> "$P/.workflow/state.yaml"
    run "${SCRIPTS_DIR}/orchestrate.sh" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"sdlc"* ]]
    run "${SCRIPTS_DIR}/orchestrate.sh" status --methodology research
    [ "$status" -eq 0 ]
    [[ "$output" == *"literature_review"* ]]
    [[ "$output" == *"rt-scout"* ]]
}

@test "orchestrate: --agent rt-verifier writes a research contract brief" {
    research_state literature_review
    run "${SCRIPTS_DIR}/orchestrate.sh" dispatch --methodology research --agent rt-verifier "Verify C-0001"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DISPATCH: agent=rt-verifier subagent=.claude/agents/uws-rt-verifier.md phase=research:literature_review"* ]]
    grep -q "research/ledger/claims.jsonl" "$P/workspace/rt-verifier/TASK.md"
    grep -q "uws research check gate literature_review" "$P/workspace/rt-verifier/TASK.md"
    run grep -q "REQ-ID" "$P/workspace/rt-verifier/TASK.md"
    [ "$status" -ne 0 ]
}

@test "orchestrate: unknown agent or methodology is refused" {
    research_state literature_review
    run "${SCRIPTS_DIR}/orchestrate.sh" dispatch --agent nobody "x"
    [ "$status" -eq 1 ]
    run "${SCRIPTS_DIR}/orchestrate.sh" status --methodology waterfall
    [ "$status" -eq 1 ]
    run "${SCRIPTS_DIR}/orchestrate.sh" status --methodology sdlc
    [ "$status" -eq 1 ]
    [[ "$output" == *"no active sdlc phase"* ]]
}

# ── What ships ────────────────────────────────────────────────────────────────

@test "ships: research agents, the lead skill and the research-check command are in the plugin" {
    local role
    for role in rt-scout rt-verifier rt-redteam; do
        [ -f "${PROJECT_ROOT}/plugins/uws/agents/uws-${role}.md" ]
        grep -q "Governing persona (docs/personas/apocalypt.md, verbatim)" "${PROJECT_ROOT}/plugins/uws/agents/uws-${role}.md"
        grep -q "Open questions for the orchestrator" "${PROJECT_ROOT}/plugins/uws/agents/uws-${role}.md"
    done
    [ -f "${PROJECT_ROOT}/plugins/uws/skills/uws-research-lead/SKILL.md" ]
    grep -q '^name: uws-research-lead$' "${PROJECT_ROOT}/plugins/uws/skills/uws-research-lead/SKILL.md"
    grep -q 'CLAUDE_PLUGIN_ROOT}/bin/uws research check' "${PROJECT_ROOT}/plugins/uws/commands/research-check.md"
}
