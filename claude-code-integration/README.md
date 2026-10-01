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
3. **Slash commands** - `/uws`, `/uws-status`, `/uws-checkpoint`, `/uws-recover`, `/uws-handoff`,
   `/uws-sdlc`, `/uws-research`

## Files Created

```
your-project/
├── .uws/                    # UWS engine (commit this: settings.json points here)
│   ├── hooks/               # Claude Code hooks
│   └── scripts/             # sdlc.sh, research.sh, checkpoint.sh, common.sh
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

| Command | Purpose |
|---------|---------|
| `/uws` | List the UWS commands |
| `/uws-status` | Show current state |
| `/uws-checkpoint "msg"` | Create checkpoint |
| `/uws-recover` | Full context recovery |
| `/uws-handoff` | Prepare for session end |
| `/uws-sdlc <action>` | SDLC phases: status, start, next, goto, fail, reset |
| `/uws-research <action>` | Research phases: status, start, next, goto, reject, reset |

These bundled scripts have no goal-driven deliverable gate, research checks, knowledge
base or subagents; those come with the plugin and the `uws` CLI (main README).

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
(`.claude/settings.local.json`, settings backups). Installers before September 2026
ignored `.uws/` and `.claude/`, which left clones with hooks that silently did nothing;
the current installer removes those entries when it upgrades a project.

## Hooks

| Hook | Event | Purpose |
|------|-------|---------|
| `session_start.sh` | SessionStart | Inject workflow context into Claude |
| `pre_compact.sh` | PreCompact | Auto-checkpoint before context loss |

## Troubleshooting

### Context not loading?
1. Check `.uws/hooks/` scripts are executable: `chmod +x .uws/hooks/*.sh`
2. Verify `.claude/settings.json` has `"hooks": {"SessionStart": [...]}` (an object keyed
   by event). A `"hooks": [...]` list is an older installer's format, which Claude Code ignores:
   re-run the installer to migrate it.
3. Commands missing from `/`? They must be `.claude/commands/uws-*.md`; files without
   `.md` (written by the February 2026 installer) are not loaded. Re-run the installer.
4. Run `claude --debug` and look for `SessionStart` in the hook log, or run `/uws-recover`.

### Checkpoints not incrementing?
Check `.workflow/checkpoints.log` format is correct (TIMESTAMP | ID | MSG)

### Hooks not triggering?
Claude Code hooks require the project to be opened with `claude` command in the project directory.

## Uninstall

From a clone of this repository, run the uninstaller inside the project:

```bash
/path/to/universal-workflow-system/claude-code-integration/uninstall.sh --dry-run   # what it would remove
/path/to/universal-workflow-system/claude-code-integration/uninstall.sh            # asks before removing
```

It copies `.workflow/` to `.workflow.backup.<date>` (it asks first), then removes
`.workflow/`, `.uws/`, the `uws*` slash commands, the UWS hooks and permissions in
`.claude/settings.json` and the UWS section of `CLAUDE.md`. `--force` skips the prompts.
It also runs as `curl -fsSL .../claude-code-integration/uninstall.sh | bash`.

## License

MIT
