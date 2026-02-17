#!/bin/bash
#
# UWS CLI Installer
# Creates a symlink so 'uws' is available globally.
#
# Usage:
#   ./install.sh              # Install to ~/.local/bin (default)
#   PREFIX=/usr/local ./install.sh  # Install to /usr/local/bin
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"

# Check prerequisites
check_prereqs() {
    local ok=true

    # Bash >= 4.0
    local bash_major="${BASH_VERSINFO[0]}"
    if (( bash_major < 4 )); then
        echo "Error: Bash 4.0+ required (found $BASH_VERSION)" >&2
        ok=false
    fi

    # Git >= 2.0
    if ! command -v git &>/dev/null; then
        echo "Error: git is required but not found" >&2
        ok=false
    else
        local git_ver
        git_ver="$(git --version | grep -oE '[0-9]+\.[0-9]+'| head -1)"
        local git_major="${git_ver%%.*}"
        if (( git_major < 2 )); then
            echo "Error: git 2.0+ required (found $git_ver)" >&2
            ok=false
        fi
    fi

    if [[ "$ok" != "true" ]]; then
        exit 1
    fi
}

main() {
    echo "UWS CLI Installer"
    echo "================="
    echo ""

    check_prereqs

    # Create bin directory if needed
    mkdir -p "$BIN_DIR"

    # Create or update symlink
    local target="$SCRIPT_DIR/bin/uws"
    local link="$BIN_DIR/uws"

    if [[ ! -x "$target" ]]; then
        echo "Error: bin/uws not found at $target" >&2
        exit 1
    fi

    if [[ -L "$link" ]]; then
        rm "$link"
    elif [[ -e "$link" ]]; then
        echo "Warning: $link exists and is not a symlink. Skipping." >&2
        echo "Remove it manually and re-run this installer." >&2
        exit 1
    fi

    ln -s "$target" "$link"
    echo "Installed: $link -> $target"

    # Check PATH
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        echo ""
        echo "Warning: $BIN_DIR is not in your PATH."
        echo "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
        echo ""
        echo "  export PATH=\"$BIN_DIR:\$PATH\""
        echo ""
    fi

    echo ""
    echo "Quick start:"
    echo "  cd your-project"
    echo "  uws init            # Initialize UWS"
    echo "  uws status          # Check workflow state"
    echo "  uws help            # See all commands"
}

main "$@"
