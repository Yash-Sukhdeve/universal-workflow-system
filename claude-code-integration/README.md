# UWS - Claude Code Integration

Plug-and-play workflow system for maintaining context across Claude Code sessions.

## Quick Install

```bash
# In your project directory:
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash

# Or clone and run:
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git /tmp/uws
/tmp/uws/claude-code-integration/install.sh
```

## What It Does

1. **Auto-loads context** - On session start, Claude automatically knows your project state
2. **Auto-checkpoints** - Before context compaction, state is saved automatically
3. **Simple commands** - `/uws:status`, `/uws:checkpoint`, `/uws:recover`

## Files Created

```
your-project/
├── .uws/                    # UWS engine
│   └── hooks/               # Claude Code hooks
├── .workflow/               # Project state (commit this!)
│   ├── state.yaml           # Current phase/checkpoint
│   ├── handoff.md           # Human-readable context
│   └── checkpoints.log      # Checkpoint history
├── .claude/
│   ├── settings.json        # Hook configuration
│   └── commands/            # Slash commands
└── CLAUDE.md                # Updated with UWS section
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/uws:status` | Show current workflow state |
| `/uws:checkpoint "msg"` | Create a checkpoint with message |
| `/uws:recover` | Full context recovery after break |
| `/uws:handoff` | Prepare handoff before session end |

## Session Workflow

### Starting a Session
Context loads automatically. If you need a full refresh:
```
/uws:recover
```

### During Work
Create checkpoints at milestones:
```
/uws:checkpoint "Completed feature X"
```

### Ending a Session
Update the handoff document:
```
/uws:handoff
```

## Git Integration

**Commit these files** (preserves state across clones):
- `.workflow/state.yaml`
- `.workflow/handoff.md`
- `.workflow/checkpoints.log`
- `.claude/commands/*`
- `CLAUDE.md`

**Optionally ignore** (hooks are reproducible):
- `.uws/`
- `.claude/settings.json` (if personal)

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `session_start.sh` | SessionStart | Inject workflow context into Claude |
| `pre_compact.sh` | PreCompact | Auto-checkpoint before context loss |

## Troubleshooting

### Context not loading?
1. Check `.uws/hooks/` scripts are executable: `chmod +x .uws/hooks/*.sh`
2. Verify `.claude/settings.json` has hook configuration
3. Run `/uws:recover` manually

### Checkpoints not incrementing?
Check `.workflow/checkpoints.log` format is correct (TIMESTAMP | ID | MSG)

### Hooks not triggering?
Claude Code hooks require the project to be opened with `claude` command in the project directory.

## Uninstall

```bash
rm -rf .uws .workflow/.uws-*
# Remove UWS section from CLAUDE.md manually
# Remove hooks from .claude/settings.json manually
```

## License

MIT
