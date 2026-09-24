# UWS - Claude Code Integration

Plug-and-play workflow system for maintaining context across Claude Code sessions.

## Quick Install

> Prefer the plugin? Inside Claude Code run
> `/plugin marketplace add Yash-Sukhdeve/universal-workflow-system` then
> `/plugin install uws@uws`. Nothing is copied into your project except `.workflow/`,
> and commands are namespaced (`/uws:status`). This page covers the per-project
> installer, which instead commits the commands and hooks into the repository so every
> collaborator gets them without installing anything.

```bash
# In your project directory:
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash

# Unattended (CI, scripts, agents): accept all defaults
curl -fsSL https://raw.githubusercontent.com/Yash-Sukhdeve/universal-workflow-system/master/claude-code-integration/install.sh | bash -s -- --yes

# Or clone and run:
git clone https://github.com/Yash-Sukhdeve/universal-workflow-system.git /tmp/uws
/tmp/uws/claude-code-integration/install.sh
```

Then commit the result so collaborators get the same commands and hooks:

```bash
git add .uws/ .claude/ .workflow/ CLAUDE.md .gitignore && git commit -m "Add UWS workflow"
```

## What It Does

1. **Auto-loads context** - On session start, Claude automatically knows your project state
2. **Auto-checkpoints** - Before context compaction, state is saved automatically
3. **Simple commands** - `/uws-status`, `/uws-checkpoint`, `/uws-recover`

## Files Created

```
your-project/
├── .uws/                    # UWS engine (commit this: settings.json points here)
│   ├── hooks/               # Claude Code hooks
│   └── scripts/             # sdlc.sh, research.sh, checkpoint.sh
├── .workflow/               # Project state (commit this!)
│   ├── state.yaml           # Current phase/checkpoint
│   ├── handoff.md           # Human-readable context
│   └── checkpoints.log      # Checkpoint history
├── .claude/
│   ├── settings.json        # Hook configuration
│   └── commands/            # Slash commands (uws*.md)
└── CLAUDE.md                # Updated with UWS section
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/uws-status` | Show current workflow state |
| `/uws-checkpoint "msg"` | Create a checkpoint with message |
| `/uws-recover` | Full context recovery after break |
| `/uws-handoff` | Prepare handoff before session end |

## Session Workflow

### Starting a Session
Context loads automatically. If you need a full refresh:
```
/uws-recover
```

### During Work
Create checkpoints at milestones:
```
/uws-checkpoint "Completed feature X"
```

### Ending a Session
Update the handoff document:
```
/uws-handoff
```

## Git Integration

**Commit these files** (preserves state, commands and hooks across clones):
- `.workflow/` (state, handoff, checkpoint history)
- `.uws/` (hook and workflow scripts; `.claude/settings.json` points at them)
- `.claude/settings.json` and `.claude/commands/uws*.md`
- `CLAUDE.md`

The installer adds only machine-local files to `.gitignore`
(`.claude/settings.local.json`, settings backups). Installers before 1.3.0 ignored
`.uws/` and `.claude/`, which left clones with hooks that silently did nothing; the
1.3.0 installer removes those entries when it upgrades a project.

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `session_start.sh` | SessionStart | Inject workflow context into Claude |
| `pre_compact.sh` | PreCompact | Auto-checkpoint before context loss |

## Troubleshooting

### Context not loading?
1. Check `.uws/hooks/` scripts are executable: `chmod +x .uws/hooks/*.sh`
2. Verify `.claude/settings.json` has `"hooks": {"SessionStart": [...]}` (an object keyed
   by event). A `"hooks": [...]` list is the pre-1.3.0 format Claude Code ignores:
   re-run the installer to migrate it.
3. Commands missing from `/`? They must be `.claude/commands/uws-*.md`; files without
   `.md` (written by installer 1.2.0) are not loaded. Re-run the installer.
4. Run `claude --debug` and look for `SessionStart` in the hook log, or run `/uws-recover`.

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
