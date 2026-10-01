#!/bin/bash
#
# User-facing command hints.
#
# Scripts tell the user (or Claude) what to run next. How that command is spelled
# depends on how UWS was reached:
#   plugin  this copy is the Claude Code plugin (its root holds
#           .claude-plugin/plugin.json): the /uws:<command> slash commands, or this
#           copy's own bin/uws by absolute path for a command with no slash command.
#           A bare `uws` is never printed there: Claude Code appends the plugin's bin/
#           to the END of PATH, so an older `uws` earlier on PATH would run instead,
#           and a bare call is outside the slash commands' allow rules.
#   cli     bin/uws and the per-project ./uws wrapper export UWS_CMD: `uws` when that
#           resolves to this install, else this install's bin/uws by absolute path.
#   script  a script run directly: this install's bin/uws (./bin/uws inside the
#           checkout), or the script itself when the scripts were copied without bin/.
# UWS_CMD_STYLE=plugin|cli|script overrides the detection (tests).
#
# Public functions:
#   uws_hint <uws arguments...>  the command to type for `uws <arguments>`
#   uws_cli_path                 `uws`, or this install's bin/uws by absolute path:
#                                for steps the PI runs in their own terminal
#   uws_in_plugin                true when this copy is the Claude Code plugin

# Guard against double-sourcing
if [[ "${_UWS_UI_LOADED:-}" == "true" ]]; then
    return 0 2>/dev/null || true
fi
_UWS_UI_LOADED="true"

_UWS_UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

uws_in_plugin() {
    case "${UWS_CMD_STYLE:-}" in
        plugin) return 0 ;;
        cli|script) return 1 ;;
    esac
    [[ -f "${_UWS_UI_ROOT}/.claude-plugin/plugin.json" ]]
}

# _uws_resolve <path>: the physical path, following symlinks (no readlink -f:
# BSD readlink has no -f before macOS 12.3)
_uws_resolve() {
    local p="$1" d
    while [[ -L "$p" ]]; do
        d="$(cd "$(dirname "$p")" && pwd)" || return 1
        p="$(readlink "$p")"
        [[ "$p" == /* ]] || p="${d}/${p}"
    done
    d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
    printf '%s/%s\n' "$d" "$(basename "$p")"
}

# _uws_rel <path>: ./relative when under the current directory, else unchanged
_uws_rel() {
    case "$1" in
        "${PWD}"/*) printf './%s\n' "${1#"${PWD}"/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

uws_cli_path() {
    local ours="${_UWS_UI_ROOT}/bin/uws" onpath a b
    if [[ ! -f "$ours" ]]; then
        echo "uws"
        return 0
    fi
    onpath="$(command -v uws 2>/dev/null || true)"
    if [[ "$onpath" == /* ]]; then
        a="$(_uws_resolve "$onpath" 2>/dev/null || true)"
        b="$(_uws_resolve "$ours" 2>/dev/null || true)"
        if [[ -n "$a" && "$a" == "$b" ]]; then
            echo "uws"
            return 0
        fi
    fi
    echo "$ours"
}

uws_hint() {
    local cmd="${1:-}" sub="${2:-}" script
    if uws_in_plugin; then
        case "$cmd" in
            sdlc|kb|orchestrate|init|recover|handoff)
                printf '/uws:%s\n' "$*"
                return 0
                ;;
            research)
                if [[ "$sub" == "check" ]]; then
                    shift 2
                    printf '/uws:research-check%s\n' "${1:+ $*}"
                else
                    printf '/uws:%s\n' "$*"
                fi
                return 0
                ;;
            status)
                if [[ $# -eq 1 ]]; then echo "/uws:status"; return 0; fi
                ;;
            checkpoint)
                if [[ "$sub" == "create" ]]; then
                    shift 2
                    printf '/uws:checkpoint%s\n' "${1:+ $*}"
                    return 0
                fi
                ;;
        esac
        printf '%s %s\n' "${_UWS_UI_ROOT}/bin/uws" "$*"
        return 0
    fi
    if [[ "${UWS_CMD_STYLE:-}" != "script" && -n "${UWS_CMD:-}" ]]; then
        printf '%s %s\n' "$UWS_CMD" "$*"
        return 0
    fi
    if [[ -x "${_UWS_UI_ROOT}/bin/uws" ]]; then
        printf '%s %s\n' "$(_uws_rel "${_UWS_UI_ROOT}/bin/uws")" "$*"
        return 0
    fi
    # Scripts copied without bin/ (tests): name the script itself
    case "$cmd" in
        init)      script="init_workflow.sh" ;;
        recover)   script="recover_context.sh" ;;
        dashboard) script="start_dashboard.sh" ;;
        detect)    script="detect_and_configure.sh" ;;
        *)         script="${cmd}.sh" ;;
    esac
    [[ $# -gt 0 ]] && shift
    printf '%s%s\n' "$(_uws_rel "${_UWS_UI_ROOT}/scripts/${script}")" "${1:+ $*}"
}
