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
  - Increment 2 (`test_research_team_inc2.bats`):
    - `research/data/raw/gb_scores.csv` was written by
      `python3 research/code/gen_scores.py --seed 7 --out research/data/raw/gb_scores.csv`.
      The generator builds **synthetic** per-fold AUC values around fixed centres (CV mean
      exactly 0.9125, test 0.9199); they are not measurements. It is registered in
      `research/data/manifest.jsonl` with its generator and seed.
    - `artifacts/model_results.json` is exactly what
      `research/code/make_results.py research/data/raw/gb_scores.csv artifacts/model_results.json`
      writes (byte-identical, so N-0001's hash is unchanged). The tests record that command
      as RUN-0001 and re-run it with the repro job.
    - `research/experiments/EXP-LEAK/plan.md` is frozen in `research/ledger/plans.jsonl`
      (written by `research_check.py plan freeze EXP-LEAK`). The tests commit the freeze
      before the rest of the fixture, as a real project must.
    - `research/sources/retractions.jsonl` holds the answer of a real Crossref lookup for
      sandve2013 (`research_check.py retraction --online`, 2026-09-30): no notice.
    - `research/reviews/REV-001.md` names the fixture manuscript hash
      (`research_check.py manuscript-hash`).
- `responses/` holds raw HTTP bodies for the fetcher tests, captured on 2026-09-26:
  - `arxiv_2309.11495.bib` from `https://arxiv.org/bibtex/2309.11495` (HTTP 200, text/plain);
  - `dblp_bot_check.html` from `https://dblp.org/rec/journals/corr/abs-2309-11495.bib`,
    which answered a scripted request with HTTP 200 and this HTML "Making sure you're not a
    bot!" page instead of BibTeX.
- `responses/` also holds bodies for the retraction tests, captured unmodified on 2026-09-30:
  - `doi_wakefield1998.bib` from `https://doi.org/10.1016/S0140-6736(97)11096-0` with
    `Accept: application/x-bibtex` (HTTP 200) - a paper The Lancet retracted in 2010;
  - `crossref_work_wakefield1998.json` from
    `https://api.crossref.org/works/10.1016/S0140-6736(97)11096-0` and
    `crossref_updates_wakefield1998.json` from
    `https://api.crossref.org/works?filter=updates:10.1016/S0140-6736(97)11096-0&rows=20`
    (a `correction` and a `retraction`, both with `source: retraction-watch`);
  - `crossref_work_sandve2013.json` and `crossref_updates_sandve2013.json`, the same two
    requests for 10.1371/journal.pcbi.1003285 (no update notices).
- `promise/` holds lines copied verbatim from the PROMISE 2026 paper
  (`github.com/Yash-Sukhdeve/uws-promise-2026` at `778ab9a`) for the field-test regression
  tests in `test_research_team_fieldtest.bats` (design section 11b):
  - `abstract.tex`: `paper/main-promise.tex:63-70`;
  - `intro-findings.tex`: `paper/sections/01-introduction-promise.tex:24-28`;
  - `intro-contribution.tex`: `paper/sections/01-introduction-promise.tex:33`;
  - `intro-first.tex`: `paper/sections/01-introduction-promise.tex:35`;
  - `background-insight.tex`: `paper/sections/02-background.tex:62`;
  - `approach-dataset.tex`: `paper/sections/03-approach.tex:24`;
  - `approach-platform.tex`: `paper/sections/03-approach.tex:120`.
