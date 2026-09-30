---
description: Run the research team's evidence checks (ledger, bib, quotes, numbers, slop) or a phase gate
argument-hint: "<ledger|bib|quotes|numbers|slop|gate <phase>|init>"
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
the generated macros). Do
not edit ledgers or `bib_sources/` to make a check pass, and do not suggest `--force`.
