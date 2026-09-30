#!/bin/bash
#
# uws kb - project knowledge base (design: docs/design/knowledge-base.md)
#
# Usage: kb.sh <verb> [args]      (normally run as `uws kb <verb>`)
#
#   add --type T --claim "..." [--evidence E] [--source S]... [--check CMD]
#       [--watch PATH]... [--author A] [--tags a,b] [--supersedes ID]...
#       [--contradicts ID]... [--no-conflict] [--falsifier TEXT]
#       [--body TEXT] [--quote TEXT]
#                              create a candidate; prints its ID on stdout
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

TYPES="fact decision lesson anti-pattern question hypothesis proposal"
EVIDENCES="verified observed reported inferred"

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

# Retire an active item: move to retired/, set status and reason, log.
retire_item() {  # retire_item <id> <reason>
    local id="$1" reason="$2" src dst
    src="${KB}/items/${id}.md"
    [[ -f "$src" ]] || die 1 "not an active item: $id"
    dst="${KB}/retired/${id}.md"
    [[ -e "$dst" ]] && die 2 "retired/${id}.md already exists"
    move_file "$src" "$dst"
    kb_fm_set "$dst" retired_at "$TODAY"
    kb_fm_set "$dst" retired_reason "$(kb_quote "$(kb_oneline "$reason")")"
    set_status "$dst" retired "$reason"
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

cmd_add() {
    local type="" claim="" evidence="" check="" author="" tags_raw="" falsifier="" body="" quote=""
    local scope="project" no_conflict=false
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
        echo "---"
        [[ -n "$quote" ]] && printf '> %s\n\n' "$quote"
        [[ -n "$body" ]] && printf '%s\n' "$body"
    } > "$tmp"
    mv "$tmp" "$file"
    kb_event "$KB" "$id" "-" candidate "add" "$author"

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
    set_status "$f" trusted "approved-by-pi"
    rebuild_stats_cache
    echo "${id}: ${st} -> trusted (approved by ${pi})"
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
    if [[ "$short" == "true" ]]; then kb_summary_line "$ROOT"; return 0; fi
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
        help|-h|--help) usage ;;
        *) die 2 "unknown verb '${verb}' (run: uws kb help)" ;;
    esac
}

main "$@"
