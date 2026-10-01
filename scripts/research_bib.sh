#!/bin/bash
#
# Universal Workflow System - authoritative BibTeX fetcher for the research team
#
# The PI's standing rule: BibTeX is downloaded from the source and never written by
# hand or by a model. This script is the only writer of bib_sources/.
# Design: docs/design/research-team.md section 6.3.
#
# Usage:
#   research_bib.sh fetch <id> [--key <citekey>] [--refetch]
#       <id> is one of
#         arxiv:<id> | <arXiv id such as 2309.11495>   -> https://arxiv.org/bibtex/<id>
#         doi:<doi>  | 10.<prefix>/<suffix>             -> https://doi.org/<doi>
#                                                        (Accept: application/x-bibtex)
#         dblp:<record key>                              -> https://dblp.org/rec/<key>.bib
#         acl:<anthology id>                             -> https://aclanthology.org/<id>.bib
#       Writes bib_sources/<citekey>.bib and bib_sources/<citekey>.meta.json. <citekey>
#       defaults to the key in the downloaded entry; --key records a rename in
#       bib_sources/KEYMAP.tsv instead of editing the entry.
#   research_bib.sh fetch <id> --from-file <file> --pi-decision D-<n> [--key <citekey>]
#       Ingest a file the PI supplied (for example when every endpoint blocks scripts).
#       The same strict parser applies and the PI decision ID is recorded.
#   research_bib.sh build [--out <path>]
#       Write references.bib as the concatenation of bib_sources/*.bib (default: the
#       existing paper/references.bib or references.bib; a new one goes to
#       paper/references.bib when paper/ exists, else to references.bib).
#
# Strictness: a response is stored only if it is HTTP 200, not HTML, and parses as
# exactly one BibTeX entry with a title. Otherwise nothing is written (DBLP answers
# scripted requests with an HTML "Making sure you're not a bot!" page with status 200).
# There is no fallback to a generated entry: a failure is an open question for the PI.
#
# Exit codes: 0 stored/built, 1 refused (bad response, existing file, bad input),
#             2 environment error (network down, python3 or curl missing).
#
# Environment:
#   UWS_BIB_CURL       curl binary to use (tests substitute a stub; default: curl)
#   UWS_BIB_TIMEOUT    per-request timeout in seconds (default 30)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="${SCRIPT_DIR}/research_check.py"
CURL="${UWS_BIB_CURL:-curl}"
TIMEOUT="${UWS_BIB_TIMEOUT:-30}"
USER_AGENT="uws-research-bib/1.0 (+https://github.com/Yash-Sukhdeve/universal-workflow-system)"

die_env() { echo "research_bib: error: $*" >&2; exit 2; }
refuse()  { echo "research_bib: refused: $*" >&2; exit 1; }

usage() {
    sed -n '9,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

command -v python3 >/dev/null 2>&1 || die_env "python3 is required"
[[ -f "$CHECK" ]] || die_env "research_check.py not found next to this script"

# Project root: nearest ancestor with research/ledger or .workflow (same rule as the checker).
find_root() {
    local d="$PWD"
    while [[ "$d" != "/" ]]; do
        if [[ -d "$d/research/ledger" || -d "$d/.workflow" ]]; then
            echo "$d"; return 0
        fi
        d="$(dirname "$d")"
    done
    echo "$PWD"
}
ROOT="${UWS_RESEARCH_ROOT:-$(find_root)}"

# Resolve <id> to: id_type, normalized identifier, URL.
resolve_id() {
    local id="$1"
    case "$id" in
        arxiv:*|arXiv:*) ID_TYPE="arxiv"; IDENT="${id#*:}" ;;
        doi:*|DOI:*)     ID_TYPE="doi";   IDENT="${id#*:}" ;;
        dblp:*)          ID_TYPE="dblp";  IDENT="${id#dblp:}" ;;
        acl:*)           ID_TYPE="acl";   IDENT="${id#acl:}" ;;
        https://doi.org/*) ID_TYPE="doi"; IDENT="${id#https://doi.org/}" ;;
        10.*/*)          ID_TYPE="doi";   IDENT="$id" ;;
        *)
            if [[ "$id" =~ ^[0-9]{4}\.[0-9]{4,5}(v[0-9]+)?$ || "$id" =~ ^[a-z-]+(\.[A-Z]{2})?/[0-9]{7}(v[0-9]+)?$ ]]; then
                ID_TYPE="arxiv"; IDENT="$id"
            else
                refuse "cannot tell what kind of identifier '$id' is (use arxiv:, doi:, dblp: or acl:)"
            fi
            ;;
    esac
    [[ -n "$IDENT" ]] || refuse "empty identifier"
    # Identifiers go into a URL: allow only the characters these schemes use.
    [[ "$IDENT" =~ ^[A-Za-z0-9./:_()\;-]+$ ]] || refuse "identifier '$IDENT' has characters that are not allowed"
    case "$ID_TYPE" in
        arxiv) URL="https://arxiv.org/bibtex/${IDENT}" ;;
        doi)   URL="https://doi.org/${IDENT}" ;;
        dblp)  URL="https://dblp.org/rec/${IDENT}.bib" ;;
        acl)   URL="https://aclanthology.org/${IDENT}.bib" ;;
    esac
}

cmd_fetch() {
    local id="" key="" refetch="" from_file="" pi_decision=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key)         key="${2:-}"; shift 2 ;;
            --refetch)     refetch="--refetch"; shift ;;
            --from-file)   from_file="${2:-}"; shift 2 ;;
            --pi-decision) pi_decision="${2:-}"; shift 2 ;;
            -h|--help)     usage; exit 0 ;;
            -*)            refuse "unknown option $1" ;;
            *)             [[ -z "$id" ]] || refuse "only one identifier per call"; id="$1"; shift ;;
        esac
    done
    [[ -n "$id" ]] || { usage >&2; exit 1; }

    ID_TYPE=""; IDENT=""; URL=""
    resolve_id "$id"

    local args=()
    [[ -n "$key" ]] && args+=(--key "$key")
    [[ -n "$refetch" ]] && args+=(--refetch)

    if [[ -n "$from_file" ]]; then
        [[ -f "$from_file" ]] || refuse "no such file: $from_file"
        [[ "$pi_decision" =~ ^D-[0-9]+$ ]] || refuse "--from-file needs --pi-decision D-<n> (the PI supplies the file)"
        python3 "$CHECK" --root "$ROOT" bib-ingest --body "$from_file" --url "$URL" \
            --id-type pi-supplied --identifier "$IDENT" --http-status "" --content-type "" \
            --pi-decision "$pi_decision" ${args[@]+"${args[@]}"}
        return $?
    fi

    command -v "$CURL" >/dev/null 2>&1 || die_env "curl not found"
    local status_line http ctype rc=0
    BIB_TMP="$(mktemp "${TMPDIR:-/tmp}/uws-bib.XXXXXX")"
    trap 'rm -f "${BIB_TMP:-}"' EXIT
    local tmp="$BIB_TMP"

    local accept="Accept: application/x-bibtex; charset=utf-8"
    status_line="$("$CURL" -sS -L --max-time "$TIMEOUT" --retry 2 --retry-delay 2 \
        -A "$USER_AGENT" -H "$accept" -o "$tmp" -w '%{http_code} %{content_type}' "$URL" 2>&1)" || rc=$?
    if (( rc != 0 )); then
        die_env "download failed (curl exit ${rc}): ${status_line}"
    fi
    http="${status_line%% *}"
    ctype="${status_line#* }"
    [[ "$ctype" == "$status_line" ]] && ctype=""

    # The strict parse and the write both happen in the checker, so the rules live in one place.
    rc=0
    python3 "$CHECK" --root "$ROOT" bib-ingest --body "$tmp" --url "$URL" --id-type "$ID_TYPE" \
        --identifier "$IDENT" --http-status "$http" --content-type "$ctype" \
        ${args[@]+"${args[@]}"} || rc=$?
    if (( rc == 1 )); then
        echo "research_bib: nothing was written. Try another authoritative endpoint (arXiv, DOI, DBLP, ACL)" >&2
        echo "  or record an open question for the PI, who may supply the file (--from-file --pi-decision)." >&2
    fi
    return "$rc"
}

cmd_build() {
    local out=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --out) out="${2:-}"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) refuse "unknown argument $1" ;;
        esac
    done
    if [[ -n "$out" ]]; then
        python3 "$CHECK" --root "$ROOT" bib-build --out "$out"
    else
        python3 "$CHECK" --root "$ROOT" bib-build
    fi
}

case "${1:-help}" in
    fetch) shift; cmd_fetch "$@" ;;
    build) shift; cmd_build "$@" ;;
    help|-h|--help) usage ;;
    *) echo "research_bib: unknown command '$1'" >&2; usage >&2; exit 1 ;;
esac
