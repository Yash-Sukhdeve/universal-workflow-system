# Research-team test fixtures

Used by `tests/integration/test_research_team.bats` (acceptance tests AT1-AT10 of
`docs/design/research-team.md` section 11).

- `project/` is a small research project that passes every phase gate of
  `scripts/research_check.py`. Each test copies it and breaks one thing.
  - `artifacts/model_results.json` holds **synthetic values written for the tests**; they
    are not measurements, and the ledger labels them `synthetic-generated`.
  - `bib_sources/sandve2013.bib` and its `.meta.json` were downloaded on 2026-09-26 by
    `scripts/research_bib.sh fetch doi:10.1371/journal.pcbi.1003285 --key sandve2013`
    (DOI content negotiation). They are not hand-written.
  - `research/sources/cache/sandve2013.txt` is an excerpt (Rule 1) of Sandve et al. 2013,
    PLoS Comput Biol 9(10): e1003285, retrieved from the PLOS article XML. The article is
    published under the Creative Commons Attribution License; the file header gives the
    attribution.
- `responses/` holds raw HTTP bodies for the fetcher tests, captured on 2026-09-26:
  - `arxiv_2309.11495.bib` from `https://arxiv.org/bibtex/2309.11495` (HTTP 200, text/plain);
  - `dblp_bot_check.html` from `https://dblp.org/rec/journals/corr/abs-2309-11495.bib`,
    which answered a scripted request with HTTP 200 and this HTML "Making sure you're not a
    bot!" page instead of BibTeX.
