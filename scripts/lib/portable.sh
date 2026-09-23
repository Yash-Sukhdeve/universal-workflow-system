#!/bin/bash
#
# Portability helpers for GNU (Linux) and BSD (macOS) userlands.
#
# GNU `sed -i 's/a/b/' file` edits in place, but BSD sed reads the script as the
# backup suffix and fails with "invalid command code". The attached-suffix form
# `sed -i.ext` is accepted by both, so sed_inplace uses it and removes the backup.

# Guard against double-sourcing
if [[ "${_UWS_PORTABLE_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UWS_PORTABLE_LOADED="true"

# sed_inplace [sed options/scripts...] <file>
# In-place sed edit on GNU and BSD sed. The file must be the last argument.
# Returns sed's exit status.
sed_inplace() {
    local file="${!#}"
    local rc=0
    sed -i.uwsbak "$@" || rc=$?
    rm -f "${file}.uwsbak"
    return "$rc"
}

# append_after_match <file> <extended-regex> <line>
# Insert <line> (verbatim, leading spaces kept) after every line matching the
# regex. Replaces GNU-only `sed -i '/re/a text'`, whose one-line form BSD rejects.
append_after_match() {
    local file="$1" regex="$2" line="$3" tmp
    tmp="$(mktemp "${file}.XXXXXX")" || return 1
    if awk -v re="$regex" -v add="$line" '{ print } $0 ~ re { print add }' "$file" > "$tmp"; then
        cat "$tmp" > "$file"
        rm -f "$tmp"
    else
        rm -f "$tmp"
        return 1
    fi
}
