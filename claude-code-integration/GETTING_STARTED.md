# Getting Started with UWS + Claude Code

A step-by-step guide to using the Universal Workflow System with Claude Code.

## Prerequisites

- Git installed
- Claude Code CLI installed (`claude` command available)
- Bash shell (Linux/macOS, or WSL on Windows)

## Installation

### Option 1: Quick Install (Recommended)

```bash
# Navigate to your project
cd /path/to/your/project

# Download and run installer
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash
```

### Option 2: Clone and Install

```bash
# Clone UWS repository
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git /tmp/uws

# Navigate to your project
cd /path/to/your/project

# Run installer
/tmp/uws/claude-code-integration/install.sh
```

### Option 3: Manual Installation

```bash
# In your project directory
mkdir -p .uws/hooks .workflow .claude/commands

# Copy from UWS repo (adjust path as needed)
cp /path/to/uws/claude-code-integration/install.sh .
./install.sh
```

## What Gets Installed

After installation, your project will have:

```
your-project/
├── .uws/                      # UWS engine
│   ├── hooks/
│   │   ├── session_start.sh   # Auto-loads context on Claude start
│   │   └── pre_compact.sh     # Auto-checkpoints before context loss
│   └── version
│
├── .workflow/                 # Project state (COMMIT THIS!)
│   ├── state.yaml             # Current phase, checkpoint, metadata
│   ├── handoff.md             # Human-readable context for continuity
│   └── checkpoints.log        # Checkpoint history
│
├── .claude/
│   ├── settings.json          # Hook configuration + permissions
│   └── commands/
│       ├── uws-status         # /uws:status command
│       ├── uws-checkpoint     # /uws:checkpoint command
│       ├── uws-recover        # /uws:recover command
│       └── uws-handoff        # /uws:handoff command
│
└── CLAUDE.md                  # Updated with UWS instructions
```

## Usage Guide

### Starting a Session

1. **Open your project with Claude Code:**
   ```bash
   cd /path/to/your/project
   claude
   ```

2. **Context loads automatically!**

   The `session_start.sh` hook injects your workflow state into Claude's context silently. Claude will know:
   - Current phase (planning, implementation, validation, etc.)
   - Current checkpoint ID
   - Recent checkpoint history
   - Priority actions from handoff.md

3. **To see your full context explicitly:**
   ```
   /uws:recover
   ```

### During Work

#### Check Status
```
/uws:status
```
Shows current phase, checkpoint, and recent activity.

#### Create Checkpoints
```
/uws:checkpoint "Completed user authentication feature"
```
Creates a timestamped checkpoint. Use this at milestones:
- After completing a feature
- Before risky changes
- At natural stopping points

#### Auto-Checkpointing
UWS automatically creates checkpoints before context compaction (when Claude's context window fills up). You don't need to do anything - state is preserved automatically.

### Ending a Session

Before closing Claude Code:

```
/uws:handoff
```

This updates `.workflow/handoff.md` with:
- What you accomplished
- What's next
- Any blockers or issues
- Critical context for the next session

### Returning to Work

Just open Claude Code again:
```bash
claude
```

Your context is automatically restored. If you need a detailed recap:
```
/uws:recover
```

## Workflow Phases

UWS tracks your project through 5 phases:

| Phase | Purpose | When |
|-------|---------|------|
| `phase_1_planning` | Requirements, design | Project start |
| `phase_2_implementation` | Building | Main development |
| `phase_3_validation` | Testing, verification | Pre-release |
| `phase_4_delivery` | Deployment, release | Launch |
| `phase_5_maintenance` | Support, iteration | Post-launch |

Phases are tracked in `state.yaml` and can be updated manually or via checkpoints.

## Checkpoint Naming

Checkpoints follow the format: `CP_<phase>_<sequence>`

Examples:
- `CP_1_001` - First checkpoint in planning phase
- `CP_2_015` - 15th checkpoint in implementation phase
- `CP_3_003` - 3rd checkpoint in validation phase

## Best Practices

### Do This

1. **Checkpoint frequently** - After completing any significant unit of work
2. **Update handoff before breaks** - Especially for multi-day breaks
3. **Commit .workflow/ to git** - Preserves state across clones
4. **Read handoff on return** - Even though context auto-loads, review handoff.md

### Don't Do This

1. **Don't manually edit state.yaml** - Use commands instead
2. **Don't skip handoff on long breaks** - Future you will thank present you
3. **Don't ignore the phase system** - It helps structure your work

## Troubleshooting

### Context not loading on session start?

1. Check hooks are executable:
   ```bash
   chmod +x .uws/hooks/*.sh
   ```

2. Verify settings.json has hooks configured:
   ```bash
   cat .claude/settings.json
   ```
   Should contain `"hooks": [...]` section

3. Ensure you're in the project directory when starting Claude

### Commands not found?

Check commands exist:
```bash
ls -la .claude/commands/
```

Should show: `uws-status`, `uws-checkpoint`, `uws-recover`, `uws-handoff`

### Checkpoints not incrementing?

Check checkpoints.log format:
```bash
cat .workflow/checkpoints.log
```

Each line should be: `TIMESTAMP | CP_X_XXX | MESSAGE`

### State file corrupted?

UWS is designed to handle corruption gracefully. The handoff.md serves as a human-readable backup. If state.yaml is corrupted:

```bash
# View handoff for context
cat .workflow/handoff.md

# Reinitialize (will preserve handoff.md)
rm .workflow/state.yaml
# Re-run installer or manually recreate state.yaml
```

## Git Integration

### What to Commit

```gitignore
# Commit these (preserves state across clones):
.workflow/state.yaml
.workflow/handoff.md
.workflow/checkpoints.log
.claude/commands/
CLAUDE.md

# Optional to commit (hooks are reproducible):
.uws/

# Optionally ignore (personal settings):
.claude/settings.json
```

### Recommended .gitignore additions

```gitignore
# UWS local files (if you want hooks private)
.uws/
.claude/settings.json
.claude/settings.local.json
```

## Advanced: Customizing Hooks

### Modify session_start.sh

Edit `.uws/hooks/session_start.sh` to include additional context:

```bash
# Add git branch info
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
CONTEXT+="- Git Branch: ${BRANCH}\n"

# Add custom project info
if [[ -f "package.json" ]]; then
    VERSION=$(grep '"version"' package.json | cut -d'"' -f4)
    CONTEXT+="- Package Version: ${VERSION}\n"
fi
```

### Modify pre_compact.sh

Edit `.uws/hooks/pre_compact.sh` to add custom checkpoint behavior:

```bash
# Add git commit hash to checkpoint
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
echo "${TIMESTAMP} | ${NEW_CP} | Auto-checkpoint (${GIT_HASH})" >> "$CHECKPOINT_LOG"
```

## Quick Reference

| Command | Purpose |
|---------|---------|
| `/uws:status` | Show current state |
| `/uws:checkpoint "msg"` | Create checkpoint |
| `/uws:recover` | Full context recovery |
| `/uws:handoff` | Prepare for session end |

| File | Purpose |
|------|---------|
| `.workflow/state.yaml` | Machine-readable state |
| `.workflow/handoff.md` | Human-readable context |
| `.workflow/checkpoints.log` | Checkpoint history |
| `.claude/settings.json` | Hook configuration |

## Need Help?

- **Issues**: https://github.com/Yash-Sukhdeve/universal-workflow-system/issues
- **Documentation**: See main README.md in repository
- **CLAUDE.md**: Project-specific instructions (auto-generated)
