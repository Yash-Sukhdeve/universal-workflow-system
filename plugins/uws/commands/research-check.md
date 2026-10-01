---
description: Run the research team's evidence checks (ledger, claims, bib, quotes, numbers, slop, plan, data, retraction) or a phase gate
argument-hint: "<ledger|claims [add '<json>']|bib|quotes|numbers [add '<json>']|slop|plan|data|run ... -- <cmd>|repro <N-ID|all>|retraction|manuscript-hash|macros|gate <phase>|init>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws research check:*), Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws research status:*)
---

Run the UWS research evidence check with the user's arguments (`$ARGUMENTS`). If they are
empty, run `${CLAUDE_PLUGIN_ROOT}/bin/uws research status` and run `gate` with the current
research phase it shows. If `research status` fails (a project without
`.workflow/state.yaml`: the checks do not need one, the phase actions do), ask the user
which phase to gate instead of guessing:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/uws research check <arguments>
```

Each finding is one line, `file:line RULE-ID message`. Exit 0 means pass, 1 means
findings, 2 means the check could not run (a gate fails closed). Report the findings
grouped by rule, with file and line, and say which role should fix each one (claims the
verifier, BibTeX the fetcher `${CLAUDE_PLUGIN_ROOT}/bin/uws research bib fetch`, numbers
the generated macros, plans the methodologist, data manifest, run records and repro the
engineer, a stale red-team review the red team). `repro` re-runs recorded commands in a
scratch copy and can take as long as the original runs. Do not edit ledgers, plans,
`research/data/` or `bib_sources/` to make a check pass, and do not suggest `--force`.
