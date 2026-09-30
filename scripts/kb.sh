#!/bin/bash
#
# uws kb - project knowledge base (design: docs/design/knowledge-base.md)
#
# Usage: kb.sh <verb> [args]      (normally run as `uws kb <verb>`)
#
#   add --type T --claim "..." [--evidence E] [--source S]... [--check CMD]
#       [--watch PATH]... [--author A] [--tags a,b] [--supersedes ID]...
#       [--contradicts ID]... [--no-conflict] [--falsifier TEXT]
#       [--body TEXT] [--quote TEXT] [--escaped-from PHASE]
#                              create a candidate; prints its ID on stdout
#                              (--escaped-from, lessons only: a bug found after
#                              PHASE's gate passed; recorded as an `escape` outcome)
#   search <words> [--type T] [--status S] [--include-stale] [--all] [--limit N]
#   links [--type contradicts|supersedes|supports] <ID | words>
#   show <ID>                  print one item
#   verify [<ID> | --changed | --all]
#                              run checks / compare watched files (never promotes)
#   recommend <ID> [reason]    record a recommendation for promotion (anyone)
#   review                     list items waiting for the PI
#   approve <ID> [--as EMAIL]  promote to trusted (PI only, not from an agent)
#   reject <ID> "<why>"        retire a candidate as rejected (PI only)
#   pi [--set EMAIL]           show or set the PI identity (kb.pi in config.yaml)
#   prune [--apply]            apply removal rules R1 R2 R3 R5 (dry run by default)
#   retire <ID> "<reason>"     retire by hand (git mv to retired/)
#   restore <ID>               bring a retired item back as a candidate
#   lint                       check invariants I1-I4, I6, I7
#   stats [--short]            counts; rebuilds .cache/stats
#   learn [--dry-run]          meta-learning: compute metrics from outcomes.tsv and
#                              write proposal candidates (never applies a change)
#   proposals                  list proposals waiting for the PI and those being tracked
#
# Exit codes: 0 ok; 1 not found / no match / lint violation; 2 invalid or
# unprovenanced; 3 duplicate; 4 undeclared conflict; 5 a check failed;
# 6 refused (only the PI may promote).
#
# Environment: UWS_KB_DIR (default docs/kb), UWS_KB_PI, UWS_KB_NOW (fake
# clock, YYYY-MM-DD), UWS_KB_SEARCH_LIMIT (5), UWS_KB_ITEM_BYTES (200),
# UWS_KB_BRIEF_BYTES (1000), UWS_KB_CHECK_TIMEOUT (10 s),
# UWS_KB_VERIFY_BUDGET (60 s), UWS_KB_CANDIDATE_TTL_DAYS (30),
# UWS_KB_STALE_GRACE_DAYS (30), UWS_KB_DISPUTE_DAYS (14),
# UWS_KB_REVIEW_DAYS_<TYPE> (fact 180, lesson/anti-pattern 365, question 30,
# hypothesis 90, proposal 30; decision never expires).
# Meta-learning (design 6.3; each metric needs n >= UWS_KB_LEARN_MIN_N):
# UWS_KB_LEARN_MIN_N (5), UWS_KB_LEARN_WINDOW (10 samples per metric, and the
# events tracked after an approval), UWS_KB_LEARN_ESCAPE_RATE (0.20),
# UWS_KB_LEARN_CR_REJECT_RATE (0.40), UWS_KB_LEARN_DISPROVEN_RATE (0.25),
# UWS_KB_LEARN_REPEAT_FAILS (3), UWS_KB_OUTCOME_FIELD_BYTES (500).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/kb_utils.sh
source "${SCRIPT_DIR}/lib/kb_utils.sh"

ROOT="$(kb_project_root)"
KB="$(kb_dir "$ROOT")"
TODAY="$(kb_today)"
TAB="$(printf '\t')"

UWS_KB_CHECK_TIMEOUT="${UWS_KB_CHECK_TIMEOUT:-10}"
UWS_KB_VERIFY_BUDGET="${UWS_KB_VERIFY_BUDGET:-60}"
UWS_KB_CANDIDATE_TTL_DAYS="${UWS_KB_CANDIDATE_TTL_DAYS:-30}"
UWS_KB_STALE_GRACE_DAYS="${UWS_KB_STALE_GRACE_DAYS:-30}"
UWS_KB_DISPUTE_DAYS="${UWS_KB_DISPUTE_DAYS:-14}"
UWS_KB_LEARN_MIN_N="${UWS_KB_LEARN_MIN_N:-5}"
UWS_KB_LEARN_WINDOW="${UWS_KB_LEARN_WINDOW:-10}"
UWS_KB_LEARN_ESCAPE_RATE="${UWS_KB_LEARN_ESCAPE_RATE:-0.20}"
UWS_KB_LEARN_CR_REJECT_RATE="${UWS_KB_LEARN_CR_REJECT_RATE:-0.40}"
UWS_KB_LEARN_DISPROVEN_RATE="${UWS_KB_LEARN_DISPROVEN_RATE:-0.25}"
UWS_KB_LEARN_REPEAT_FAILS="${UWS_KB_LEARN_REPEAT_FAILS:-3}"
# UWS installation (scripts/..): where proposal targets such as scripts/sdlc.sh
# or docs/personas/ live when they are not part of the project itself
UWS_HOME="$(cd "${SCRIPT_DIR}/.." && pwd)"

TYPES="fact decision lesson anti-pattern question hypothesis proposal"
EVIDENCES="verified observed reported inferred"
SDLC_PHASE_NAMES="requirements design implementation verification deployment maintenance"
RESEARCH_PHASE_NAMES="hypothesis literature_review experiment_design data_collection analysis peer_review publication"

die() {
    local code="$1"; shift
    echo "uws kb: $*" >&2
    exit "$code"
}
warn() { echo "uws kb: $*" >&2; }

usage() {
    awk 'NR >= 3 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

word_in() {  # word_in <word> <space-separated list>
    case " $2 " in *" $1 "*) return 0 ;; esac
    return 1
}

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Review window in days for a type ("" = never expires)
review_days() {
    local t="$1" var
    var="UWS_KB_REVIEW_DAYS_$(printf '%s' "$t" | tr 'a-z-' 'A-Z_')"
    if [[ -n "${!var:-}" ]]; then printf '%s\n' "${!var}"; return 0; fi
    case "$t" in
        fact) echo 180 ;;
        lesson|anti-pattern) echo 365 ;;
        question|proposal) echo 30 ;;
        hypothesis) echo 90 ;;
        decision) echo "" ;;
        *) echo 180 ;;
    esac
}

review_by_for() {  # review_by_for <type> <from-date>
    local n
    n="$(review_days "$1")"
    if [[ -z "$n" ]]; then echo "never"; else kb_date_add "$2" "$n"; fi
}

ensure_kb() {
    mkdir -p "${KB}/items" "${KB}/retired"
    # .cache/ is local (search/usage caches); events.tsv merges as a union
    [[ -f "${KB}/.gitignore" ]] || printf '.cache/\n' > "${KB}/.gitignore"
    [[ -f "${KB}/.gitattributes" ]] || printf 'events.tsv merge=union\noutcomes.tsv merge=union\n' > "${KB}/.gitattributes"
    [[ -f "${KB}/events.tsv" ]] || : > "${KB}/events.tsv"
}

in_git() { git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; }

head_sha() { git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true; }

# Blob hash of a project-relative path ("missing" when absent)
blob_of() {
    local p="$1"
    if [[ -f "${ROOT}/${p}" ]]; then
        git hash-object "${ROOT}/${p}" 2>/dev/null || echo "unhashable"
    else
        echo "missing"
    fi
}

# Move a file, through git when it is tracked (keeps `git log --follow`)
move_file() {
    local from="$1" to="$2"
    if in_git && git -C "$ROOT" ls-files --error-unmatch "$from" >/dev/null 2>&1; then
        git -C "$ROOT" mv "$from" "$to"
    else
        mv "$from" "$to"
    fi
}

rebuild_stats_cache() {
    local t s x c r
    read -r t s x c r <<EOF
$(kb_counts "$KB")
EOF
    mkdir -p "${KB}/.cache"
    printf 'trusted=%s\nstale=%s\ndisputed=%s\ncandidate=%s\nretired=%s\n' \
        "$t" "$s" "$x" "$c" "$r" > "${KB}/.cache/stats"
}

require_item() {  # require_item <id> -> path (exit 1 when not found)
    local p
    p="$(kb_item_path "$KB" "$1" || true)"
    [[ -n "$p" ]] || die 1 "no such item: $1"
    printf '%s\n' "$p"
}

set_status() {  # set_status <file> <new-status> <reason>
    local f="$1" to="$2" reason="$3" id from
    id="$(kb_fm_get "$f" id)"
    from="$(kb_fm_get "$f" status)"
    kb_fm_set "$f" status "$to"
    kb_fm_set "$f" status_since "$TODAY"
    kb_event "$KB" "$id" "$from" "$to" "$reason" "$(kb_actor "$ROOT")"
}

# Reason code of a retirement for outcomes.tsv, and the item it points to:
# prints "<code><TAB><related item or ->".
retire_code() {
    local r="$1"
    case "$r" in
        superseded-by:*) printf 'superseded-by\t%s\n' "${r#superseded-by:}" ;;
        disproven-by:*)  printf 'disproven-by\t%s\n' "${r#disproven-by:}" ;;
        disproven|expired|unpromoted) printf '%s\t-\n' "$r" ;;
        rejected|rejected:*) printf 'rejected\t-\n' ;;
        graduated:*)     printf 'graduated\t-\n' ;;
        *)               printf 'manual\t-\n' ;;
    esac
}

# Retire an active item: move to retired/, set status and reason, log, and
# record a kb_retire outcome (reason code, evidence, captured_by, prior status).
retire_item() {  # retire_item <id> <reason>
    local id="$1" reason="$2" src dst ev cb au ty from code rel
    src="${KB}/items/${id}.md"
    [[ -f "$src" ]] || die 1 "not an active item: $id"
    dst="${KB}/retired/${id}.md"
    [[ -e "$dst" ]] && die 2 "retired/${id}.md already exists"
    ev="$(kb_fm_get "$src" evidence)"; cb="$(kb_fm_get "$src" captured_by)"
    au="$(kb_fm_get "$src" author)"; ty="$(kb_fm_get "$src" type)"; from="$(kb_fm_get "$src" status)"
    move_file "$src" "$dst"
    kb_fm_set "$dst" retired_at "$TODAY"
    kb_fm_set "$dst" retired_reason "$(kb_quote "$(kb_oneline "$reason")")"
    set_status "$dst" retired "$reason"
    IFS="$TAB" read -r code rel <<EOF
$(retire_code "$reason")
EOF
    cb="$(printf '%s' "${cb:--}" | tr -s '[:space:]' '_')"
    kb_outcome kb_retire - "${au:--}" - "$id" \
        "${code} evidence=${ev:--} captured_by=${cb} from=${from:--} type=${ty:--}" "${rel:--}"
}

# ── Source resolution (R8) ──────────────────────────────────────────────────

# resolve_source <source> -> prints the normalised source; returns
# non-zero with a one-line reason on stderr when it cannot be resolved.
# file: sources get "@<HEAD>" appended when the repository has a commit.
resolve_source() {
    local s="$1" rest path line commit out
    case "$s" in
        file:*)
            rest="${s#file:}"
            commit=""
            if [[ "$rest" == *@* ]]; then commit="${rest##*@}"; rest="${rest%@*}"; fi
            line=""
            if [[ "$rest" =~ :[0-9]+(-[0-9]+)?$ ]]; then line="${rest##*:}"; path="${rest%:*}"; else path="$rest"; fi
            [[ -n "$path" ]] || { echo "empty path in source '$s'" >&2; return 1; }
            case "$path" in /*|../*|*/../*) echo "source path must be inside the project: '$path'" >&2; return 1 ;; esac
            if [[ -n "$commit" ]]; then
                git -C "$ROOT" cat-file -e "${commit}:${path}" 2>/dev/null \
                    || { echo "source does not resolve: ${path} at ${commit}" >&2; return 1; }
            else
                [[ -f "${ROOT}/${path}" ]] || { echo "source file does not exist: ${path}" >&2; return 1; }
                if [[ -n "$line" ]]; then
                    local nlines first="${line%%-*}"
                    nlines="$(wc -l < "${ROOT}/${path}" | tr -d ' ')"
                    (( first >= 1 && first <= nlines + 1 )) \
                        || { echo "line ${first} is past the end of ${path} (${nlines} lines)" >&2; return 1; }
                fi
                commit="$(head_sha)"
                [[ -n "$commit" ]] || warn "no commit yet: source ${path} is not pinned to a commit"
            fi
            out="file:${path}"
            [[ -n "$line" ]] && out+=":${line}"
            [[ -n "$commit" ]] && out+="@${commit}"
            printf '%s\n' "$out"
            ;;
        commit:*)
            commit="${s#commit:}"
            git -C "$ROOT" cat-file -e "${commit}^{commit}" 2>/dev/null \
                || { echo "commit does not exist: ${commit}" >&2; return 1; }
            printf '%s\n' "$s"
            ;;
        url:http://*|url:https://*)
            printf '%s\n' "$s"
            ;;
        url:*)
            echo "url source must be http(s): '$s'" >&2; return 1
            ;;
        cmd:*#*)
            rest="${s#cmd:}"
            local outfile="${rest##*#}"
            [[ -n "${rest%#*}" ]] || { echo "empty command in source '$s'" >&2; return 1; }
            outfile="${outfile%@*}"
            [[ -f "${ROOT}/${outfile}" ]] || { echo "cmd output file does not exist: ${outfile}" >&2; return 1; }
            printf '%s\n' "$s"
            ;;
        cmd:*)
            echo "cmd source needs '#<output-file>': '$s'" >&2; return 1
            ;;
        item:*)
            kb_item_path "$KB" "${s#item:}" >/dev/null 2>&1 \
                || { echo "source item does not exist: ${s#item:}" >&2; return 1; }
            printf '%s\n' "$s"
            ;;
        *)
            echo "unknown source kind '$s' (use file: commit: url: cmd: item:)" >&2; return 1
            ;;
    esac
}

# Secret scan: refuse text that looks like a credential (design risk 5).
secret_scan() {
    local text="$1" re name
    for re in \
        'aws-key:(AKIA|ASIA)[0-9A-Z]{16}' \
        'private-key:-----BEGIN [A-Z ]*PRIVATE KEY' \
        'github-token:(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}' \
        'github-token:github_pat_[A-Za-z0-9_]{20,}' \
        'slack-token:xox[abprs]-[A-Za-z0-9-]{10,}' \
        'api-key:sk-[A-Za-z0-9_-]{20,}' \
        'google-key:AIza[0-9A-Za-z_-]{35}' \
        'assignment:([Pp]assword|[Pp]asswd|[Ss]ecret|[Aa][Pp][Ii][_-]?[Kk]ey|[Tt]oken)[\"'"'"']?[[:space:]]*[:=][[:space:]]*[\"'"'"']?[A-Za-z0-9/+_.=-]{12,}'; do
        name="${re%%:*}"
        if printf '%s' "$text" | grep -Eq -- "${re#*:}"; then
            printf '%s\n' "$name"
            return 0
        fi
    done
    return 1
}

# Refuse obviously destructive checks; review of the diff is the real control.
check_denied() {
    printf '%s' "$1" | grep -Eq '(^|[;&|[:space:]])(rm|sudo|mkfs|shutdown|reboot)([[:space:]]|$)|git[[:space:]]+push|(curl|wget)[^|]*\||dd[[:space:]]+if=|>[[:space:]]*/dev/(sd|disk|nvme)'
}

# Run a check with a time limit. Portable: GNU `timeout` is not in macOS base.
# Prints pass | fail | timeout.
run_check() {
    local cmd="$1" limit="${2:-$UWS_KB_CHECK_TIMEOUT}" pid ticks=0 rc=0
    # Item files can be edited by hand, so re-screen the check before running it
    if check_denied "$cmd"; then
        warn "refusing to run a destructive-looking check: ${cmd}"
        echo fail
        return 0
    fi
    ( cd "$ROOT" && exec bash -c "$cmd" ) </dev/null >/dev/null 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if (( ticks >= limit * 10 )); then
            pkill -TERM -P "$pid" 2>/dev/null || true
            kill -TERM "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            echo timeout
            return 0
        fi
        sleep 0.1
        ticks=$((ticks + 1))
    done
    wait "$pid" 2>/dev/null || rc=$?
    if (( rc == 0 )); then echo pass; else echo fail; fi
}

# Watch paths whose blob changed since recording (or whose file is missing)
changed_watches() {  # changed_watches <file>
    local f="$1" w b i=0
    local -a paths=() blobs=()
    while IFS= read -r w; do [[ -n "$w" ]] && paths+=("$w"); done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" watch)")
EOF
    while IFS= read -r b; do [[ -n "$b" ]] && blobs+=("$b"); done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" watch_blob)")
EOF
    for w in ${paths[@]+"${paths[@]}"}; do
        b="${blobs[$i]:-}"
        [[ "$(blob_of "$w")" == "$b" ]] || printf '%s\n' "$w"
        i=$((i + 1))
    done
    # file: sources whose path is gone at HEAD's working tree
    while IFS= read -r w; do
        case "$w" in
            file:*)
                w="${w#file:}"; w="${w%@*}"
                [[ "$w" =~ :[0-9]+(-[0-9]+)?$ ]] && w="${w%:*}"
                [[ -f "${ROOT}/${w}" ]] || printf 'source-missing:%s\n' "$w"
                ;;
        esac
    done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" source)")
EOF
}

refresh_watch_blobs() {  # refresh_watch_blobs <file>
    local f="$1" w
    local -a blobs=()
    while IFS= read -r w; do
        [[ -n "$w" ]] && blobs+=("$(blob_of "$w")")
    done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" watch)")
EOF
    kb_fm_set "$f" watch_blob "$(kb_list_format ${blobs[@]+"${blobs[@]}"})"
}

# ── Listing / search ────────────────────────────────────────────────────────

# Formats matching items as "score<TAB>id<TAB>line". Environment in:
# KBQ (query words), KBSTAT (|status|... filter), KBTYPE, KBONLY (|id|... or
# empty), KBLINK (link type that must be present, or empty), KBTODAY.
# shellcheck disable=SC2016
KB_AWK_SEARCH='
function powi(b, n,    r) {   # b^n for integer n >= 0 (no exp/log: some awks lack math)
    if (n < 0) return 1
    r = 1
    while (n > 0) { if (n % 2 == 1) r *= b; b *= b; n = int(n / 2) }
    return r
}
function trunc(s, n,    c) {
    if (length(s) <= n) return s
    s = substr(s, 1, n - 3)
    while (length(s) > 0) { c = substr(s, length(s), 1); if (c < "\200") break; s = substr(s, 1, length(s) - 1) }
    return s "..."
}
BEGIN {
    nq = split(tolower(ENVIRON["KBQ"]), raw, /[^a-z0-9_.-]+/); q = 0
    for (i = 1; i <= nq; i++) if (length(raw[i]) >= 2 && !(raw[i] in seen)) { seen[raw[i]] = 1; Q[++q] = raw[i] }
    today = kb_days(ENVIRON["KBTODAY"]); cap = ENVIRON["KBITEM"] + 0
    trust["verified"] = 1.0; trust["reported"] = 0.75; trust["observed"] = 0.6; trust["inferred"] = 0.3
}
function kb_emit(    id, st, ty, ev, claim, hay, m, i, rel, d, rec, score, src, n, a, when, links, lk, ln, prefix, room, cs) {
    if ("_invalid" in F) return
    id = kb_unq(F["id"]); st = kb_unq(F["status"]); ty = kb_unq(F["type"]); ev = kb_unq(F["evidence"])
    if (index(ENVIRON["KBSTAT"], "|" st "|") == 0) return
    if (ENVIRON["KBTYPE"] != "" && ty != ENVIRON["KBTYPE"]) return
    if (ENVIRON["KBONLY"] != "" && index(ENVIRON["KBONLY"], "|" id "|") == 0) return
    links = ""
    if (ENVIRON["KBLINK"] != "") {
        ln = kb_list(F[ENVIRON["KBLINK"]], lk)
        if (ln == 0) return
    }
    claim = kb_unq(F["claim"])
    rel = 1
    if (q > 0) {
        hay = tolower(claim " " F["tags"] " " BODY " " id); m = 0
        for (i = 1; i <= q; i++) if (index(hay, Q[i]) > 0) m++
        if (m == 0) return
        rel = m / q
    }
    when = kb_unq(F["verified_at"]); if (when == "") when = kb_unq(F["created"])
    d = kb_days(when); rec = (d < 0 || today < 0) ? 0 : powi(0.995, today - d)
    if (rec > 1) rec = 1
    score = rel + (ev in trust ? trust[ev] : 0) + rec
    n = kb_list(F["source"], a); src = (n > 0 ? a[1] : "no source")
    ln = kb_list(F["contradicts"], lk)
    for (i = 1; i <= ln; i++) links = links (i > 1 ? "," : "") lk[i]
    cs = kb_unq(F["check_status"])
    prefix = id " [" ty "|" st "|" (ev == "" ? "-" : ev) (cs == "pass" && st != "trusted" ? "|check-passed" : "") "|" when "] "
    src = " (" trunc(src, 60) ")" (links != "" ? " {contradicts " links "}" : "")
    room = cap - length(prefix) - length(src)
    if (room < 20) { src = ""; room = cap - length(prefix) }
    printf "%09d\t%s\t%s%s%s\n", int(score * 1000000), id, prefix, trunc(claim, room), src
}
'

# search_lines <status-filter> <type> <only-ids> <link> <query...>: ranked
# lines, unbudgeted, best first.
search_lines() {
    local stat="$1" type="$2" only="$3" link="$4"; shift 4
    local -a files=()
    local f
    for f in "${KB}"/items/*.md; do [[ -f "$f" ]] && files+=("$f"); done
    if [[ "$stat" == *"|retired|"* ]]; then
        for f in "${KB}"/retired/*.md; do [[ -f "$f" ]] && files+=("$f"); done
    fi
    [[ ${#files[@]} -gt 0 ]] || return 0
    KBQ="$*" KBSTAT="$stat" KBTYPE="$type" KBONLY="$only" KBLINK="$link" KBTODAY="$TODAY" \
        KBITEM="$UWS_KB_ITEM_BYTES" LC_ALL=C \
        awk "${KB_AWK_DATE}${KB_AWK_VALUES}${KB_AWK_SEARCH}${KB_AWK_ITEMS}" "${files[@]}" \
        | LC_ALL=C sort -t "$TAB" -k1,1r -k2,2 | cut -f3-
}

# Apply the output budget: <= limit lines, each <= UWS_KB_ITEM_BYTES bytes,
# total (with newlines) <= UWS_KB_BRIEF_BYTES bytes.
budget() {
    local limit="$1" line n=0 used=0 len LC_ALL=C
    while IFS= read -r line; do
        (( n < limit )) || break
        line="${line:0:$UWS_KB_ITEM_BYTES}"
        len=$(( ${#line} + 1 ))
        (( used + len <= UWS_KB_BRIEF_BYTES )) || break
        printf '%s\n' "$line"
        used=$((used + len)); n=$((n + 1))
    done
}

status_filter_for() {  # status_filter_for <status|""> <include-stale> <all>
    if [[ -n "$1" ]]; then printf '|%s|' "$1"; return 0; fi
    if [[ "$3" == "true" ]]; then printf '|candidate|trusted|stale|disputed|'; return 0; fi
    if [[ "$2" == "true" ]]; then printf '|trusted|stale|'; return 0; fi
    printf '|trusted|'
}

cmd_search() {
    local type="" status="" stale=false all=false limit="$UWS_KB_SEARCH_LIMIT"
    local -a words=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) type="${2:-}"; shift 2 ;;
            --status) status="${2:-}"; shift 2 ;;
            --include-stale) stale=true; shift ;;
            --all) all=true; shift ;;
            --limit) limit="${2:-}"; shift 2 ;;
            -*) die 2 "search: unknown option $1" ;;
            *) words+=("$1"); shift ;;
        esac
    done
    [[ ${#words[@]} -gt 0 ]] || die 2 "search: give one or more words"
    is_uint "$limit" || die 2 "search: --limit must be a number"
    (( limit > UWS_KB_SEARCH_LIMIT )) && limit="$UWS_KB_SEARCH_LIMIT"
    [[ -z "$type" ]] || word_in "$type" "$TYPES" || die 2 "search: unknown type '$type'"
    [[ -z "$status" ]] || word_in "$status" "candidate trusted stale disputed retired" \
        || die 2 "search: unknown status '$status'"
    local out
    out="$(search_lines "$(status_filter_for "$status" "$stale" "$all")" "$type" "" "" "${words[@]}" | budget "$limit")"
    [[ -n "$out" ]] || exit 1
    printf '%s\n' "$out"
}

cmd_links() {
    local type="contradicts"
    local -a words=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type) type="${2:-}"; shift 2 ;;
            -*) die 2 "links: unknown option $1" ;;
            *) words+=("$1"); shift ;;
        esac
    done
    word_in "$type" "contradicts supersedes supports" || die 2 "links: --type must be contradicts, supersedes or supports"
    [[ ${#words[@]} -gt 0 ]] || die 2 "links: give an item ID or search words"
    local statuses="|candidate|trusted|stale|disputed|retired|" out="" f l only="|"
    if [[ ${#words[@]} -eq 1 && "${words[0]}" =~ ^K-[0-9]{8}-[0-9a-f]+$ ]]; then
        f="$(require_item "${words[0]}")"
        # Items linked from this one, plus items that link to it
        while IFS= read -r l; do [[ -n "$l" ]] && only+="${l}|"; done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" "$type")"; [[ "$type" == "supersedes" ]] && kb_fm_get "$f" superseded_by)
EOF
        local g
        for g in "${KB}"/items/*.md "${KB}"/retired/*.md; do
            [[ -f "$g" ]] || continue
            if kb_list_parse "$(kb_fm_raw "$g" "$type")" | grep -qx -- "${words[0]}"; then
                only+="$(kb_fm_get "$g" id)|"
            fi
        done
        [[ "$only" != "|" ]] || exit 1
        out="$(search_lines "$statuses" "" "$only" "" | budget "$UWS_KB_SEARCH_LIMIT")"
    else
        local link="$type"
        out="$(search_lines "$statuses" "" "" "$link" "${words[@]}" | budget "$UWS_KB_SEARCH_LIMIT")"
    fi
    [[ -n "$out" ]] || exit 1
    printf '%s\n' "$out"
}

cmd_show() {
    [[ $# -eq 1 ]] || die 2 "show: give one item ID"
    cat "$(require_item "$1")"
}

# ── add ─────────────────────────────────────────────────────────────────────

# Significant terms of a claim (for the conflict heuristic)
terms_of() {
    printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -cs 'a-z0-9_' '\n' \
        | awk 'length($0) >= 4 && !/^(that|this|with|from|have|when|then|than|into|only|does|will|must|should|each|they|them|their|there|which|while|where|what|also|been|were|more|less|over|under|about|after|before)$/' \
        | LC_ALL=C sort -u
}

# Trusted items that may conflict with a new claim: same watched path, or
# half or more of the significant terms shared (Jaccard >= 0.5).
conflicts_for() {  # conflicts_for <claim> <watch paths (newline-separated)>
    local claim="$1" watches="$2" f id new old inter union w
    new="$(terms_of "$claim")"
    for f in "${KB}"/items/*.md; do
        [[ -f "$f" ]] || continue
        [[ "$(kb_fm_get "$f" status)" == "trusted" ]] || continue
        id="$(kb_fm_get "$f" id)"
        if [[ -n "$watches" ]]; then
            while IFS= read -r w; do
                [[ -n "$w" ]] || continue
                if printf '%s\n' "$watches" | grep -qxF -- "$w"; then
                    printf '%s\n' "$id"; continue 2
                fi
            done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" watch)")
EOF
        fi
        [[ -n "$new" ]] || continue
        old="$(terms_of "$(kb_fm_get "$f" claim)")"
        [[ -n "$old" ]] || continue
        inter="$(printf '%s\n%s\n' "$new" "$old" | LC_ALL=C sort | uniq -d | grep -c . || true)"
        union="$(printf '%s\n%s\n' "$new" "$old" | LC_ALL=C sort -u | grep -c . || true)"
        if (( union > 0 && inter * 2 >= union )); then printf '%s\n' "$id"; fi
    done
}

# Normalise a phase name for --escaped-from to "<methodology>:<phase>".
# Accepts "sdlc:verification" or a bare phase name (the SDLC and research
# phase names do not overlap). Prints nothing when the name is unknown.
normalize_phase() {
    local p="$1" m=""
    case "$p" in
        sdlc:*|research:*) m="${p%%:*}"; p="${p#*:}" ;;
    esac
    if word_in "$p" "$SDLC_PHASE_NAMES" && [[ -z "$m" || "$m" == "sdlc" ]]; then
        printf 'sdlc:%s\n' "$p"
    elif word_in "$p" "$RESEARCH_PHASE_NAMES" && [[ -z "$m" || "$m" == "research" ]]; then
        printf 'research:%s\n' "$p"
    fi
}

cmd_add() {
    local type="" claim="" evidence="" check="" author="" tags_raw="" falsifier="" body="" quote=""
    local scope="project" no_conflict=false escaped_from=""
    local -a sources=() watches=() supersedes=() contradicts=()
    while [[ $# -gt 0 ]]; do
        [[ "$1" == --* && "$1" != "--no-conflict" && $# -lt 2 ]] && die 2 "add: $1 needs a value"
        case "$1" in
            --type) type="$2"; shift 2 ;;
            --claim) claim="$2"; shift 2 ;;
            --evidence) evidence="$2"; shift 2 ;;
            --source) sources+=("$2"); shift 2 ;;
            --check) check="$2"; shift 2 ;;
            --watch) watches+=("$2"); shift 2 ;;
            --author) author="$2"; shift 2 ;;
            --tags) tags_raw="$2"; shift 2 ;;
            --supersedes) supersedes+=("$2"); shift 2 ;;
            --contradicts) contradicts+=("$2"); shift 2 ;;
            --no-conflict) no_conflict=true; shift ;;
            --falsifier) falsifier="$2"; shift 2 ;;
            --body) body="$2"; shift 2 ;;
            --quote) quote="$2"; shift 2 ;;
            --scope) scope="$2"; shift 2 ;;
            --escaped-from) escaped_from="$2"; shift 2 ;;
            --reviewer) die 2 "add: --reviewer is not accepted; the reviewer is recorded by 'approve' (PI only)" ;;
            *) die 2 "add: unknown argument '$1'" ;;
        esac
    done

    # ── Field validation (exit 2) ──
    [[ "$scope" == "project" ]] || die 2 "add: only --scope project exists in this version (global KB is increment 2)"
    [[ -n "$type" ]] || die 2 "add: --type is required ($TYPES)"
    word_in "$type" "$TYPES" || die 2 "add: unknown type '$type' ($TYPES)"
    [[ -n "$claim" ]] || die 2 "add: --claim is required"
    case "$claim" in *$'\n'*|*$'\r'*|*"$TAB"*) die 2 "add: claim must be one line (put detail in --body)" ;; esac
    local cb
    cb="$(kb_bytes "$claim")"
    (( cb <= UWS_KB_CLAIM_BYTES )) || die 2 "add: claim is ${cb} bytes; the cap is ${UWS_KB_CLAIM_BYTES} (put detail in --body)"
    if [[ "$type" != "question" ]]; then
        [[ -n "$evidence" ]] || die 2 "add: --evidence is required ($EVIDENCES)"
        [[ ${#sources[@]} -gt 0 ]] || die 2 "add: at least one --source is required (R8: no unprovenanced items)"
    fi
    [[ -z "$evidence" ]] || word_in "$evidence" "$EVIDENCES" || die 2 "add: unknown evidence '$evidence' ($EVIDENCES)"
    if [[ "$evidence" == "verified" ]]; then
        [[ -n "$check" ]] || die 2 "add: --evidence verified needs --check <command>"
    fi
    [[ "$type" != "hypothesis" || -n "$falsifier" ]] || die 2 "add: a hypothesis needs --falsifier (the observation that would refute it)"
    if [[ -n "$escaped_from" ]]; then
        [[ "$type" == "lesson" ]] || die 2 "add: --escaped-from is for --type lesson (a bug found after that phase's gate passed)"
        local ef
        ef="$(normalize_phase "$escaped_from")"
        [[ -n "$ef" ]] || die 2 "add: --escaped-from: unknown phase '${escaped_from}' (e.g. verification, sdlc:verification, research:analysis)"
        escaped_from="$ef"
    fi
    if [[ -n "$check" ]]; then
        case "$check" in *$'\n'*) die 2 "add: --check must be one line" ;; esac
        if check_denied "$check"; then die 2 "add: --check looks destructive (rm/sudo/git push/curl|...); refused"; fi
    fi
    if [[ -n "$author" ]]; then
        [[ "$author" =~ ^[A-Za-z0-9._@+:-]+$ ]] || die 2 "add: --author must be one token (e.g. uws-implementer, human, you@example.com)"
    else
        author="$(kb_actor "$ROOT")"
    fi
    local -a tags=()
    local t
    if [[ -n "$tags_raw" ]]; then
        tags_raw="${tags_raw#[}"; tags_raw="${tags_raw%]}"
        while IFS= read -r t; do
            t="$(printf '%s' "$t" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            [[ -n "$t" ]] || continue
            [[ "$t" =~ ^[A-Za-z0-9._:+/-]+$ ]] || die 2 "add: bad tag '$t' (letters, digits and ._:+/- only)"
            tags+=("$t")
        done <<EOF
$(printf '%s' "$tags_raw" | tr ',' '\n')
EOF
    fi

    # ── Secret scan (exit 2) ──
    local hit
    if hit="$(secret_scan "${claim}"$'\n'"${body}"$'\n'"${quote}"$'\n'"${check}"$'\n'"${falsifier}"$'\n'"${sources[*]+${sources[*]}}")"; then
        die 2 "add: refused: text looks like a secret (${hit}); never store credentials in the KB"
    fi

    # ── Evidence-specific provenance (R8, exit 2) ──
    local s
    case "$evidence" in
        inferred)
            for s in ${sources[@]+"${sources[@]}"}; do
                [[ "$s" == item:* ]] || die 2 "add: inferred items take item:<id> sources only"
            done ;;
        reported)
            local has_url=false
            for s in ${sources[@]+"${sources[@]}"}; do [[ "$s" == url:* ]] && has_url=true; done
            [[ "$has_url" == "true" ]] || die 2 "add: reported evidence needs a url: source"
            [[ -n "$quote" ]] || printf '%s\n' "$body" | grep -q '^>' \
                || die 2 "add: reported evidence needs a verbatim quote (--quote, or a '> ' line in --body)"
            ;;
        observed)
            for s in ${sources[@]+"${sources[@]}"}; do
                [[ "$s" == item:* || "$s" == url:* ]] && die 2 "add: observed evidence needs file:, cmd: or commit: sources"
            done ;;
    esac

    ensure_kb
    local -a resolved=()
    local r err
    for s in ${sources[@]+"${sources[@]}"}; do
        if ! r="$(resolve_source "$s" 2>&1)"; then
            err="$(printf '%s' "$r" | grep -v '^uws kb: no commit yet' | tail -1)"
            die 2 "add: unresolvable source (R8): ${err}"
        fi
        # a warning (unpinned source) was merged into r: keep the last line
        printf '%s\n' "$r" | grep '^uws kb: ' >&2 || true
        resolved+=("$(printf '%s\n' "$r" | grep -v '^uws kb: ' | tail -1)")
    done

    # Watch list: explicit --watch paths plus every file: source path
    local -a wlist=()
    local w p
    for w in ${watches[@]+"${watches[@]}"}; do
        [[ "$w" =~ ^[A-Za-z0-9._/+@-]+$ ]] || die 2 "add: bad --watch path '$w' (no spaces or quotes)"
        [[ -f "${ROOT}/${w}" ]] || die 2 "add: --watch path does not exist: $w"
        wlist+=("$w")
    done
    for s in ${resolved[@]+"${resolved[@]}"}; do
        case "$s" in
            file:*)
                p="${s#file:}"; p="${p%@*}"
                [[ "$p" =~ :[0-9]+(-[0-9]+)?$ ]] && p="${p%:*}"
                [[ "$p" =~ ^[A-Za-z0-9._/+@-]+$ ]] || continue
                local dup=false x
                for x in ${wlist[@]+"${wlist[@]}"}; do [[ "$x" == "$p" ]] && dup=true; done
                [[ "$dup" == "true" ]] || wlist+=("$p")
                ;;
        esac
    done

    # ── Linked items must exist and be active ──
    local l
    for l in ${supersedes[@]+"${supersedes[@]}"} ${contradicts[@]+"${contradicts[@]}"}; do
        [[ -f "${KB}/items/${l}.md" ]] || die 2 "add: linked item is not active (or does not exist): $l"
    done

    # ── Duplicates (R7, exit 3) ──
    local norm f
    norm="$(kb_normalize_claim "$claim")"
    for f in "${KB}"/items/*.md; do
        [[ -f "$f" ]] || continue
        if [[ "$(kb_normalize_claim "$(kb_fm_get "$f" claim)")" == "$norm" ]]; then
            local dupid
            dupid="$(kb_fm_get "$f" id)"
            printf '%s\n' "$dupid"
            die 3 "add: duplicate of ${dupid} (R7)"
        fi
    done

    # ── Undeclared conflicts with trusted items (exit 4) ──
    if [[ "$no_conflict" != "true" && ${#supersedes[@]} -eq 0 && ${#contradicts[@]} -eq 0 ]]; then
        local conf
        conf="$(conflicts_for "$claim" "$(printf '%s\n' ${wlist[@]+"${wlist[@]}"})" | LC_ALL=C sort -u)"
        if [[ -n "$conf" ]]; then
            local c
            while IFS= read -r c; do
                warn "possible overlap with trusted ${c}: $(kb_fm_get "${KB}/items/${c}.md" claim)"
            done <<< "$conf"
            die 4 "add: declare --supersedes <id>, --contradicts <id> or --no-conflict"
        fi
    fi

    # ── ID: K-<yyyymmdd>-<hex of sha1(normalised claim)> ──
    local hex id n=6
    while :; do
        hex="$(kb_hash6 "$norm" "$n")" || die 2 "add: cannot hash the claim (git missing?)"
        id="K-$(printf '%s' "$TODAY" | tr -d '-')-${hex}"
        [[ -e "${KB}/items/${id}.md" || -e "${KB}/retired/${id}.md" ]] || break
        if [[ -f "${KB}/retired/${id}.md" && "$(kb_normalize_claim "$(kb_fm_get "${KB}/retired/${id}.md" claim)")" == "$norm" ]]; then
            printf '%s\n' "$id"
            die 3 "add: this claim was retired as ${id}; use 'uws kb restore ${id}'"
        fi
        n=$((n + 2))
        (( n <= 12 )) || die 2 "add: cannot mint a unique ID"
    done

    local -a blobs=()
    for w in ${wlist[@]+"${wlist[@]}"}; do blobs+=("$(blob_of "$w")"); done

    local file="${KB}/items/${id}.md" tmp
    tmp="$(mktemp "${KB}/items/.new.XXXXXX")"
    {
        echo "---"
        echo "id: ${id}"
        echo "type: ${type}"
        echo "scope: project"
        echo "status: candidate"
        echo "claim: $(kb_quote "$claim")"
        echo "evidence: ${evidence}"
        echo "source: $(kb_list_format --quote ${resolved[@]+"${resolved[@]}"})"
        [[ -n "$check" ]] && echo "check: $(kb_quote "$check")"
        echo "watch: $(kb_list_format ${wlist[@]+"${wlist[@]}"})"
        echo "watch_blob: $(kb_list_format ${blobs[@]+"${blobs[@]}"})"
        [[ -n "$falsifier" ]] && echo "falsifier: $(kb_quote "$(kb_oneline "$falsifier")")"
        echo "author: ${author}"
        echo "reviewer:"
        echo "captured_by: cli"
        echo "created: ${TODAY}"
        echo "verified_at: ${TODAY}"
        echo "status_since: ${TODAY}"
        echo "review_by: $(review_by_for "$type" "$TODAY")"
        echo "supersedes: $(kb_list_format ${supersedes[@]+"${supersedes[@]}"})"
        echo "superseded_by:"
        echo "contradicts: $(kb_list_format ${contradicts[@]+"${contradicts[@]}"})"
        echo "supports: []"
        echo "tags: $(kb_list_format ${tags[@]+"${tags[@]}"})"
        [[ -n "$escaped_from" ]] && echo "escaped_from: ${escaped_from}"
        echo "---"
        [[ -n "$quote" ]] && printf '> %s\n\n' "$quote"
        [[ -n "$body" ]] && printf '%s\n' "$body"
    } > "$tmp"
    mv "$tmp" "$file"
    kb_event "$KB" "$id" "-" candidate "add" "$author"
    # Meta-learning: a bug that escaped this phase's gate. It counts in
    # `learn` only once the PI has approved the lesson (design 6.4).
    if [[ -n "$escaped_from" ]]; then
        kb_outcome escape "$escaped_from" "$author" - "$id" "$claim" "$(kb_head_ref "$ROOT")"
    fi

    # Reciprocal contradicts link, so the old item shows the dispute
    for l in ${contradicts[@]+"${contradicts[@]}"}; do
        local lf="${KB}/items/${l}.md" cur
        cur="$(kb_list_parse "$(kb_fm_raw "$lf" contradicts)")"
        # shellcheck disable=SC2086
        kb_fm_set "$lf" contradicts "$(kb_list_format $cur "$id")"
        kb_event "$KB" "$l" "$(kb_fm_get "$lf" status)" "$(kb_fm_get "$lf" status)" "contradicted-by:${id}" "$author"
    done
    # R1: retire what this item supersedes
    for l in ${supersedes[@]+"${supersedes[@]}"}; do
        kb_fm_set "${KB}/items/${l}.md" superseded_by "$id"
        retire_item "$l" "superseded-by:${id}"
    done
    rebuild_stats_cache
    printf '%s\n' "$id"
}

# ── verify ──────────────────────────────────────────────────────────────────

# verify_one <file> <mode: one|changed|all>; sets VERIFY_FAILED=true on a
# failed check. Never promotes: only `approve` writes status trusted.
VERIFY_FAILED=false
VERIFY_START=0
verify_one() {
    local f="$1" mode="$2" id st check changed res
    id="$(kb_fm_get "$f" id)"
    st="$(kb_fm_get "$f" status)"
    check="$(kb_fm_get "$f" check)"
    changed="$(changed_watches "$f")"
    if [[ "$mode" == "changed" && ( "$st" != "trusted" || -z "$changed" ) ]]; then
        return 0
    fi
    if [[ -n "$check" ]]; then
        local elapsed=$(( $(date +%s) - VERIFY_START ))
        if (( elapsed >= UWS_KB_VERIFY_BUDGET )); then
            echo "${id}: skipped (verify budget of ${UWS_KB_VERIFY_BUDGET}s used up)"
            return 0
        fi
        res="$(run_check "$check")"
        kb_fm_set "$f" check_status "$res"
        kb_fm_set "$f" checked_at "$TODAY"
        case "$res:$st" in
            pass:trusted)
                kb_fm_set "$f" verified_at "$TODAY"
                refresh_watch_blobs "$f"
                echo "${id}: check passed; still trusted (refreshed)" ;;
            pass:*)
                refresh_watch_blobs "$f"
                echo "${id}: check passed; stays ${st} until the PI approves it" ;;
            fail:trusted)
                set_status "$f" disputed "check-failed"
                VERIFY_FAILED=true
                echo "${id}: check FAILED; trusted -> disputed" ;;
            fail:*)
                VERIFY_FAILED=true
                echo "${id}: check FAILED; stays ${st}" ;;
            timeout:trusted)
                set_status "$f" stale "check-timeout"
                echo "${id}: check timed out; trusted -> stale" ;;
            timeout:*)
                echo "${id}: check timed out; stays ${st}" ;;
        esac
        return 0
    fi
    if [[ -n "$changed" ]]; then
        if [[ "$st" == "trusted" ]]; then
            set_status "$f" stale "watch-changed:$(printf '%s' "$changed" | tr '\n' ' ' | sed 's/ $//')"
            echo "${id}: watched source changed, no check; trusted -> stale"
        else
            echo "${id}: watched source changed ($(printf '%s' "$changed" | tr '\n' ' ' | sed 's/ $//')); stays ${st}"
        fi
    else
        echo "${id}: no check; watched sources unchanged"
    fi
}

cmd_verify() {
    local target="${1:---all}" f
    [[ -d "${KB}/items" ]] || { echo "No KB at ${KB}"; return 0; }
    VERIFY_START="$(date +%s)"
    case "$target" in
        --changed|--all)
            local mode="${target#--}"
            for f in "${KB}"/items/*.md; do
                [[ -f "$f" ]] || continue
                case "$(kb_fm_get "$f" status)" in
                    candidate|trusted|stale|disputed) verify_one "$f" "$mode" ;;
                esac
            done ;;
        -*) die 2 "verify: use <ID>, --changed or --all" ;;
        *)
            f="$(require_item "$target")"
            [[ "$f" == "${KB}/items/"* ]] || die 1 "verify: ${target} is retired"
            verify_one "$f" one ;;
    esac
    rebuild_stats_cache
    [[ "$VERIFY_FAILED" == "true" ]] && exit 5
    return 0
}

# ── PI gate: approve / reject / pi ──────────────────────────────────────────

# pi_gate <verb> [--as value]: exit 6 unless the caller is the PI, in a
# terminal that is not an AI agent's tool call. Prints the PI identity.
pi_gate() {
    local verb="$1" as="${2:-}" ctx pi email
    if ctx="$(kb_agent_context)"; then
        die 6 "${verb}: refused: running inside an AI agent (${ctx} is set). Only the PI may promote; run this in your own terminal. Agents may use 'uws kb recommend'."
    fi
    pi="$(kb_pi_identity "$ROOT")"
    [[ -n "$pi" ]] || die 6 "${verb}: refused: no PI configured. The PI runs: uws kb pi --set <your git e-mail>"
    email="$(kb_git_email "$ROOT")"
    if [[ -n "$as" && "$(kb_lower "$as")" != "$(kb_lower "$pi")" ]]; then
        die 6 "${verb}: refused: --as ${as} is not the PI (${pi})"
    fi
    if [[ "$(kb_lower "$email")" != "$(kb_lower "$pi")" ]]; then
        die 6 "${verb}: refused: git user.email '${email:-unset}' is not the PI (${pi})"
    fi
    printf '%s\n' "$pi"
}

parse_as() {  # sets AS_VALUE and REST_ARGS from "<id> [--as X] [...]"
    AS_VALUE=""
    REST_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --as) AS_VALUE="${2:-}"; [[ -n "$AS_VALUE" ]] || die 2 "--as needs a value"; shift 2 ;;
            *) REST_ARGS+=("$1"); shift ;;
        esac
    done
}

cmd_approve() {
    parse_as "$@"
    [[ ${#REST_ARGS[@]} -eq 1 ]] || die 2 "approve: give one item ID"
    local id="${REST_ARGS[0]}" f pi st ev check res s r
    f="$(require_item "$id")"
    [[ "$f" == "${KB}/items/"* ]] || die 1 "approve: ${id} is retired; restore it first"
    st="$(kb_fm_get "$f" status)"
    pi="$(pi_gate approve "$AS_VALUE")"
    if [[ "$st" == "trusted" ]]; then echo "${id}: already trusted"; return 0; fi
    ev="$(kb_fm_get "$f" evidence)"
    check="$(kb_fm_get "$f" check)"
    # Sources must still resolve at promotion time
    while IFS= read -r s; do
        [[ -n "$s" ]] || continue
        case "$s" in
            file:*@*)
                local p="${s#file:}"; p="${p%@*}"
                [[ "$p" =~ :[0-9]+(-[0-9]+)?$ ]] && p="${p%:*}"
                [[ -f "${ROOT}/${p}" ]] || die 2 "approve: source no longer exists: ${p}"
                ;;
            *)
                r="$(resolve_source "$s" 2>&1)" || die 2 "approve: source does not resolve: ${r}"
                ;;
        esac
    done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" source)")
EOF
    if [[ -n "$check" ]]; then
        res="$(run_check "$check")"
        kb_fm_set "$f" check_status "$res"
        kb_fm_set "$f" checked_at "$TODAY"
        [[ "$res" == "pass" ]] || die 5 "approve: the item's check did not pass (${res}); not promoted"
    elif [[ "$ev" == "verified" ]]; then
        die 2 "approve: verified evidence without a check"
    fi
    # The PI's approval settles contradictions: trusted items this one
    # contradicts are retired as disproven (design 5.5).
    local l lf
    while IFS= read -r l; do
        [[ -n "$l" ]] || continue
        lf="${KB}/items/${l}.md"
        [[ -f "$lf" ]] || continue
        if [[ "$(kb_fm_get "$lf" status)" == "trusted" ]]; then
            retire_item "$l" "disproven-by:${id}"
            echo "${l}: retired (disproven-by:${id})"
        fi
    done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" contradicts)")
EOF
    refresh_watch_blobs "$f"
    kb_fm_set "$f" reviewer "$pi"
    kb_fm_set "$f" verified_at "$TODAY"
    kb_fm_set "$f" review_by "$(review_by_for "$(kb_fm_get "$f" type)" "$TODAY")"
    # A meta-learning proposal: approval records the PI's acceptance and the
    # moment `learn` starts measuring the metric again. It never applies the
    # proposed change (design 6.4): the change goes through a normal CR.
    local is_proposal=false
    if [[ "$(kb_fm_get "$f" type)" == "proposal" ]]; then
        is_proposal=true
        kb_fm_set "$f" approved_ts "$(kb_timestamp)"
    fi
    set_status "$f" trusted "approved-by-pi"
    rebuild_stats_cache
    echo "${id}: ${st} -> trusted (approved by ${pi})"
    if [[ "$is_proposal" == "true" ]]; then
        local tgt
        tgt="$(kb_fm_get "$f" target)"
        echo "Acceptance recorded; nothing was changed${tgt:+ in ${tgt}}."
        echo "Apply the change in the item's body through a change request (uws kb show ${id})."
        if [[ "$(kb_fm_get "$f" proposal_kind)" == "change" ]]; then
            echo "uws kb learn will measure $(kb_fm_get "$f" metric) over the next ${UWS_KB_LEARN_WINDOW:-10} events and propose a revert if it does not improve."
        fi
    fi
}

cmd_reject() {
    parse_as "$@"
    [[ ${#REST_ARGS[@]} -ge 2 ]] || die 2 "reject: give an item ID and a reason"
    local id="${REST_ARGS[0]}" why="${REST_ARGS[*]:1}"
    [[ -f "${KB}/items/${id}.md" ]] || die 1 "reject: not an active item: ${id}"
    pi_gate reject "$AS_VALUE" >/dev/null
    retire_item "$id" "rejected:${why}"
    rebuild_stats_cache
    echo "${id}: retired (rejected)"
}

cmd_recommend() {
    [[ $# -ge 1 ]] || die 2 "recommend: give an item ID"
    local id="$1" why="${*:2}" f st actor cur
    f="${KB}/items/${id}.md"
    [[ -f "$f" ]] || die 1 "recommend: not an active item: ${id}"
    st="$(kb_fm_get "$f" status)"
    [[ "$st" != "trusted" ]] || die 2 "recommend: ${id} is already trusted"
    actor="$(kb_actor "$ROOT")"
    cur="$(kb_list_parse "$(kb_fm_raw "$f" recommended_by)")"
    if ! printf '%s\n' "$cur" | grep -qxF -- "$actor"; then
        # shellcheck disable=SC2086
        kb_fm_set "$f" recommended_by "$(kb_list_format $cur "$actor")"
    fi
    kb_event "$KB" "$id" "$st" "$st" "recommend${why:+:$why}" "$actor"
    echo "${id}: recommendation recorded; only the PI can promote it (uws kb approve ${id})"
}

cmd_review() {
    local f any=false id st ev cs rec
    for f in "${KB}"/items/*.md; do
        [[ -f "$f" ]] || continue
        st="$(kb_fm_get "$f" status)"
        [[ "$st" == "trusted" ]] && continue
        any=true
        id="$(kb_fm_get "$f" id)"; ev="$(kb_fm_get "$f" evidence)"; cs="$(kb_fm_get "$f" check_status)"
        rec="$(kb_list_parse "$(kb_fm_raw "$f" recommended_by)" | tr '\n' ',' | sed 's/,$//')"
        printf '%s [%s|%s|check:%s|recommended:%s] %s\n' "$id" "$st" "${ev:--}" "${cs:-none}" "${rec:-none}" \
            "$(kb_fm_get "$f" claim)"
    done
    [[ "$any" == "true" ]] || echo "Nothing to review."
    echo "Promote: uws kb approve <ID> (PI only, own terminal). Reject: uws kb reject <ID> \"<why>\"."
}

cmd_pi() {
    if [[ "${1:-}" == "--set" ]]; then
        local email="${2:-}" ctx cfg tmp
        [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+$ ]] || die 2 "pi --set: give an e-mail address"
        if ctx="$(kb_agent_context)"; then
            die 6 "pi --set: refused inside an AI agent (${ctx} is set); run it in your own terminal"
        fi
        cfg="${WORKFLOW_DIR:-${ROOT}/.workflow}/config.yaml"
        mkdir -p "$(dirname "$cfg")"
        [[ -f "$cfg" ]] || : > "$cfg"
        tmp="$(mktemp "${cfg}.XXXXXX")"
        if grep -q '^kb:' "$cfg"; then
            KBV="$email" awk '
                /^[^[:space:]#]/ { if (insec && !done) { print "  pi: \"" ENVIRON["KBV"] "\""; done = 1 } insec = ($0 ~ /^kb:/) ; print; next }
                insec && /^[[:space:]]+pi:/ { if (!done) print "  pi: \"" ENVIRON["KBV"] "\""; done = 1; next }
                { print }
                END { if (insec && !done) print "  pi: \"" ENVIRON["KBV"] "\"" }
            ' "$cfg" > "$tmp"
        else
            { cat "$cfg"; printf '\nkb:\n  pi: "%s"\n' "$email"; } > "$tmp"
        fi
        mv "$tmp" "$cfg"
        ensure_kb
        kb_event "$KB" "-" "-" "-" "pi-set:${email}" "$(kb_actor "$ROOT")"
        echo "PI set to ${email} (kb.pi in ${cfg})"
        return 0
    fi
    [[ $# -eq 0 ]] || die 2 "pi: use 'pi' or 'pi --set <email>'"
    local pi
    pi="$(kb_pi_identity "$ROOT")"
    if [[ -n "$pi" ]]; then echo "$pi"; else echo "No PI configured (uws kb pi --set <email>)"; return 1; fi
}

# ── retire / restore / prune ────────────────────────────────────────────────

cmd_retire() {
    [[ $# -ge 2 ]] || die 2 "retire: give an item ID and a reason"
    local id="$1" why="${*:2}"
    [[ -f "${KB}/items/${id}.md" ]] || die 1 "retire: not an active item: ${id}"
    retire_item "$id" "$why"
    rebuild_stats_cache
    echo "${id}: retired (${why})"
}

cmd_restore() {
    [[ $# -eq 1 ]] || die 2 "restore: give one item ID"
    local id="$1" src="${KB}/retired/${1}.md" dst="${KB}/items/${1}.md" by g cur rest
    [[ -f "$src" ]] || die 1 "restore: not a retired item: ${id}"
    [[ -e "$dst" ]] && die 2 "restore: items/${id}.md already exists"
    move_file "$src" "$dst"
    kb_fm_del "$dst" retired_at
    kb_fm_del "$dst" retired_reason
    by="$(kb_fm_get "$dst" superseded_by)"
    kb_fm_set "$dst" superseded_by ""
    kb_fm_set "$dst" reviewer ""
    # Undo the supersession link so prune (R1) does not retire it again
    for g in "${KB}"/items/*.md "${KB}"/retired/*.md; do
        [[ -f "$g" && "$g" != "$dst" ]] || continue
        cur="$(kb_list_parse "$(kb_fm_raw "$g" supersedes)")"
        if printf '%s\n' "$cur" | grep -qxF -- "$id"; then
            rest="$(printf '%s\n' "$cur" | grep -vxF -- "$id" || true)"
            # shellcheck disable=SC2086
            kb_fm_set "$g" supersedes "$(kb_list_format $rest)"
            kb_event "$KB" "$(kb_fm_get "$g" id)" "$(kb_fm_get "$g" status)" "$(kb_fm_get "$g" status)" "unsupersede:${id}" "$(kb_actor "$ROOT")"
        fi
    done
    set_status "$dst" candidate "restored${by:+ (was superseded-by:$by)}"
    rebuild_stats_cache
    echo "${id}: restored as candidate"
}

cmd_prune() {
    local apply=false
    case "${1:-}" in
        --apply) apply=true ;;
        "") ;;
        *) die 2 "prune: use 'prune' (dry run) or 'prune --apply'" ;;
    esac
    [[ -d "${KB}/items" ]] || { echo "Nothing to prune (no KB at ${KB})."; return 0; }
    local f id st since age rb plan="" line g
    # R1: active items listed in another item's supersedes
    local superseded=""
    for g in "${KB}"/items/*.md "${KB}"/retired/*.md; do
        [[ -f "$g" ]] || continue
        while IFS= read -r line; do
            [[ -n "$line" ]] && superseded+="${line}${TAB}$(kb_fm_get "$g" id)"$'\n'
        done <<EOF
$(kb_list_parse "$(kb_fm_raw "$g" supersedes)")
EOF
    done
    for f in "${KB}"/items/*.md; do
        [[ -f "$f" ]] || continue
        id="$(kb_fm_get "$f" id)"; st="$(kb_fm_get "$f" status)"
        since="$(kb_fm_get "$f" status_since)"; [[ -n "$since" ]] || since="$(kb_fm_get "$f" created)"
        age="$(kb_days_between "$since" "$TODAY" || echo 0)"
        line="$(printf '%s' "$superseded" | awk -F '\t' -v id="$id" '$1 == id { print $2; exit }')"
        if [[ -n "$line" ]]; then
            plan+="${id}${TAB}retire${TAB}superseded-by:${line}"$'\n'; continue
        fi
        case "$st" in
            disputed)   # R2
                (( age >= UWS_KB_DISPUTE_DAYS )) && plan+="${id}${TAB}retire${TAB}disproven"$'\n' ;;
            stale)      # R3 (second half)
                (( age >= UWS_KB_STALE_GRACE_DAYS )) && plan+="${id}${TAB}retire${TAB}expired"$'\n' ;;
            candidate)  # R5
                (( age >= UWS_KB_CANDIDATE_TTL_DAYS )) && plan+="${id}${TAB}retire${TAB}unpromoted"$'\n' ;;
            trusted)    # R3 (first half): review_by passed -> stale
                rb="$(kb_fm_get "$f" review_by)"
                if [[ -n "$rb" && "$rb" != "never" ]]; then
                    local over
                    over="$(kb_days_between "$rb" "$TODAY" || echo -1)"
                    (( over > 0 )) && plan+="${id}${TAB}stale${TAB}review_by-passed:${rb}"$'\n'
                fi ;;
        esac
    done
    if [[ -z "$plan" ]]; then echo "Nothing to prune."; return 0; fi
    local pid act why
    while IFS="$TAB" read -r pid act why; do
        [[ -n "$pid" ]] || continue
        if [[ "$apply" != "true" ]]; then
            echo "would ${act} ${pid} (${why})"
        elif [[ "$act" == "stale" ]]; then
            set_status "${KB}/items/${pid}.md" stale "$why"
            echo "${pid}: trusted -> stale (${why})"
        else
            retire_item "$pid" "$why"
            echo "${pid}: retired (${why})"
        fi
    done <<< "$plan"
    if [[ "$apply" == "true" ]]; then
        rebuild_stats_cache
    else
        echo "(dry run: nothing changed; run 'uws kb prune --apply', then review and commit)"
    fi
}

# ── learn / proposals (meta-learning, design section 6) ─────────────────────
#
# `learn` reads only outcomes.tsv rows (written by scripts from exit codes and
# review decisions) plus the status of the items those rows name, so that
# candidate and inferred items never feed a metric (design 6.4). A metric is
# computed per key over the last UWS_KB_LEARN_WINDOW samples recorded after the
# key's latest proposal (so a proposal the PI turned down is not repeated from
# the same rows) and proposes only with n >= UWS_KB_LEARN_MIN_N. It writes
# `proposal` candidates; nothing it does edits a rule, persona or route.

# awk helper: drop a cut-off UTF-8 sequence at the end of a string (C locale)
# shellcheck disable=SC2016
KB_AWK_UTF8='
function whole(s,    n, i, c, need) {
    n = length(s)
    for (i = n; i > 0 && i > n - 4; i--) {
        c = substr(s, i, 1)
        if (c < "\200") return s
        if (c >= "\300") { need = (c >= "\360") ? 4 : ((c >= "\340") ? 3 : 2); return (n - i + 1 < need) ? substr(s, 1, i - 1) : s }
    }
    return s
}
'

# Metrics from outcomes.tsv. Input: the side table (KBSIDE) then outcomes.tsv.
# Side table lines: "C<TAB>id" for items the PI approved (not inferred), and
# "P<TAB>id<TAB>open<TAB>metric<TAB>key<TAB>created_ts<TAB>approved_ts<TAB>
# followup_ts<TAB>kind<TAB>before<TAB>track_key<TAB>tracking" per proposal.
# Output lines (sorted by the caller; empty values are "-"):
#   M fam key n k value status window-start detail refs
#       status: small-n | below | open:<id> | propose
#   N note
#   T id pending|improved|not-improved n after before k
# shellcheck disable=SC2016
KB_AWK_LEARN='
function unesc(s,    out, i, n, c) {
    out = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\" && i < n) {
            i++; c = substr(s, i, 1)
            if (c == "t") c = "\t"; else if (c == "n") c = "\n"; else if (c == "r") c = "\r"
        }
        out = out c
    }
    return out
}
function norm(s) {   # same normalised text: case, spacing and trailing punctuation ignored
    if (s == "-") return ""
    s = tolower(unesc(s)); gsub(/[ \t\r\n]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); sub(/[.!?;:,]+$/, "", s)
    if (length(s) > 160) s = whole(substr(s, 1, 160))
    return s
}
function add(fam, key, ts, idx, bad, ref, note,    n) {
    n = ++SN[fam, key]; KEYS[fam, key] = 1
    STS[fam, key, n] = ts; SBAD[fam, key, n] = bad; SREF[fam, key, n] = ref; SNOTE[fam, key, n] = note
}
function parse_retire(s,    n, a, i) {
    RC = ""; REV = ""; RCB = ""; RFROM = ""; RTYPE = ""
    n = split(s, a, " "); RC = a[1]
    for (i = 2; i <= n; i++) {
        if (substr(a[i], 1, 9) == "evidence=") REV = substr(a[i], 10)
        else if (substr(a[i], 1, 12) == "captured_by=") RCB = substr(a[i], 13)
        else if (substr(a[i], 1, 5) == "from=") RFROM = substr(a[i], 6)
        else if (substr(a[i], 1, 5) == "type=") RTYPE = substr(a[i], 6)
    }
}
function start_of(fam, key) { return ((fam SUBSEP key) in WSTART) ? WSTART[fam, key] : "" }
function report(fam, key, n, k, val, crossed, d1, d2,    fk, st, ws) {
    fk = fam SUBSEP key
    if (n < MIN) st = "small-n"
    else if (!crossed) st = "below"
    else if (fk in BLOCK) st = "open:" BLOCK[fk]
    else st = "propose"
    ws = ((fk in WSTART) && WSTART[fk] != "") ? WSTART[fk] : "-"
    printf "M\t%s\t%s\t%d\t%d\t%.4f\t%s\t%s\t%s\t%s\n", fam, key, n, k, val, st, ws, (d1 == "" ? "-" : d1), (d2 == "" ? "-" : d2)
}
# Gate-escape rate of phase p: approved escapes after the earliest of the last
# W passes, divided by those passes.
function eval_escape(p,    fam, key, start, i, j, n, k, first, ids, last) {
    fam = "gate-escape-rate"; key = "phase=" p; start = start_of(fam, key)
    n = 0; first = 0
    for (i = PN[p]; i >= 1 && n < W; i--) {
        if (start != "" && PTS[p, i] <= start) continue
        n++; first = PIX[p, i]
    }
    if (n == 0) return
    k = 0; ids = ""; last = ""
    for (j = 1; j <= EN[p]; j++) {
        if (EIX[p, j] <= first) continue
        if (start != "" && ETS[p, j] <= start) continue
        k++; ids = ids (ids == "" ? "" : ",") EID[p, j]; last = EID[p, j]
    }
    report(fam, key, n, k, k / n, (k / n > THR[fam]), last, ids)
}
# Share of bad samples among the last W; detail = most frequent note (latest on a tie).
function eval_rate(fam, key,    start, i, n, k, refs, why, best, bestn, cnt, lastpos) {
    start = start_of(fam, key)
    n = 0; k = 0; refs = ""; split("", cnt); split("", lastpos)
    for (i = SN[fam, key]; i >= 1 && n < W; i--) {
        if (start != "" && STS[fam, key, i] <= start) continue
        n++
        if (SBAD[fam, key, i]) {
            k++; refs = SREF[fam, key, i] (refs == "" ? "" : "," refs)
            why = SNOTE[fam, key, i]
            if (why != "") { cnt[why]++; if (!(why in lastpos)) lastpos[why] = i }
        }
    }
    if (n == 0) return
    best = ""; bestn = 0
    for (why in cnt) if (cnt[why] > bestn || (cnt[why] == bestn && lastpos[why] > lastpos[best] + 0)) { best = why; bestn = cnt[why] }
    report(fam, key, n, k, k / n, (k / n > THR[fam]), best, refs)
}
# Reason r among the last W gate failures; detail = the phase the failures sent
# work back to (the failing phase when there was no regression).
function eval_repeat(r,    fam, key, start, i, n, k, refs, t, tc, tl, best, bestn) {
    fam = "repeated-gate-fail"; key = "reason=" r; start = start_of(fam, key)
    n = 0; k = 0; refs = ""; split("", tc); split("", tl)
    for (i = FN; i >= 1 && n < W; i--) {
        if (start != "" && FTS[i] <= start) continue
        n++
        if (FR[i] == r) {
            k++; t = (FTO[i] != "-" ? FTO[i] : FPH[i]); tc[t]++; if (!(t in tl)) tl[t] = i
            refs = FPH[i] (refs == "" ? "" : "," refs)
        }
    }
    if (n == 0 || k == 0) return
    best = ""; bestn = 0
    for (t in tc) if (tc[t] > bestn || (tc[t] == bestn && tl[t] > tl[best] + 0)) { best = t; bestn = tc[t] }
    report(fam, key, n, k, k / n, (k >= REP), best, refs)
}
# An approved change: the same metric over the first W samples after approval.
function track(t,    fam, key, A, i, j, n, k, p, r, first, lastidx, tf, after, verdict) {
    fam = T_metric[t]; key = T_key[t]; A = T_ts[t]; n = 0; k = 0
    if (fam == "gate-escape-rate") {
        p = substr(key, 7); first = 0; lastidx = 0
        for (i = 1; i <= PN[p] && n < W; i++) {
            if (PTS[p, i] <= A) continue
            n++; if (!first) first = PIX[p, i]; lastidx = PIX[p, i]
        }
        if (n >= W) for (j = 1; j <= EN[p]; j++) if (EIX[p, j] > first && EIX[p, j] <= lastidx && ETS[p, j] > A) k++
    } else if (fam == "repeated-gate-fail") {
        r = substr(key, 8)
        for (i = 1; i <= FN && n < W; i++) { if (FTS[i] <= A) continue; n++; if (FR[i] == r) k++ }
    } else {
        tf = (fam == "cr-first-pass-rejection") ? "cr-role" : fam
        for (i = 1; i <= SN[tf, key] && n < W; i++) { if (STS[tf, key, i] <= A) continue; n++; if (SBAD[tf, key, i]) k++ }
    }
    if (n < W) { printf "T\t%s\tpending\t%d\t-\t%s\t%d\n", T_id[t], n, T_before[t], k; return }
    after = k / n
    verdict = ((sprintf("%.2f", after) + 0) < (sprintf("%.2f", T_before[t]) + 0)) ? "improved" : "not-improved"
    printf "T\t%s\t%s\t%d\t%.4f\t%s\t%d\n", T_id[t], verdict, n, after, T_before[t], k
}
BEGIN {
    FS = "\t"; SIDE = ENVIRON["KBSIDE"]
    W = ENVIRON["KBW"] + 0; MIN = ENVIRON["KBMIN"] + 0; REP = ENVIRON["KBREP"] + 0
    THR["gate-escape-rate"] = ENVIRON["KBTESC"] + 0
    THR["cr-first-pass-rejection"] = ENVIRON["KBTCR"] + 0
    THR["disproven-rate"] = ENVIRON["KBTDIS"] + 0
}
FILENAME == SIDE {
    if ($1 == "C") CONF[$2] = 1
    else if ($1 == "P") {
        fk = $4 SUBSEP $5
        t = ($8 != "-") ? $8 : (($7 != "-") ? $7 : $6); if (t == "-") t = ""
        if (!(fk in WSTART) || t > WSTART[fk]) WSTART[fk] = t
        if ($3 == "1") BLOCK[fk] = $2
        if ($12 == "1") { NT++; T_id[NT] = $2; T_metric[NT] = $4; T_key[NT] = ($11 != "-" ? $11 : $5); T_ts[NT] = $7; T_before[NT] = $10 }
    }
    next
}
NF != 8 { BAD++; next }
{
    R++; ts = $1; ev = $2
    if (ev == "gate_pass") { n = ++PN[$3]; PTS[$3, n] = ts; PIX[$3, n] = R; PH[$3] = 1 }
    else if (ev == "escape") {
        if ($6 in CONF) { n = ++EN[$3]; ETS[$3, n] = ts; EIX[$3, n] = R; EID[$3, n] = $6; PH[$3] = 1 }
        else UNCONF++
    }
    else if (ev == "gate_fail") { n = ++FN; FTS[n] = ts; FR[n] = norm($7); FPH[n] = $3; FTO[n] = $6 }
    else if (ev == "dispatch") { if ($7 == "dispatched") { PEND[$4] = 1; PMOD[$4] = $5 } }
    else if (ev == "cr_decision") {
        role = $4
        if (role != "-" && PEND[role] == 1) {   # first decision since the role was dispatched
            PEND[role] = 0
            bad = (substr($7, 1, 8) == "rejected"); why = ""
            if (bad) { why = $7; sub(/^rejected:?[ ]*/, "", why); why = norm(why) }
            add("cr-first-pass-rejection", "role=" role ",model=" PMOD[role], ts, R, bad, $8, why)
            add("cr-role", "role=" role, ts, R, bad, $8, why)
        }
    }
    else if (ev == "kb_retire") {
        parse_retire($7)
        if ((RFROM == "trusted" || RFROM == "stale" || RFROM == "disputed") \
            && (REV == "verified" || REV == "observed" || REV == "reported") \
            && RTYPE != "proposal" && RTYPE != "hypothesis" && RTYPE != "question") {
            bad = (RC == "disproven" || RC == "disproven-by")
            add("disproven-rate", "evidence=" REV, ts, R, bad, $6, "")
            add("disproven-rate", "captured_by=" RCB, ts, R, bad, $6, "")
        } else RSKIP++
    }
}
END {
    if (BAD) printf "N\t%d malformed row(s) in outcomes.tsv skipped (want 8 tab-separated columns)\n", BAD
    if (UNCONF) printf "N\t%d escape row(s) not counted: the lesson is not approved by the PI yet, or is inferred\n", UNCONF
    if (RSKIP) printf "N\t%d retirement(s) not counted: candidates, inferred items, hypotheses, questions and proposals do not feed metrics\n", RSKIP
    for (p in PH) eval_escape(p)
    for (fk in KEYS) { split(fk, a, SUBSEP); if (a[1] != "cr-role") eval_rate(a[1], a[2]) }
    for (i = 1; i <= FN; i++) if (FR[i] != "") RSN[FR[i]] = 1
    for (r in RSN) eval_repeat(r)
    for (t = 1; t <= NT; t++) track(t)
}
'

# Side table for KB_AWK_LEARN from every item file (active and retired).
learn_side_table() {
    local -a files=()
    local f
    for f in "${KB}"/items/*.md "${KB}"/retired/*.md; do [[ -f "$f" ]] && files+=("$f"); done
    [[ ${#files[@]} -gt 0 ]] || return 0
    awk "${KB_AWK_VALUES}"'
        function fmv(k,    x) { x = kb_unq(F[k]); return (x == "" ? "-" : x) }
        function kb_emit(    id, st, ev, dir, kind, appr, fu, open, tracking, rr) {
            if ("_invalid" in F) return
            id = kb_unq(F["id"]); st = kb_unq(F["status"]); ev = kb_unq(F["evidence"])
            dir = (index(FILE, "/retired/") > 0) ? "retired" : "items"
            rr = kb_unq(F["retired_reason"])
            # Approved by the PI and not inferred (design 6.4): trusted or stale
            # now, or retired later as superseded or graduated.
            if (ev != "" && ev != "inferred") {
                if (dir == "items" && (st == "trusted" || st == "stale")) print "C\t" id
                else if (dir == "retired" && kb_unq(F["reviewer"]) != "" && rr ~ /^(superseded-by|graduated):/) print "C\t" id
            }
            if (kb_unq(F["type"]) != "proposal" || kb_unq(F["metric"]) == "") return
            kind = kb_unq(F["proposal_kind"]); if (kind == "") kind = "change"
            appr = kb_unq(F["approved_ts"]); fu = kb_unq(F["followup_ts"])
            tracking = (kind == "change" && appr != "" && fu == "" && rr !~ /^rejected/) ? 1 : 0
            open = ((dir == "items" && st == "candidate") || tracking) ? 1 : 0
            printf "P\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%d\n", id, open, fmv("metric"), fmv("metric_key"), \
                fmv("created_ts"), fmv("approved_ts"), fmv("followup_ts"), kind, fmv("metric_before"), fmv("track_key"), tracking
        }
    '"${KB_AWK_ITEMS}" "${files[@]}"
}

pct() { awk -v v="$1" 'BEGIN { printf "%d%%", int(v * 100 + 0.5) }'; }
fmt2() { awk -v v="$1" 'BEGIN { printf "%.2f", v }'; }

# One line of text that is safe inside a double-quoted shell string and in a
# claim: no quotes, $, backquotes or backslashes; at most N bytes.
safe_text() {
    KBV="$1" KBN="${2:-120}" LC_ALL=C awk "${KB_AWK_UTF8}"'
        BEGIN {
            s = ENVIRON["KBV"]; n = ENVIRON["KBN"] + 0
            gsub(/["$`\\]/, "", s); gsub(/[[:space:][:cntrl:]]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
            if (length(s) > n) s = whole(substr(s, 1, n - 3)) "..."
            printf "%s", s
        }'
}

# find_target <rel-path>...: the first candidate that exists in the project,
# else in the UWS installation. Sets TARGET_REL, TARGET_ABS, TARGET_WHERE.
find_target() {
    local rel
    TARGET_REL="$1"; TARGET_ABS=""; TARGET_WHERE="the UWS installation"
    for rel in "$@"; do
        if [[ -f "${ROOT}/${rel}" ]]; then TARGET_REL="$rel"; TARGET_ABS="${ROOT}/${rel}"; TARGET_WHERE="this project"; return 0; fi
    done
    for rel in "$@"; do
        if [[ -f "${UWS_HOME}/${rel}" ]]; then TARGET_REL="$rel"; TARGET_ABS="${UWS_HOME}/${rel}"; return 0; fi
    done
    return 1
}

# diff_insert <file> <rel> <after-line> <new-line>: unified diff adding a line
diff_insert() {
    KBREL="$2" KBL="$3" KBADD="$4" awk '
        { line[NR] = $0 }
        END {
            L = ENVIRON["KBL"] + 0; s = L - 2; if (s < 1) s = 1; e = L + 3; if (e > NR) e = NR
            printf "--- a/%s\n+++ b/%s\n@@ -%d,%d +%d,%d @@\n", ENVIRON["KBREL"], ENVIRON["KBREL"], s, e - s + 1, s, e - s + 2
            for (i = s; i <= e; i++) { printf " %s\n", line[i]; if (i == L) printf "+%s\n", ENVIRON["KBADD"] }
        }' "$1"
}

# diff_replace <file> <rel> <line> <new-line>: unified diff replacing one line
diff_replace() {
    KBREL="$2" KBL="$3" KBNEW="$4" awk '
        { line[NR] = $0 }
        END {
            L = ENVIRON["KBL"] + 0; s = L - 2; if (s < 1) s = 1; e = L + 2; if (e > NR) e = NR
            printf "--- a/%s\n+++ b/%s\n@@ -%d,%d +%d,%d @@\n", ENVIRON["KBREL"], ENVIRON["KBREL"], s, e - s + 1, s, e - s + 1
            for (i = s; i <= e; i++) {
                if (i == L) printf "-%s\n+%s\n", line[i], ENVIRON["KBNEW"]
                else printf " %s\n", line[i]
            }
        }' "$1"
}

# Line number of the last `echo "- ..."` deliverable of <phase> in
# get_phase_deliverables of scripts/sdlc.sh or scripts/research.sh
deliverable_anchor() {
    KBP="$2" awk '
        /^get_phase_deliverables\(\)/ { infn = 1; next }
        infn && /^}/ { exit }
        infn && index($0, "\"" ENVIRON["KBP"] "\")") > 0 { incase = 1; next }
        incase && /;;/ { exit }
        incase && /^[[:space:]]*echo "- / { last = NR }
        END { if (last) print last }
    ' "$1"
}

# Line number of the last "- [ ]" item under a persona's "## Quality Gate" heading
quality_gate_anchor() {
    awk '/^## Quality Gate/ { inq = 1; next } inq && /^## / { exit } inq && /^- \[ \]/ { last = NR } END { if (last) print last }' "$1"
}

# The ```diff block of a proposal with its + and - lines swapped
reverse_diff() {
    awk '/^```diff$/ { f = 1; next } f && /^```$/ { exit } f { print }' "$1" | awk '
        /^--- / || /^\+\+\+ / { print; next }
        /^@@ / { a = $2; c = $3; sub(/^-/, "", a); sub(/^\+/, "", c); printf "@@ -%s +%s @@\n", c, a; next }
        /^\+/ { print "-" substr($0, 2); next }
        /^-/ { print "+" substr($0, 2); next }
        { print }'
}

# Another model for a role whose first-pass CRs are often rejected. A
# heuristic (the next larger tier; opus goes to sonnet), not evidence that the
# other model does better: the proposal says so.
alt_model() {
    case "$1" in
        haiku) echo sonnet ;;
        sonnet) echo opus ;;
        opus) echo sonnet ;;
        *) echo opus ;;
    esac
}

# Add a deliverable line to <phase> of scripts/<m>.sh (sets P_TARGET, P_WHERE,
# P_DIFF or P_TEXT)
plan_deliverable_line() {
    local m="$1" p="$2" text="$3" L="" indent
    if [[ "$m" == "sdlc" || "$m" == "research" ]] && find_target "scripts/${m}.sh"; then
        L="$(deliverable_anchor "$TARGET_ABS" "$p")"
    fi
    P_TARGET="scripts/${m}.sh"; P_WHERE="${TARGET_WHERE:-the UWS installation}"
    if [[ -n "$L" ]]; then
        indent="$(sed -n "${L}p" "$TARGET_ABS" | sed 's/[^[:space:]].*//')"
        P_DIFF="$(diff_insert "$TARGET_ABS" "$TARGET_REL" "$L" "${indent}echo \"- ${text}\"")"
    else
        P_TEXT="In scripts/${m}.sh, get_phase_deliverables, case \"${p}\", add the line: echo \"- ${text}\""
    fi
}

# plan_proposal <fam> <key> <n> <k> <value> <detail> <refs>: fill the P_*
# globals for a new change proposal. Returns 1 when the metric is unknown.
plan_proposal() {
    local fam="$1" key="$2" n="$3" k="$4" val="$5" d1="$6" refs="$7"
    local vp ph m p f eclaim text L role model alt persona lvl old new line cb reason
    P_FAM="$fam"; P_KEY="$key"; P_TRACK="$key"; P_N="$n"; P_K="$k"; P_BEFORE="$(fmt2 "$val")"; P_AFTER=""
    P_REFS="$refs"; P_KIND="change"; P_REVERTS=""; P_DIFF=""; P_TEXT=""; P_NOTE=""; P_TARGET=""; P_WHERE=""
    vp="$(pct "$val")"
    case "$fam" in
        gate-escape-rate)
            ph="${key#phase=}"; m="${ph%%:*}"; p="${ph#*:}"
            P_THR="$UWS_KB_LEARN_ESCAPE_RATE"
            P_SUBJECT="passes of the ${ph} gate followed by an escaped bug"
            eclaim=""
            if [[ "$d1" != "-" ]] && f="$(kb_item_path "$KB" "$d1")"; then eclaim="$(kb_fm_get "$f" claim)"; fi
            plan_deliverable_line "$m" "$p" "Escape check (${d1}): $(safe_text "$eclaim" 110)"
            P_CLAIM="Gate escapes after ${ph}: ${k} escaped bug(s) followed the last ${n} passes (${vp}), above $(pct "$P_THR"); proposal: add the escaped check to its exit checklist."
            P_FALSIFIER="Revert if the escape rate after ${ph} does not fall below ${vp} over the next ${UWS_KB_LEARN_WINDOW} passes of that gate."
            P_CONFOUND="an escape counts only when someone records a lesson with --escaped-from and the PI approves it, so escapes are probably under-counted; phases differ in how much work passes through them, and a pass may be forced or ungated (see the result column)."
            ;;
        cr-first-pass-rejection)
            role="${key#role=}"; role="${role%%,model=*}"; model="${key##*,model=}"
            P_THR="$UWS_KB_LEARN_CR_REJECT_RATE"; P_TRACK="role=${role}"
            P_SUBJECT="first-pass CR decisions for ${role} (model ${model}) that were rejections"
            P_FALSIFIER="Revert if the first-pass CR rejection rate of ${role} (any model) does not fall below ${vp} over its next ${UWS_KB_LEARN_WINDOW} first-pass CR decisions."
            P_CONFOUND="roles and models are given different tasks and reviewers differ, so the rate is an association, not the effect of the model or the persona."
            if [[ "$d1" != "-" ]]; then
                persona="$role"; [[ "$role" == rt-* ]] && persona="research-${role#rt-}"
                text="- [ ] Not a repeat of a first-pass CR rejection (${k} of ${n} recent CRs): $(safe_text "$d1" 120)"
                P_CLAIM="First-pass CR rejections for ${role} (model ${model}): ${k} of ${n} (${vp}), above $(pct "$P_THR"); proposal: add the most frequent rejection reason to its Quality Gate."
                P_TARGET="docs/personas/${persona}.md"; P_WHERE="the UWS installation"
                if find_target "docs/personas/${persona}.md"; then
                    P_WHERE="$TARGET_WHERE"
                    L="$(quality_gate_anchor "$TARGET_ABS")"
                    [[ -z "$L" ]] || P_DIFF="$(diff_insert "$TARGET_ABS" "$TARGET_REL" "$L" "$text")"
                fi
                [[ -n "$P_DIFF" ]] || P_TEXT="In docs/personas/${persona}.md, add to the Quality Gate list: ${text}"
                P_NOTE="Then regenerate the subagent: ./scripts/gen_subagents.sh"
            else
                alt="$(alt_model "$model")"
                P_CLAIM="First-pass CR rejections for ${role} (model ${model}): ${k} of ${n} (${vp}), above $(pct "$P_THR"); no reasons were recorded; proposal: route ${role} to ${alt}."
                P_TARGET=".claude/agents/uws-${role}.md"; P_WHERE="the UWS installation"
                if find_target ".claude/agents/uws-${role}.md" "agents/uws-${role}.md"; then
                    P_TARGET="$TARGET_REL"; P_WHERE="$TARGET_WHERE"
                    L="$(awk 'NR > 1 && /^---$/ { exit } /^model:/ { print NR; exit }' "$TARGET_ABS")"
                    [[ -z "$L" ]] || P_DIFF="$(diff_replace "$TARGET_ABS" "$TARGET_REL" "$L" "model: ${alt}")"
                fi
                [[ -n "$P_DIFF" ]] || P_TEXT="Set model: ${alt} in the front matter of .claude/agents/uws-${role}.md."
                P_NOTE="The agent file is generated: make the change with UWS_AGENT_MODEL_$(printf '%s' "$role" | tr 'a-z-' 'A-Z_')=${alt} ./scripts/gen_subagents.sh. The other model is a heuristic choice (the next tier), not evidence that it does better."
            fi
            ;;
        disproven-rate)
            P_THR="$UWS_KB_LEARN_DISPROVEN_RATE"
            P_SUBJECT="retirements of formerly trusted items with ${key} that were disproven"
            P_FALSIFIER="Revert if the disproven rate for ${key} does not fall below ${vp} over the next ${UWS_KB_LEARN_WINDOW} retirements of trusted items with ${key}."
            P_CONFOUND="the denominator is retirements recorded in outcomes.tsv, not every item with ${key}: items still trusted are not counted, and a level or source used for harder claims will look worse."
            case "$key" in
                evidence=*)
                    lvl="${key#evidence=}"
                    P_TARGET="scripts/kb.sh"; P_WHERE="the UWS installation"; old=""
                    if find_target "scripts/kb.sh"; then
                        P_WHERE="$TARGET_WHERE"
                        line="$(KBL="$lvl" awk '{ k = "trust[\"" ENVIRON["KBL"] "\"] = "; i = index($0, k)
                            if (i) { v = substr($0, i + length(k)); sub(/[^0-9.].*/, "", v); print NR "\t" v; exit } }' "$TARGET_ABS")"
                        IFS="$TAB" read -r L old <<< "$line"
                    fi
                    if [[ -n "$L" && -n "$old" ]]; then
                        new="$(awk -v o="$old" -v r="$val" 'BEGIN { printf "%.2f", o * (1 - r) }')"
                        line="$(KBL="$lvl" KBOLD="$old" KBNEW="$new" awk -v L="$L" 'NR == L {
                            k = "trust[\"" ENVIRON["KBL"] "\"] = "; i = index($0, k) + length(k)
                            print substr($0, 1, i - 1) ENVIRON["KBNEW"] substr($0, i + length(ENVIRON["KBOLD"])); exit }' "$TARGET_ABS")"
                        P_DIFF="$(diff_replace "$TARGET_ABS" "$TARGET_REL" "$L" "$line")"
                        P_CLAIM="Disproven rate for ${lvl} evidence: ${k} of the last ${n} retired trusted items (${vp}), above $(pct "$P_THR"); proposal: lower its search trust weight ${old} -> ${new}."
                    else
                        P_CLAIM="Disproven rate for ${lvl} evidence: ${k} of the last ${n} retired trusted items (${vp}), above $(pct "$P_THR"); proposal: lower its search trust weight."
                        P_TEXT="In scripts/kb.sh (KB_AWK_SEARCH), multiply trust[\"${lvl}\"] by $(awk -v r="$val" 'BEGIN { printf "%.2f", 1 - r }')."
                    fi
                    P_NOTE="The new weight is the old one times the share not disproven (1 - ${P_BEFORE}); that factor is a heuristic, not a fitted value."
                    ;;
                captured_by=*)
                    cb="${key#captured_by=}"
                    text="- Items captured via \`$(safe_text "$cb" 40)\` were disproven in ${k} of the last ${n} retirements of trusted items: give two independent sources before you recommend one."
                    P_CLAIM="Disproven rate for items captured by $(safe_text "$cb" 40): ${k} of the last ${n} retired trusted items (${vp}), above $(pct "$P_THR"); proposal: ask for two independent sources in the uws-kb skill."
                    P_TARGET=".claude/skills/uws-kb/SKILL.md"; P_WHERE="the UWS installation"
                    if find_target ".claude/skills/uws-kb/SKILL.md" "skills/uws-kb/SKILL.md"; then
                        P_TARGET="$TARGET_REL"; P_WHERE="$TARGET_WHERE"
                        L="$(grep -n -F 'Never put credentials' "$TARGET_ABS" | head -1 | cut -d: -f1 || true)"
                        [[ -z "$L" ]] || P_DIFF="$(diff_insert "$TARGET_ABS" "$TARGET_REL" "$L" "$text")"
                    fi
                    [[ -n "$P_DIFF" ]] || P_TEXT="In the uws-kb skill (SKILL.md, section 'Add what you learned'), add: ${text}"
                    P_NOTE="The plugin ships a second copy of the skill (plugins/uws/skills/uws-kb/SKILL.md); change both."
                    ;;
                *) return 1 ;;
            esac
            ;;
        repeated-gate-fail)
            reason="${key#reason=}"; ph="$d1"; m="${ph%%:*}"; p="${ph#*:}"
            P_THR="$UWS_KB_LEARN_REPEAT_FAILS"
            P_SUBJECT="gate failures (all phases) that gave this reason"
            plan_deliverable_line "$m" "$p" "Checked that this gate failure does not recur (${k} of ${n} recent failures): $(safe_text "$reason" 100)"
            P_CLAIM="Gate failure reason repeated ${k} times in the last ${n} gate failures: '$(safe_text "$reason" 70)'; proposal: add a check for it to the ${p} exit checklist."
            P_FALSIFIER="Revert if this reason's share of gate failures does not fall below ${vp} over the next ${UWS_KB_LEARN_WINDOW} gate failures."
            P_CONFOUND="reasons are free text compared after normalisation (case, spacing, trailing punctuation), so one problem worded two ways counts twice; the check goes to ${ph}, the phase the failures sent work back to (or the failing phase when there was no regression)."
            ;;
        *) return 1 ;;
    esac
    return 0
}

# plan_revert <proposal-file> <n> <k> <after>: fill P_* for a revert proposal
plan_revert() {
    local f="$1" n="$2" k="$3" after="$4" oid shown
    oid="$(kb_fm_get "$f" id)"
    P_FAM="$(kb_fm_get "$f" metric)"; P_KEY="$(kb_fm_get "$f" metric_key)"; P_TRACK="$(kb_fm_get "$f" track_key)"
    [[ -n "$P_TRACK" ]] || P_TRACK="$P_KEY"
    P_N="$n"; P_K="$k"; P_BEFORE="$(kb_fm_get "$f" metric_before)"; P_AFTER="$(fmt2 "$after")"
    P_THR="$(kb_fm_get "$f" threshold)"; P_KIND="revert"; P_REVERTS="$oid"; P_REFS="-"
    P_TARGET="$(kb_fm_get "$f" target)"; P_WHERE="where ${oid} was applied"
    P_DIFF="$(reverse_diff "$f")"; P_TEXT=""; P_NOTE=""
    [[ -n "$P_DIFF" ]] || P_TEXT="Undo the change described in ${oid} (uws kb show ${oid})."
    shown="$(safe_text "$P_TRACK" 60)"
    P_SUBJECT="events after the approval of ${oid} (${P_FAM}, ${shown})"
    P_CLAIM="Revert ${oid}: ${P_FAM} for ${shown} went $(pct "$P_BEFORE") -> $(pct "$after") over the ${n} events after its approval (no improvement)."
    P_FALSIFIER="Keep ${oid} instead if ${P_FAM} for ${shown} gets worse over the next ${UWS_KB_LEARN_WINDOW} events once this revert is applied (a revert is not tracked automatically)."
    P_CONFOUND="the metric can move for reasons unrelated to ${oid} (other changes, different tasks); this reports that it did not improve, not that ${oid} made it worse."
}

# Markdown body of the proposal described by the P_* globals
proposal_body() {
    local thr
    if [[ "$P_FAM" == "repeated-gate-fail" ]]; then thr=">= ${P_THR} times"; else thr="> $(pct "$P_THR")"; fi
    printf 'Written by `uws kb learn` from %s/outcomes.tsv. It reports counts, not causes.\n' "$KB_REL"
    printf 'Approving it (PI only) records acceptance; it changes no file.\n\n'
    printf '## Metric\n\n'
    if [[ "$P_KIND" == "revert" ]]; then
        printf -- '- %s for %s: %s when %s was proposed; %s of %s = %s (%s) over the %s events after its approval.\n' \
            "$P_FAM" "$P_TRACK" "$(pct "$P_BEFORE")" "$P_REVERTS" "$P_K" "$P_N" "$P_AFTER" "$(pct "$P_AFTER")" "$P_N"
        printf -- '- Did not improve: the value after approval is not below the value before.\n'
    else
        printf -- '- %s for %s: %s of %s %s = %s (%s); threshold %s, with n >= %s.\n' \
            "$P_FAM" "$P_KEY" "$P_K" "$P_N" "$P_SUBJECT" "$P_BEFORE" "$(pct "$P_BEFORE")" "$thr" "$UWS_KB_LEARN_MIN_N"
        printf -- '- Window: the last %s samples (at most %s) recorded after %s.\n' \
            "$P_N" "$UWS_KB_LEARN_WINDOW" "$( [[ "${P_WSTART:--}" == "-" ]] && echo "the start of the log" || echo "the previous proposal on this key (${P_WSTART})")"
        printf -- '- Rows behind the count: %s\n' "$(safe_text "$P_REFS" 400)"
    fi
    printf '\n## Proposed change (not applied)\n\n'
    printf 'Target: `%s` (%s). Apply it, if you accept it, through a normal change request.\n\n' "$P_TARGET" "$P_WHERE"
    if [[ -n "$P_DIFF" ]]; then
        printf '```diff\n%s\n```\n' "$P_DIFF"
    else
        printf '%s\n' "$P_TEXT"
    fi
    [[ -z "$P_NOTE" ]] || printf '\n%s\n' "$P_NOTE"
    printf '\n## Falsifier\n\n%s\n' "$P_FALSIFIER"
    if [[ "$P_KIND" == "change" ]]; then
        printf '`uws kb learn` measures this once the PI approves the proposal and proposes the revert if it does not improve.\n'
    fi
    printf '\n## Caveats\n\n'
    printf -- '- Small n: %s samples; with n = %s one event moves the rate by %s, so this can be chance.\n' \
        "$P_N" "$P_N" "$(pct "$(awk -v n="$P_N" 'BEGIN { print (n > 0 ? 1 / n : 1) }')")"
    printf -- '- Confounding: %s\n' "$P_CONFOUND"
    printf -- '- Inputs: only rows that scripts wrote to outcomes.tsv; candidate and inferred items were not counted (design 6.4).\n'
}

# write_proposal <body>: create the proposal item from the P_* globals and set
# NEW_ID. Returns 3 (NEW_ID = existing item) when an active item already has
# the same claim, 1 on any other failure.
write_proposal() {
    local body="$1" norm f hex n=6 id tmp src head hit
    NEW_ID=""
    norm="$(kb_normalize_claim "$P_CLAIM")"
    for f in "${KB}"/items/*.md; do
        [[ -f "$f" ]] || continue
        if [[ "$(kb_normalize_claim "$(kb_fm_get "$f" claim)")" == "$norm" ]]; then
            NEW_ID="$(kb_fm_get "$f" id)"
            return 3
        fi
    done
    if hit="$(secret_scan "${P_CLAIM}"$'\n'"${body}")"; then
        warn "learn: not writing a proposal whose text looks like a secret (${hit}); check outcomes.tsv"
        return 1
    fi
    while :; do
        hex="$(kb_hash6 "$norm" "$n")" || { warn "learn: cannot hash the claim (git missing?)"; return 1; }
        id="K-$(printf '%s' "$TODAY" | tr -d '-')-${hex}"
        [[ -e "${KB}/items/${id}.md" || -e "${KB}/retired/${id}.md" ]] || break
        n=$((n + 2))
        (( n <= 12 )) || { warn "learn: cannot mint a unique ID"; return 1; }
    done
    src="file:${KB_REL}/outcomes.tsv"
    head="$(head_sha)"
    [[ -z "$head" ]] || src+="@${head}"
    ensure_kb
    tmp="$(mktemp "${KB}/items/.new.XXXXXX")" || return 1
    {
        echo "---"
        echo "id: ${id}"
        echo "type: proposal"
        echo "scope: project"
        echo "status: candidate"
        echo "claim: $(kb_quote "$P_CLAIM")"
        echo "evidence: observed"
        echo "source: $(kb_list_format --quote "$src")"
        echo "watch: []"
        echo "watch_blob: []"
        echo "falsifier: $(kb_quote "$P_FALSIFIER")"
        echo "author: kb-learn"
        echo "reviewer:"
        echo "captured_by: script:kb-learn"
        echo "created: ${TODAY}"
        echo "verified_at: ${TODAY}"
        echo "status_since: ${TODAY}"
        echo "review_by: $(review_by_for proposal "$TODAY")"
        echo "supersedes: []"
        echo "superseded_by:"
        echo "contradicts: []"
        echo "supports: []"
        echo "tags: [meta-learning, ${P_FAM}]"
        echo "proposal_kind: ${P_KIND}"
        [[ -z "$P_REVERTS" ]] || echo "reverts: ${P_REVERTS}"
        echo "metric: ${P_FAM}"
        echo "metric_key: $(kb_quote "$P_KEY")"
        echo "track_key: $(kb_quote "$P_TRACK")"
        echo "metric_n: ${P_N}"
        echo "metric_k: ${P_K}"
        echo "metric_before: ${P_BEFORE}"
        [[ -z "$P_AFTER" ]] || echo "metric_after: ${P_AFTER}"
        echo "threshold: ${P_THR}"
        echo "target: $(kb_quote "$P_TARGET")"
        echo "created_ts: $(kb_timestamp)"
        echo "---"
        printf '%s\n' "$body"
    } > "$tmp"
    mv "$tmp" "${KB}/items/${id}.md"
    kb_event "$KB" "$id" "-" candidate "learn:${P_FAM}" "$(kb_actor "$ROOT")"
    NEW_ID="$id"
    return 0
}

# set_followup <proposal-file> <text>: close the tracking of an adopted change
set_followup() {
    local f="$1" text="$2" st
    st="$(kb_fm_get "$f" status)"
    kb_fm_set "$f" followup "$(kb_quote "$(kb_oneline "$text")")"
    kb_fm_set "$f" followup_ts "$(kb_timestamp)"
    kb_event "$KB" "$(kb_fm_get "$f" id)" "$st" "$st" "followup:${text}" "$(kb_actor "$ROOT")"
}

# Print a planned proposal (dry run) or write it; LEARN_WRITES counts writes.
emit_proposal() {
    local body rc=0
    body="$(proposal_body)"
    if [[ "$LEARN_DRY" == "true" ]]; then
        echo "    would propose: ${P_CLAIM}"
        echo "      target: ${P_TARGET} (${P_WHERE})"
        if [[ -n "$P_DIFF" ]]; then printf '%s\n' "$P_DIFF" | sed 's/^/      | /'; else echo "      | ${P_TEXT}"; fi
        return 0
    fi
    write_proposal "$body" || rc=$?
    case "$rc" in
        0) LEARN_WRITES=$((LEARN_WRITES + 1)); echo "    proposed ${NEW_ID}: ${P_CLAIM}" ;;
        3) echo "    already proposed as ${NEW_ID}" ;;
        *) echo "    not proposed (see the message above)" ;;
    esac
    return "$rc"
}

learn_metric_line() {
    local tag fam key n k val st ws d1 refs
    IFS="$TAB" read -r tag fam key n k val st ws d1 refs <<EOF
$1
EOF
    [[ "$tag" == "M" ]] || return 0
    printf '  %s %s: %s of %s (%s) -> ' "$fam" "$(safe_text "$key" 90)" "$k" "$n" "$(pct "$val")"
    case "$st" in
        small-n) echo "n < ${UWS_KB_LEARN_MIN_N}: no proposal" ;;
        below) echo "within the threshold" ;;
        open:*) echo "over the threshold; already proposed (${st#open:})" ;;
        propose)
            echo "over the threshold"
            P_WSTART="$ws"
            if plan_proposal "$fam" "$key" "$n" "$k" "$val" "$d1" "$refs"; then
                emit_proposal || true
            else
                echo "    (no proposal template for this metric)"
            fi
            ;;
    esac
}

learn_track_line() {
    local tag id state n after before k f rc=0
    IFS="$TAB" read -r tag id state n after before k <<EOF
$1
EOF
    f="$(kb_item_path "$KB" "$id" || true)"
    [[ -n "$f" ]] || return 0
    case "$state" in
        pending)
            echo "  tracking ${id} ($(kb_fm_get "$f" metric), $(safe_text "$(kb_fm_get "$f" track_key)" 60)): ${n} of ${UWS_KB_LEARN_WINDOW} events since approval"
            ;;
        improved)
            if [[ "$LEARN_DRY" == "true" ]]; then
                echo "  ${id}: would record an improvement ($(pct "$before") -> $(pct "$after") over ${n} events)"
            else
                set_followup "$f" "improved $(fmt2 "$before") -> $(fmt2 "$after") over ${n} events"
                LEARN_WRITES=$((LEARN_WRITES + 1))
                echo "  ${id}: improved ($(pct "$before") -> $(pct "$after") over ${n} events); tracking closed"
            fi
            ;;
        not-improved)
            echo "  ${id}: did not improve ($(pct "$before") -> $(pct "$after") over ${n} events)"
            plan_revert "$f" "$n" "$k" "$after"
            emit_proposal || rc=$?
            if [[ "$LEARN_DRY" != "true" ]] && (( rc == 0 || rc == 3 )); then
                set_followup "$f" "revert-proposed:${NEW_ID}"
            fi
            ;;
    esac
}

cmd_learn() {
    LEARN_DRY=false
    LEARN_WRITES=0
    case "$#:${1:-}" in
        0:) ;;
        1:--dry-run) LEARN_DRY=true ;;
        *) die 2 "learn: use 'learn' or 'learn --dry-run'" ;;
    esac
    local v
    for v in UWS_KB_LEARN_MIN_N UWS_KB_LEARN_WINDOW UWS_KB_LEARN_REPEAT_FAILS; do
        if ! is_uint "${!v}" || (( ${!v} < 1 )); then die 2 "learn: ${v} must be a whole number >= 1"; fi
    done
    for v in UWS_KB_LEARN_ESCAPE_RATE UWS_KB_LEARN_CR_REJECT_RATE UWS_KB_LEARN_DISPROVEN_RATE; do
        [[ "${!v}" =~ ^(0(\.[0-9]+)?|1(\.0+)?|\.[0-9]+)$ ]] || die 2 "learn: ${v} must be a number from 0 to 1"
    done
    if [[ ! -d "$KB" ]]; then echo "No KB at ${KB#"${ROOT}"/}; nothing to learn."; return 0; fi
    case "$KB" in
        "$ROOT"/*) KB_REL="${KB#"${ROOT}"/}" ;;
        *) die 2 "learn: the KB (${KB}) must be inside the project so proposals can cite its outcomes.tsv" ;;
    esac
    local out="${KB}/outcomes.tsv"
    if [[ ! -s "$out" ]]; then
        echo "No outcomes recorded yet in ${KB_REL}/outcomes.tsv; nothing to learn."
        return 0
    fi
    local side results rc=0
    side="$(mktemp "${TMPDIR:-/tmp}/uws-kb-learn.XXXXXX")" || die 2 "learn: cannot create a temporary file"
    learn_side_table > "$side" || rc=$?
    if (( rc == 0 )); then
        results="$(KBSIDE="$side" KBW="$UWS_KB_LEARN_WINDOW" KBMIN="$UWS_KB_LEARN_MIN_N" \
            KBREP="$UWS_KB_LEARN_REPEAT_FAILS" KBTESC="$UWS_KB_LEARN_ESCAPE_RATE" \
            KBTCR="$UWS_KB_LEARN_CR_REJECT_RATE" KBTDIS="$UWS_KB_LEARN_DISPROVEN_RATE" \
            LC_ALL=C awk "${KB_AWK_UTF8}${KB_AWK_LEARN}" "$side" "$out" | LC_ALL=C sort)" || rc=$?
    fi
    rm -f "$side"
    (( rc == 0 )) || die 2 "learn: could not compute the metrics from ${KB_REL}/outcomes.tsv"

    echo "Meta-learning from ${KB_REL}/outcomes.tsv (counts, not causes; n >= ${UWS_KB_LEARN_MIN_N}; last ${UWS_KB_LEARN_WINDOW} samples)$([[ "$LEARN_DRY" == "true" ]] && echo ", dry run"):"
    local line any=false
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        case "$line" in
            N"$TAB"*) echo "  note: ${line#N"$TAB"}" ;;
            M"$TAB"*) any=true; learn_metric_line "$line" ;;
            T"$TAB"*) learn_track_line "$line" ;;
        esac
    done <<EOF
$results
EOF
    [[ "$any" == "true" ]] || echo "  no metric has data yet"
    echo "  r4-unused-share: not measured (R4 usage counts are not built yet; design section 17)"
    if [[ "$LEARN_DRY" == "true" ]]; then
        echo "(dry run: nothing written)"
    elif (( LEARN_WRITES > 0 )); then
        rebuild_stats_cache
        echo "Proposals are candidates: only the PI decides (uws kb proposals; uws kb approve|reject <ID>)."
    fi
    return 0
}

cmd_proposals() {
    [[ $# -eq 0 ]] || die 2 "proposals: takes no arguments"
    local f id st kind metric appr fu rr open="" tracking=""
    for f in "${KB}"/items/*.md "${KB}"/retired/*.md; do
        [[ -f "$f" ]] || continue
        [[ "$(kb_fm_get "$f" type)" == "proposal" ]] || continue
        id="$(kb_fm_get "$f" id)"; st="$(kb_fm_get "$f" status)"
        kind="$(kb_fm_get "$f" proposal_kind)"; kind="${kind:-change}"
        metric="$(kb_fm_get "$f" metric)"; metric="${metric:-manual}"
        appr="$(kb_fm_get "$f" approved_ts)"; fu="$(kb_fm_get "$f" followup_ts)"; rr="$(kb_fm_get "$f" retired_reason)"
        if [[ "$f" == "${KB}/items/"* && "$st" == "candidate" ]]; then
            open+="${id} [${metric}|${kind}] $(kb_fm_get "$f" claim)"$'\n'
            open+="    target: $(kb_fm_get "$f" target); details: uws kb show ${id}"$'\n'
        elif [[ "$kind" == "change" && "$metric" != "manual" && -n "$appr" && -z "$fu" && "$rr" != rejected* ]]; then
            tracking+="${id} [${metric}] approved ${appr%%T*}; uws kb learn checks it after ${UWS_KB_LEARN_WINDOW} events"$'\n'
        fi
    done
    if [[ -z "$open" ]]; then
        echo "No proposals waiting for the PI."
    else
        echo "Waiting for the PI (approving records acceptance and never applies the change):"
        printf '%s' "$open"
        echo "Decide in your own terminal: uws kb approve <ID> | uws kb reject <ID> \"<why>\""
    fi
    if [[ -n "$tracking" ]]; then
        echo "Adopted, being measured:"
        printf '%s' "$tracking"
    fi
    return 0
}

# ── lint / stats ────────────────────────────────────────────────────────────

cmd_lint() {
    local bad=0 f dir id st t ev k p pi
    pi="$(kb_pi_identity "$ROOT")"
    for dir in items retired; do
        for f in "${KB}/${dir}"/*.md; do
            [[ -f "$f" ]] || continue
            local base
            base="$(basename "$f" .md)"
            if [[ "$(head -1 "$f")" != "---" ]] || [[ "$(grep -c '^---$' "$f" || true)" -lt 2 ]]; then
                echo "I1 ${dir}/${base}.md: no front matter block"; bad=1; continue
            fi
            id="$(kb_fm_get "$f" id)"; st="$(kb_fm_get "$f" status)"
            t="$(kb_fm_get "$f" type)"; ev="$(kb_fm_get "$f" evidence)"
            for k in id type scope status claim author captured_by created verified_at review_by; do
                [[ -n "$(kb_fm_get "$f" "$k")" ]] || { echo "I1 ${base}: missing ${k}"; bad=1; }
            done
            [[ "$id" == "$base" ]] || { echo "I1 ${base}: id '${id}' does not match the file name"; bad=1; }
            word_in "$t" "$TYPES" || { echo "I1 ${base}: bad type '${t}'"; bad=1; }
            word_in "$st" "candidate trusted stale disputed retired" || { echo "I1 ${base}: bad status '${st}'"; bad=1; }
            if [[ "$dir" == "retired" && "$st" != "retired" ]] || [[ "$dir" == "items" && "$st" == "retired" ]]; then
                echo "I1 ${base}: status '${st}' does not match directory ${dir}/"; bad=1
            fi
            if [[ "$t" != "question" ]]; then
                word_in "$ev" "$EVIDENCES" || { echo "I1 ${base}: bad evidence '${ev}'"; bad=1; }
                [[ -n "$(kb_list_parse "$(kb_fm_raw "$f" source)")" ]] || { echo "I1 ${base}: no source"; bad=1; }
            fi
            [[ "$ev" != "verified" || -n "$(kb_fm_get "$f" check)" ]] || { echo "I1 ${base}: verified evidence without a check"; bad=1; }
            (( $(kb_bytes "$(kb_fm_get "$f" claim)") <= UWS_KB_CLAIM_BYTES )) || { echo "I1 ${base}: claim over ${UWS_KB_CLAIM_BYTES} bytes"; bad=1; }
            if [[ "$st" == "trusted" ]]; then
                # I2: sources resolve
                while IFS= read -r p; do
                    [[ -n "$p" ]] || continue
                    case "$p" in
                        file:*)
                            local fp="${p#file:}"; fp="${fp%@*}"
                            [[ "$fp" =~ :[0-9]+(-[0-9]+)?$ ]] && fp="${fp%:*}"
                            [[ -f "${ROOT}/${fp}" ]] || { echo "I2 ${base}: source file missing: ${fp}"; bad=1; } ;;
                        url:*)
                            grep -q '^>' "$f" || { echo "I2 ${base}: url source without a quoted line in the body"; bad=1; } ;;
                        *)
                            resolve_source "$p" >/dev/null 2>&1 || { echo "I2 ${base}: source does not resolve: ${p}"; bad=1; } ;;
                    esac
                done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" source)")
EOF
                # I3: no two trusted items contradict
                while IFS= read -r p; do
                    [[ -n "$p" && -f "${KB}/items/${p}.md" ]] || continue
                    if [[ "$(kb_fm_get "${KB}/items/${p}.md" status)" == "trusted" && "$base" < "$p" ]]; then
                        echo "I3 trusted items contradict: ${base} ${p}"; bad=1
                    fi
                done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" contradicts)")
EOF
                # I7 (PI decision D4): trusted means approved by the PI
                if [[ -n "$pi" && "$(kb_lower "$(kb_fm_get "$f" reviewer)")" != "$(kb_lower "$pi")" ]]; then
                    echo "I7 ${base}: trusted but reviewer is '$(kb_fm_get "$f" reviewer)', not the PI (${pi})"; bad=1
                fi
            fi
            # I4: supersedes targets are retired
            while IFS= read -r p; do
                [[ -n "$p" ]] || continue
                if [[ -f "${KB}/items/${p}.md" ]]; then echo "I4 ${base}: supersedes ${p}, which is not retired"; bad=1; fi
            done <<EOF
$(kb_list_parse "$(kb_fm_raw "$f" supersedes)")
EOF
        done
    done
    # I6: output budgets (search over every tag, and the session line)
    local tagwords out lines total maxl
    tagwords="$(for f in "${KB}"/items/*.md; do [[ -f "$f" ]] && kb_list_parse "$(kb_fm_raw "$f" tags)"; done | LC_ALL=C sort -u | head -20 | tr '\n' ' ')"
    if [[ -n "${tagwords// /}" ]]; then
        # shellcheck disable=SC2086
        out="$(search_lines "|candidate|trusted|stale|disputed|" "" "" "" $tagwords | budget "$UWS_KB_SEARCH_LIMIT")"
        lines="$(printf '%s' "$out" | grep -c . || true)"
        total="$(printf '%s\n' "$out" | LC_ALL=C wc -c | tr -d ' ')"
        maxl="$(printf '%s\n' "$out" | LC_ALL=C awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
        if (( lines > UWS_KB_SEARCH_LIMIT || total > UWS_KB_BRIEF_BYTES || maxl > UWS_KB_ITEM_BYTES )); then
            echo "I6 search output over budget (${lines} lines, ${total} bytes, longest ${maxl})"; bad=1
        fi
    fi
    local sl
    sl="$(kb_summary_line "$ROOT")"
    (( $(kb_bytes "$sl") <= 120 )) || { echo "I6 session line over 120 bytes"; bad=1; }
    if (( bad )); then return 1; fi
    echo "KB lint: OK"
}

cmd_stats() {
    local short=false
    [[ "${1:-}" == "--short" ]] && short=true
    if [[ ! -d "${KB}/items" && ! -d "${KB}/retired" ]]; then
        echo "No KB yet at ${KB#"${ROOT}"/} (add one: uws kb add ...)"
        return 0
    fi
    rebuild_stats_cache
    if [[ "$short" == "true" ]]; then kb_summary_line "$ROOT"; kb_proposals_line "$ROOT"; return 0; fi
    local t s x c r
    read -r t s x c r <<EOF
$(kb_counts "$KB")
EOF
    echo "KB ${KB#"${ROOT}"/}: $((t + s + x + c)) active (${t} trusted, ${s} stale, ${x} disputed, ${c} candidate), ${r} retired"
    local -a files=()
    local f
    for f in "${KB}"/items/*.md; do [[ -f "$f" ]] && files+=("$f"); done
    if [[ ${#files[@]} -gt 0 ]]; then
        awk "${KB_AWK_VALUES}"'
            function kb_emit() { ty[kb_unq(F["type"])]++; ev[kb_unq(F["evidence"]) == "" ? "none" : kb_unq(F["evidence"])]++ }
            '"${KB_AWK_ITEMS}"'
            END {
                n = 0; for (k in ty) keys[++n] = k
                for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (keys[j] < keys[i]) { t = keys[i]; keys[i] = keys[j]; keys[j] = t }
                printf "by type:"; for (i = 1; i <= n; i++) printf " %s=%d", keys[i], ty[keys[i]]; printf "\n"
                n = 0; for (k in ev) ekeys[++n] = k
                for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (ekeys[j] < ekeys[i]) { t = ekeys[i]; ekeys[i] = ekeys[j]; ekeys[j] = t }
                printf "by evidence:"; for (i = 1; i <= n; i++) printf " %s=%d", ekeys[i], ev[ekeys[i]]; printf "\n"
            }' "${files[@]}"
    fi
}

# ── main ────────────────────────────────────────────────────────────────────

main() {
    local verb="${1:-help}"
    shift 2>/dev/null || true
    case "$verb" in
        add) cmd_add "$@" ;;
        search) cmd_search "$@" ;;
        links) cmd_links "$@" ;;
        show) cmd_show "$@" ;;
        verify) cmd_verify "$@" ;;
        approve) cmd_approve "$@" ;;
        reject) cmd_reject "$@" ;;
        recommend) cmd_recommend "$@" ;;
        review) cmd_review "$@" ;;
        pi) cmd_pi "$@" ;;
        prune) cmd_prune "$@" ;;
        retire) cmd_retire "$@" ;;
        restore) cmd_restore "$@" ;;
        lint) cmd_lint "$@" ;;
        stats) cmd_stats "$@" ;;
        learn) cmd_learn "$@" ;;
        proposals) cmd_proposals "$@" ;;
        help|-h|--help) usage ;;
        *) die 2 "unknown verb '${verb}' (run: uws kb help)" ;;
    esac
}

main "$@"
