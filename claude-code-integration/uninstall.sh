#!/bin/bash
#
# UWS (Universal Workflow System) - Claude Code Integration Uninstaller
# Version 1.2.0
#
# One-liner uninstall:
#   curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/uninstall.sh | bash
#
# Or run locally:
#   ./claude-code-integration/uninstall.sh [--dry-run] [--force]
#
# Removes all per-project UWS artifacts installed by the Claude Code integration
# installer. Does NOT remove system-level installations (use 'uws uninstall --global').
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Configuration
PROJECT_DIR="${PWD}"
DRY_RUN=false
FORCE=false
REMOVED_COUNT=0
SKIPPED_COUNT=0

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n) DRY_RUN=true; shift ;;
        --force|-f)   FORCE=true; shift ;;
        --help|-h)
            echo "UWS Claude Code Integration Uninstaller"
            echo ""
            echo "Usage: ./uninstall.sh [--dry-run|-n] [--force|-f]"
            echo ""
            echo "  --dry-run, -n  Show what would be removed"
            echo "  --force, -f    Skip confirmations"
            exit 0
            ;;
        *) echo -e "${RED}Unknown option: $1${NC}" >&2; exit 1 ;;
    esac
done

echo -e "${BOLD}${RED}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    UWS - Claude Code Integration Uninstaller                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${CYAN}Project: ${PROJECT_DIR}${NC}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN — no files will be modified${NC}"
    echo ""
fi

# ── Helpers ─────────────────────────────────────────────────────────────────

log_remove() {
    local path="$1" desc="${2:-}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run]${NC} Would remove: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    else
        echo -e "  ${RED}✗${NC} Removed: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    fi
    ((REMOVED_COUNT++)) || true
}

log_skip() {
    local path="$1" reason="${2:-not found}"
    echo -e "  ${DIM}  Skip: ${path} (${reason})${NC}"
    ((SKIPPED_COUNT++)) || true
}

log_clean() {
    local path="$1" desc="${2:-}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${DIM}[dry-run]${NC} Would clean: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    else
        echo -e "  ${GREEN}✓${NC} Cleaned: ${CYAN}${path}${NC}${desc:+ ($desc)}"
    fi
    ((REMOVED_COUNT++)) || true
}

safe_rm() {
    [[ "$DRY_RUN" == true ]] && return 0
    if [[ -d "$1" ]]; then rm -rf "$1"
    elif [[ -f "$1" ]] || [[ -L "$1" ]]; then rm -f "$1"
    fi
}

safe_rmdir_if_empty() {
    [[ "$DRY_RUN" == true ]] && return 0
    [[ -d "$1" ]] && [[ -z "$(ls -A "$1" 2>/dev/null)" ]] && rmdir "$1" && return 0
    return 1
}

confirm() {
    [[ "$FORCE" == true ]] && return 0
    [[ ! -t 0 ]] && return 0
    read -p "  $1 [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# ── Confirmation ────────────────────────────────────────────────────────────

if [[ "$DRY_RUN" == false ]] && [[ "$FORCE" == false ]] && [[ -t 0 ]]; then
    echo -e "${YELLOW}This will remove UWS artifacts from this project.${NC}"
    read -p "Continue? [y/N]: " top_confirm
    if [[ ! "$top_confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    echo ""
fi

# ── Step 1: Backup .workflow/ ───────────────────────────────────────────────
echo -e "${BLUE}[1/12]${NC} Backup workflow state..."
if [[ -d "$PROJECT_DIR/.workflow" ]]; then
    local_backup="$PROJECT_DIR/.workflow.backup.$(date +%Y%m%d_%H%M%S)"
    if [[ "$DRY_RUN" == false ]]; then
        do_backup=true
        if [[ "$FORCE" != true ]] && [[ -t 0 ]]; then
            read -p "  Backup .workflow/ to $(basename "$local_backup")? [Y/n]: " ba
            [[ "$ba" =~ ^[Nn]$ ]] && do_backup=false
        fi
        if [[ "$do_backup" == true ]]; then
            cp -r "$PROJECT_DIR/.workflow" "$local_backup"
            echo -e "  ${GREEN}✓${NC} Backed up to ${DIM}${local_backup}${NC}"
        fi
    else
        echo -e "  ${DIM}[dry-run]${NC} Would backup .workflow/"
    fi
else
    log_skip ".workflow/" "not found"
fi

# ── Step 2: Remove .uws/ ───────────────────────────────────────────────────
echo -e "${BLUE}[2/12]${NC} Remove .uws/..."
if [[ -d "$PROJECT_DIR/.uws" ]]; then
    safe_rm "$PROJECT_DIR/.uws"
    log_remove ".uws/" "hooks, scripts, version"
else
    log_skip ".uws/"
fi

# ── Step 3: Remove .workflow/ ───────────────────────────────────────────────
echo -e "${BLUE}[3/12]${NC} Remove .workflow/..."
if [[ -d "$PROJECT_DIR/.workflow" ]]; then
    safe_rm "$PROJECT_DIR/.workflow"
    log_remove ".workflow/" "state, checkpoints, handoff"
else
    log_skip ".workflow/"
fi

# ── Step 4: Remove .claude/commands/uws* ────────────────────────────────────
echo -e "${BLUE}[4/12]${NC} Remove UWS slash commands..."
if compgen -G "$PROJECT_DIR/.claude/commands/uws*" >/dev/null 2>&1; then
    for f in "$PROJECT_DIR"/.claude/commands/uws*; do
        safe_rm "$f"
        log_remove ".claude/commands/$(basename "$f")"
    done
else
    log_skip ".claude/commands/uws*"
fi
safe_rmdir_if_empty "$PROJECT_DIR/.claude/commands" && log_clean ".claude/commands/" "empty" || true

# ── Step 5: Clean .claude/settings.json ─────────────────────────────────────
echo -e "${BLUE}[5/12]${NC} Clean settings.json..."
settings_file="$PROJECT_DIR/.claude/settings.json"
if [[ -f "$settings_file" ]]; then
    if command -v jq &>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            temp_s=$(mktemp)
            jq '
              .hooks = [(.hooks // [])[] | select(.command // "" | test("^\\./.uws/") | not)] |
              (.permissions.allow // []) as $orig |
              .permissions.allow = [$orig[] |
                select(. as $p |
                  ["Bash(./.uws/hooks/*:*)", "Bash(./.uws/scripts/*:*)",
                   "Bash(cat .workflow/*:*)", "Bash(grep:*)", "Bash(tail:*)",
                   "Bash(head:*)", "Bash(date:*)", "Bash(sed:*)", "Bash(git:*)",
                   "Bash(./scripts/*:*)"] |
                  index($p) | not)]
            ' "$settings_file" > "$temp_s" 2>/dev/null
            if jq empty "$temp_s" 2>/dev/null; then
                remaining=$(jq '(.permissions.allow // [] | length) + (.hooks // [] | length)' "$temp_s" 2>/dev/null || echo "0")
                if [[ "$remaining" == "0" ]]; then
                    rm -f "$settings_file"
                    log_remove ".claude/settings.json" "no non-UWS entries"
                else
                    mv "$temp_s" "$settings_file"
                    log_clean ".claude/settings.json" "UWS entries removed"
                fi
            else
                echo -e "  ${YELLOW}!${NC} jq error cleaning settings.json"
            fi
            rm -f "$temp_s" 2>/dev/null
        else
            log_clean ".claude/settings.json" "would remove UWS hooks/permissions"
        fi
    else
        echo -e "  ${YELLOW}!${NC} jq not available — manually remove .uws/ hooks from settings.json"
    fi
else
    log_skip ".claude/settings.json"
fi

# ── Step 6: Clean CLAUDE.md ─────────────────────────────────────────────────
echo -e "${BLUE}[6/12]${NC} Clean CLAUDE.md..."
if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
    if grep -q '<!-- UWS-BEGIN -->' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            sed -i '/<!-- UWS-BEGIN -->/,/<!-- UWS-END -->/d' "$PROJECT_DIR/CLAUDE.md"
            sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null || true
            content_lines=$(grep -cE '[^[:space:]#]' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null | head -1 || echo "0")
            if [[ "$content_lines" -le 0 ]]; then
                rm -f "$PROJECT_DIR/CLAUDE.md"
                log_remove "CLAUDE.md" "empty after UWS removal"
            else
                log_clean "CLAUDE.md" "UWS section removed"
            fi
        else
            log_clean "CLAUDE.md" "would remove UWS section"
        fi
    else
        log_skip "CLAUDE.md" "no UWS section"
    fi
else
    log_skip "CLAUDE.md"
fi

# ── Step 7: Clean .mcp.json ────────────────────────────────────────────────
echo -e "${BLUE}[7/12]${NC} Clean .mcp.json..."
if [[ -f "$PROJECT_DIR/.mcp.json" ]]; then
    if command -v jq &>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            temp_m=$(mktemp)
            jq '.mcpServers = ((.mcpServers // {}) | del(.vector_memory_local, .vector_memory_global))' \
                "$PROJECT_DIR/.mcp.json" > "$temp_m" 2>/dev/null
            if jq empty "$temp_m" 2>/dev/null; then
                remaining_s=$(jq '.mcpServers // {} | length' "$temp_m" 2>/dev/null || echo "0")
                if [[ "$remaining_s" == "0" ]]; then
                    rm -f "$PROJECT_DIR/.mcp.json"
                    log_remove ".mcp.json" "no servers remain"
                else
                    mv "$temp_m" "$PROJECT_DIR/.mcp.json"
                    log_clean ".mcp.json" "UWS entries removed"
                fi
            fi
            rm -f "$temp_m" 2>/dev/null
        else
            log_clean ".mcp.json" "would remove vector memory entries"
        fi
    elif command -v python3 &>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            python3 -c "
import json, sys
with open('$PROJECT_DIR/.mcp.json') as f:
    data = json.load(f)
servers = data.get('mcpServers', {})
servers.pop('vector_memory_local', None)
servers.pop('vector_memory_global', None)
if not servers:
    sys.exit(42)
data['mcpServers'] = servers
with open('$PROJECT_DIR/.mcp.json', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null
            py_exit=$?
            if [[ "$py_exit" == 42 ]]; then
                rm -f "$PROJECT_DIR/.mcp.json"
                log_remove ".mcp.json" "no servers remain"
            else
                log_clean ".mcp.json" "UWS entries removed"
            fi
        else
            log_clean ".mcp.json" "would remove vector memory entries"
        fi
    else
        echo -e "  ${YELLOW}!${NC} Neither jq nor python3 available"
    fi
else
    log_skip ".mcp.json"
fi

# ── Step 8: Remove memory/ ─────────────────────────────────────────────────
echo -e "${BLUE}[8/12]${NC} Remove local vector DB..."
if [[ -d "$PROJECT_DIR/memory" ]]; then
    safe_rm "$PROJECT_DIR/memory"
    log_remove "memory/" "local vector database"
else
    log_skip "memory/"
fi

# ── Step 9: Remove ./uws wrapper ───────────────────────────────────────────
echo -e "${BLUE}[9/12]${NC} Remove ./uws CLI wrapper..."
if [[ -f "$PROJECT_DIR/uws" ]] && head -5 "$PROJECT_DIR/uws" 2>/dev/null | grep -q "UWS CLI"; then
    safe_rm "$PROJECT_DIR/uws"
    log_remove "./uws" "project CLI wrapper"
else
    log_skip "./uws"
fi

# ── Step 10: Remove empty work directories ──────────────────────────────────
echo -e "${BLUE}[10/12]${NC} Clean empty directories..."
for dir in phases artifacts workspace archive; do
    if [[ -d "$PROJECT_DIR/$dir" ]]; then
        file_count=$(find "$PROJECT_DIR/$dir" -not -name '.gitkeep' -not -type d 2>/dev/null | wc -l)
        if [[ "$file_count" -eq 0 ]]; then
            safe_rm "$PROJECT_DIR/$dir"
            log_remove "$dir/" "empty"
        else
            log_skip "$dir/" "not empty"
        fi
    else
        log_skip "$dir/"
    fi
done

# ── Step 11: Clean .git/hooks/pre-commit ────────────────────────────────────
echo -e "${BLUE}[11/12]${NC} Clean git hooks..."
hook_file="$PROJECT_DIR/.git/hooks/pre-commit"
if [[ -f "$hook_file" ]]; then
    if grep -qiE 'UWS|workflow|\.workflow' "$hook_file" 2>/dev/null; then
        non_uws=$(grep -cvE '^#|^$|workflow|UWS|\.workflow|state\.yaml|checkpoints\.log|#!/bin/bash' "$hook_file" 2>/dev/null || echo "0")
        if [[ "$non_uws" -le 0 ]]; then
            safe_rm "$hook_file"
            log_remove ".git/hooks/pre-commit" "UWS-only hook"
        else
            echo -e "  ${YELLOW}!${NC} pre-commit has non-UWS content — not removing"
        fi
    else
        log_skip ".git/hooks/pre-commit" "no UWS markers"
    fi
else
    log_skip ".git/hooks/pre-commit"
fi

# ── Step 12: Clean .gitignore ───────────────────────────────────────────────
echo -e "${BLUE}[12/12]${NC} Clean .gitignore..."
if [[ -f "$PROJECT_DIR/.gitignore" ]]; then
    if grep -qE '\.uws/|# UWS internal|# Claude Code project|# Workflow system' "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            temp_gi=$(mktemp)
            grep -vE '^\s*\.uws/|^\s*\.claude/|^\s*memory/|^# UWS internal|^# Claude Code project|^# Workflow system|^\s*\.workflow/agents/memory|^\s*\.workflow/\*\.tmp|^\s*\.workflow/\*\.backup|^\s*workspace/\*|^\s*!workspace/\.gitkeep' \
                "$PROJECT_DIR/.gitignore" > "$temp_gi" 2>/dev/null || true
            sed -i '/^$/N;/^\n$/d' "$temp_gi" 2>/dev/null || true
            sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$temp_gi" 2>/dev/null || true
            remaining_l=$(tr -d '[:space:]' < "$temp_gi" | wc -c)
            if [[ "$remaining_l" -eq 0 ]]; then
                rm -f "$PROJECT_DIR/.gitignore"
                log_remove ".gitignore" "empty after cleanup"
            else
                mv "$temp_gi" "$PROJECT_DIR/.gitignore"
                log_clean ".gitignore" "UWS patterns removed"
            fi
            rm -f "$temp_gi" 2>/dev/null
        else
            log_clean ".gitignore" "would remove UWS patterns"
        fi
    else
        log_skip ".gitignore" "no UWS patterns"
    fi
else
    log_skip ".gitignore"
fi

# Remove stale settings backups
for f in "$PROJECT_DIR"/.claude/settings.json.backup.* "$PROJECT_DIR"/.claude/settings.json.uws; do
    if [[ -f "$f" ]]; then
        safe_rm "$f"
        log_remove ".claude/$(basename "$f")" "stale backup"
    fi
done

# Remove .claude/ if empty
safe_rmdir_if_empty "$PROJECT_DIR/.claude" && log_clean ".claude/" "empty directory removed" || true

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN complete${NC}: $REMOVED_COUNT items would be removed, $SKIPPED_COUNT skipped"
    echo -e "Run without --dry-run to execute."
else
    echo -e "${GREEN}UWS project uninstall complete!${NC}"
    echo -e "  $REMOVED_COUNT items removed, $SKIPPED_COUNT skipped"
fi
echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""
if [[ "$DRY_RUN" == false ]]; then
    echo -e "To also remove system-level UWS: ${CYAN}uws uninstall --global${NC}"
fi
