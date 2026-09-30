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
#   kb_item_path, kb_counts, kb_summary_line

if [[ "${_UWS_KB_UTILS_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UWS_KB_UTILS_LOADED="true"

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
        } else if (c == "\"") { inq = 1; quoted = 1 }
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
kb_pi_identity() {
    local root="${1:-.}" cfg v=""
    cfg="${WORKFLOW_DIR:-${root}/.workflow}/config.yaml"
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
    printf 'KB: %s trusted, %s stale, %s disputed, %s to review. Search: uws kb search <words> (skill uws-kb)\n' \
        "$t" "$s" "$x" "$c"
}
