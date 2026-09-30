---
description: Run the research team's evidence checks (ledger, bib, quotes, numbers, slop, plan, data, retraction) or a phase gate
argument-hint: "<ledger|bib|quotes|numbers|slop|plan|data|retraction|repro <N-ID|all>|manuscript-hash|gate <phase>|init>"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/bin/uws research check:*)
---

Run the UWS research evidence check with the user's arguments (`$ARGUMENTS`; if empty,
run `gate` with the current research phase shown by
`${CLAUDE_PLUGIN_ROOT}/bin/uws research status`):

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
