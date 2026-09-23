# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Installability: every documented install path now produces a working setup, and CI
checks the artifacts a user's project receives rather than only this repository.

### Added
- Claude Code plugin at `plugins/uws/`, installable with
  `/plugin marketplace add Yash-Sukhdeve/universal-workflow-system` and
  `/plugin install uws@uws`: seven `/uws:*` commands, SessionStart/PreCompact hooks,
  the seven `uws-*` subagents, and a bundled `uws` CLI
- `claude-code-integration/install.sh --yes` (or `UWS_YES=true`) for unattended installs
- `tests/integration/test_installability.bats` (20 tests) covering the installer, the
  global CLI and the plugin; CI now lints user-facing entry points at warning level
  and runs `claude plugin validate`

### Fixed
- Installer wrote slash commands without the `.md` extension, so Claude Code never
  loaded them; it now writes `uws*.md` and removes the extensionless files on upgrade
- Installer wrote hooks as a flat `[{"event": ...}]` list, which Claude Code ignores;
  hooks now use the nested format with `$CLAUDE_PROJECT_DIR` paths, and upgrades
  migrate the old list while keeping unrelated settings
- Installer prompts read from `/dev/tty`, so `curl | bash` no longer consumes the
  script as input; with no terminal the default answer is used and printed
- Installer no longer adds `.uws/` and `.claude/` to `.gitignore` (clones got hooks
  pointing at missing scripts) and drops the broad `Bash(git:*)`/`Bash(sed:*)`
  permissions it used to grant; generated commands and hooks use portable
  `sed -i.bak` and `date -u`
- Installer's `/uws-status`, `/uws-recover` and `/uws-handoff` used `! cmd` lines,
  which Claude Code does not execute; they now use `` !`cmd` ``
- `bin/uws` ran scripts from the user's project instead of the UWS installation, so
  every command after `uws init` failed with "No such file or directory"
- `uws status` exited 1 without a terminal (`clear` with no `TERM`)
- `init_workflow.sh` no longer moves an existing `.workflow/` aside when run without
  a terminal (set `UWS_FORCE_REINIT=true` to do so), no longer overwrites an existing
  git `pre-commit` hook, and skips the per-project `./uws` wrapper when a global `uws`
  is in use
- The ~1.5GB vector-memory install is opt-in: prompts default to No, and
  non-interactive runs skip it unless `UWS_VECTOR_MEMORY=true`
- macOS: CI had failed there since February. BSD `sed` rejects `sed -i 's/..' file`,
  so every in-place state write failed; bash 3.2 (macOS `/bin/bash`) treats an empty
  `"${arr[@]}"` as unbound and has no `${var,,}`; BSD `date +%s%3N` prints a literal
  `3N`, which crashed `recover_context.sh`. Added `scripts/lib/portable.sh`
  (`sed_inplace`, `append_after_match`, `now_ms`) and a CI step rejecting these
  constructs. First fully green CI run: Ubuntu 741/741, macOS 671/671
- `grep -c … || echo 0` printed `0` twice when nothing matched (e.g. "Modified: 0
  0 files" in recovery and status output)
- CI summary treated skipped jobs as passing; it now requires success
- `.claude-plugin/marketplace.json` and the plugin manifest failed
  `claude plugin validate` (spaces in the name, no `owner`/`plugins`, hooks declared as
  prose)

## [1.1.0] - 2026-02-17

### Added
- CLI wrapper (`bin/uws`) for unified command interface covering all 15 scripts
- Root-level installer (`install.sh`) with symlink to `~/.local/bin`
- 26 BATS tests for the CLI wrapper (646 total tests)
- Examples for ML research project and Node.js webapp workflows
- GitHub Pages landing site (`docs/index.html`)
- CONTRIBUTORS.md
- CHANGELOG.md
- State schema documentation (`docs/state-schema.md`)
- Vector Memory section in README
- CI/CD section in README
- GitHub repository topics for discoverability

### Fixed
- 22 documentation errors across README, CONTRIBUTING, and plugin files
- Research phases updated from 5 to 7 in README (added literature_review, peer_review)
- Test count badges updated from 361 to 620+
- Plugin/marketplace URLs corrected from `lab2208` to `Yash-Sukhdeve`
- Install script URLs corrected from `YOUR_REPO/main` to `Yash-Sukhdeve/.../master`
- `.env.example` in README updated to match actual file (JWT_SECRET_KEY, postgresql, 15 min)
- MCP config section updated for vector memory servers
- Removed reference to nonexistent `handoff.sh` script

## [1.0.0] - 2026-02-17

### Added
- Initial release with full workflow system
- 7 specialized agents (researcher, architect, implementer, experimenter, optimizer, deployer, documenter)
- Research workflow (7 phases: hypothesis through publication)
- SDLC workflow (6 phases: requirements through maintenance)
- Checkpoint system with snapshot/restore and integrity verification
- Context recovery system with automatic session injection
- Vector memory integration (local + global databases)
- 620 BATS tests across unit, integration, and system categories
- Claude Code plugin with slash commands, hooks, and autonomous skills
- Company OS backend (FastAPI) and React dashboard
- PROMISE 2026 research paper and replication package
