#!/bin/bash
#
# Knowledge base (KB) library - shared by scripts/kb.sh and the SessionStart
# hook (scripts/lib/hook_context.sh). Design: docs/design/knowledge-base.md.
#
# One Markdown file per item under <kb>/items/<id>.md (retired items under
# <kb>/retired/), with flat `key: value` YAML front matter. Lists are one-line
# flow sequences (`[a, b]`; `source` elements are always double-quoted), so the
# files parse with awk alone: yq is optional in UWS and is not used here.
#
# Constraints: bash 3.2 and BSD awk/sed/date (CLAUDE.md "Portability rules").
# Sourcing this file has no side effects and never changes shell options, so
# the read-only SessionStart hook can use it.
#
# Public functions:
#   kb_project_root, kb_dir, kb_today, kb_timestamp, kb_date_add, kb_days_between
#   kb_bytes, kb_quote, kb_fm_get, kb_fm_raw, kb_fm_set, kb_fm_del
#   kb_list_parse, kb_list_format, kb_normalize_claim, kb_hash6
#   kb_agent_context, kb_git_email, kb_actor, kb_pi_identity, kb_event
#   kb_item_path, kb_counts, kb_summary_line, kb_open_proposals, kb_proposals_line
#   Meta-learning outcomes (design section 6.2): kb_outcome, kb_outcomes_enabled, kb_head_ref,
#   kb_agent_model, kb_current_phase, kb_cr_model, kb_record_gate_fail,
#   kb_record_gate_pass
#   Increment 2 (design section 18): kb_global_memory_dir, kb_global_dir, kb_global_ready,
#   kb_guarded, kb_session_id, kb_usage_record, kb_is_global_id, kb_scan_scope_args,
#   kb_git_env_clear, kb_shell_quote

if [[ "${_UWS_KB_UTILS_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UWS_KB_UTILS_LOADED="true"
_KB_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UWS_KB_ITEM_BYTES="${UWS_KB_ITEM_BYTES:-200}"
UWS_KB_BRIEF_BYTES="${UWS_KB_BRIEF_BYTES:-1000}"
UWS_KB_SEARCH_LIMIT="${UWS_KB_SEARCH_LIMIT:-5}"
# shellcheck disable=SC2034  # used by scripts/kb.sh
UWS_KB_CLAIM_BYTES=240

# awk date helpers (proleptic Gregorian day numbers; H. Hinnant's
# days_from_civil / civil_from_days). POSIX awk has no mktime, and BSD `date`
# cannot do `-d`, so all date arithmetic happens here.
# shellcheck disable=SC2016
KB_AWK_DATE='
function kb_dfc(y, m, d,    era, yoe, doy, doe) {
    y -= (m <= 2)
    era = int((y >= 0 ? y : y - 399) / 400)
    yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    return era * 146097 + doe - 719468
}
function kb_cfd(z,    era, doe, yoe, y, doy, mp, d, m) {
    z += 719468
    era = int((z >= 0 ? z : z - 146096) / 146097)
    doe = z - era * 146097
    yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
    y = yoe + era * 400
    doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
    mp = int((5 * doy + 2) / 153)
    d = doy - int((153 * mp + 2) / 5) + 1
    m = mp + (mp < 10 ? 3 : -9)
    y += (m <= 2)
    return sprintf("%04d-%02d-%02d", y, m, d)
}
function kb_days(s) {
    if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return -1
    return kb_dfc(substr(s, 1, 4) + 0, substr(s, 6, 2) + 0, substr(s, 9, 2) + 0)
}
'

# awk helpers for front-matter values: unquote a scalar, split a flow list.
# shellcheck disable=SC2016
KB_AWK_VALUES='
function kb_unq(v,    q, out, i, c) {
    sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    q = substr(v, 1, 1)
    if (q == "\"" && length(v) >= 2 && substr(v, length(v), 1) == "\"") {
        v = substr(v, 2, length(v) - 2); out = ""
        for (i = 1; i <= length(v); i++) {
            c = substr(v, i, 1)
            if (c == "\\" && i < length(v)) { i++; c = substr(v, i, 1) }
            out = out c
        }
        return out
    }
    if (q == "'"'"'" && length(v) >= 2 && substr(v, length(v), 1) == "'"'"'") {
        v = substr(v, 2, length(v) - 2); gsub(/'"''"'/, "'"'"'", v); return v
    }
    return v
}
function kb_list(v, arr,    n, i, c, cur, inq, quoted) {
    sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    if (substr(v, 1, 1) != "[") { if (v == "") return 0; arr[1] = kb_unq(v); return 1 }
    v = substr(v, 2); sub(/\][ \t]*$/, "", v)
    n = 0; cur = ""; inq = 0; quoted = 0
    for (i = 1; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (inq) {
            if (c == "\\" && i < length(v)) { i++; cur = cur substr(v, i, 1) }
            else if (c == "\"") inq = 0
            else cur = cur c
        } else if (c == "\"") {
            # spacing before an opening quote is not part of the element
            if (!quoted && cur ~ /^[ \t]*$/) cur = ""
            inq = 1; quoted = 1
        }
        else if (c == ",") {
            if (!quoted) { sub(/^[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur) }
            if (cur != "" || quoted) arr[++n] = cur
            cur = ""; quoted = 0
        } else if (!quoted) cur = cur c
    }
    if (!quoted) { sub(/^[ \t]+/, "", cur); sub(/[ \t]+$/, "", cur) }
    if (cur != "" || quoted) arr[++n] = cur
    return n
}
'

# awk main loop that parses item files: front matter into F[], body into BODY,
# then calls the program-supplied `function kb_emit()` once per item. Items
# without a front matter block get F["_invalid"] = 1.
# shellcheck disable=SC2016,SC2034  # awk source, used by scripts/kb.sh
KB_AWK_ITEMS='
function kb_finish() { if (FILE != "") { if (ST < 2) F["_invalid"] = 1; kb_emit() } }
FNR == 1 { kb_finish(); split("", F); BODY = ""; FILE = FILENAME; ST = 0
           if ($0 == "---") { ST = 1; next } }
ST == 1 && $0 == "---" { ST = 2; next }
ST == 1 { k = $0; sub(/:.*/, "", k); v = $0
          if (index(v, ":") == 0) { F["_badline"] = $0; next }
          sub(/^[^:]*:[ \t]*/, "", v); F[k] = v; next }
ST == 2 { BODY = BODY " " $0 }
END { kb_finish() }
'

# Project root: parent of WORKFLOW_DIR, else the git top level, else $PWD.
kb_project_root() {
    if [[ -n "${WORKFLOW_DIR:-}" && -d "${WORKFLOW_DIR}" ]]; then
        (cd "${WORKFLOW_DIR}/.." && pwd)
        return 0
    fi
    local top
    top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$top" ]]; then printf '%s\n' "$top"; else pwd; fi
}

# KB root: UWS_KB_DIR (absolute, or relative to the project root), default docs/kb.
# Arguments: $1 - project root (optional; computed when absent)
kb_dir() {
    local root="${1:-}" d="${UWS_KB_DIR:-docs/kb}"
    [[ -n "$root" ]] || root="$(kb_project_root)"
    case "$d" in
        /*) printf '%s\n' "$d" ;;
        *)  printf '%s\n' "${root}/${d}" ;;
    esac
}

# Today as YYYY-MM-DD; UWS_KB_NOW (same format) fakes the clock for tests.
kb_today() {
    if [[ -n "${UWS_KB_NOW:-}" ]]; then
        if [[ "$UWS_KB_NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            printf '%s\n' "$UWS_KB_NOW"
            return 0
        fi
        echo "uws kb: ignoring UWS_KB_NOW='${UWS_KB_NOW}' (want YYYY-MM-DD)" >&2
    fi
    date +%Y-%m-%d
}

# UTC timestamp for events.tsv (midnight of UWS_KB_NOW when the clock is faked).
kb_timestamp() {
    if [[ -n "${UWS_KB_NOW:-}" && "$UWS_KB_NOW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        printf '%sT00:00:00Z\n' "$UWS_KB_NOW"
    else
        date -u +%Y-%m-%dT%H:%M:%SZ
    fi
}

# kb_date_add <YYYY-MM-DD> <days>  -> YYYY-MM-DD
kb_date_add() {
    awk -v s="$1" -v n="$2" "${KB_AWK_DATE}"'BEGIN { d = kb_days(s); if (d < 0) exit 1; print kb_cfd(d + n) }'
}

# kb_days_between <from> <to> -> integer days (to - from); empty when a date is invalid
kb_days_between() {
    awk -v a="$1" -v b="$2" "${KB_AWK_DATE}"'BEGIN { x = kb_days(a); y = kb_days(b); if (x < 0 || y < 0) exit 1; print y - x }'
}

# Byte length, locale-independent
kb_bytes() {
    local LC_ALL=C
    printf '%s' "${#1}"
}

# YAML double-quoted scalar: escape backslash and double quote.
kb_quote() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# Raw front-matter value of <key> (quotes kept). Prints nothing when absent.
kb_fm_raw() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    KBK="$key" awk '
        NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        { k = $0; sub(/:.*/, "", k)
          if (k == ENVIRON["KBK"]) { v = $0; sub(/^[^:]*:[ \t]*/, "", v); print v; exit } }
    ' "$file"
}

# Front-matter scalar with one level of YAML quoting removed.
kb_fm_get() {
    local raw
    raw="$(kb_fm_raw "$1" "$2")"
    [[ -n "$raw" ]] || return 0
    KBV="$raw" awk "${KB_AWK_VALUES}"'BEGIN { printf "%s", kb_unq(ENVIRON["KBV"]) }'
}

# kb_fm_set <file> <key> <raw-value>: replace the key's line, or insert it
# before the closing `---`. The value is written verbatim (quote it first with
# kb_quote / kb_list_format). Atomic: temp file in the same directory + mv.
kb_fm_set() {
    local file="$1" key="$2" val="$3" tmp
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    if KBK="$key" KBV="$val" awk '
        BEGIN { k = ENVIRON["KBK"]; v = ENVIRON["KBV"]; line = (v == "" ? k ":" : k ": " v) }
        NR == 1 && $0 == "---" { infm = 1; print; next }
        infm && $0 == "---" { if (!done) print line; done = 1; infm = 0; print; next }
        infm { kk = $0; sub(/:.*/, "", kk); if (kk == k) { if (!done) print line; done = 1; next } }
        { print }
    ' "$file" > "$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}

# kb_fm_del <file> <key>: drop the key's line from the front matter.
kb_fm_del() {
    local file="$1" key="$2" tmp
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    if KBK="$key" awk '
        NR == 1 && $0 == "---" { infm = 1; print; next }
        infm && $0 == "---" { infm = 0; print; next }
        infm { kk = $0; sub(/:.*/, "", kk); if (kk == ENVIRON["KBK"]) next }
        { print }
    ' "$file" > "$tmp"; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Print the elements of a raw flow list, one per line.
kb_list_parse() {
    KBV="$1" awk "${KB_AWK_VALUES}"'BEGIN { n = kb_list(ENVIRON["KBV"], a); for (i = 1; i <= n; i++) print a[i] }'
}

# kb_list_format [--quote] elem... -> "[a, b]" ("[]" when empty)
kb_list_format() {
    local quote=false out="" e
    if [[ "${1:-}" == "--quote" ]]; then quote=true; shift; fi
    for e in "$@"; do
        [[ -n "$out" ]] && out+=", "
        if [[ "$quote" == "true" ]]; then out+="$(kb_quote "$e")"; else out+="$e"; fi
    done
    printf '[%s]' "$out"
}

# Normalised claim for duplicate detection (R7): lower case, whitespace
# collapsed, trailing punctuation dropped.
kb_normalize_claim() {
    printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -s '[:space:]' ' ' \
        | sed -e 's/^ //' -e 's/ $//' -e 's/[.!?;:,]*$//'
}

# First N (default 6) hex digits of the SHA-1 of the text. git is a UWS
# dependency on every platform (sha1sum is not on macOS, shasum is Perl), so
# the hash is `git hash-object`: SHA-1 of the text framed as a git blob.
kb_hash6() {
    local n="${2:-6}" h
    h="$(printf '%s' "$1" | git hash-object --stdin 2>/dev/null || true)"
    [[ -n "$h" ]] || return 1
    printf '%s\n' "${h:0:$n}"
}

# Succeeds (and prints the variable name) when the process runs inside an AI
# agent: Claude Code sets CLAUDECODE=1 and CLAUDE_CODE_ENTRYPOINT in the
# environment of every tool call it runs; UWS_AGENT is set by UWS dispatch
# wrappers; AI_AGENT / GEMINI_CLI / CODEX_SANDBOX by other agent CLIs.
kb_agent_context() {
    local v
    for v in CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_CHILD_SESSION AI_AGENT UWS_AGENT GEMINI_CLI CODEX_SANDBOX; do
        if [[ -n "${!v:-}" ]]; then
            printf '%s\n' "$v"
            return 0
        fi
    done
    return 1
}

# git user.email of the project repository (empty when unset)
kb_git_email() {
    git -C "${1:-.}" config user.email 2>/dev/null || true
}

# Actor recorded in events.tsv: "agent:<name>" inside an agent, else the git
# e-mail, else $USER.
kb_actor() {
    local root="${1:-.}" e
    if kb_agent_context >/dev/null; then
        printf 'agent:%s\n' "${UWS_AGENT:-${AI_AGENT:-claude-code}}"
        return 0
    fi
    e="$(kb_git_email "$root")"
    printf '%s\n' "${e:-${USER:-unknown}}"
}

# The PI identity (an e-mail). `kb: { pi: ... }` in .workflow/config.yaml is
# authoritative; UWS_KB_PI is used only when the config does not set it.
# The global KB keeps its own PI in <global kb>/config.yaml ($2).
# Arguments: $1 - project root, $2 - config file (optional)
kb_pi_identity() {
    local root="${1:-.}" cfg="${2:-}" v=""
    [[ -n "$cfg" ]] || cfg="${WORKFLOW_DIR:-${root}/.workflow}/config.yaml"
    if [[ -f "$cfg" ]]; then
        v="$(awk '
            /^[^[:space:]#]/ { insec = ($0 ~ /^kb:/); next }
            insec && /^[[:space:]]+pi:/ { sub(/^[[:space:]]+pi:[[:space:]]*/, ""); sub(/[[:space:]]*(#.*)?$/, ""); print; exit }
        ' "$cfg" 2>/dev/null || true)"
        case "$v" in
            \"*\") v="${v#\"}"; v="${v%\"}" ;;
            \'*\') v="${v#\'}"; v="${v%\'}" ;;
        esac
    fi
    [[ "$v" == "null" ]] && v=""
    [[ -z "$v" ]] && v="${UWS_KB_PI:-}"
    printf '%s\n' "$v"
}

# Lower-case a string (bash 3.2 has no case-modification expansion)
kb_lower() {
    printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

# Replace tabs, newlines and other control characters with spaces.
kb_oneline() {
    printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' '
}

# kb_event <kbdir> <id> <from> <to> <reason> <actor>: append one row to
# events.tsv. One printf of a short line to an O_APPEND file is a single
# write, so concurrent writers do not interleave within a row.
kb_event() {
    local d="$1" tab
    tab="$(printf '\t')"
    printf '%s%s%s%s%s%s%s%s%s%s%s\n' "$(kb_timestamp)" "$tab" "$2" "$tab" "${3:--}" "$tab" \
        "${4:--}" "$tab" "$(kb_oneline "$5")" "$tab" "$(kb_oneline "$6")" >> "${d}/events.tsv"
}

# Path of an item by ID (items/ first, then retired/); prints nothing when absent.
kb_item_path() {
    local d="$1" id="$2"
    [[ "$id" =~ ^K-[0-9]{8}-[0-9a-f]{6,12}$ ]] || return 1
    if [[ -f "${d}/items/${id}.md" ]]; then printf '%s\n' "${d}/items/${id}.md"; return 0; fi
    if [[ -f "${d}/retired/${id}.md" ]]; then printf '%s\n' "${d}/retired/${id}.md"; return 0; fi
    return 1
}

# Counts of active items by status: "trusted stale disputed candidate retired"
kb_counts() {
    local d="$1" retired=0 f
    local t=0 s=0 x=0 c=0
    if [[ -d "${d}/retired" ]]; then
        for f in "${d}"/retired/*.md; do [[ -f "$f" ]] && retired=$((retired + 1)); done
    fi
    if [[ -d "${d}/items" ]]; then
        set -- "${d}"/items/*.md
        if [[ -f "$1" ]]; then
            read -r t s x c <<EOF
$(awk '
    FNR == 1 { infm = ($0 == "---"); next }
    infm && $0 == "---" { infm = 0; next }
    infm && /^status:/ { v = $0; sub(/^status:[ \t]*/, "", v); gsub(/"/, "", v); n[v]++ }
    END { printf "%d %d %d %d\n", n["trusted"], n["stale"], n["disputed"], n["candidate"] }
' "$@" 2>/dev/null || echo "0 0 0 0")
EOF
        fi
    fi
    printf '%s %s %s %s %s\n' "$t" "$s" "$x" "$c" "$retired"
}

# _kb_hint <uws arguments...>: the command in the byte-capped session lines below: the
# plugin's /uws:kb ... (its bin/ comes last on PATH, so a bare `uws` there may be an older
# install; lib/uws_ui.sh), else `uws kb ...` (a path would not fit the 120-byte budget)
_kb_hint() {
    if ! declare -f uws_in_plugin > /dev/null 2>&1; then
        # shellcheck source=uws_ui.sh
        source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/uws_ui.sh" 2>/dev/null || { echo "uws $*"; return 0; }
    fi
    if uws_in_plugin; then uws_hint "$@"; else echo "uws $*"; fi
}

# Tier-0 session line (<= 120 bytes), or nothing when the project has no KB.
# Read-only: safe for the SessionStart hook.
# Arguments: $1 - project root
kb_summary_line() {
    local root="$1" d t s x c
    d="$(kb_dir "$root")"
    [[ -d "${d}/items" || -d "${d}/retired" ]] || return 0
    read -r t s x c _ <<EOF
$(kb_counts "$d")
EOF
    printf 'KB: %s trusted, %s stale, %s disputed, %s to review. Search: %s (skill uws-kb)\n' \
        "$t" "$s" "$x" "$c" "$(_kb_hint kb search '<words>')"
}

# Number of proposals (type proposal, status candidate) waiting for the PI.
# Read-only: safe for the SessionStart hook.
kb_open_proposals() {
    local d="$1"
    [[ -d "${d}/items" ]] || { echo 0; return 0; }
    set -- "${d}"/items/*.md
    [[ -f "$1" ]] || { echo 0; return 0; }
    awk '
        function tally() { if (ty == "proposal" && st == "candidate") n++ }
        FNR == 1 { if (seen) tally(); seen = 1; ty = ""; st = ""; infm = ($0 == "---"); next }
        infm && $0 == "---" { infm = 0; next }
        infm && /^type:/ { ty = $0; sub(/^type:[ \t]*/, "", ty); gsub(/["\047 \t]/, "", ty) }
        infm && /^status:/ { st = $0; sub(/^status:[ \t]*/, "", st); gsub(/["\047 \t]/, "", st) }
        END { if (seen) tally(); print n + 0 }
    ' "$@" 2>/dev/null || echo 0
}

# Second tier-0 line, printed only when meta-learning proposals wait for the
# PI (nothing otherwise). Read-only. Arguments: $1 - project root
kb_proposals_line() {
    local d n
    d="$(kb_dir "$1")"
    n="$(kb_open_proposals "$d")"
    [[ "$n" =~ ^[0-9]+$ ]] || return 0
    (( n > 0 )) || return 0
    if (( n == 1 )); then
        printf 'KB: 1 meta-learning proposal awaits the PI (%s).\n' "$(_kb_hint kb proposals)"
    else
        printf 'KB: %s meta-learning proposals await the PI (%s).\n' "$n" "$(_kb_hint kb proposals)"
    fi
}

# ── Meta-learning outcomes (design section 6.2) ─────────────────────────────
#
# <kb>/outcomes.tsv is an append-only, tracked log of what happened to UWS's
# own process. Only scripts write it, through kb_outcome. One row per event,
# no header, 8 tab-separated columns:
#
#   ts  event  phase  role  model  subject  result  ref
#
#   event        phase          role    model  subject          result                          ref
#   gate_fail    <m>:<failed>   -       -      <m>:<target>|-   reason text (- if none)          HEAD
#   gate_pass    <m>:<left>     -       -      <m>:<entered>    <done>/<total>[ forced|ungated]  HEAD
#   cr_decision  <m>:<phase>|-  agent   model  CR summary       approved | rejected[: reason]    CR ID
#   dispatch     <m>:<phase>    agent   model  target artifact  dispatched | collected          HEAD | CR ID
#   escape       <m>:<phase>    author  -      lesson item ID   the lesson's claim              HEAD
#   kb_retire    -              author  -      retired item ID  <code> evidence=E captured_by=C from=S type=T  related item | -
#
# <m> is sdlc or research; model is the agent file's `model:` front matter.
# Fields are TSV-escaped (backslash, tab, newline and CR become \\ \t \n \r;
# other control characters become spaces), an empty field is "-", and free
# text is capped at UWS_KB_OUTCOME_FIELD_BYTES (500) bytes.
# `uws kb learn` (scripts/kb.sh) is the only reader.

KB_OUTCOME_EVENTS=" gate_fail gate_pass cr_decision dispatch escape kb_retire "

# Succeeds when the project has a KB directory, i.e. outcomes are recorded.
# Callers check it first so projects without a KB pay for nothing else.
kb_outcomes_enabled() {
    local root d
    root="$(kb_project_root 2>/dev/null)" || return 1
    [[ -n "$root" ]] || return 1
    d="$(kb_dir "$root" 2>/dev/null)" || return 1
    [[ -n "$d" && -d "$d" ]] || return 1
    ! kb_guarded "$d"
}

# kb_outcome <event> <phase> <role> <model> <subject> <result> <ref>
# Append one row. Best effort by design: a no-op when the project has no KB
# directory, and a failure prints one line on stderr and still returns 0, so
# a caller under `set -e` never stops or changes its exit code because of it.
# One awk process writes the whole row with a single printf to an O_APPEND file.
kb_outcome() {
    local ev="${1:-}" root d
    root="$(kb_project_root 2>/dev/null)" || root=""
    [[ -n "$root" ]] || return 0
    d="$(kb_dir "$root" 2>/dev/null)" || d=""
    [[ -n "$d" && -d "$d" ]] || return 0
    kb_guarded "$d" && return 0
    case "$KB_OUTCOME_EVENTS" in
        *" ${ev} "*) ;;
        *) echo "uws: not recording unknown outcome event '${ev}'" >&2; return 0 ;;
    esac
    if ! KBO1="$(kb_timestamp)" KBO2="$ev" KBO3="${2:-}" KBO4="${3:-}" KBO5="${4:-}" \
         KBO6="${5:-}" KBO7="${6:-}" KBO8="${7:-}" KBMAX="${UWS_KB_OUTCOME_FIELD_BYTES:-500}" \
         LC_ALL=C awk '
        function utf8_whole(s,    n, i, c, need) {   # drop a cut-off UTF-8 sequence at the end
            n = length(s)
            for (i = n; i > 0 && i > n - 4; i--) {
                c = substr(s, i, 1)
                if (c < "\200") return s
                if (c >= "\300") {
                    need = (c >= "\360") ? 4 : ((c >= "\340") ? 3 : 2)
                    return (n - i + 1 < need) ? substr(s, 1, i - 1) : s
                }
            }
            return s
        }
        function esc(s,    out, i, n, c, cut) {
            out = ""; n = length(s); cut = 0
            for (i = 1; i <= n; i++) {
                if (i > max) { cut = 1; break }
                c = substr(s, i, 1)
                if (c == "\\") c = "\\\\"
                else if (c == "\t") c = "\\t"
                else if (c == "\n") c = "\\n"
                else if (c == "\r") c = "\\r"
                else if (c < " " || c == "\177") c = " "
                out = out c
            }
            if (cut) out = utf8_whole(out) "..."
            return (out == "" ? "-" : out)
        }
        BEGIN {
            max = ENVIRON["KBMAX"] + 0; if (max < 16) max = 16
            row = ENVIRON["KBO1"]
            for (k = 2; k <= 8; k++) row = row "\t" esc(ENVIRON["KBO" k])
            printf "%s\n", row
        }' >> "${d}/outcomes.tsv"; then
        echo "uws: could not record the '${ev}' outcome in ${d}/outcomes.tsv (continuing)" >&2
    fi
    return 0
}

# Short HEAD commit of a repository, or "-" (no repository or no commit yet).
kb_head_ref() {
    local h
    h="$(git -C "${1:-.}" rev-parse --short HEAD 2>/dev/null || true)"
    printf '%s\n' "${h:--}"
}

# Model of a UWS subagent, from the `model:` front matter of uws-<role>.md:
# the project's .claude/agents first, then the UWS installation (the repo's
# .claude/agents, or the plugin's agents/). Prints "unknown" when not found.
# Arguments: $1 - role (e.g. implementer), $2 - project root (optional)
kb_agent_model() {
    local role="${1:-}" root="${2:-}" f m=""
    if [[ ! "$role" =~ ^[A-Za-z0-9._-]+$ ]]; then echo unknown; return 0; fi
    [[ -n "$root" ]] || root="$(kb_project_root)"
    for f in "${root}/.claude/agents/uws-${role}.md" \
             "${_KB_UTILS_DIR}/../../.claude/agents/uws-${role}.md" \
             "${_KB_UTILS_DIR}/../../agents/uws-${role}.md"; do
        [[ -f "$f" ]] || continue
        m="$(kb_fm_get "$f" model 2>/dev/null || true)"
        [[ -n "$m" ]] && break
    done
    printf '%s\n' "${m:-unknown}"
}

# The active methodology phase as "<m>:<phase>" (sdlc first, as orchestrate.sh
# resolves it), or "-". Reads $WORKFLOW_DIR/state.yaml; quoted (sed) and
# unquoted (yq) scalars both work.
kb_current_phase() {
    local state m v
    state="${WORKFLOW_DIR:-$(kb_project_root)/.workflow}/state.yaml"
    [[ -f "$state" ]] || { echo "-"; return 0; }
    for m in sdlc research; do
        v="$(KBK="${m}_phase" awk '
            index($0, ENVIRON["KBK"] ":") == 1 {
                v = substr($0, length(ENVIRON["KBK"]) + 2); gsub(/^[ \t]+|[ \t]+$/, "", v)
                gsub(/^["\047]|["\047]$/, "", v); print v; exit
            }' "$state" 2>/dev/null || true)"
        if [[ -n "$v" && "$v" != "null" ]]; then printf '%s:%s\n' "$m" "$v"; return 0; fi
    done
    echo "-"
}

# Model recorded when a change request was collected (the `dispatch` row with
# result `collected` and ref <CR ID>); falls back to the agent file's model.
# Arguments: $1 - CR ID, $2 - role
kb_cr_model() {
    local cr="$1" role="$2" d m=""
    d="$(kb_dir "$(kb_project_root)")"
    if [[ -f "${d}/outcomes.tsv" ]]; then
        m="$(KBCR="$cr" awk -F '\t' '$2 == "dispatch" && $7 == "collected" && $8 == ENVIRON["KBCR"] { m = $5 } END { print m }' \
            "${d}/outcomes.tsv" 2>/dev/null || true)"
    fi
    [[ -n "$m" && "$m" != "-" ]] || m="$(kb_agent_model "$role")"
    printf '%s\n' "$m"
}

# kb_record_gate_fail <methodology> <failed-phase> <target-phase|""> <reason>
# Called by `sdlc.sh fail` and `research.sh reject`.
kb_record_gate_fail() {
    local m="$1" from="$2" to="${3:-}" reason="${4:-}"
    kb_outcomes_enabled || return 0
    kb_outcome gate_fail "${m}:${from}" - - "${to:+${m}:${to}}" "$reason" "$(kb_head_ref "$(kb_project_root)")"
}

# kb_record_gate_pass <methodology> <left-phase> <entered-phase> <total> [--force]
# Called by `sdlc.sh next` / `research.sh next` after a transition. done comes
# from the methodology_progress ledger (workflow_routing.sh); "ungated" marks a
# pass with no goal declared (the deliverable gate was not active).
kb_record_gate_pass() {
    local m="$1" from="$2" to="$3" total="${4:-0}" force="${5:-}" done="-" result
    kb_outcomes_enabled || return 0
    total="$(printf '%s' "$total" | tr -d '[:space:]')"
    if declare -f _mp_done_count >/dev/null 2>&1; then
        done="$(_mp_done_count "$m" "$from" 2>/dev/null || true)"
        [[ "$done" =~ ^[0-9]+$ ]] || done="-"
    fi
    result="${done}/${total:-0}"
    if [[ "$force" == "--force" ]]; then
        result+=" forced"
    elif declare -f gate_enabled >/dev/null 2>&1 && ! gate_enabled 2>/dev/null; then
        result+=" ungated"
    fi
    kb_outcome gate_pass "${m}:${from}" - - "${m}:${to}" "$result" "$(kb_head_ref "$(kb_project_root)")"
}

# ── Increment 2: global KB, test-suite guard, usage log (design section 18) ──

# Directory of the cross-project memory: UWS_GLOBAL_MEMORY_DIR, else
# global_memory_dir in ~/.config/uws/config.yaml, else ~/uws-global-knowledge
# (the chain of uws_resolve_global_memory_dir in uws_config.sh). That library
# changes shell options when sourced, so it runs in a subshell here.
kb_global_memory_dir() {
    if [[ -n "${UWS_GLOBAL_MEMORY_DIR:-}" ]]; then
        printf '%s\n' "$UWS_GLOBAL_MEMORY_DIR"
        return 0
    fi
    local d
    d="$( ( source "${_KB_UTILS_DIR}/uws_config.sh" >/dev/null 2>&1 && uws_resolve_global_memory_dir ) 2>/dev/null || true )"
    printf '%s\n' "${d:-${HOME}/uws-global-knowledge}"
}

# The global KB root: <global memory dir>/kb (design 4.5)
kb_global_dir() {
    printf '%s/kb\n' "$(kb_global_memory_dir)"
}

# kb_git_env_clear: unset the variables that point git at another repository
# than the one around the directory it runs in (GIT_DIR, GIT_WORK_TREE,
# GIT_INDEX_FILE, ...: `git rev-parse --local-env-vars`), as git's own scripts
# do. git exports GIT_DIR to hooks (absolute in a worktree), and with it set
# `git -C <any dir> rev-parse --show-toplevel` prints <any dir>. Changes the
# caller's environment: call it in a subshell, or in a process that works on
# the global KB only.
kb_git_env_clear() {
    # shellcheck disable=SC2046
    unset $(git rev-parse --local-env-vars 2>/dev/null)
    return 0
}

# Succeeds when <dir> exists and is the top level of its own git repository
# (design risk 13: global writes are refused otherwise, so every change to the
# cross-project KB stays auditable and reversible in git). An inherited
# GIT_DIR is ignored (kb_git_env_clear, in the command substitution's subshell).
kb_global_ready() {
    local d="$1" top real
    [[ -n "$d" && -d "$d" ]] || return 1
    top="$(kb_git_env_clear; git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ -n "$top" ]] || return 1
    real="$(cd "$d" && pwd -P)" || return 1
    top="$(cd "$top" && pwd -P)" || return 1
    [[ "$top" == "$real" ]]
}

# Succeeds when writes into the KB at <dir> must be refused because the test
# suite is running: tests/helpers/test_helper.bash exports UWS_KB_GUARD_ROOT
# (the UWS source checkout), and a KB inside that directory belongs to the
# real project, not to a test fixture. A test that means to write there opts
# in with UWS_KB_ALLOW_GUARDED_WRITE=1. Without UWS_KB_GUARD_ROOT this never
# refuses, so projects (UWS itself included) are unaffected outside the tests.
kb_guarded() {
    local g="${UWS_KB_GUARD_ROOT:-}" p="${1:-}"
    [[ -n "$g" && -n "$p" ]] || return 1
    [[ "${UWS_KB_ALLOW_GUARDED_WRITE:-}" == "1" ]] && return 1
    g="$(cd "$g" 2>/dev/null && pwd -P)" || return 1
    while [[ ! -d "$p" && "$p" == */* ]]; do p="${p%/*}"; done
    [[ -n "$p" ]] || p="/"
    p="$(cd "$p" 2>/dev/null && pwd -P)" || return 1
    case "${p}/" in
        "${g}/"*) return 0 ;;
    esac
    return 1
}

# The session an item retrieval belongs to (R4 counts sessions): UWS_KB_SESSION,
# else Claude Code's CLAUDE_CODE_SESSION_ID, else the calendar day
# ("day-<date>", a terminal user's working day). Only [A-Za-z0-9._:-], at most
# 64 bytes.
kb_session_id() {
    local s="${UWS_KB_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}"
    [[ -n "$s" ]] || s="day-$(kb_today)"
    printf '%s' "$s" | LC_ALL=C tr -c 'A-Za-z0-9._:-' '_' | cut -c1-64
}

# kb_usage_record <kb-dir> <via> <id>...: append one row per retrieved item to
# <kb-dir>/.cache/usage.tsv (gitignored, so usage is per machine; design 5.6):
#   ts  session  id  via            (via: search | show | task)
# The id "-" records that the KB was searched in this session without naming an
# item, so a session whose searches found nothing still counts for R4.
# Best effort: a no-op when the KB has no items directory or is guarded, and a
# failure prints one line on stderr and returns 0.
kb_usage_record() {
    local d="${1:-}" via="${2:-search}" ts sess id rows="" tab
    [[ $# -ge 3 && -d "${d}/items" ]] || return 0
    shift 2
    kb_guarded "$d" && return 0
    [[ "$via" =~ ^[a-z-]+$ ]] || via="search"
    ts="$(kb_timestamp)"
    sess="$(kb_session_id)"
    tab="$(printf '\t')"
    for id in "$@"; do
        [[ "$id" == "-" || "$id" =~ ^K-[0-9]{8}-[0-9a-f]{6,12}$ ]] || continue
        rows+="${ts}${tab}${sess}${tab}${id}${tab}${via}"$'\n'
    done
    [[ -n "$rows" ]] || return 0
    if ! { mkdir -p "${d}/.cache" && printf '%s' "$rows" >> "${d}/.cache/usage.tsv"; } 2>/dev/null; then
        echo "uws kb: could not record item usage in ${d}/.cache/usage.tsv (continuing)" >&2
    fi
    return 0
}

# kb_shell_quote <word>: the word as a POSIX shell reads it back, for commands
# printed for a person or a subagent to run: as is when it has only
# [A-Za-z0-9_./:@%+=-], else in single quotes (each ' written '\'').
kb_shell_quote() {
    case "$1" in
        "" ) printf "''" ;;
        *[!A-Za-z0-9_./:@%+=-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
        * ) printf '%s' "$1" ;;
    esac
}

# Succeeds when the argument is a whole global item ID: global:K-<yyyymmdd>-<hex>
kb_is_global_id() {
    [[ "${1:-}" =~ ^global:K-[0-9]{8}-[0-9a-f]{6,12}$ ]]
}

# Options of `uws kb` verbs that take a value (the next argument), and those of
# them whose value is an item ID. kb_scan_scope_args passes every value on as
# it is, except that a global ID in an ID option selects the global KB.
KB_VALUE_OPTS=" --type --claim --evidence --source --check --watch --author --tags --supersedes --contradicts --falsifier --body --quote --escaped-from --status --limit --min-terms --by --as --set --db --dir "
KB_ID_OPTS=" --supersedes --contradicts --by "

# kb_scan_scope_args <arguments after the verb>: the scope of a `uws kb`
# command, for scripts/kb.sh and bin/uws. Sets KB_SCAN_SCOPE (empty, or the
# value given: project, global, all or anything else for the caller to refuse)
# and KB_SCAN_ARGS (the arguments without the scope flags). --global,
# --scope <s> and --scope=<s> set it. A global ID (global:K-...) selects the
# global KB, and is passed on without its prefix, only in an ID position: the
# first positional argument, or the value of --supersedes, --contradicts or
# --by. Every other value (a --quote, --claim or --body text, a reason) is
# passed on unchanged, even when it starts with global:K- or reads --global.
# Everything after -- is passed on unchanged. Returns 2 when --scope has no value.
kb_scan_scope_args() {
    local a v pos=0
    KB_SCAN_SCOPE=""
    KB_SCAN_ARGS=()
    while [[ $# -gt 0 ]]; do
        a="$1"
        case "$a" in
            --global) KB_SCAN_SCOPE="global"; shift; continue ;;
            --scope) [[ $# -ge 2 ]] || return 2; KB_SCAN_SCOPE="$2"; shift 2; continue ;;
            --scope=*) KB_SCAN_SCOPE="${a#--scope=}"; shift; continue ;;
            --) KB_SCAN_ARGS+=("$@"); break ;;
        esac
        if [[ "$KB_VALUE_OPTS" == *" ${a} "* && $# -ge 2 ]]; then
            v="$2"
            if [[ "$KB_ID_OPTS" == *" ${a} "* ]] && kb_is_global_id "$v"; then
                v="${v#global:}"
                [[ -n "$KB_SCAN_SCOPE" ]] || KB_SCAN_SCOPE="global"
            fi
            KB_SCAN_ARGS+=("$a" "$v")
            shift 2
            continue
        fi
        if [[ "$a" != -* ]]; then
            pos=$((pos + 1))
            if (( pos == 1 )) && kb_is_global_id "$a"; then
                a="${a#global:}"
                [[ -n "$KB_SCAN_SCOPE" ]] || KB_SCAN_SCOPE="global"
            fi
        fi
        KB_SCAN_ARGS+=("$a")
        shift
    done
    return 0
}
