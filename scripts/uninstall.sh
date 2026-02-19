#!/bin/bash
#
# UWS Uninstall Script
# Removes UWS artifacts from a project and/or the system.
#
# Usage:
#   ./scripts/uninstall.sh [--project|--global|--all] [--dry-run|-n] [--force|-f]
#
# Modes:
#   --project  (default) Remove UWS from the current project
#   --global             Remove system-level UWS installation
#   --all                Both project + global
#   --dry-run / -n       Show what would be removed without doing it
#   --force / -f         Skip confirmation prompts
#

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Globals ─────────────────────────────────────────────────────────────────
DRY_RUN=false
FORCE=false
MODE="project"  # project | global | all
REMOVED_COUNT=0
SKIPPED_COUNT=0

# ── Helpers ─────────────────────────────────────────────────────────────────

log_remove() {
    local path="$1"
    local desc="${2:-}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run]${NC} Would remove: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    else
        echo -e "  ${RED}✗${NC} Removed: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    fi
    ((REMOVED_COUNT++)) || true
}

log_skip() {
    local path="$1"
    local reason="${2:-not found}"
    echo -e "  ${DIM}  Skip: ${path} (${reason})${NC}"
    ((SKIPPED_COUNT++)) || true
}

log_clean() {
    local path="$1"
    local desc="${2:-}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run]${NC} Would clean: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    else
        echo -e "  ${GREEN}✓${NC} Cleaned: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    fi
    ((REMOVED_COUNT++)) || true
}

confirm() {
    local msg="$1"
    if [[ "$FORCE" == true ]]; then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        # Non-interactive: default to yes
        return 0
    fi
    read -p "  $msg [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

safe_rm() {
    local target="$1"
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    if [[ -d "$target" ]]; then
        rm -rf "$target"
    elif [[ -f "$target" ]] || [[ -L "$target" ]]; then
        rm -f "$target"
    fi
}

safe_rmdir_if_empty() {
    local target="$1"
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    if [[ -d "$target" ]] && [[ -z "$(ls -A "$target" 2>/dev/null)" ]]; then
        rmdir "$target"
        return 0
    fi
    return 1
}

# ── Project root discovery ──────────────────────────────────────────────────

find_project_root() {
    # 1. Explicit env var
    if [[ -n "${UWS_ROOT:-}" ]] && [[ -d "${UWS_ROOT}/.workflow" ]]; then
        echo "$UWS_ROOT"
        return 0
    fi

    # 2. Walk up from CWD looking for .workflow/
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -d "$dir/.workflow" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done

    # 3. CWD might be an install target even without .workflow/ (partial install)
    #    Check for .uws/ or .claude/commands/uws*
    if [[ -d "$PWD/.uws" ]] || compgen -G "$PWD/.claude/commands/uws*" >/dev/null 2>&1; then
        echo "$PWD"
        return 0
    fi

    return 1
}

# ── Project Uninstall ───────────────────────────────────────────────────────

uninstall_project() {
    local root
    if ! root="$(find_project_root)"; then
        echo -e "${YELLOW}No UWS project found in current directory tree.${NC}"
        echo "  Run this from inside a UWS-initialized project."
        return 1
    fi

    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  UWS Project Uninstall: ${CYAN}${root}${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}DRY RUN — no files will be modified${NC}"
        echo ""
    fi

    # ── Step 1: Backup .workflow/ ───────────────────────────────────────
    if [[ -d "$root/.workflow" ]]; then
        local backup_dir="$root/.workflow.backup.$(date +%Y%m%d_%H%M%S)"
        if [[ "$DRY_RUN" == false ]]; then
            local do_backup=true
            if [[ "$FORCE" != true ]] && [[ -t 0 ]]; then
                read -p "  Backup .workflow/ to ${backup_dir}? [Y/n]: " backup_answer
                if [[ "$backup_answer" =~ ^[Nn]$ ]]; then
                    do_backup=false
                fi
            fi
            if [[ "$do_backup" == true ]]; then
                cp -r "$root/.workflow" "$backup_dir"
                echo -e "  ${GREEN}✓${NC} Backed up .workflow/ to ${DIM}${backup_dir}${NC}"
            fi
        else
            echo -e "  ${DIM}[dry-run]${NC} Would backup .workflow/ to ${backup_dir}"
        fi
    fi

    # ── Step 2: Remove .uws/ ───────────────────────────────────────────
    if [[ -d "$root/.uws" ]]; then
        safe_rm "$root/.uws"
        log_remove ".uws/" "hooks, scripts, version"
    else
        log_skip ".uws/"
    fi

    # ── Step 3: Remove .workflow/ ──────────────────────────────────────
    if [[ -d "$root/.workflow" ]]; then
        safe_rm "$root/.workflow"
        log_remove ".workflow/" "state, checkpoints, handoff, agents, skills"
    else
        log_skip ".workflow/"
    fi

    # ── Step 4: Remove .claude/commands/uws* ───────────────────────────
    local uws_cmds_found=false
    if compgen -G "$root/.claude/commands/uws*" >/dev/null 2>&1; then
        for f in "$root"/.claude/commands/uws*; do
            safe_rm "$f"
            log_remove ".claude/commands/$(basename "$f")"
        done
        uws_cmds_found=true
    else
        log_skip ".claude/commands/uws*"
    fi

    # Remove .claude/commands/ if now empty
    safe_rmdir_if_empty "$root/.claude/commands" && log_clean ".claude/commands/" "empty directory removed" || true

    # ── Step 5: Clean .claude/settings.json ────────────────────────────
    local settings_file="$root/.claude/settings.json"
    if [[ -f "$settings_file" ]]; then
        if command -v jq &>/dev/null; then
            if [[ "$DRY_RUN" == false ]]; then
                local temp_settings
                temp_settings=$(mktemp)

                # Remove UWS hooks and all installer-added permissions
                jq '
                  # Remove hooks pointing to .uws/
                  .hooks = [(.hooks // [])[] | select(.command // "" | test("^\\./.uws/") | not)] |
                  # Remove UWS-specific permissions (exact set from installer)
                  (.permissions.allow // []) as $orig |
                  .permissions.allow = [$orig[] |
                    select(. as $p |
                      ["Bash(./.uws/hooks/*:*)", "Bash(./.uws/scripts/*:*)",
                       "Bash(cat .workflow/*:*)", "Bash(grep:*)", "Bash(tail:*)",
                       "Bash(head:*)", "Bash(date:*)", "Bash(sed:*)", "Bash(git:*)",
                       "Bash(./scripts/*:*)"] |
                      index($p) | not)]
                ' "$settings_file" > "$temp_settings" 2>/dev/null

                if jq empty "$temp_settings" 2>/dev/null; then
                    # Check if file is effectively empty
                    local remaining
                    remaining=$(jq '(.permissions.allow // [] | length) + (.hooks // [] | length)' "$temp_settings" 2>/dev/null || echo "0")
                    if [[ "$remaining" == "0" ]]; then
                        rm -f "$settings_file"
                        log_remove ".claude/settings.json" "no non-UWS entries remain"
                    else
                        mv "$temp_settings" "$settings_file"
                        log_clean ".claude/settings.json" "UWS hooks/permissions removed"
                    fi
                else
                    rm -f "$temp_settings"
                    echo -e "  ${YELLOW}!${NC} Could not clean settings.json (jq error), leaving as-is"
                fi
                rm -f "$temp_settings" 2>/dev/null
            else
                log_clean ".claude/settings.json" "would remove UWS hooks/permissions"
            fi
        else
            echo -e "  ${YELLOW}!${NC} jq not available — cannot clean settings.json automatically"
            echo -e "  ${YELLOW}!${NC} Manually remove hooks referencing .uws/ from .claude/settings.json"
        fi
    else
        log_skip ".claude/settings.json"
    fi

    # ── Step 6: Clean CLAUDE.md ────────────────────────────────────────
    if [[ -f "$root/CLAUDE.md" ]]; then
        if grep -q '<!-- UWS-BEGIN -->' "$root/CLAUDE.md" 2>/dev/null; then
            if [[ "$DRY_RUN" == false ]]; then
                sed -i '/<!-- UWS-BEGIN -->/,/<!-- UWS-END -->/d' "$root/CLAUDE.md"
                # Remove trailing blank lines
                sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$root/CLAUDE.md" 2>/dev/null || true

                # Check if file is now empty or just a header
                local content_lines
                content_lines=$(grep -cE '[^[:space:]#]' "$root/CLAUDE.md" 2>/dev/null | head -1 || echo "0")
                if [[ "$content_lines" -le 0 ]]; then
                    rm -f "$root/CLAUDE.md"
                    log_remove "CLAUDE.md" "empty after UWS section removal"
                else
                    log_clean "CLAUDE.md" "UWS section removed"
                fi
            else
                log_clean "CLAUDE.md" "would remove UWS-BEGIN/UWS-END section"
            fi
        else
            log_skip "CLAUDE.md" "no UWS section found"
        fi
    else
        log_skip "CLAUDE.md"
    fi

    # ── Step 7: Clean .mcp.json ────────────────────────────────────────
    if [[ -f "$root/.mcp.json" ]]; then
        if command -v jq &>/dev/null; then
            if [[ "$DRY_RUN" == false ]]; then
                local temp_mcp
                temp_mcp=$(mktemp)

                jq '
                  .mcpServers = ((.mcpServers // {}) | del(.vector_memory_local, .vector_memory_global))
                ' "$root/.mcp.json" > "$temp_mcp" 2>/dev/null

                if jq empty "$temp_mcp" 2>/dev/null; then
                    local remaining_servers
                    remaining_servers=$(jq '.mcpServers // {} | length' "$temp_mcp" 2>/dev/null || echo "0")
                    if [[ "$remaining_servers" == "0" ]]; then
                        rm -f "$root/.mcp.json"
                        log_remove ".mcp.json" "no non-UWS servers remain"
                    else
                        mv "$temp_mcp" "$root/.mcp.json"
                        log_clean ".mcp.json" "UWS vector memory entries removed"
                    fi
                else
                    rm -f "$temp_mcp"
                    echo -e "  ${YELLOW}!${NC} Could not clean .mcp.json (jq error), leaving as-is"
                fi
                rm -f "$temp_mcp" 2>/dev/null
            else
                log_clean ".mcp.json" "would remove vector_memory_local/global entries"
            fi
        elif command -v python3 &>/dev/null; then
            if [[ "$DRY_RUN" == false ]]; then
                python3 -c "
import json, sys
with open('$root/.mcp.json') as f:
    data = json.load(f)
servers = data.get('mcpServers', {})
servers.pop('vector_memory_local', None)
servers.pop('vector_memory_global', None)
if not servers:
    sys.exit(42)  # signal: delete file
data['mcpServers'] = servers
with open('$root/.mcp.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null
                local py_exit=$?
                if [[ "$py_exit" == 42 ]]; then
                    rm -f "$root/.mcp.json"
                    log_remove ".mcp.json" "no non-UWS servers remain"
                else
                    log_clean ".mcp.json" "UWS vector memory entries removed"
                fi
            else
                log_clean ".mcp.json" "would remove vector_memory_local/global entries"
            fi
        else
            echo -e "  ${YELLOW}!${NC} Neither jq nor python3 available — cannot clean .mcp.json"
        fi
    else
        log_skip ".mcp.json"
    fi

    # ── Step 8: Remove memory/ (local vector DB) ──────────────────────
    if [[ -d "$root/memory" ]]; then
        safe_rm "$root/memory"
        log_remove "memory/" "local vector database"
    else
        log_skip "memory/"
    fi

    # ── Step 9: Remove ./uws wrapper ──────────────────────────────────
    if [[ -f "$root/uws" ]] && head -5 "$root/uws" 2>/dev/null | grep -q "UWS CLI"; then
        safe_rm "$root/uws"
        log_remove "./uws" "project CLI wrapper"
    else
        log_skip "./uws"
    fi

    # ── Step 10: Remove empty phase/work directories ──────────────────
    local work_dirs=("phases" "artifacts" "workspace" "archive")
    for dir in "${work_dirs[@]}"; do
        if [[ -d "$root/$dir" ]]; then
            # Only remove if empty (or contains only .gitkeep)
            local file_count
            file_count=$(find "$root/$dir" -not -name '.gitkeep' -not -type d 2>/dev/null | wc -l)
            if [[ "$file_count" -eq 0 ]]; then
                safe_rm "$root/$dir"
                log_remove "$dir/" "empty directory"
            else
                log_skip "$dir/" "not empty ($file_count files)"
            fi
        else
            log_skip "$dir/"
        fi
    done

    # Also try phase subdirectories
    if [[ -d "$root/phases" ]]; then
        for pdir in "$root"/phases/phase_*; do
            [[ -d "$pdir" ]] || continue
            local pcount
            pcount=$(find "$pdir" -not -name '.gitkeep' -not -type d 2>/dev/null | wc -l)
            if [[ "$pcount" -eq 0 ]]; then
                safe_rm "$pdir"
                log_remove "phases/$(basename "$pdir")/" "empty"
            fi
        done
        safe_rmdir_if_empty "$root/phases" && log_clean "phases/" "empty directory removed" || true
    fi

    # ── Step 11: Clean .git/hooks/pre-commit ──────────────────────────
    local hook_file="$root/.git/hooks/pre-commit"
    if [[ -f "$hook_file" ]]; then
        if grep -qiE 'UWS|workflow|\.workflow' "$hook_file" 2>/dev/null; then
            # Check if the entire hook is UWS-only (not mixed with user hooks)
            local non_uws_lines
            non_uws_lines=$(grep -cvE '^#|^$|workflow|UWS|\.workflow|state\.yaml|checkpoints\.log|#!/bin/bash' "$hook_file" 2>/dev/null || echo "0")
            if [[ "$non_uws_lines" -le 0 ]]; then
                safe_rm "$hook_file"
                log_remove ".git/hooks/pre-commit" "UWS-only hook"
            else
                echo -e "  ${YELLOW}!${NC} .git/hooks/pre-commit contains non-UWS content — not removing"
                log_skip ".git/hooks/pre-commit" "mixed content"
            fi
        else
            log_skip ".git/hooks/pre-commit" "no UWS markers found"
        fi
    else
        log_skip ".git/hooks/pre-commit"
    fi

    # ── Step 12: Clean .gitignore ──────────────────────────────────────
    if [[ -f "$root/.gitignore" ]]; then
        local uws_patterns=(
            '\.uws/'
            '\.claude/'
            'memory/'
            '# UWS internal hooks'
            '# Claude Code project config'
            '# Workflow system'
            '\.workflow/agents/memory/\*'
            '\.workflow/\*\.tmp'
            '\.workflow/\*\.backup'
            'workspace/\*'
            '!workspace/\.gitkeep'
        )

        local has_uws_lines=false
        for pattern in "${uws_patterns[@]}"; do
            if grep -qF "$(echo "$pattern" | sed 's/\\//g')" "$root/.gitignore" 2>/dev/null; then
                has_uws_lines=true
                break
            fi
        done

        if [[ "$has_uws_lines" == true ]]; then
            if [[ "$DRY_RUN" == false ]]; then
                local temp_gi
                temp_gi=$(mktemp)
                # Remove UWS-specific lines
                grep -vE '^\s*\.uws/|^\s*\.claude/|^\s*memory/|^# UWS internal|^# Claude Code project|^# Workflow system|^\s*\.workflow/agents/memory|^\s*\.workflow/\*\.tmp|^\s*\.workflow/\*\.backup|^\s*workspace/\*|^\s*!workspace/\.gitkeep' "$root/.gitignore" > "$temp_gi" 2>/dev/null || true

                # Remove consecutive blank lines left behind
                sed -i '/^$/N;/^\n$/d' "$temp_gi" 2>/dev/null || true
                # Remove trailing blank lines
                sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$temp_gi" 2>/dev/null || true

                local remaining_lines
                remaining_lines=$(tr -d '[:space:]' < "$temp_gi" | wc -c)
                if [[ "$remaining_lines" -eq 0 ]]; then
                    rm -f "$root/.gitignore"
                    log_remove ".gitignore" "empty after UWS lines removed"
                else
                    mv "$temp_gi" "$root/.gitignore"
                    log_clean ".gitignore" "UWS patterns removed"
                fi
                rm -f "$temp_gi" 2>/dev/null
            else
                log_clean ".gitignore" "would remove UWS patterns"
            fi
        else
            log_skip ".gitignore" "no UWS patterns found"
        fi
    else
        log_skip ".gitignore"
    fi

    # ── Step 13: Remove stale backups ─────────────────────────────────
    local backup_found=false
    for f in "$root"/.claude/settings.json.backup.* "$root"/.claude/settings.json.uws; do
        if [[ -f "$f" ]]; then
            safe_rm "$f"
            log_remove ".claude/$(basename "$f")" "stale backup"
            backup_found=true
        fi
    done
    if [[ "$backup_found" == false ]]; then
        log_skip ".claude/settings.json.backup.*"
    fi

    # ── Step 14: Remove .claude/ if now empty ─────────────────────────
    safe_rmdir_if_empty "$root/.claude" && log_clean ".claude/" "empty directory removed" || true

    echo ""
    echo -e "${BOLD}${BLUE}───────────────────────────────────────────────────────────────${NC}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}DRY RUN complete${NC}: $REMOVED_COUNT items would be removed, $SKIPPED_COUNT skipped"
    else
        echo -e "  ${GREEN}Project uninstall complete${NC}: $REMOVED_COUNT items removed, $SKIPPED_COUNT skipped"
    fi
    echo -e "${BOLD}${BLUE}───────────────────────────────────────────────────────────────${NC}"
}

# ── Global Uninstall ────────────────────────────────────────────────────────

uninstall_global() {
    local prefix="${PREFIX:-$HOME/.local}"
    local bin_dir="$prefix/bin"

    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  UWS Global Uninstall${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}DRY RUN — no files will be modified${NC}"
        echo ""
    fi

    local global_removed=0
    local global_skipped=0

    # ── Step 1: Remove CLI symlink ────────────────────────────────────
    local uws_bin="$bin_dir/uws"
    if [[ -L "$uws_bin" ]] || [[ -f "$uws_bin" ]]; then
        safe_rm "$uws_bin"
        log_remove "$uws_bin" "CLI symlink"
        ((global_removed++)) || true
    else
        log_skip "$uws_bin"
        ((global_skipped++)) || true
    fi

    # ── Step 2: Remove ~/.uws/ (vector memory server + venv) ─────────
    if [[ -d "$HOME/.uws" ]]; then
        local uws_size
        uws_size=$(du -sh "$HOME/.uws" 2>/dev/null | cut -f1 || echo "unknown")
        echo -e "  ${YELLOW}~/.uws/ contains vector memory server (${uws_size})${NC}"
        if confirm "Delete ~/.uws/ (vector memory server)?"; then
            safe_rm "$HOME/.uws"
            log_remove "~/.uws/" "vector memory server + venv"
            ((global_removed++)) || true
        else
            log_skip "~/.uws/" "user declined"
            ((global_skipped++)) || true
        fi
    else
        log_skip "~/.uws/"
        ((global_skipped++)) || true
    fi

    # ── Step 3: Remove ~/uws-global-knowledge/ ───────────────────────
    if [[ -d "$HOME/uws-global-knowledge" ]]; then
        echo -e "  ${YELLOW}~/uws-global-knowledge/ contains cross-project knowledge DB${NC}"
        if confirm "Delete ~/uws-global-knowledge/ (cross-project knowledge)?"; then
            safe_rm "$HOME/uws-global-knowledge"
            log_remove "~/uws-global-knowledge/" "global knowledge database"
            ((global_removed++)) || true
        else
            log_skip "~/uws-global-knowledge/" "user declined"
            ((global_skipped++)) || true
        fi
    else
        log_skip "~/uws-global-knowledge/"
        ((global_skipped++)) || true
    fi

    # ── Step 4: Remove ~/.config/uws/ ────────────────────────────────
    if [[ -d "$HOME/.config/uws" ]]; then
        safe_rm "$HOME/.config/uws"
        log_remove "~/.config/uws/" "global configuration"
        ((global_removed++)) || true
    else
        log_skip "~/.config/uws/"
        ((global_skipped++)) || true
    fi

    echo ""
    echo -e "${BOLD}${BLUE}───────────────────────────────────────────────────────────────${NC}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${YELLOW}DRY RUN complete${NC}: $global_removed items would be removed, $global_skipped skipped"
    else
        echo -e "  ${GREEN}Global uninstall complete${NC}: $global_removed items removed, $global_skipped skipped"
    fi
    echo -e "${BOLD}${BLUE}───────────────────────────────────────────────────────────────${NC}"
}

# ── Usage ───────────────────────────────────────────────────────────────────

show_help() {
    cat <<'EOF'
UWS Uninstaller — Remove UWS from project and/or system

Usage: uninstall.sh [options]

Modes:
  --project      Remove UWS from current project (default)
  --global       Remove system-level UWS installation
  --all          Both project + global

Options:
  --dry-run, -n  Show what would be removed without doing it
  --force, -f    Skip confirmation prompts
  --help, -h     Show this help

Examples:
  ./scripts/uninstall.sh --dry-run          # Preview project removal
  ./scripts/uninstall.sh --project          # Remove from project
  ./scripts/uninstall.sh --global --force   # Remove global (no prompts)
  ./scripts/uninstall.sh --all -n           # Preview full removal
EOF
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project)   MODE="project"; shift ;;
            --global)    MODE="global"; shift ;;
            --all)       MODE="all"; shift ;;
            --dry-run|-n) DRY_RUN=true; shift ;;
            --force|-f)  FORCE=true; shift ;;
            --help|-h)   show_help; exit 0 ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}" >&2
                show_help >&2
                exit 1
                ;;
        esac
    done

    echo ""
    echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║           UWS Uninstaller (mode: ${MODE})${NC}"
    echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Confirmation gate
    if [[ "$DRY_RUN" == false ]] && [[ "$FORCE" == false ]] && [[ -t 0 ]]; then
        echo -e "  ${YELLOW}This will remove UWS artifacts.${NC}"
        read -p "  Continue? [y/N]: " top_confirm
        if [[ ! "$top_confirm" =~ ^[Yy]$ ]]; then
            echo "  Cancelled."
            exit 0
        fi
        echo ""
    fi

    case "$MODE" in
        project)
            uninstall_project
            ;;
        global)
            uninstall_global
            ;;
        all)
            uninstall_project
            echo ""
            uninstall_global
            ;;
    esac

    echo ""
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}No changes were made. Run without --dry-run to execute.${NC}"
    else
        echo -e "${GREEN}UWS uninstall complete.${NC}"
    fi
}

main "$@"
