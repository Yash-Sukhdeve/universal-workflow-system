#!/usr/bin/env python3
"""Deterministic evidence checks for the UWS research team.

Design: docs/design/research-team.md (sections 5, 6 and 11). Python 3.8+ standard
library only (PI decision 5 in that file). Every check is offline and deterministic:
the same committed files give the same result, so CI and `research.sh next` agree.

Usage:
    research_check.py [--root DIR] [--json] <command> [options]

Commands (increment 1):
    ledger              claim/number ledger schema, separation of duties, append-only
    bib                 bib_sources/ provenance and references.bib equality
    quotes              recorded quotes are verbatim substrings of the cached source text
    numbers             number provenance: output hash, pointer value, rounding, macros,
                        hand-typed decimals; formulas over other numbers; evaluation split
    slop                S1 S2 S4 S6 (prose) and C1 C3 C5 C6 (code / disclosure)
    gate <phase>        the evidence gate for one research phase
    role-exit           SubagentStop hook check (reads the hook JSON on stdin)
    init                scaffold research/ and bib_sources/ (never overwrites)
Commands (increment 2):
    plan [new|freeze <EXP-ID>]
                        pre-registration: plan fields, frozen hash, freeze before results,
                        deviations after results need a PI decision
    data [add <path> ...]
                        data manifest (research/data/manifest.jsonl): hashes, sizes,
                        seeds of generated data, inputs of every number
    run [options] -- <command>
                        run a command and write research/runs/RUN-*/run.json
    repro <N-ID ...|all>
                        re-run the recorded commands in a scratch copy and compare
                        each number within its tolerance; writes research/repro/
    retraction [--online]
                        retraction notices (Crossref) for bib_sources/ DOIs; --online
                        refreshes research/sources/retractions.jsonl, gates stay offline
    manuscript-hash     the hash a red-team review must name (`Manuscript: sha256:...`)
    macros              write the generated macro file from the number ledger
Internal (called by scripts/research_bib.sh):
    bib-ingest          validate a downloaded BibTeX body and store it with .meta.json
    bib-build           write references.bib from bib_sources/ only

Output: one line per finding, `file:line RULE-ID message` (`[warn]` marks a finding that
does not fail the check). Exit codes: 0 pass, 1 findings, 2 environment error.
Only `run`, `repro` and `retraction --online` execute commands or use the network.
"""

import argparse
import ast
import csv
import datetime
import glob
import hashlib
import io
import json
import os
import platform
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import tokenize
import unicodedata
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_DOWN, ROUND_FLOOR, ROUND_HALF_EVEN, ROUND_HALF_UP
from urllib.parse import quote as url_quote

EXIT_OK, EXIT_FINDINGS, EXIT_ENV = 0, 1, 2
# role-exit uses its own codes so the hook wrapper never confuses "block" with a crash.
EXIT_ROLE_BLOCK, EXIT_ROLE_EXHAUSTED = 10, 11

PHASES = ("hypothesis", "literature_review", "experiment_design", "data_collection",
          "analysis", "peer_review", "publication")

# Ledger vocabulary (design section 6.2; apocalypt.md P3 and P4).
CATEGORIES = ("established_fact", "reported_finding", "own_observation", "inference",
              "hypothesis", "estimate", "open_question")
STRENGTH_RANK = {"none": 0, "association": 1, "empirical": 2, "causal": 3, "proof": 4}
STATUSES = ("unverified", "verified", "supported", "disputed", "refuted",
            "unverifiable-access", "retracted")
VERDICTS = ("supports", "partial", "does-not-support", "contradicts", "unverifiable-access")
DATA_ORIGINS = ("measured", "simulated", "synthetic-generated", "literature")
NON_MEASURED = ("simulated", "synthetic-generated")
HYPOTHESIS_FIELDS = ("mechanism", "distinguishing_prediction", "strongest_alternative",
                     "undermining_observation")
LIT_VERIFIER_ROLES = ("verifier", "pi")
BIB_ID_TYPES = ("arxiv", "doi", "dblp", "acl", "pi-supplied")

CID_RE = re.compile(r"\bC-\d+\b")
NID_RE = re.compile(r"^N-\d+$")
ROLE_RE = re.compile(r"^[a-z][a-z0-9_-]*$")
DID_RE = re.compile(r"\bD-\d+\b")
CITEKEY_RE = re.compile(r"^[^\s,{}()\"#%'=\\~]+$")
EXP_RE = re.compile(r"^EXP-[A-Za-z0-9_-]+$")
RUN_RE = re.compile(r"^RUN-[\w-]+$")
DEV_RE = re.compile(r"\bDEV-\d+\b")

# Increment 2 vocabulary.
# How a number was evaluated. A cross-validation mean is not a held-out result (the
# PROMISE audit found CV means reported as if they were held-out test values).
EVALUATIONS = ("held-out", "validation", "cross-validation", "training", "n/a")
EXPLORATORY = "exploratory"
# Where the labels of a dataset come from; "generator-rule" labels are not ground truth.
LABEL_ORIGINS = ("generator-rule", "annotation", "measurement", "none")
UNRECORDED_SEEDS = ("", "none", "unrecorded", "unknown", "null")
# Crossref update types (Crossmark schema, 12 types; see retraction_status()).
RETRACTED_TYPES = ("retraction", "withdrawal", "removal")
CONCERN_TYPES = ("partial_retraction", "expression_of_concern")
TOLERANCE_KINDS = ("exact", "abs", "rel")

DEFAULT_EXCLUDES = {".git", ".workflow", ".uws", "workspace", "node_modules", "venv", ".venv",
                    "__pycache__", "bib_sources", "archive"}

DEFAULT_CONFIG = {
    "tex_main": None,            # restrict prose to files reachable from this .tex via \input
    "prose_dirs": None,          # default: every .tex under the root, plus paper/**/*.md
    "code_dirs": ["research", "benchmarks"],
    "references": None,          # default: paper/references.bib, then references.bib
    "numbers_tex": "paper/generated/numbers.tex",
    "exclude_dirs": [],
    "min_quote_words": 5,
    "allow_missing_cache": False,
}


# --------------------------------------------------------------------------- findings

class Finding(object):
    __slots__ = ("path", "line", "rule", "msg", "level")

    def __init__(self, path, line, rule, msg, level="block"):
        self.path, self.line, self.rule, self.msg, self.level = path, line, rule, msg, level

    def render(self):
        tag = " [warn]" if self.level == "warn" else ""
        return "%s:%d %s%s %s" % (self.path, self.line, self.rule, tag, self.msg)

    def as_dict(self):
        return {"file": self.path, "line": self.line, "rule": self.rule,
                "level": self.level, "message": self.msg}


def dedupe(findings):
    """Drop repeats (a gate runs overlapping checks, e.g. ledger and numbers both check the
    number-row schema), keeping the first of each."""
    seen, out = set(), []
    for f in findings:
        key = (f.path, f.line, f.rule, f.msg, f.level)
        if key not in seen:
            seen.add(key)
            out.append(f)
    return out


class EnvError(Exception):
    """The check could not run (missing file, bad config). Exit 2: gates fail closed."""


# --------------------------------------------------------------------------- project

class Project(object):
    def __init__(self, root):
        self.root = os.path.abspath(root)
        self.config = dict(DEFAULT_CONFIG)
        cfg_path = self.path("research/checks.json")
        if os.path.isfile(cfg_path):
            try:
                with open(cfg_path, encoding="utf-8") as fh:
                    user = json.load(fh)
            except (OSError, ValueError) as exc:
                raise EnvError("research/checks.json is not valid JSON: %s" % exc)
            if not isinstance(user, dict):
                raise EnvError("research/checks.json must be a JSON object")
            unknown = sorted(set(user) - set(DEFAULT_CONFIG))
            if unknown:
                raise EnvError("research/checks.json: unknown keys %s" % ", ".join(unknown))
            self.config.update(user)
        self._claims = None
        self._numbers = None
        self._manifest = None
        self._runs = None
        self._plans = None
        self._docs = {}
        self._links = None

    def doc(self, path):
        """A parsed prose file, read once per check run."""
        key = os.path.abspath(path)
        if key not in self._docs:
            self._docs[key] = Doc(self, key)
        return self._docs[key]

    def links(self):
        """Ledger rows located in the manuscript by their `where` field (see WhereLinks)."""
        if self._links is None:
            self._links = WhereLinks(self)
        return self._links

    def macro_index(self):
        """Macro name of each current number row -> its N-ID."""
        return {row["macro"]: nid for nid, (_l, row) in sorted(self.numbers().latest.items())
                if isinstance(row.get("macro"), str) and row.get("macro")}

    def path(self, rel):
        return os.path.join(self.root, rel)

    def rel(self, path):
        return os.path.relpath(path, self.root)

    def excluded(self, rel_dir_parts):
        extra = set(self.config.get("exclude_dirs") or [])
        for i, part in enumerate(rel_dir_parts):
            if part in DEFAULT_EXCLUDES or part in extra:
                return True
            joined = "/".join(rel_dir_parts[:i + 1])
            if joined in extra or joined == "research/sources":
                return True
        return False

    def walk(self, start_rel, exts):
        start = self.path(start_rel)
        if os.path.isfile(start):
            return [start] if start.endswith(exts) else []
        out = []
        for dirpath, dirnames, filenames in os.walk(start):
            rel_parts = [p for p in os.path.relpath(dirpath, self.root).split(os.sep) if p != "."]
            if self.excluded(rel_parts):
                dirnames[:] = []
                continue
            dirnames.sort()
            for name in sorted(filenames):
                if name.endswith(exts):
                    out.append(os.path.join(dirpath, name))
        return out

    # ---- ledgers
    def claims(self):
        if self._claims is None:
            self._claims = Ledger(self, "research/ledger/claims.jsonl", "C")
        return self._claims

    def numbers(self):
        if self._numbers is None:
            self._numbers = Ledger(self, "research/ledger/numbers.jsonl", "N")
        return self._numbers

    def manifest(self):
        if self._manifest is None:
            self._manifest = Manifest(self)
        return self._manifest

    def runs(self):
        """RUN-ID -> (rel path of run.json, record dict or None, error message or None)."""
        if self._runs is None:
            self._runs = {}
            d = self.path("research/runs")
            if os.path.isdir(d):
                for name in sorted(os.listdir(d)):
                    path = os.path.join(d, name, "run.json")
                    if not os.path.isfile(path):
                        continue
                    rel = self.rel(path)
                    try:
                        with open(path, encoding="utf-8") as fh:
                            rec = json.load(fh)
                    except (OSError, ValueError) as exc:
                        self._runs[name] = (rel, None, "not valid JSON: %s" % exc)
                        continue
                    if not isinstance(rec, dict):
                        self._runs[name] = (rel, None, "must be one JSON object")
                        continue
                    self._runs[name] = (rel, rec, None)
        return self._runs

    def plans(self):
        if self._plans is None:
            self._plans = Plans(self)
        return self._plans

    # ---- prose and code scope
    def tex_files(self):
        main = self.config.get("tex_main")
        if main:
            files, _missing = tex_closure(self, main)
            return files
        dirs = self.config.get("prose_dirs")
        out = []
        for d in (dirs or ["."]):
            out.extend(self.walk(d, (".tex",)))
        return sorted(set(out))

    def prose_files(self):
        files = list(self.tex_files())
        dirs = self.config.get("prose_dirs")
        md_dirs = dirs if dirs else (["paper"] if os.path.isdir(self.path("paper")) else [])
        for d in md_dirs:
            files.extend(self.walk(d, (".md",)))
        return sorted(set(files))

    def code_files(self):
        out = []
        for d in self.config.get("code_dirs") or []:
            if os.path.exists(self.path(d)):
                out.extend(self.walk(d, (".py", ".sh", ".R", ".r", ".jl")))
        return sorted(set(out))

    def references_path(self):
        ref = self.config.get("references")
        if ref:
            return self.path(ref)
        for cand in ("paper/references.bib", "references.bib"):
            if os.path.isfile(self.path(cand)):
                return self.path(cand)
        return None


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


# --------------------------------------------------------------------------- ledgers

class Ledger(object):
    """An append-only JSON Lines ledger. The latest revision of each ID is current."""

    def __init__(self, project, rel, prefix):
        self.project, self.rel, self.prefix = project, rel, prefix
        self.path = project.path(rel)
        self.exists = os.path.isfile(self.path)
        self.rows = []          # (lineno, dict)
        self.parse_errors = []  # Finding
        self.latest = {}        # id -> (lineno, dict)
        if self.exists:
            self._load()

    def _load(self):
        with open(self.path, encoding="utf-8") as fh:
            for lineno, raw in enumerate(fh, 1):
                if not raw.strip():
                    continue
                try:
                    obj = json.loads(raw)
                except ValueError as exc:
                    self.parse_errors.append(Finding(self.rel, lineno, "LEDGER-PARSE",
                                                     "not valid JSON: %s" % exc))
                    continue
                if not isinstance(obj, dict):
                    self.parse_errors.append(Finding(self.rel, lineno, "LEDGER-PARSE",
                                                     "each line must be one JSON object"))
                    continue
                self.rows.append((lineno, obj))
                rid = obj.get("id")
                if isinstance(rid, str):
                    prev = self.latest.get(rid)
                    if prev is None or _rev(obj) >= _rev(prev[1]):
                        self.latest[rid] = (lineno, obj)


    def appended(self, obj):
        """(a copy of this ledger with `obj` appended in memory, the line it would take)."""
        new = Ledger.__new__(Ledger)
        new.project, new.rel, new.prefix, new.path = self.project, self.rel, self.prefix, self.path
        new.exists, new.parse_errors = True, list(self.parse_errors)
        new.rows, new.latest = list(self.rows), dict(self.latest)
        lineno = 1
        if os.path.isfile(self.path):
            with open(self.path, encoding="utf-8") as fh:
                lineno = sum(1 for _ in fh) + 1
        new.rows.append((lineno, obj))
        rid = obj.get("id")
        if isinstance(rid, str):
            prev = new.latest.get(rid)
            if prev is None or _rev(obj) >= _rev(prev[1]):
                new.latest[rid] = (lineno, obj)
        return new, lineno


def _rev(obj):
    r = obj.get("rev", 1)
    return r if isinstance(r, int) and not isinstance(r, bool) else 1


def check_ledger(project, bases=None):
    """Claim ledger rules (design 6.2) plus the number ledger's shape. AT1, AT9."""
    findings = []
    claims = project.claims()
    numbers = project.numbers()
    if not os.path.isdir(project.path("research/ledger")):
        raise EnvError("research/ledger/ not found under %s (run: research_check.py init)" % project.root)
    for led in (claims, numbers):
        findings.extend(led.parse_errors)
        findings.extend(_check_revisions(led))
        findings.extend(check_append_only(project, led, bases))

    # Separation of duties and category rules apply to the current revision of each claim.
    for cid in sorted(claims.latest):
        lineno, row = claims.latest[cid]
        findings.extend(_check_claim(project, claims, numbers, lineno, row))
    findings.extend(_check_number_shapes(numbers))
    return findings


def _check_revisions(led):
    out = []
    seen = {}
    id_re = re.compile(r"^%s-\d+$" % led.prefix)
    for lineno, row in led.rows:
        rid = row.get("id")
        if not isinstance(rid, str) or not id_re.match(rid):
            out.append(Finding(led.rel, lineno, "LEDGER-SCHEMA",
                               "id must look like %s-0001 (got %r)" % (led.prefix, rid)))
            continue
        rev = row.get("rev", 1)
        if not isinstance(rev, int) or isinstance(rev, bool) or rev < 1:
            out.append(Finding(led.rel, lineno, "LEDGER-SCHEMA", "%s: rev must be an integer >= 1" % rid))
            continue
        last = seen.get(rid, 0)
        if rev == last or rev < last:
            out.append(Finding(led.rel, lineno, "LEDGER-REV",
                               "%s@%d repeats or goes back (latest so far @%d); append a new revision" % (rid, rev, last)))
        elif rev != last + 1:
            out.append(Finding(led.rel, lineno, "LEDGER-REV",
                               "%s@%d skips revision %d" % (rid, rev, last + 1)))
        want = None if rev == 1 else "%s@%d" % (rid, rev - 1)
        if row.get("supersedes") != want:
            out.append(Finding(led.rel, lineno, "LEDGER-REV",
                               "%s@%d must have supersedes=%s" % (rid, rev, json.dumps(want))))
        seen[rid] = max(last, rev)
    return out


def _check_claim(project, claims, numbers, lineno, row):
    rel = claims.rel
    cid = row["id"]
    out = []

    def bad(rule, msg, level="block"):
        out.append(Finding(rel, lineno, rule, "%s: %s" % (cid, msg), level))

    for key in ("text", "category", "status", "author"):
        if not isinstance(row.get(key), str) or not row.get(key).strip():
            bad("LEDGER-SCHEMA", "missing required field '%s'" % key)
    cat, status, author = row.get("category"), row.get("status"), row.get("author")
    if cat not in CATEGORIES:
        bad("LEDGER-SCHEMA", "category %r is not one of %s" % (cat, ", ".join(CATEGORIES)))
    if status not in STATUSES:
        bad("LEDGER-SCHEMA", "status %r is not one of %s" % (status, ", ".join(STATUSES)))
    if isinstance(author, str) and author and not ROLE_RE.match(author):
        bad("LEDGER-SCHEMA", "author must be a role name such as 'scout' (got %r)" % author)
    strength = row.get("strength", "none")
    if strength not in STRENGTH_RANK:
        bad("LEDGER-SCHEMA", "strength %r is not one of %s" % (strength, ", ".join(STRENGTH_RANK)))
    origin = row.get("data_origin")
    if origin is not None and origin not in DATA_ORIGINS:
        bad("LEDGER-SCHEMA", "data_origin %r is not one of %s" % (origin, ", ".join(DATA_ORIGINS)))
    # Where the claim's labels come from (optional); "generator-rule" makes C6 block on any
    # sentence the claim is attached to.
    if row.get("labels") is not None and row.get("labels") not in LABEL_ORIGINS:
        bad("LEDGER-SCHEMA", "labels %r is not one of %s" % (row.get("labels"), ", ".join(LABEL_ORIGINS)))
    if row.get("where") is not None and not isinstance(row.get("where"), str):
        bad("LEDGER-SCHEMA", "where must be a string such as \"paper/main.tex:12\"")

    verified_by = row.get("verified_by")
    # The core rule: the author of a claim can never be the one who verifies it (AT1).
    if verified_by and verified_by == author:
        bad("LEDGER-SELFVERIFY", "verified_by == author (%s); a different role must verify, "
            "so append a new revision with status 'unverified'" % author)
    if status == "verified":
        if not verified_by:
            bad("LEDGER-VERIFY", "status 'verified' needs verified_by")
        if not row.get("verified_at"):
            bad("LEDGER-VERIFY", "status 'verified' needs verified_at")
        if row.get("verdict") != "supports":
            bad("LEDGER-VERIFY", "status 'verified' needs verdict 'supports' (got %r)" % row.get("verdict"))
    if row.get("verdict") is not None and row.get("verdict") not in VERDICTS:
        bad("LEDGER-SCHEMA", "verdict %r is not one of %s" % (row.get("verdict"), ", ".join(VERDICTS)))

    sources = row.get("sources") or []
    if not isinstance(sources, list):
        bad("LEDGER-SCHEMA", "sources must be a list")
        sources = []
    for i, src in enumerate(sources):
        if not isinstance(src, dict) or not src.get("citekey"):
            bad("LEDGER-SCHEMA", "sources[%d] needs a citekey" % i)
        elif not src.get("quote") or not src.get("locator"):
            bad("LEDGER-SOURCE", "sources[%d] (%s) needs a verbatim quote and a locator" % (i, src.get("citekey")))

    if cat in ("established_fact", "reported_finding") and status == "verified" and not sources:
        bad("LEDGER-SOURCE", "a verified %s needs at least one source with a quote" % cat)

    nums = row.get("numbers") or []
    if not isinstance(nums, list):
        bad("LEDGER-SCHEMA", "numbers must be a list of N-IDs")
        nums = []
    for nid in nums:
        if not isinstance(nid, str) or not NID_RE.match(nid):
            bad("LEDGER-REF", "numbers entry %r is not an N-ID" % (nid,))
        elif nid not in numbers.latest:
            bad("LEDGER-REF", "%s is not in research/ledger/numbers.jsonl" % nid)
    if cat == "own_observation" and status == "verified" and not nums and not row.get("run"):
        bad("LEDGER-EVIDENCE", "a verified own_observation needs N-IDs or a run ID")

    deps = row.get("depends_on") or []
    if not isinstance(deps, list):
        bad("LEDGER-SCHEMA", "depends_on must be a list of C-IDs")
        deps = []
    for dep in deps:
        if dep not in claims.latest:
            bad("LEDGER-REF", "depends_on %s is not in the claim ledger" % dep)
    if cat == "inference":
        if not deps:
            bad("LEDGER-EVIDENCE", "an inference needs depends_on")
        else:
            ranks = [STRENGTH_RANK.get(claims.latest[d][1].get("strength", "none"), 0)
                     for d in deps if d in claims.latest]
            if ranks and STRENGTH_RANK.get(strength, 0) > min(ranks):
                bad("LEDGER-STRENGTH", "inference strength '%s' is stronger than its weakest dependency" % strength)

    if cat == "hypothesis":
        if status == "verified":
            bad("LEDGER-HYPOTHESIS", "a hypothesis is never 'verified'; it becomes 'supported' or 'refuted' through an EXP")
        if status in ("supported", "refuted") and not re.match(r"^EXP-[\w-]+$", str(row.get("exp") or "")):
            bad("LEDGER-HYPOTHESIS", "status '%s' needs exp=EXP-... (the experiment that decided it)" % status)
        for field in HYPOTHESIS_FIELDS:
            if not isinstance(row.get(field), str) or not row.get(field).strip():
                bad("LEDGER-HYPOTHESIS", "missing '%s' (apocalypt.md P2)" % field)
    elif status == "supported":
        bad("LEDGER-SCHEMA", "status 'supported' is only for hypotheses")
    return out


NUMBER_REQUIRED = ("macro", "printed", "raw", "rounding", "metric", "output", "pointer",
                   "output_sha256", "data_origin")


def _check_number_shapes(numbers):
    """Schema of the current revision of every number row, plus macro names used twice."""
    out = []
    owners = {}
    for nid in sorted(numbers.latest):
        lineno, row = numbers.latest[nid]
        out.extend(_number_shape(numbers.rel, nid, lineno, row))
        if isinstance(row.get("macro"), str) and row.get("macro"):
            owners.setdefault(row["macro"], []).append((nid, lineno))
    for macro, rows in sorted(owners.items()):
        if len(rows) > 1:
            for nid, lineno in rows[1:]:
                out.append(Finding(numbers.rel, lineno, "NUM-SCHEMA", "%s: macro %s is also used by %s; each number "
                                   "needs its own macro" % (nid, macro, rows[0][0])))
    return out


def _number_shape(rel, nid, lineno, row):
    """Schema of one number row (design 6.4, increment 2 and the field-test fields)."""
    out = []

    def bad(msg):
        out.append(Finding(rel, lineno, "NUM-SCHEMA", "%s: %s" % (nid, msg)))

    for key in NUMBER_REQUIRED:
        if row.get(key) in (None, ""):
            bad("missing '%s'" % key)
    if row.get("data_origin") not in (None, "") and row.get("data_origin") not in DATA_ORIGINS:
        bad("data_origin %r is not one of %s" % (row.get("data_origin"), ", ".join(DATA_ORIGINS)))
    macro = row.get("macro")
    if macro and not re.match(r"^\\[A-Za-z]+$", str(macro)):
        bad("macro must look like \\\\Name")
    # Optional fields; their values are checked when present.
    ev = row.get("evaluation")
    if ev is not None and ev not in EVALUATIONS:
        bad("evaluation %r is not one of %s" % (ev, ", ".join(EVALUATIONS)))
    exp = row.get("exp")
    if exp is not None and exp != EXPLORATORY and not EXP_RE.match(str(exp)):
        bad("exp must be EXP-<name> or %r (got %r)" % (EXPLORATORY, exp))
    inputs = row.get("inputs")
    if inputs is not None and (not isinstance(inputs, list) or not all(isinstance(i, str) for i in inputs)):
        bad("inputs must be a list of project paths")
    if row.get("formula") is not None and not isinstance(row.get("formula"), str):
        bad("formula must be a string such as \"N-0002/(N-0002+N-0003)\"")
    tol_err = tolerance_error(row.get("tolerance"))
    if tol_err:
        bad(tol_err)
    where = row.get("where")
    if where is not None and not isinstance(where, str):
        bad("where must be a string such as \"paper/main.tex:12; paper/results.tex#tab:auc\"")
    unr = row.get("unrounded")
    if unr is not None and (not isinstance(unr, dict) or not all(isinstance(unr.get(k), str) and unr.get(k)
                                                                 for k in ("run", "output", "pointer"))):
        bad("unrounded must be {\"run\": RUN-ID, \"output\": path, \"pointer\": \"/json/pointer\"}")
    return out


def tolerance_error(tol):
    """None when `tol` is absent or a valid {"kind": exact|abs|rel, "value": x}."""
    if tol is None:
        return None
    if not isinstance(tol, dict) or tol.get("kind") not in TOLERANCE_KINDS:
        return "tolerance must be {\"kind\": \"exact\"|\"abs\"|\"rel\", \"value\": <number>}"
    if tol["kind"] != "exact":
        v = tol.get("value")
        if isinstance(v, bool) or not isinstance(v, (int, float)) or v < 0:
            return "tolerance value must be a number >= 0"
    return None


def _git(project, args):
    try:
        proc = subprocess.run(["git", "-C", project.root] + args, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.decode("utf-8", "replace")


def check_append_only(project, led, bases=None):
    """Every line committed at a base ref is still present, byte for byte (AT9).

    Default bases: HEAD (catches uncommitted edits or deletions) and HEAD~1 (catches a
    committed deletion). Outside a git repository there is nothing to compare against.
    """
    if not led.exists:
        return []
    return append_only_findings(project, led.rel, "LEDGER-APPEND", bases)


def append_only_findings(project, rel, rule, bases=None):
    """Lines of a JSON Lines file committed at HEAD / HEAD~1 must still be present."""
    out = []
    path = project.path(rel)
    if not os.path.isfile(path):
        return out
    if not in_git(project):
        return out
    current = set()
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            if raw.strip():
                current.add(raw.rstrip("\n"))
    for ref in (bases or ["HEAD", "HEAD~1"]):
        old = _git(project, ["show", "%s:./%s" % (ref, rel)])
        if old is None:
            continue
        for oldline in old.splitlines():
            if not oldline.strip() or oldline in current:
                continue
            label = "?"
            try:
                obj = json.loads(oldline)
                key = obj.get("id") or obj.get("exp") or obj.get("path") or obj.get("citekey") or "?"
                label = "%s@%s" % (key, obj.get("rev", 1))
            except (ValueError, AttributeError):
                pass
            out.append(Finding(rel, 1, rule,
                               "%s was removed or edited compared with %s; this file is append-only "
                               "(restore it from git and append a new row instead)" % (label, ref)))
    return out


def in_git(project):
    return _git(project, ["rev-parse", "--is-inside-work-tree"]) is not None


def git_head(project):
    out = _git(project, ["rev-parse", "HEAD"])
    return out.strip() if out else None


def is_ancestor(project, older, newer):
    """True when `older` is `newer` or one of its ancestors."""
    proc = _git_rc(project, ["merge-base", "--is-ancestor", older, newer])
    return proc == 0


def _git_rc(project, args):
    try:
        proc = subprocess.run(["git", "-C", project.root] + args, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return proc.returncode


def first_appearance(project, rel, extract):
    """Map each key that `extract(text)` finds in a committed version of `rel` to the first
    commit (in HEAD's history, parents before children) whose version of `rel` contains it."""
    log = _git(project, ["log", "--topo-order", "--reverse", "--format=%H", "--", rel])
    first = {}
    for commit in (log or "").split():
        text = _git(project, ["show", "%s:./%s" % (commit, rel)])
        if text is None:
            continue
        for key in extract(text):
            first.setdefault(key, commit)
    return first


def _jsonl_objects(text):
    for raw in text.splitlines():
        if not raw.strip():
            continue
        try:
            obj = json.loads(raw)
        except ValueError:
            continue
        if isinstance(obj, dict):
            yield obj


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_utc(text):
    try:
        return datetime.datetime.strptime(str(text), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except ValueError:
        return None


def canonical_sha(obj):
    """Hash of a JSON value that does not depend on key order or whitespace."""
    return hashlib.sha256(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def safe_rel(project, rel):
    """A project-relative path that stays inside the project, or None."""
    if not isinstance(rel, str) or not rel.strip() or os.path.isabs(rel):
        return None
    norm = os.path.normpath(rel)
    if norm == ".." or norm.startswith(".." + os.sep) or norm == ".":
        return None
    return norm.replace(os.sep, "/")


# --------------------------------------------------------------------------- BibTeX

class BibEntry(object):
    __slots__ = ("etype", "key", "fields", "start", "end", "line", "text")

    def __init__(self, etype, key, fields, start, end, line, text):
        self.etype, self.key, self.fields = etype, key, fields
        self.start, self.end, self.line, self.text = start, end, line, text


class BibError(Exception):
    pass


def looks_like_html(text):
    head = text.lstrip()[:2048].lower()
    return head.startswith("<") or "<html" in head or "<!doctype" in head or "<body" in head


def parse_bib(text):
    """Parse BibTeX strictly. Returns (entries, outside_text). Raises BibError."""
    entries, outside = [], []
    i, n = 0, len(text)
    while i < n:
        at = text.find("@", i)
        if at < 0:
            outside.append(text[i:])
            break
        outside.append(text[i:at])
        m = re.match(r"@\s*([A-Za-z]+)\s*([{(])", text[at:])
        if not m:
            raise BibError("line %d: '@' is not followed by an entry type and '{'" % (text.count("\n", 0, at) + 1))
        etype, opener = m.group(1).lower(), m.group(2)
        j = at + m.end()
        depth, k, end = 0, j, None
        while k < n:
            c = text[k]
            if c == "{":
                depth += 1
            elif c == "}":
                if depth == 0 and opener == "{":
                    end = k
                    break
                depth -= 1
                if depth < 0:
                    raise BibError("line %d: unbalanced '}'" % (text.count("\n", 0, k) + 1))
            elif c == ")" and opener == "(" and depth == 0:
                end = k
                break
            k += 1
        if end is None:
            raise BibError("line %d: entry is not closed" % (text.count("\n", 0, at) + 1))
        body = text[j:end]
        line = text.count("\n", 0, at) + 1
        if etype == "comment":
            i = end + 1
            continue
        if etype in ("preamble", "string"):
            entries.append(BibEntry(etype, None, {}, at, end + 1, line, text[at:end + 1]))
            i = end + 1
            continue
        comma = body.find(",")
        key = (body if comma < 0 else body[:comma]).strip()
        if not key or not CITEKEY_RE.match(key):
            raise BibError("line %d: missing or invalid citation key %r" % (line, key))
        fields = _parse_fields(body[comma + 1:] if comma >= 0 else "", line)
        entries.append(BibEntry(etype, key, fields, at, end + 1, line, text[at:end + 1]))
        i = end + 1
    return entries, "".join(outside)


def _parse_fields(s, line):
    fields = {}
    i, n = 0, len(s)
    while i < n:
        while i < n and (s[i].isspace() or s[i] == ","):
            i += 1
        if i >= n:
            break
        m = re.match(r"[A-Za-z][\w:.+-]*", s[i:])
        if not m:
            raise BibError("line %d: expected a field name near %r" % (line, s[i:i + 20]))
        name = m.group(0).lower()
        i += m.end()
        while i < n and s[i].isspace():
            i += 1
        if i >= n or s[i] != "=":
            raise BibError("line %d: field %r has no '='" % (line, name))
        i += 1
        parts = []
        while True:
            while i < n and s[i].isspace():
                i += 1
            if i >= n:
                raise BibError("line %d: field %r has no value" % (line, name))
            if s[i] == "{":
                depth, k = 0, i
                while k < n:
                    if s[k] == "{":
                        depth += 1
                    elif s[k] == "}":
                        depth -= 1
                        if depth == 0:
                            break
                    k += 1
                if k >= n:
                    raise BibError("line %d: field %r is not closed" % (line, name))
                parts.append(s[i + 1:k])
                i = k + 1
            elif s[i] == '"':
                depth, k = 0, i + 1
                while k < n and not (s[k] == '"' and depth == 0):
                    if s[k] == "{":
                        depth += 1
                    elif s[k] == "}":
                        depth -= 1
                    k += 1
                if k >= n:
                    raise BibError("line %d: field %r quote is not closed" % (line, name))
                parts.append(s[i + 1:k])
                i = k + 1
            else:
                m = re.match(r"[\w:.+-]+", s[i:])
                if not m:
                    raise BibError("line %d: field %r has an invalid value" % (line, name))
                parts.append(m.group(0))
                i += m.end()
            while i < n and s[i].isspace():
                i += 1
            if i < n and s[i] == "#":
                i += 1
                continue
            break
        if name in fields:
            raise BibError("line %d: duplicate field %r" % (line, name))
        fields[name] = "".join(parts).strip()
    return fields


def validate_fetched_bib(text):
    """A download is accepted only if it is exactly one real BibTeX entry (design 6.3)."""
    if not text.strip():
        raise BibError("empty response")
    if looks_like_html(text):
        raise BibError("response is HTML (a bot check or error page), not BibTeX")
    entries, outside = parse_bib(text)
    stray = [ln for ln in outside.splitlines() if ln.strip() and not ln.strip().startswith("%")]
    if stray:
        raise BibError("text outside the entry: %r" % stray[0][:60])
    real = [e for e in entries if e.key]
    if len(real) != 1 or len(entries) != 1:
        raise BibError("expected exactly one BibTeX entry, found %d" % len(entries))
    entry = real[0]
    if not entry.fields.get("title"):
        raise BibError("entry %s has no title" % entry.key)
    return entry


def read_keymap(project):
    """bib_sources/KEYMAP.tsv: `<citekey>\t<key in the downloaded file>`."""
    path = project.path("bib_sources/KEYMAP.tsv")
    mapping, findings = {}, []
    if not os.path.isfile(path):
        return mapping, findings
    for lineno, raw in enumerate(read_text(path).splitlines(), 1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 2 or not all(CITEKEY_RE.match(p.strip()) for p in parts):
            findings.append(Finding("bib_sources/KEYMAP.tsv", lineno, "BIB-KEYMAP",
                                    "expected '<citekey><TAB><source key>'"))
            continue
        mapping[parts[0].strip()] = parts[1].strip()
    return mapping, findings


def bib_source_files(project):
    d = project.path("bib_sources")
    if not os.path.isdir(d):
        return []
    return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".bib"))


REFS_HEADER = "% references.bib: generated by `uws research bib build` from bib_sources/. Do not edit by hand.\n"


def expected_references(project):
    """The one allowed references.bib: header plus bib_sources/*.bib in citekey order."""
    keymap, _ = read_keymap(project)
    chunks = [REFS_HEADER]
    for path in bib_source_files(project):
        stem = os.path.basename(path)[:-4]
        text = read_text(path).strip() + "\n"
        src_key = keymap.get(stem)
        if src_key and src_key != stem:
            text = re.sub(r"^(\s*@\s*[A-Za-z]+\s*[{(]\s*)" + re.escape(src_key) + r"(\s*,)",
                          lambda m: m.group(1) + stem + m.group(2), text, count=1)
        chunks.append(text)
    return "\n".join(chunks)


def cited_keys(project):
    """Citekeys used in .tex (\\cite variants) and Markdown ([@key]) with their locations."""
    out = []
    files = set(project.tex_files()) | set(project.prose_files())
    if os.path.isdir(project.path("research")):
        files |= set(project.walk("research", (".md",)))
    cite_re = re.compile(r"\\(?:no)?cite[a-zA-Z]*\*?(?:\[[^\]]*\]){0,2}\{([^}]*)\}")
    md_re = re.compile(r"\[(-?@[^\]]+)\]")
    for path in sorted(files):
        rel = project.rel(path)
        for lineno, raw in enumerate(read_text(path).splitlines(), 1):
            code = split_tex_comment(raw)[0] if path.endswith(".tex") else raw
            if path.endswith(".tex"):
                for m in cite_re.finditer(code):
                    for key in m.group(1).split(","):
                        key = key.strip()
                        if key and key != "*":
                            out.append((rel, lineno, key))
            else:
                for m in md_re.finditer(code):
                    for key in re.findall(r"-?@([\w:./-]+[\w])", m.group(1)):
                        out.append((rel, lineno, key))
    return out


def check_bib(project):
    """bib_sources provenance, references.bib equality, and cited keys resolve (AT2)."""
    findings = []
    keymap, km_findings = read_keymap(project)
    findings.extend(km_findings)
    decisions = pi_decision_ids(project)
    stems = set()
    for path in bib_source_files(project):
        rel = project.rel(path)
        stem = os.path.basename(path)[:-4]
        stems.add(stem)
        try:
            entry = validate_fetched_bib(read_text(path))
        except BibError as exc:
            findings.append(Finding(rel, 1, "BIB-PARSE", str(exc)))
            continue
        want_key = keymap.get(stem, stem)
        if entry.key != want_key:
            findings.append(Finding(rel, entry.line, "BIB-KEY",
                                    "entry key %r does not match the file name; rename through "
                                    "bib_sources/KEYMAP.tsv, never by editing the entry" % entry.key))
        meta_path = path[:-4] + ".meta.json"
        meta_rel = project.rel(meta_path)
        if not os.path.isfile(meta_path):
            findings.append(Finding(rel, 1, "BIB-META", "%s is missing: this entry was not fetched by research_bib.sh" % meta_rel))
            continue
        try:
            with open(meta_path, encoding="utf-8") as fh:
                meta = json.load(fh)
        except (OSError, ValueError) as exc:
            findings.append(Finding(meta_rel, 1, "BIB-META", "not valid JSON: %s" % exc))
            continue
        for key in ("source_url", "id_type", "fetched_at", "http_status", "sha256"):
            if meta.get(key) in (None, ""):
                findings.append(Finding(meta_rel, 1, "BIB-META", "missing '%s'" % key))
        if meta.get("id_type") not in BIB_ID_TYPES:
            findings.append(Finding(meta_rel, 1, "BIB-META", "id_type %r is not one of %s"
                                    % (meta.get("id_type"), ", ".join(BIB_ID_TYPES))))
        if meta.get("sha256") and meta.get("sha256") != sha256_file(path):
            findings.append(Finding(rel, 1, "BIB-HASH", "file changed after it was fetched (sha256 differs "
                                    "from %s); re-fetch it instead of editing" % meta_rel))
        if meta.get("id_type") == "pi-supplied":
            did = meta.get("pi_decision") or ""
            if not DID_RE.fullmatch(did) or did not in decisions:
                findings.append(Finding(meta_rel, 1, "BIB-PI", "a PI-supplied entry needs pi_decision "
                                        "naming a D-ID recorded in research/pi/decisions.md"))
    for stem in sorted(keymap):
        if stem not in stems:
            findings.append(Finding("bib_sources/KEYMAP.tsv", 1, "BIB-KEYMAP", "%s has no bib_sources/%s.bib" % (stem, stem)))

    # references.bib must be exactly the concatenation of bib_sources.
    refs = project.references_path()
    cites = cited_keys(project)
    if refs and os.path.isfile(refs):
        findings.extend(_compare_references(project, refs))
    elif any(r.endswith(".tex") for r, _l, _k in cites):
        findings.append(Finding(project.rel(refs) if refs else "references.bib", 1, "BIB-REFS",
                                "references.bib is missing; build it with `uws research bib build`"))

    # A key that references.bib does not define prints as [?]: that is a different problem
    # (a citation to nothing) from a defined entry that was not fetched (BIB-MISSING).
    ref_keys = None
    if refs and os.path.isfile(refs):
        try:
            ref_keys = set(e.key for e in parse_bib(read_text(refs))[0] if e.key)
        except BibError:
            ref_keys = None   # BIB-REFS reports the parse error
    refs_rel = project.rel(refs) if refs else "references.bib"
    for rel, lineno, key in cites:
        if key in stems:
            continue
        if ref_keys is not None and key in ref_keys:
            findings.append(Finding(rel, lineno, "BIB-MISSING", "\\cite{%s} has no bib_sources/%s.bib" % (key, key)))
        else:
            findings.append(Finding(rel, lineno, "BIB-UNDEFINED", "\\cite{%s} is not defined in %s and has no "
                                    "bib_sources/%s.bib: it cites nothing and prints as [?]" % (key, refs_rel, key)))
    claims = project.claims()
    for cid in sorted(claims.latest):
        lineno, row = claims.latest[cid]
        for src in row.get("sources") or []:
            if isinstance(src, dict) and src.get("citekey") and src["citekey"] not in stems:
                findings.append(Finding(claims.rel, lineno, "BIB-MISSING",
                                        "%s cites %s, which has no bib_sources/%s.bib" % (cid, src["citekey"], src["citekey"])))
    return findings


def _compare_references(project, refs):
    rel = project.rel(refs)
    actual = read_text(refs)
    expected = expected_references(project)
    if actual == expected:
        return []
    out = []
    try:
        entries, _ = parse_bib(actual)
    except BibError as exc:
        return [Finding(rel, 1, "BIB-REFS", "cannot parse: %s" % exc)]
    try:
        exp_entries = {e.key: e.text for e in parse_bib(expected)[0] if e.key}
    except BibError as exc:
        return [Finding(rel, 1, "BIB-REFS", "bib_sources/ does not parse: %s" % exc)]
    for e in entries:
        if not e.key:
            continue
        if e.key not in exp_entries:
            out.append(Finding(rel, e.line, "BIB-REFS", "entry %s is not in bib_sources/ (hand-written?)" % e.key))
        elif e.text != exp_entries[e.key]:
            out.append(Finding(rel, e.line, "BIB-REFS", "entry %s is not byte-equal to bib_sources/%s.bib" % (e.key, e.key)))
    if not out:
        out.append(Finding(rel, 1, "BIB-REFS", "not byte-equal to the concatenation of bib_sources/; "
                           "rebuild with `uws research bib build`"))
    return out


def pi_decision_ids(project):
    path = project.path("research/pi/decisions.md")
    if not os.path.isfile(path):
        return set()
    ids = set()
    for raw in read_text(path).splitlines():
        m = re.match(r"^\s*(?:[-*]\s*)?(?:#+\s*)?(D-\d+)\b", raw)
        if m:
            ids.add(m.group(1))
    return ids


def bib_ingest(project, args):
    """Validate a downloaded body and store it (called by research_bib.sh fetch)."""
    try:
        with open(args.body, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        raise EnvError("cannot read %s: %s" % (args.body, exc))
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        print("refused: response is not UTF-8 text", file=sys.stderr)
        return EXIT_FINDINGS
    ctype = (args.content_type or "").lower()
    if "text/html" in ctype:
        print("refused: content type is %s, not BibTeX" % args.content_type, file=sys.stderr)
        return EXIT_FINDINGS
    if args.http_status and args.http_status != "200":
        print("refused: HTTP status %s" % args.http_status, file=sys.stderr)
        return EXIT_FINDINGS
    try:
        entry = validate_fetched_bib(text)
    except BibError as exc:
        print("refused: %s" % exc, file=sys.stderr)
        return EXIT_FINDINGS
    citekey = args.key or entry.key
    if not CITEKEY_RE.match(citekey):
        print("refused: invalid citekey %r" % citekey, file=sys.stderr)
        return EXIT_FINDINGS
    if args.id_type == "pi-supplied" and not DID_RE.fullmatch(args.pi_decision or ""):
        print("refused: a PI-supplied file needs --pi-decision D-<n>", file=sys.stderr)
        return EXIT_FINDINGS
    dest_dir = project.path("bib_sources")
    dest = os.path.join(dest_dir, citekey + ".bib")
    if os.path.exists(dest) and not args.refetch:
        print("refused: bib_sources/%s.bib exists (use --refetch to replace it with a new download)" % citekey,
              file=sys.stderr)
        return EXIT_FINDINGS
    os.makedirs(dest_dir, exist_ok=True)
    stored = text.strip() + "\n"
    meta = {
        "citekey": citekey,
        "source_key": entry.key,
        "source_url": args.url,
        "id_type": args.id_type,
        "identifier": args.identifier,
        "fetched_at": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "http_status": (int(args.http_status) if (args.http_status or "").isdigit()
                        else ("n/a (pi-supplied)" if args.id_type == "pi-supplied" else args.http_status)),
        "content_type": args.content_type,
        "response_sha256": hashlib.sha256(raw).hexdigest(),
        "sha256": hashlib.sha256(stored.encode("utf-8")).hexdigest(),
    }
    if args.pi_decision:
        meta["pi_decision"] = args.pi_decision
    _atomic_write(dest, stored)
    _atomic_write(dest[:-4] + ".meta.json", json.dumps(meta, indent=2, sort_keys=True) + "\n")
    if entry.key != citekey:
        _keymap_set(project, citekey, entry.key)
    print("bib_sources/%s.bib (%s %s)" % (citekey, entry.etype, entry.key))
    return EXIT_OK


def _keymap_set(project, citekey, source_key):
    path = project.path("bib_sources/KEYMAP.tsv")
    lines = read_text(path).splitlines() if os.path.isfile(path) else [
        "# citekey<TAB>key in the downloaded entry (the only allowed way to rename a key)"]
    lines = [ln for ln in lines if not ln.startswith(citekey + "\t")]
    lines.append("%s\t%s" % (citekey, source_key))
    _atomic_write(path, "\n".join(lines) + "\n")


def bib_build(project, args):
    out = project.path(args.out) if args.out else (project.references_path() or project.path("references.bib"))
    findings = []
    for path in bib_source_files(project):
        try:
            validate_fetched_bib(read_text(path))
        except BibError as exc:
            findings.append(Finding(project.rel(path), 1, "BIB-PARSE", str(exc)))
    if findings:
        emit(findings, False)
        print("refused: fix bib_sources/ first (references.bib was not written)", file=sys.stderr)
        return EXIT_FINDINGS
    d = os.path.dirname(out)
    if d:
        os.makedirs(d, exist_ok=True)
    _atomic_write(out, expected_references(project))
    print("%s (%d entries from bib_sources/)" % (project.rel(out), len(bib_source_files(project))))
    return EXIT_OK


def _atomic_write(path, text):
    d = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-", suffix=".part")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# --------------------------------------------------------------------------- quotes

_QUOTE_MAP = {ord(k): v for k, v in {
    "\u2018": "'", "\u2019": "'", "\u201a": "'", "\u201b": "'", "\u2032": "'",
    "\u201c": '"', "\u201d": '"', "\u201e": '"', "\u201f": '"', "\u2033": '"',
    "\u2010": "-", "\u2011": "-", "\u2012": "-", "\u2013": "-", "\u2014": "-", "\u2212": "-",
    "\u00a0": " ", "\u00ad": "",
}.items()}


def normalize_quote_text(s, join_hyphens):
    s = unicodedata.normalize("NFKC", s).translate(_QUOTE_MAP)
    if join_hyphens:
        s = re.sub(r"(\w)-[ \t]*\r?\n\s*(\w)", r"\1\2", s)
    else:
        s = re.sub(r"(\w)-[ \t]*\r?\n\s*(\w)", r"\1-\2", s)
    return re.sub(r"\s+", " ", s).strip()


def load_source_index(project):
    path = project.path("research/sources/index.jsonl")
    index, findings = {}, []
    if not os.path.isfile(path):
        return index, findings
    for lineno, raw in enumerate(read_text(path).splitlines(), 1):
        if not raw.strip():
            continue
        try:
            obj = json.loads(raw)
        except ValueError as exc:
            findings.append(Finding("research/sources/index.jsonl", lineno, "QUOTE-INDEX", "not valid JSON: %s" % exc))
            continue
        if not isinstance(obj, dict) or not obj.get("citekey"):
            findings.append(Finding("research/sources/index.jsonl", lineno, "QUOTE-INDEX", "each row needs a citekey"))
            continue
        index[obj["citekey"]] = (lineno, obj)
    return index, findings


def check_quotes(project, allow_missing_cache=None):
    """Every recorded quote is a verbatim substring of the cached source (AT4)."""
    if allow_missing_cache is None:
        allow_missing_cache = bool(project.config.get("allow_missing_cache"))
    min_words = int(project.config.get("min_quote_words") or 5)
    claims = project.claims()
    index, findings = load_source_index(project)
    texts = {}
    for cid in sorted(claims.latest):
        lineno, row = claims.latest[cid]
        verified = row.get("status") == "verified"
        for src in row.get("sources") or []:
            if not isinstance(src, dict) or not src.get("citekey") or not src.get("quote"):
                continue
            key, quote = src["citekey"], str(src["quote"])
            where = "%s cites %s" % (cid, key)
            if len(quote.split()) < min_words:
                findings.append(Finding(claims.rel, lineno, "QUOTE-SHORT",
                                        "%s: quote has fewer than %d words, too short to identify a passage" % (where, min_words)))
            entry = index.get(key)
            if entry is None:
                findings.append(Finding(claims.rel, lineno, "QUOTE-NOINDEX",
                                        "%s: no research/sources/index.jsonl row for %s" % (where, key),
                                        "block" if verified else "warn"))
                continue
            meta = entry[1]
            if meta.get("access") == "none":
                if verified:
                    findings.append(Finding(claims.rel, lineno, "QUOTE-ACCESS",
                                            "%s: source has access=none; it cannot support a verified claim "
                                            "until the PI provides the text" % where))
                continue
            cache = project.path(meta.get("path") or "research/sources/cache/%s.txt" % key)
            if not os.path.isfile(cache):
                level = "warn" if (allow_missing_cache or not verified) else "block"
                findings.append(Finding(claims.rel, lineno, "QUOTE-NOCACHE",
                                        "%s: cached text %s is missing, so the quote cannot be checked"
                                        % (where, project.rel(cache)), level))
                continue
            if key not in texts:
                digest = sha256_file(cache)
                if meta.get("text_sha256") and meta["text_sha256"] != digest:
                    findings.append(Finding("research/sources/index.jsonl", entry[0], "QUOTE-HASH",
                                            "%s: cached text changed since it was indexed" % key))
                raw = read_text(cache)
                texts[key] = (normalize_quote_text(raw, True), normalize_quote_text(raw, False))
            joined, kept = texts[key]
            q1, q2 = normalize_quote_text(quote, True), normalize_quote_text(quote, False)
            if q1 not in joined and q2 not in kept and q2 not in joined:
                findings.append(Finding(claims.rel, lineno, "QUOTE-MISMATCH",
                                        "%s: quote is not in the cached text: %r" % (where, quote[:80])))
    return findings


# --------------------------------------------------------------------------- LaTeX helpers

def split_tex_comment(line):
    """Return (code, comment) split at the first unescaped '%'."""
    i = 0
    while True:
        j = line.find("%", i)
        if j < 0:
            return line, ""
        k, bs = j - 1, 0
        while k >= 0 and line[k] == "\\":
            bs += 1
            k -= 1
        if bs % 2 == 0:
            return line[:j], line[j + 1:]
        i = j + 1


def tex_closure(project, main_rel):
    """Files reachable from a main .tex through \\input/\\include; missing inputs."""
    main = project.path(main_rel)
    base = os.path.dirname(main)
    seen, missing, stack = [], [], [(main, main_rel, 0)]
    input_re = re.compile(r"\\(?:input|include|subfile)\s*\{([^}]+)\}")
    while stack:
        path, origin, oline = stack.pop()
        if path in seen:
            continue
        if not os.path.isfile(path):
            missing.append((origin, oline, project.rel(path)))
            continue
        seen.append(path)
        lines = read_text(path).splitlines()
        for lineno in range(len(lines), 0, -1):
            code = split_tex_comment(lines[lineno - 1])[0]
            for m in reversed(list(input_re.finditer(code))):
                target = m.group(1).strip()
                cand = os.path.join(base, target)
                if not cand.endswith(".tex") and not os.path.isfile(cand):
                    cand += ".tex"
                stack.append((os.path.normpath(cand), project.rel(path), lineno))
    return sorted(seen), missing


# A period after one of these does not end a sentence (LaTeX writers often omit `\ `).
_ABBREV_RE = re.compile(r"(?:^|[\s(~{])(?:e\.g|i\.e|cf|vs|et al|Figs?|Secs?|Tabs?|Eqs?|No|approx|resp|viz)\.$", re.I)
_CLOSERS = "})]'\""


def sentence_spans(text):
    """(start, end) of each sentence of `text`; together they cover all of it.

    A sentence ends at `.`, `!` or `?` (repeated, and followed by closing braces, brackets
    or quotes) when whitespace or the end of the text comes next. So the dots in
    `recover\\_context.sh`, `0.912`, `Fig.~3` and `et al.\\ ` end nothing (LaTeX's own rule:
    `.~` and `.\\ ` are not sentence ends), `\\.` is an accent, and a period after a common
    abbreviation (e.g., i.e., Fig., et al.) does not end the sentence either. No text is
    ever dropped: the part after the last stop is a sentence of its own."""
    spans = []
    n, start, i = len(text), 0, 0
    while i < n:
        c = text[i]
        if c not in ".!?" or (i > 0 and text[i - 1] == "\\"):
            i += 1
            continue
        j = i
        while j < n and text[j] in ".!?":
            j += 1
        k = j
        while k < n and text[k] in _CLOSERS:
            k += 1
        if k >= n or text[k].isspace():
            abbrev = c == "." and j == i + 1 and _ABBREV_RE.search(text[max(0, i - 12):i + 1])
            if not abbrev:
                spans.append((start, k))
                start = k
        i = k
    if start < n:
        spans.append((start, n))
    return spans


class Sentence(object):
    """One sentence of a Doc: its text, first line, attached C-IDs, and where each character
    came from (`line_of(offset)`; `offset_of(lineno, col)` for a column of a code line)."""
    __slots__ = ("start", "text", "cids", "lines", "_a", "_spans")

    def __init__(self, text, start_offset, spans):
        self.text, self._a, self._spans, self.cids = text, start_offset, spans, set()
        end = start_offset + len(text)
        self.lines = [ln for (st, en, ln) in spans if st < end and en > start_offset]
        self.start = self.lines[0] if self.lines else spans[0][2]

    def line_of(self, off):
        pos = self._a + off
        for st, en, ln in self._spans:
            if st <= pos < en:
                return ln
        return self._spans[-1][2]

    def offset_of(self, lineno, col):
        """Offset in `text` of column `col` of line `lineno`, or None when it is not in it."""
        for st, _en, ln in self._spans:
            if ln == lineno:
                off = st + col - self._a
                return off if 0 <= off < len(self.text) else None
        return None


class Doc(object):
    """A prose file as paragraphs of sentences, with per-line context."""

    def __init__(self, project, path):
        self.path = path
        self.rel = project.rel(path)
        self.is_tex = path.endswith(".tex")
        self.lines = read_text(path).splitlines()
        self.code = []       # comment-stripped text per line (1-based index - 1)
        self.comment = []
        self.cids = []       # C-IDs attached to each line
        self.env = []        # innermost float environment id per line (or None)
        self.float_lines = {}  # float env id -> [first line, last line]
        self.in_abstract = []
        self.in_tabular = []
        self.section = []    # current \section, \subsection ... title per line
        self.top_section = []  # current top-level \section title per line
        self.captions = {}   # float env id -> caption text
        self.labels = {}     # \label name -> line
        self._sentences = None
        self._scan()

    def _scan(self):
        stack, float_id, floats = [], 0, []
        section = top = ""
        in_md_comment = False
        for lineno, raw in enumerate(self.lines, 1):
            if self.is_tex:
                code, comment = split_tex_comment(raw)
            else:
                code, comment = raw, ""
                # Markdown C-IDs live in HTML comments: <!-- C-0001 -->
                pieces = []
                rest = code
                while rest:
                    if in_md_comment:
                        end = rest.find("-->")
                        if end < 0:
                            comment += rest
                            rest = ""
                        else:
                            comment += rest[:end]
                            rest = rest[end + 3:]
                            in_md_comment = False
                    else:
                        start = rest.find("<!--")
                        if start < 0:
                            pieces.append(rest)
                            rest = ""
                        else:
                            pieces.append(rest[:start])
                            rest = rest[start + 4:]
                            in_md_comment = True
                code = "".join(pieces)
            ended = []
            for m in re.finditer(r"\\(begin|end)\{([^}]+)\}", code):
                kind, name = m.group(1), m.group(2).rstrip("*")
                if kind == "begin":
                    if name in ("table", "figure"):
                        float_id += 1
                        floats.append(float_id)
                        self.float_lines[float_id] = [lineno, lineno]
                    stack.append(name)
                elif stack and stack[-1].rstrip("*") == name:
                    stack.pop()
                    if name in ("table", "figure") and floats:
                        ended.append(floats.pop())
            if self.is_tex:
                sm = re.search(r"\\(sub)*section\*?\{([^}]*)\}", code)
                if sm:
                    section = sm.group(2)
                    if not sm.group(1):
                        top = section
            else:
                sm = re.match(r"^(#+)\s+(.*)", code)
                if sm:
                    section = sm.group(2)
                    if len(sm.group(1)) <= 2:
                        top = section
            # The line that closes a float still belongs to it.
            cur_float = floats[-1] if floats else (ended[-1] if ended else None)
            for fid in floats + ended:
                self.float_lines[fid][1] = lineno
            if cur_float is not None and "\\caption" in code:
                self.captions[cur_float] = self.captions.get(cur_float, "") + " " + code
            for m in re.finditer(r"\\label\{([^}]+)\}", code):
                self.labels.setdefault(m.group(1).strip(), lineno)
            self.code.append(code)
            self.comment.append(comment)
            self.cids.append(set(CID_RE.findall(comment)))
            self.env.append(cur_float)
            self.in_abstract.append("abstract" in stack or bool(re.search(r"\\begin\{abstract\}", code)))
            self.in_tabular.append(any(s.startswith(("tabular", "longtable", "array")) for s in stack))
            self.section.append(section)
            self.top_section.append(top)
        # a caption may appear after the content it describes; extend per float
        if self.captions:
            for fid in list(self.captions):
                self.captions[fid] = self.captions[fid].strip()

    def paragraph_lines(self, lineno):
        """First and last line of the paragraph (run of non-blank lines) around `lineno`."""
        lo = hi = lineno
        while lo > 1 and self.code[lo - 2].strip():
            lo -= 1
        while hi < len(self.code) and self.code[hi].strip():
            hi += 1
        return lo, hi

    def sentence_list(self):
        """Every sentence of the file as a Sentence (computed once)."""
        if self._sentences is not None:
            return self._sentences
        para, results = [], []

        def flush():
            if not para:
                return
            text, spans = "", []
            for lineno, code in para:
                start = len(text)
                text += code + " "
                spans.append((start, len(text), lineno))
            for a0, b in sentence_spans(text):
                raw = text[a0:b]
                s = raw.strip()
                if not s:
                    continue
                sent = Sentence(s, a0 + (len(raw) - len(raw.lstrip())), spans)
                if not sent.lines:
                    continue
                for ln in sent.lines:
                    sent.cids |= self.cids[ln - 1]
                results.append(sent)
            del para[:]

        structural = re.compile(r"^\s*\\(?:begin|end|(?:sub)*section|paragraph|chapter|item|caption|label)\b")
        for idx, code in enumerate(self.code):
            lineno = idx + 1
            if not code.strip():
                flush()
                continue
            if self.is_tex and structural.match(code):
                # environment and sectioning lines start a new sentence
                flush()
            para.append((lineno, code))
        flush()
        self._sentences = results
        return results

    def sentences(self):
        """(start_line, text, cids, line_of(offset)) for each sentence."""
        return [(x.start, x.text, x.cids, x.line_of) for x in self.sentence_list()]


# --------------------------------------------------------------------------- numbers

ROUNDING = {"round": ROUND_HALF_UP, "round-half-even": ROUND_HALF_EVEN, "floor": ROUND_FLOOR,
            "ceil": ROUND_CEILING, "trunc": ROUND_DOWN}


def apply_rounding(raw, rule, scale=None):
    """Printed form of raw under an explicit rule such as 'floor:3' or 'round:1'."""
    d = Decimal(str(raw))
    if scale not in (None, "", 1):
        d = d * Decimal(str(scale))
    if rule == "exact":
        return format(d, "f")
    kind, _, digits = str(rule).partition(":")
    if kind not in ROUNDING or not digits.isdigit():
        raise ValueError("rounding must be exact or <%s>:<digits>" % "|".join(sorted(ROUNDING)))
    q = Decimal(1).scaleb(-int(digits))
    return format(d.quantize(q, rounding=ROUNDING[kind]), "f")


def resolve_pointer(path, pointer):
    """JSON pointer (RFC 6901) into a .json file; for .csv, /<row>/<column> or /<col>=<value>/<column>."""
    if not pointer.startswith("/"):
        raise ValueError("pointer must start with '/'")
    parts = [p.replace("~1", "/").replace("~0", "~") for p in pointer[1:].split("/")]
    if path.endswith(".csv") or path.endswith(".tsv"):
        with open(path, encoding="utf-8", newline="") as fh:
            rows = list(csv.DictReader(fh, delimiter="\t" if path.endswith(".tsv") else ","))
        if len(parts) != 2:
            raise ValueError("a CSV pointer is /<row>/<column>")
        sel, col = parts
        if "=" in sel:
            k, v = sel.split("=", 1)
            match = [r for r in rows if r.get(k) == v]
            if not match:
                raise ValueError("no row with %s=%s" % (k, v))
            row = match[0]
        else:
            row = rows[int(sel)]
        if col not in row:
            raise ValueError("no column %r" % col)
        return row[col]
    with open(path, encoding="utf-8") as fh:
        node = json.load(fh)
    for p in parts:
        if isinstance(node, list):
            node = node[int(p)]
        elif isinstance(node, dict):
            if p not in node:
                raise ValueError("key %r not found" % p)
            node = node[p]
        else:
            raise ValueError("cannot descend into %r" % type(node).__name__)
    return node


def _values_equal(a, b):
    try:
        return Decimal(str(a)) == Decimal(str(b))
    except (InvalidOperation, ValueError):
        return str(a) == str(b)


def read_number_macros(project):
    """Macros defined in the generated numbers file: name -> (value, line)."""
    rel = project.config.get("numbers_tex") or "paper/generated/numbers.tex"
    path = project.path(rel)
    macros = {}
    if not os.path.isfile(path):
        return rel, None
    pat = re.compile(r"\\(?:newcommand|renewcommand|providecommand)\*?\s*\{?\\([A-Za-z]+)\}?\s*\{(.*)\}\s*$|\\def\\([A-Za-z]+)\s*\{(.*)\}\s*$")
    for lineno, raw in enumerate(read_text(path).splitlines(), 1):
        code = split_tex_comment(raw)[0].strip()
        m = pat.match(code)
        if m:
            name = m.group(1) or m.group(3)
            value = (m.group(2) if m.group(1) else m.group(4)).replace("\\xspace", "").strip()
            macros["\\" + name] = (value, lineno)
    return rel, macros


NUM_STRIP_RE = re.compile(
    r"\\(?:cite\w*|citep|citet|ref|eqref|autoref|cref|Cref|label|url|href|includegraphics|input|include|"
    r"vspace|hspace|setlength|addtolength|resizebox|scalebox|rule|cmidrule|renewcommand|newcommand|"
    r"definecolor|begin|end|usepackage|documentclass|bibliography\w*|arraystretch|multicolumn|multirow|"
    r"fontsize|linespread|setcounter|pgfplots\w*)\*?(?:\[[^\]]*\])*(?:\{[^{}]*\})*")
# A number in prose: a decimal such as 0.913, or any number with a unit attached, such as
# 1.1ms, 1.1\,ms, 30\% or 3x (a sentence-ending period may follow). Version strings such
# as 3.2.1, identifiers such as v1.2 or F1, and the second number of a range (0--90) are
# not matched.
_UNIT_WORDS = r"\\%|%|ms|[µu]s|ns|secs?|seconds?|mins?|minutes?|hours?|hrs?|s|h|[kKMGT]i?B"
NUMBER_RE = re.compile(
    r"(?<![\w.\\-])(?P<num>-?\d+(?:\.\d+)?)"
    r"(?P<unit>(?:\\[,;:! ]|~|\s)?(?:" + _UNIT_WORDS + r")|\s?(?:\\times|×)|x)?"
    r"(?!\w|\.\d)")
# A bare integer is usually a count, a year or an identifier, so an integer is reported
# only with a unit; `s` and `h` after an integer are not units ("the 1990s", "24h").
_INT_NOT_UNITS = ("s", "h")
NUM_PREFIX_EXEMPT = re.compile(
    r"(?:Section|Sec\.|Sections|§|Table|Tab\.|Fig\.|Figure|Eq\.|Equation|Algorithm|Alg\.|Appendix|"
    r"Chapter|Theorem|Lemma|Definition|v|version|Version|Python|release|RFC|ISO|IEEE)\s*~?\s*$")
NUM_SUFFIX_EXEMPT = re.compile(r"^\s*\\?(?:textwidth|linewidth|columnwidth|textheight|cm|mm|pt|em|ex|in|bp|pc)\b")
LITERAL_RE = re.compile(r"uws:literal\b(.*)")

# Where results are reported (design 6.4 d): the abstract, tables and figures, and files or
# top-level sections named introduction, results, evaluation, experiments, discussion or
# conclusion. A subsection title counts only for the narrower list (so "Evaluation Metrics"
# inside a method section is not in scope).
_SCOPE_RE = re.compile(r"(abstract|intro|result|evaluation|experiments\b|discussion|conclusion)", re.I)
_SCOPE_SUB_RE = re.compile(r"(abstract|intro|result|conclusion)", re.I)


def number_tokens(code):
    """Numbers in one comment-stripped line: [(start, end, text, number, reportable)].

    Commands whose arguments are not prose (\\cite, \\ref, \\label, lengths ...) are blanked
    first, keeping columns. `reportable` is true for a decimal, or an integer with a unit."""
    stripped = NUM_STRIP_RE.sub(lambda m: " " * len(m.group(0)), code)
    out = []
    for m in NUMBER_RE.finditer(stripped):
        if NUM_PREFIX_EXEMPT.search(stripped[:m.start()]) or NUM_SUFFIX_EXEMPT.match(stripped[m.end():]):
            continue
        num, unit = m.group("num"), m.group("unit") or ""
        word = re.sub(r"^(?:\\[,;:! ]|~|\s)+", "", unit)
        reportable = "." in num or bool(word and word not in _INT_NOT_UNITS)
        out.append((m.start(), m.end(), m.group(0), num, reportable))
    return out


def _number_scope(doc, idx):
    rel = doc.rel.lower()
    if doc.in_abstract[idx] or doc.in_tabular[idx] or doc.env[idx] is not None:
        return True
    if _SCOPE_RE.search(os.path.basename(rel)) or "/tables/" in "/" + rel:
        return True
    return bool(_SCOPE_RE.search(doc.top_section[idx]) or _SCOPE_SUB_RE.search(doc.section[idx]))


# `where` of a ledger row: places in the manuscript, separated by ';' (free text between
# them is ignored): file:line, file:first-last, file:l1,l2 or file#label.
WHERE_ITEM_RE = re.compile(r"(?<![\w./-])([\w./-]+\.(?:tex|md))(?::(\d+(?:\s*[-,]\s*\d+)*)|#([^\s;,()]+))")


def parse_where(text):
    """[(path, spec, [(first, last), ...] or None, label or None)] of a `where` field."""
    out = []
    for m in WHERE_ITEM_RE.finditer(str(text or "")):
        path, spec, label = m.group(1), m.group(2), m.group(3)
        if spec:
            locs = []
            for part in re.split(r"\s*,\s*", spec):
                ends = [int(x) for x in re.split(r"\s*-\s*", part)]
                locs.append((min(ends), max(ends)))
            out.append((path, spec, locs, None))
        else:
            out.append((path, "#" + label, None, label))
    return out


class WhereLinks(object):
    """Ledger rows located in the manuscript by their `where` field.

    Numbers: a hand-typed value on a named line that equals the row's printed value is that
    row's occurrence. NUM-LITERAL names the row, and NUM-SPLIT, C3 and C6 judge the value as
    they judge a macro use, so typing a number by hand (with or without `uws:literal`) no
    longer hides it from them. A named place that does not show the value is a NUM-WHERE
    warning (line numbers drift when the manuscript is edited).
    Claims: the C-ID counts as attached to the named lines for C6 only, so a claim row that
    records its sentence as resting on generator data can make C6 block; a `where` link
    never clears a finding."""

    def __init__(self, project):
        self.numbers = {}   # abs path -> {lineno: [(start, end, text, nid)]}
        self.claims = {}    # abs path -> {lineno: set of C-IDs}
        self.findings = []
        prose = set(os.path.abspath(f) for f in project.prose_files())
        numbers = project.numbers()
        for nid in sorted(numbers.latest):
            lineno, row = numbers.latest[nid]
            if not row.get("where") or row.get("printed") is None:
                continue
            try:
                want = Decimal(str(row["printed"]).strip())
            except InvalidOperation:
                continue
            for label, doc, locs in self._places(project, prose, numbers.rel, lineno, nid, row["where"], True):
                for lo, hi in locs:
                    self._link_number(numbers.rel, lineno, nid, row, want, label, doc, lo, hi)
        claims = project.claims()
        for cid in sorted(claims.latest):
            lineno, row = claims.latest[cid]
            if not row.get("where"):
                continue
            for _label, doc, locs in self._places(project, prose, claims.rel, lineno, cid, row["where"], False):
                for lo, hi in locs:
                    for ln in range(lo, hi + 1):
                        self.claims.setdefault(doc.path, {}).setdefault(ln, set()).add(cid)

    def _places(self, project, prose, rel, lineno, rid, where, report):
        for path, spec, locs, label in parse_where(where):
            place = "%s%s" % (path, spec if label else ":" + spec)
            full = os.path.abspath(project.path(path))
            if full not in prose:
                if report:
                    why = "is not among the checked manuscript files" if os.path.isfile(full) else "does not exist"
                    self.findings.append(Finding(rel, lineno, "NUM-WHERE", "%s: where names %s, which %s, so the number "
                                                 "printed there is not checked" % (rid, path, why), "warn"))
                continue
            doc = project.doc(full)
            if label:
                ln = doc.labels.get(label)
                if ln is None:
                    if report:
                        self.findings.append(Finding(rel, lineno, "NUM-WHERE", "%s: where names %s, but %s has no "
                                                     "\\label{%s}" % (rid, place, path, label), "warn"))
                    continue
                fid = doc.env[ln - 1]
                locs = [tuple(doc.float_lines[fid])] if fid is not None else [doc.paragraph_lines(ln)]
            if len(locs) > 1:
                for lo, hi in locs:
                    yield ("%s:%d" % (path, lo) if lo == hi else "%s:%d-%d" % (path, lo, hi)), doc, [(lo, hi)]
            else:
                yield place, doc, locs

    def _link_number(self, rel, lineno, nid, row, want, place, doc, lo, hi):
        hits, seen, macro_there = [], [], False
        macro = row.get("macro")
        for ln in range(max(lo, 1), min(hi, len(doc.code)) + 1):
            code = doc.code[ln - 1]
            if macro and re.search(re.escape(macro) + r"(?![A-Za-z])", code):
                macro_there = True
            for st, en, text, num, _rep in number_tokens(code):
                seen.append(text)
                try:
                    equal = Decimal(num) == want
                except InvalidOperation:
                    equal = False
                if equal:
                    hits.append((ln, st, en, text))
        for ln, st, en, text in hits:
            self.numbers.setdefault(doc.path, {}).setdefault(ln, []).append((st, en, text, nid))
        if not hits and not macro_there:
            shown = " (it shows %s)" % ", ".join(sorted(set(seen))) if seen else ""
            self.findings.append(Finding(rel, lineno, "NUM-WHERE", "%s: where names %s, but its printed value %s is not "
                                         "there%s; if the line moved, append a revision with the new place"
                                         % (nid, place, row.get("printed"), shown), "warn"))


def number_occurrences(project, doc, sent):
    """Ledger numbers in a sentence: [(offset, label, N-ID, row)] for uses of ledger macros
    (never other LaTeX commands) and for hand-typed values located by a row's `where`."""
    numbers = project.numbers()
    by_macro = project.macro_index()
    out = []
    for mm in MACRO_USE_RE.finditer(sent.text):
        nid = by_macro.get("\\" + mm.group(1))
        if nid:
            out.append((mm.start(), "\\" + mm.group(1), nid, numbers.latest[nid][1]))
    linked = project.links().numbers.get(doc.path, {})
    for ln in sent.lines:
        for st, _en, text, nid in linked.get(ln, []):
            off = sent.offset_of(ln, st)
            if off is not None:
                out.append((off, "hand-typed " + text, nid, numbers.latest[nid][1]))
    out.sort(key=lambda t: (t[0], t[2]))
    return out


def check_numbers(project, only_ids=None):
    """Number provenance (design 6.4 a-e; AT5)."""
    findings = []
    numbers = project.numbers()
    findings.extend(numbers.parse_errors)
    findings.extend(_check_number_shapes(numbers))
    ids = sorted(numbers.latest)
    if only_ids:
        unknown = [i for i in only_ids if i not in numbers.latest]
        for i in unknown:
            findings.append(Finding(numbers.rel, 1, "NUM-UNKNOWN", "%s is not in the number ledger" % i))
        ids = [i for i in ids if i in only_ids]

    macro_rel, macros = read_number_macros(project)
    row_by_macro = {}
    for nid in ids:
        lineno, row = numbers.latest[nid]
        where = lambda msg, rule="NUM-TRACE", ln=lineno: findings.append(Finding(numbers.rel, ln, rule, "%s: %s" % (nid, msg)))
        if row.get("macro"):
            row_by_macro[row["macro"]] = nid
        out_rel = row.get("output")
        if out_rel:
            out_path = project.path(out_rel)
            if not os.path.isfile(out_path):
                where("output %s does not exist" % out_rel)
            else:
                if row.get("output_sha256") and sha256_file(out_path) != row["output_sha256"]:
                    where("output %s changed: sha256 does not match the ledger" % out_rel, "NUM-HASH")
                if row.get("pointer"):
                    try:
                        value = resolve_pointer(out_path, str(row["pointer"]))
                    except (ValueError, IndexError, KeyError, OSError) as exc:
                        where("pointer %s: %s" % (row["pointer"], exc))
                    else:
                        if not _values_equal(value, row.get("raw")):
                            where("value at %s is %r, ledger raw is %r" % (row["pointer"], value, row.get("raw")), "NUM-VALUE")
        if row.get("rounding") and row.get("raw") is not None and row.get("printed") is not None:
            findings.extend(_check_rounding(project, numbers.rel, lineno, nid, row))
        run = row.get("run")
        if run:
            findings.extend(_check_run(project, numbers.rel, lineno, nid, run, row))
        findings.extend(_check_formula(numbers, nid, lineno, row))
        findings.extend(_check_evaluation(numbers.rel, nid, lineno, row))
        if macros is not None and row.get("macro"):
            if row["macro"] not in macros:
                where("macro %s is not defined in %s" % (row["macro"], macro_rel), "NUM-MACRO")
            elif macros[row["macro"]][0] != str(row.get("printed")):
                findings.append(Finding(macro_rel, macros[row["macro"]][1], "NUM-MACRO",
                                        "%s expands to %r but %s printed is %r"
                                        % (row["macro"], macros[row["macro"]][0], nid, row.get("printed"))))
    if macros is not None and not only_ids:
        for name, (_v, ln) in sorted(macros.items()):
            if name not in row_by_macro:
                findings.append(Finding(macro_rel, ln, "NUM-MACRO", "%s has no row in the number ledger" % name))
    elif macros is None and ids:
        findings.append(Finding(macro_rel, 1, "NUM-MACRO", "generated macro file is missing; the ledger's macros are not defined"))

    if not only_ids:
        findings.extend(project.links().findings)
        findings.extend(_hand_typed_numbers(project, macro_rel))
        findings.extend(_split_disclosure(project, macro_rel))
    return findings


def _printed_number(printed):
    pm = re.match(r"^\s*(-?\d+(?:\.\d+)?)", str(printed))
    return pm.group(1) if pm else None


def _decimals(value):
    """Decimal places of a value as written (0.9125 -> 4, 3 -> 0)."""
    exp = Decimal(str(value)).as_tuple().exponent
    return -exp if isinstance(exp, int) and exp < 0 else 0


def _rounds_to(value, stored):
    """True when `stored` is `value` rounded to the places `stored` has, under any common
    convention (half up, half even, down, floor, or Python's binary round())."""
    d, s = Decimal(str(value)), Decimal(str(stored))
    q = Decimal(1).scaleb(-_decimals(stored))
    for mode in (ROUND_HALF_UP, ROUND_HALF_EVEN, ROUND_DOWN, ROUND_FLOOR, ROUND_CEILING):
        if d.quantize(q, rounding=mode) == s:
            return True
    try:
        return Decimal(str(round(float(value), _decimals(stored)))) == s
    except (TypeError, ValueError, OverflowError):
        return False


def _unrounded_value(project, spec):
    """The full-precision value that a wrapper run wrote: (value, description) or raises ValueError."""
    if not isinstance(spec, dict):
        raise ValueError("unrounded must be {\"run\": RUN-ID, \"output\": path, \"pointer\": /json/pointer}")
    run_id, pointer = str(spec.get("run") or ""), str(spec.get("pointer") or "")
    out_rel = safe_rel(project, spec.get("output"))
    if not RUN_RE.match(run_id) or not out_rel or not pointer.startswith("/"):
        raise ValueError("unrounded needs run (RUN-ID), output (a project path) and pointer (/...)")
    rel, rec, err = project.runs().get(run_id, (None, None, "research/runs/%s/run.json does not exist" % run_id))
    if rec is None:
        raise ValueError("%s: %s" % (run_id, err))
    if rec.get("exit_code") != 0:
        raise ValueError("%s exited %r, so it does not provide a value" % (run_id, rec.get("exit_code")))
    produced = {o.get("path"): o.get("sha256") for o in rec.get("outputs") or [] if isinstance(o, dict)}
    if out_rel not in produced:
        raise ValueError("%s does not list %s among its outputs" % (run_id, out_rel))
    path = project.path(out_rel)
    if not os.path.isfile(path):
        raise ValueError("%s does not exist" % out_rel)
    if sha256_file(path) != produced[out_rel]:
        raise ValueError("%s changed after %s wrote it" % (out_rel, run_id))
    try:
        value = resolve_pointer(path, pointer)
        Decimal(str(value))
    except (ValueError, IndexError, KeyError, OSError, InvalidOperation) as exc:
        raise ValueError("%s %s: %s" % (out_rel, pointer, exc))
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError("%s %s is not a number" % (out_rel, pointer))
    return value, "%s %s %s" % (run_id, out_rel, pointer)


def _check_rounding(project, rel, lineno, nid, row):
    """NUM-ROUND: printed equals the rounding rule applied to the value (design 6.4 c).

    An output that stores a value already rounded (0.9125 for a true 0.9124502) cannot show
    whether the printed digits are right, because the rule can give different answers for the
    values that store the same way. Then:
    - with `unrounded` (a run output holding the full-precision value), judge against it;
    - otherwise report "pre-rounded, cannot judge" as a warning. A printed value that no
      stored-equivalent value could produce is still blocked."""
    rule, raw, printed, scale = row["rounding"], row["raw"], row["printed"], row.get("scale")

    def bad(msg, level="block"):
        return [Finding(rel, lineno, "NUM-ROUND", "%s: %s" % (nid, msg), level)]

    try:
        want = apply_rounding(raw, rule, scale)
    except (ValueError, InvalidOperation) as exc:
        return bad(str(exc))
    got = _printed_number(printed)
    if row.get("unrounded") is not None:
        try:
            value, source = _unrounded_value(project, row["unrounded"])
        except ValueError as exc:
            return bad("unrounded: %s" % exc)
        if not _rounds_to(value, raw):
            return bad("the unrounded value %s (%s) does not round to raw %r: it is not the quantity the output "
                       "stores" % (value, source, raw))
        want_u = apply_rounding(value, rule, scale)
        if got != want_u:
            return bad("printed %r is not %s applied to the unrounded value %s (expected %s; %s)"
                       % (printed, rule, value, want_u, source))
        return []
    if got == want:
        return []
    if isinstance(raw, (int, str)) and not isinstance(raw, bool) and "." not in str(raw):
        return bad("printed %r is not %s applied to raw %r (expected %s)" % (printed, rule, raw, want))
    k = _decimals(raw)
    half = Decimal(5).scaleb(-(k + 1))
    lo = apply_rounding(Decimal(str(raw)) - half, rule, scale)
    hi = apply_rounding(Decimal(str(raw)) + half, rule, scale)
    try:
        possible = got is not None and _decimals(got) == _decimals(want) and Decimal(lo) <= Decimal(got) <= Decimal(hi)
    except InvalidOperation:
        possible = False
    if possible:
        return bad("printed %r is not %s applied to raw %r (expected %s), but the output file is pre-rounded: raw has "
                   "%d decimals, and the true values it may stand for print as %s to %s, so the rounding cannot be "
                   "judged. Add `unrounded` {run, output, pointer} from a run that writes the full-precision value"
                   % (printed, rule, raw, want, k, lo, hi), "warn")
    return bad("printed %r is not %s applied to raw %r (expected %s)" % (printed, rule, raw, want))


def _check_run(project, rel, lineno, nid, run, row=None):
    out = []
    path = project.path("research/runs/%s/run.json" % run)
    if not RUN_RE.match(str(run)):
        return [Finding(rel, lineno, "NUM-RUN", "%s: run %r is not a RUN-ID" % (nid, run))]
    if not os.path.isfile(path):
        return [Finding(rel, lineno, "NUM-RUN", "%s: %s has no run record" % (nid, run))]
    try:
        with open(path, encoding="utf-8") as fh:
            rec = json.load(fh)
    except (OSError, ValueError) as exc:
        return [Finding(project.rel(path), 1, "NUM-RUN", "not valid JSON: %s" % exc)]
    if not isinstance(rec, dict):
        return [Finding(project.rel(path), 1, "NUM-RUN", "must be one JSON object")]
    if rec.get("exit_code") != 0:
        out.append(Finding(project.rel(path), 1, "NUM-RUN", "%s: exit_code is %r, not 0" % (run, rec.get("exit_code"))))
    commit = rec.get("git_commit")
    if not commit:
        out.append(Finding(project.rel(path), 1, "NUM-RUN", "%s: git_commit is missing" % run))
    elif in_git(project):
        if _git(project, ["merge-base", "--is-ancestor", commit, "HEAD"]) is None:
            out.append(Finding(project.rel(path), 1, "NUM-RUN", "%s: commit %s is not an ancestor of HEAD" % (run, commit)))
    # The number's output must be a file this run wrote, in the version the run wrote.
    if row is not None and row.get("output") and isinstance(rec.get("outputs"), list):
        produced = {o.get("path"): o.get("sha256") for o in rec["outputs"] if isinstance(o, dict)}
        out_rel = safe_rel(project, row["output"])
        if out_rel not in produced:
            out.append(Finding(rel, lineno, "NUM-RUN", "%s: %s does not list %s among its outputs; the number "
                               "cannot be traced to that run" % (nid, run, row["output"])))
        elif row.get("output_sha256") and produced[out_rel] != row["output_sha256"]:
            out.append(Finding(rel, lineno, "NUM-RUN", "%s: %s wrote a different version of %s (sha256 %s, ledger %s)"
                               % (nid, run, row["output"], str(produced[out_rel])[:12], str(row["output_sha256"])[:12])))
    return out


# ---- formulas (a declared metric definition is recomputed from other ledger values)

_FORMULA_ID_RE = re.compile(r"\bN-(\d+)\b")


def eval_formula(formula, values):
    """Evaluate `formula` (N-IDs, numbers, + - * / and parentheses) with Decimal arithmetic.

    `values` maps N-ID -> raw value. Raises ValueError with a readable reason."""
    src = _FORMULA_ID_RE.sub(lambda m: "N_" + m.group(1), formula)
    try:
        tree = ast.parse(src, mode="eval")
    except SyntaxError:
        raise ValueError("formula %r does not parse (use N-IDs, numbers, + - * / and parentheses)" % formula)

    def ev(node):
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Sub, ast.Mult, ast.Div)):
            a, b = ev(node.left), ev(node.right)
            if isinstance(node.op, ast.Add):
                return a + b
            if isinstance(node.op, ast.Sub):
                return a - b
            if isinstance(node.op, ast.Mult):
                return a * b
            if b == 0:
                raise ValueError("formula %r divides by zero" % formula)
            return a / b
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.USub, ast.UAdd)):
            v = ev(node.operand)
            return -v if isinstance(node.op, ast.USub) else v
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)) and not isinstance(node.value, bool):
            return Decimal(str(node.value))
        if isinstance(node, ast.Name) and re.match(r"^N_\d+$", node.id):
            nid = "N-" + node.id[2:]
            if nid not in values:
                raise ValueError("formula refers to %s, which is not in the number ledger" % nid)
            try:
                return Decimal(str(values[nid]))
            except (InvalidOperation, ValueError):
                raise ValueError("%s has a non-numeric raw value %r" % (nid, values[nid]))
        raise ValueError("formula %r may only use N-IDs, numbers, + - * / and parentheses" % formula)

    return ev(tree)


def within_tolerance(expected, observed, tol, default_rel=None):
    """Compare two values under a ledger tolerance. Non-numbers compare as strings."""
    try:
        a, b = Decimal(str(expected)), Decimal(str(observed))
    except (InvalidOperation, ValueError):
        return str(expected) == str(observed)
    if not tol or tol.get("kind") == "exact":
        if default_rel is not None:
            return abs(a - b) <= abs(a) * Decimal(str(default_rel))
        return a == b
    limit = Decimal(str(tol.get("value", 0)))
    if tol["kind"] == "rel":
        limit = abs(a) * limit
    return abs(a - b) <= limit


def _check_formula(numbers, nid, lineno, row):
    formula = row.get("formula")
    if not isinstance(formula, str) or not formula.strip():
        return []
    rel = numbers.rel
    refs = set("N-" + m for m in _FORMULA_ID_RE.findall(formula))
    if nid in refs:
        return [Finding(rel, lineno, "NUM-FORMULA", "%s: formula refers to itself" % nid)]
    values = {k: numbers.latest[k][1].get("raw") for k in refs if k in numbers.latest}
    try:
        computed = eval_formula(formula, values)
    except ValueError as exc:
        return [Finding(rel, lineno, "NUM-FORMULA", "%s: %s" % (nid, exc))]
    out = []
    shown = ", ".join("%s=%s" % (k, values[k]) for k in sorted(refs))
    # A float in a JSON file carries about 17 significant digits; 1e-9 relative covers that.
    if row.get("raw") is not None and not within_tolerance(computed, row["raw"], row.get("tolerance"), default_rel="1e-9"):
        out.append(Finding(rel, lineno, "NUM-FORMULA",
                           "%s: formula %s = %s (%s), but raw is %r; the metric does not follow its definition"
                           % (nid, formula, _fmt_decimal(computed), shown, row["raw"])))
    if row.get("rounding") and row.get("printed") is not None:
        try:
            want = apply_rounding(computed, row["rounding"], row.get("scale"))
        except (ValueError, InvalidOperation):
            want = None
        pm = re.match(r"^\s*(-?\d+(?:\.\d+)?)", str(row["printed"]))
        if want is not None and (not pm or pm.group(1) != want):
            out.append(Finding(rel, lineno, "NUM-FORMULA",
                               "%s: printed %r, but %s applied to the formula's value gives %s"
                               % (nid, row["printed"], row["rounding"], want)))
    return out


def _fmt_decimal(d):
    return "%.6g" % float(d)


# ---- evaluation split (cross-validation means are not held-out results)

CV_WORD_RE = re.compile(r"(cross[- ]?validat\w*|\bCV\b|\b\d+[- ]fold\b|\bfolds?\b)", re.I)
TRAIN_WORD_RE = re.compile(r"\b(training|train(?:ing)?[- ](?:set|split|data)|in[- ]sample)\b", re.I)
VALID_WORD_RE = re.compile(r"\bvalidation\b", re.I)
HELDOUT_WORD_RE = re.compile(r"(held[- ]out|\btest(?:ing)?[- ](?:set|split|data|score|AUC|F1|accuracy)\b|\bunseen\b|out[- ]of[- ]sample)", re.I)
SPLIT_WORDS = {"cross-validation": CV_WORD_RE, "training": TRAIN_WORD_RE, "validation": VALID_WORD_RE}
_CV_SOURCE_RE = re.compile(r"(\bcv\b|cv_|_cv|cross[-_ ]?valid|\bfolds?\b|\d+[-_ ]?fold)", re.I)
_TEST_SOURCE_RE = re.compile(r"(\btest\b|test_|_test|held[-_ ]?out)", re.I)


def _check_evaluation(rel, nid, lineno, row):
    if row.get("data_origin") == "literature":
        return []
    ev = row.get("evaluation")
    if ev is None:
        return [Finding(rel, lineno, "NUM-SPLIT", "%s: missing 'evaluation' (%s); say which split the value "
                        "comes from" % (nid, "|".join(EVALUATIONS)))]
    source = "%s %s" % (row.get("metric") or "", row.get("pointer") or "")
    if ev == "held-out" and _CV_SOURCE_RE.search(source) and not _TEST_SOURCE_RE.search(source):
        return [Finding(rel, lineno, "NUM-SPLIT", "%s: evaluation is held-out, but its metric/pointer describe a "
                        "cross-validation value (%s)" % (nid, source.strip()))]
    if ev in ("cross-validation", "training") and _TEST_SOURCE_RE.search(source) and not _CV_SOURCE_RE.search(source):
        return [Finding(rel, lineno, "NUM-SPLIT", "%s: evaluation is %s, but its metric/pointer describe a held-out "
                        "test value (%s)" % (nid, ev, source.strip()))]
    return []


def _split_disclosure(project, macro_rel):
    """A CV, training or validation value must say so where it is used: through its macro,
    or typed by hand at a place its row's `where` names."""
    out = []
    if not any(r.get("evaluation") in SPLIT_WORDS for _l, r in project.numbers().latest.values()):
        return out
    for path in project.tex_files():
        doc = project.doc(path)
        if doc.rel == macro_rel:
            continue
        for sent in doc.sentence_list():
            fid = doc.env[sent.start - 1]
            context = sent.text + " " + (doc.captions.get(fid, "") if fid is not None else "")
            for off, label, nid, row in number_occurrences(project, doc, sent):
                ev = row.get("evaluation")
                if ev not in SPLIT_WORDS:
                    continue
                if not SPLIT_WORDS[ev].search(context):
                    out.append(Finding(doc.rel, sent.line_of(off), "NUM-SPLIT",
                                       "%s (%s) is a %s value, but the sentence/caption does not say so; "
                                       "a reader will take it for a held-out result" % (label, nid, ev)))
                elif HELDOUT_WORD_RE.search(sent.text):
                    out.append(Finding(doc.rel, sent.line_of(off), "NUM-SPLIT",
                                       "%s (%s) is a %s value in a sentence that also says %r; check that it is "
                                       "not presented as held-out" % (label, nid, ev,
                                                                       HELDOUT_WORD_RE.search(sent.text).group(0)), "warn"))
    return out


def _hand_typed_numbers(project, macro_rel):
    """NUM-LITERAL (design 6.4 d): hand-typed numbers where results are reported, and every
    hand-typed value that a row's `where` locates, wherever it is."""
    out = []
    numbers = project.numbers()
    links = project.links()
    for path in project.tex_files():
        rel = project.rel(path)
        if rel == macro_rel:
            continue
        doc = project.doc(path)
        linked = links.numbers.get(doc.path, {})
        for idx, code in enumerate(doc.code):
            lit = LITERAL_RE.search(doc.comment[idx])
            if lit:
                if not lit.group(1).strip():
                    out.append(Finding(rel, idx + 1, "NUM-LITERAL", "uws:literal needs a reason"))
                continue
            here = dict(((st, en), nid) for st, en, _t, nid in linked.get(idx + 1, []))
            in_scope = _number_scope(doc, idx)
            for st, en, text, _num, reportable in number_tokens(code):
                nid = here.get((st, en))
                if nid:
                    macro = numbers.latest[nid][1].get("macro")
                    out.append(Finding(rel, idx + 1, "NUM-LITERAL",
                                       "hand-typed number %s is %s: use its macro %s, or mark the line "
                                       "`%% uws:literal <reason>`" % (text, nid, macro or "(it has none yet)")))
                elif in_scope and reportable:
                    out.append(Finding(rel, idx + 1, "NUM-LITERAL",
                                       "hand-typed number %s: use a generated macro from the number ledger, "
                                       "or mark the line `%% uws:literal <reason>`" % text))
    return out


# --------------------------------------------------------------------------- slop

S1_RE = re.compile(r"\b(novel(?:ty)?|state[- ]of[- ]the[- ]art|breakthroughs?|unprecedented|"
                   r"outperform(?:s|ed|ing)?|best|(?:the|a) first|first to|first time)\b", re.I)
# Fixed idioms in which "best" makes no claim about the work itself. The list is narrow on
# purpose and matched as whole phrases, never as a broad pattern that could hide a claim;
# "to the best of our knowledge" is NOT on it, because it usually introduces a novelty
# claim that needs a verified C-ID.
S1_IDIOM_RE = re.compile(r"\b(best[- ]practices?|best[- ]effort|best[- ]case|at best)\b", re.I)
S2_RE = re.compile(r"\b(studies (?:have )?(?:show|shown|suggest|found|demonstrate)\w*|research (?:has )?(?:show|shown)\w*|"
                   r"it is (?:well[- ]known|widely (?:known|accepted|believed|recognized))|"
                   r"researchers have (?:found|shown|argued)|experts (?:agree|say|believe)|"
                   r"it has been (?:shown|argued|suggested|demonstrated)|many (?:studies|researchers|experts))\b", re.I)
S4_TEXT_RE = re.compile(r"\b(TODO|TBD|FIXME|XXX)\b|lorem ipsum|\[citation needed\]|\?\?", re.I)
S4_TAG_RE = re.compile(r"\b(TODO|TBD|FIXME|XXX)\b")
S6_PROOF_RE = re.compile(r"\b(prove[sdn]?|proving|proof that)\b", re.I)
S6_CAUSAL_RE = re.compile(r"\b(caus(?:e|es|ed|ing|al|ally|ation)|enables? causal)\b", re.I)
CITE_RE = re.compile(r"\\(?:no)?cite[a-zA-Z]*\*?(?:\[[^\]]*\]){0,2}\{|\[-?@\w")
DISCLOSURE_RE = re.compile(r"\b(simulat\w*|synthetic\w*|generated|modell?ed|artificial)\b", re.I)
GROUND_TRUTH_RE = re.compile(r"\b(ground[- ]truth|gold[- ]standard|gold labels?|human[- ]annotated|annotated|"
                             r"manually (?:labell?ed|annotated)|expert[- ]labell?ed)\b", re.I)
GEN_LABEL_DISCLOSURE_RE = re.compile(r"\b(generator\w*|generated labels?|rule[- ]based|by construction|simulat\w*|synthetic labels?)\b", re.I)
MACRO_USE_RE = re.compile(r"\\([A-Za-z]+)")
LOG_UNDEF_RE = re.compile(r"(?:LaTeX|Package \w+) Warning: (?:Reference|Citation) [`'](.+?)' .*undefined")

RANDOM_DRAWS = {"random", "uniform", "gauss", "normalvariate", "lognormvariate", "expovariate",
                "triangular", "betavariate", "gammavariate", "randint", "randrange", "choice",
                "choices", "sample", "normal", "rand", "randn", "lognormal", "exponential",
                "poisson", "beta", "gamma", "binomial", "integers"}


def _claim_row(project, cid):
    item = project.claims().latest.get(cid)
    return item[1] if item else None


def check_slop(project, files=None, prose=True, code=True):
    findings = []
    if prose:
        tex_main = project.config.get("tex_main")
        if tex_main and not files:
            _f, missing = tex_closure(project, tex_main)
            for origin, oline, target in missing:
                findings.append(Finding(origin, oline, "S4", "\\input target %s does not exist (the manuscript does not build)" % target))
        # The generated macro file is the ledger printed as LaTeX, not prose.
        macro_file = os.path.abspath(project.path(project.config.get("numbers_tex") or "paper/generated/numbers.tex"))
        prose_files = [f for f in (files or project.prose_files())
                       if f.endswith((".tex", ".md")) and os.path.abspath(f) != macro_file]
        for path in prose_files:
            findings.extend(_slop_prose(project, project.doc(path)))
        if not files:
            findings.extend(_slop_latex_logs(project))
    if code:
        code_files = [f for f in (files or project.code_files()) if f.endswith((".py", ".sh", ".R", ".r", ".jl"))]
        for path in code_files:
            findings.extend(_slop_code(project, path))
        findings.extend(_c3_measured_random(project))
    return findings


def s1_match(text):
    """The first novelty or superlative word of `text` that is not part of an allowed idiom."""
    idioms = [m.span() for m in S1_IDIOM_RE.finditer(text)]
    for m in S1_RE.finditer(text):
        if not any(a <= m.start() and m.end() <= b for a, b in idioms):
            return m
    return None


def _slop_prose(project, doc):
    out = []
    links = project.links().claims.get(doc.path, {})

    # S4 placeholders: line level, including comments for the TODO family.
    for idx, code in enumerate(doc.code):
        for m in S4_TEXT_RE.finditer(code):
            out.append(Finding(doc.rel, idx + 1, "S4", "placeholder %r" % m.group(0)))
        for m in S4_TAG_RE.finditer(doc.comment[idx]):
            out.append(Finding(doc.rel, idx + 1, "S4", "placeholder %r in a comment" % m.group(0)))
    out.extend(_empty_cells(doc))

    for sentence in doc.sentence_list():
        start, sent, cids, line_of = sentence.start, sentence.text, sentence.cids, sentence.line_of
        rows = [(c, _claim_row(project, c)) for c in sorted(cids)]
        # S1 novelty or superlative words need a verified, non-hypothesis claim.
        m = s1_match(sent)
        if m and "candidate contribution" not in sent.lower():
            ok = [c for c, r in rows if r and r.get("status") == "verified" and r.get("category") != "hypothesis"]
            if not ok:
                why = "no C-ID on the sentence" if not rows else "its C-ID is unknown, unverified or a hypothesis (%s)" % ", ".join(c for c, _r in rows)
                out.append(Finding(doc.rel, line_of(m.start()), "S1",
                                   "%r needs a verified claim: %s; otherwise call it a candidate contribution" % (m.group(0), why)))
        # S2 vague attribution without a citation in the same sentence.
        m = S2_RE.search(sent)
        if m and not CITE_RE.search(sent):
            out.append(Finding(doc.rel, line_of(m.start()), "S2", "vague attribution %r with no citation" % m.group(0)))
        # S6 strength drift.
        for regex, need in ((S6_PROOF_RE, "proof"), (S6_CAUSAL_RE, "causal")):
            m = regex.search(sent)
            if not m:
                continue
            strong = [c for c, r in rows if r and STRENGTH_RANK.get(r.get("strength", "none"), 0) >= STRENGTH_RANK[need]]
            if not strong:
                out.append(Finding(doc.rel, line_of(m.start()), "S6",
                                   "%r claims %s-level evidence, but no C-ID on the sentence has strength >= %s"
                                   % (m.group(0), need, need)))
        # Ledger numbers in the sentence: macro uses and hand-typed values located by `where`.
        occurrences = number_occurrences(project, doc, sentence)
        # C3 disclosure: non-measured numbers or claims need a disclosure word nearby.
        disclosed = bool(DISCLOSURE_RE.search(sent))
        if not disclosed:
            fid = doc.env[start - 1]
            if fid is not None and DISCLOSURE_RE.search(doc.captions.get(fid, "")):
                disclosed = True
        if not disclosed:
            for off, label, nid, row in occurrences:
                if row.get("data_origin") in NON_MEASURED:
                    out.append(Finding(doc.rel, line_of(off), "C3", "%s (%s) is %s data but the sentence/caption "
                                       "does not say so" % (label, nid, row.get("data_origin"))))
            for c, r in rows:
                if r and r.get("data_origin") in NON_MEASURED:
                    out.append(Finding(doc.rel, start, "C3",
                                       "%s rests on %s data but the sentence does not say so" % (c, r.get("data_origin"))))
        # C6: labels a generator assigned are not ground truth (PROMISE audit). Evidence
        # tied to the sentence (a C-ID on it, a claim row whose `where` names its line, or a
        # ledger number in it) blocks; without such a link the only evidence is that some
        # registered data has generator-rule labels, so it warns.
        m = GROUND_TRUTH_RE.search(sent)
        if m and not GEN_LABEL_DISCLOSURE_RE.search(sent):
            linked = set()
            for ln in sentence.lines:
                linked |= links.get(ln, set())
            traced = rows + [(c, _claim_row(project, c)) for c in sorted(linked - set(cids))]
            why = _generated_label_trace(project, traced, occurrences)
            if why:
                out.append(Finding(doc.rel, line_of(m.start()), "C6",
                                   "%r, but %s; call them generator-assigned labels" % (m.group(0), why)))
            elif not traced and not occurrences and _manifest_has_generator_labels(project):
                out.append(Finding(doc.rel, line_of(m.start()), "C6",
                                   "%r in a sentence with no C-ID or number macro, while the data manifest has "
                                   "generator-rule labels; trace the sentence or qualify the wording" % m.group(0), "warn"))
    return out


def _manifest_has_generator_labels(project):
    return any(r.get("labels") == "generator-rule" for _l, r in project.manifest().latest.values())


def _generated_label_trace(project, rows, occurrences):
    """Why the data behind a sentence is not ground truth, or None. `rows` are the claims
    traced to the sentence, `occurrences` the ledger numbers in it."""
    numbers = project.numbers()
    nids = set()
    for c, r in rows:
        if r and r.get("labels") == "generator-rule":
            return "%s records generator-rule labels" % c
        if r and r.get("data_origin") in NON_MEASURED:
            return "%s rests on %s data" % (c, r.get("data_origin"))
        for nid in (r or {}).get("numbers") or []:
            nids.add(nid)
    for _off, _label, nid, _row in occurrences:
        nids.add(nid)
    man = project.manifest()
    for nid in sorted(nids):
        item = numbers.latest.get(nid)
        if not item:
            continue
        row = item[1]
        if row.get("data_origin") in NON_MEASURED:
            return "%s is %s data" % (nid, row.get("data_origin"))
        for p, _sha in number_inputs(project, row):
            entry = man.latest.get(p)
            if entry and entry[1].get("labels") == "generator-rule":
                return "%s uses %s, whose labels come from generator rules" % (nid, p)
    return None


# A table cell that holds a number (optionally in math mode, with sign, %, or \pm).
_NUMERIC_CELL_RE = re.compile(r"^\$?[-+]?\d+(?:[.,]\d+)?\s*(?:\\%|%|\$)?")


def _empty_cells(doc):
    out = []
    multirow_seen = False
    for idx, code in enumerate(doc.code):
        if not doc.in_tabular[idx]:
            multirow_seen = False
            continue
        if "\\multirow" in code or "\\multicolumn" in code:
            multirow_seen = True
        if multirow_seen or "&" not in code or "\\\\" not in code:
            continue
        row = code.split("\\\\")[0]
        cells = re.split(r"(?<!\\)&", row)
        # A blank only signals a missing value in a row of numbers. The first cell is the row
        # label (or the empty corner of a header row), and blanks in qualitative tables
        # (e.g. checkmark feature comparisons) are meaningful, so neither is flagged.
        data = [c.strip() for c in cells[1:]]
        if any(not c for c in data) and any(_NUMERIC_CELL_RE.search(c) for c in data if c):
            if LITERAL_RE.search(doc.comment[idx]):
                continue
            out.append(Finding(doc.rel, idx + 1, "S4", "empty cell in a row of numbers (missing value?)"))
    return out


def _slop_latex_logs(project):
    out = []
    seen = set()
    for path in project.tex_files():
        log = path[:-4] + ".log"
        if log in seen or not os.path.isfile(log):
            continue
        seen.add(log)
        for lineno, raw in enumerate(read_text(log).splitlines(), 1):
            m = LOG_UNDEF_RE.search(raw)
            if m:
                out.append(Finding(project.rel(log), lineno, "S4", "undefined reference or citation %r prints as ??" % m.group(1)))
    return out


def _slop_code(project, path):
    rel = project.rel(path)
    out = []
    text = read_text(path)
    if not path.endswith(".py"):
        for lineno, raw in enumerate(text.splitlines(), 1):
            if "#" in raw and S4_TAG_RE.search(raw.split("#", 1)[1]):
                out.append(Finding(rel, lineno, "C1", "placeholder comment: %s" % raw.strip()[:60]))
            if path.endswith(".sh") and re.search(r"\bls\s+-[A-Za-z]*t", raw.split("#", 1)[0]):
                out.append(Finding(rel, lineno, "C5", "input chosen by modification time (ls -t); pin it by path and hash"))
        return out
    try:
        tree = ast.parse(text, filename=rel)
    except SyntaxError as exc:
        return [Finding(rel, exc.lineno or 1, "C1", "does not parse: %s" % exc.msg)]
    try:
        for tok in tokenize.generate_tokens(io.StringIO(text).readline):
            if tok.type == tokenize.COMMENT and S4_TAG_RE.search(tok.string):
                out.append(Finding(rel, tok.start[0], "C1", "placeholder comment: %s" % tok.string.strip()[:60]))
    except (tokenize.TokenError, IndentationError):
        pass
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            decos = {_dotted(d) for d in node.decorator_list}
            if decos & {"abstractmethod", "abc.abstractmethod", "overload", "typing.overload"}:
                continue
            body = list(node.body)
            if body and isinstance(body[0], ast.Expr) and isinstance(getattr(body[0], "value", None), ast.Constant) \
                    and isinstance(body[0].value.value, str):
                body = body[1:]
            if len(body) == 1 and (isinstance(body[0], ast.Pass) or
                                   (isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant)
                                    and body[0].value.value is Ellipsis)):
                out.append(Finding(rel, node.lineno, "C1", "function %s has an empty body (pass/...)" % node.name))
            for sub in ast.walk(node):
                if isinstance(sub, ast.Raise) and sub.exc is not None and \
                        _dotted(sub.exc.func if isinstance(sub.exc, ast.Call) else sub.exc) == "NotImplementedError":
                    out.append(Finding(rel, sub.lineno, "C1", "%s raises NotImplementedError" % node.name))
        elif isinstance(node, ast.ExceptHandler):
            if node.type is None and len(node.body) == 1 and isinstance(node.body[0], ast.Pass):
                out.append(Finding(rel, node.lineno, "C1", "bare `except: pass` hides every error"))
        elif isinstance(node, ast.Call):
            fname = _dotted(node.func)
            if fname in ("max", "min", "sorted") or fname.endswith(".sort"):
                for kw in node.keywords:
                    if kw.arg == "key" and re.search(r"(st_mtime|st_ctime|getmtime|getctime)", ast.dump(kw.value)):
                        out.append(Finding(rel, node.lineno, "C5",
                                           "input chosen by modification time (%s with key=...mtime); pin it by path and hash" % fname))
    return out


def _dotted(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = _dotted(node.value)
        return base + "." + node.attr if base else node.attr
    if isinstance(node, ast.Call):
        return _dotted(node.func)
    return ""


def _random_draws(path):
    try:
        tree = ast.parse(read_text(path))
    except (SyntaxError, OSError, ValueError):
        return []
    hits = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = _dotted(node.func)
            parts = name.split(".")
            if len(parts) >= 2 and parts[-1] in RANDOM_DRAWS and parts[-2] == "random":
                hits.append((node.lineno, name))
    return hits


def _c3_measured_random(project):
    """C3: a 'measured' number whose producing script draws random values."""
    out = []
    numbers = project.numbers()
    for nid in sorted(numbers.latest):
        lineno, row = numbers.latest[nid]
        if row.get("data_origin") != "measured":
            continue
        scripts = []
        if row.get("script"):
            scripts.append(row["script"])
        run = row.get("run")
        run_path = project.path("research/runs/%s/run.json" % run) if run else None
        if run_path and os.path.isfile(run_path):
            try:
                with open(run_path, encoding="utf-8") as fh:
                    rec = json.load(fh)
            except (OSError, ValueError):
                rec = {}
            rec = rec if isinstance(rec, dict) else {}
            cmd = rec.get("command") or ""
            if isinstance(cmd, list):
                cmd = " ".join(cmd)
            scripts.extend(re.findall(r"[\w./-]+\.py\b", str(cmd)))
            scripts.extend(p for p in run_code_paths(rec) if p.endswith(".py") and p not in scripts)
        for script in scripts:
            spath = project.path(script)
            if not os.path.isfile(spath):
                continue
            for sline, name in _random_draws(spath):
                out.append(Finding(numbers.rel, lineno, "C3",
                                   "%s is labelled measured, but %s:%d draws %s(); label it simulated or remove the draw"
                                   % (nid, script, sline, name)))
    return out


# --------------------------------------------------------------------------- plans (pre-registration)

PLANS_REL = "research/ledger/plans.jsonl"
EXPERIMENTS_REL = "research/experiments"

# apocalypt.md P5 (hypothesis, independent unit, baseline, metric, controls, decision rule,
# fixed before outcomes are inspected), P7 (stopping condition) and design section 5
# (grouping variable when samples repeat; power analysis or a reason for the sample size).
PLAN_FIELDS = (
    ("hypothesis", ("hypothesis",)),
    ("unit of evaluation", ("unit of evaluation", "evaluation unit", "independent unit", "unit")),
    ("baseline", ("baseline", "baselines")),
    ("metric", ("metric", "metrics", "primary metric")),
    ("controls", ("controls", "control")),
    ("split and grouping", ("split and grouping", "split", "splits", "data split", "grouping")),
    ("sample size", ("sample size", "power analysis", "sample size and power")),
    ("decision rule", ("decision rule",)),
    ("stopping condition", ("stopping condition", "stopping conditions", "stopping rule")),
)

PLAN_TEMPLATE = """# {exp}: pre-registered plan

<!-- apocalypt.md P5/P7. Fill every section BEFORE any result exists, then freeze it:
       uws research check plan freeze {exp}
     and commit the freeze. The analysis gate fails for results that were committed before
     the freeze, and for a plan changed after results without a PI-approved deviation. -->

## Hypothesis
<!-- The claim under test, with its C-ID (a hypothesis row in research/ledger/claims.jsonl). -->

## Unit of evaluation
<!-- The independent unit (e.g. scenario, subject, repository), not a row if rows repeat. -->

## Baseline

## Metric
<!-- Exact definition, e.g. FPR = FP / (FP + TN) on the held-out test split. -->

## Controls

## Split and grouping
<!-- Train/validation/test or cross-validation; the grouping variable if units repeat. -->

## Sample size
<!-- A power analysis, or the written reason for this sample size. -->

## Decision rule
<!-- What result supports, and what result refutes, the hypothesis. -->

## Stopping condition
"""


class Plans(object):
    """research/ledger/plans.jsonl: one freeze record per (exp, rev), append-only."""

    def __init__(self, project):
        self.rel = PLANS_REL
        self.path = project.path(self.rel)
        self.rows, self.parse_errors = [], []
        self.by_exp = {}
        if os.path.isfile(self.path):
            for lineno, obj, err in _read_jsonl(self.path):
                if err:
                    self.parse_errors.append(Finding(self.rel, lineno, "PLAN-SCHEMA", err))
                    continue
                self.rows.append((lineno, obj))
                if isinstance(obj.get("exp"), str):
                    self.by_exp.setdefault(obj["exp"], []).append((lineno, obj))


def _read_jsonl(path):
    """Yield (lineno, dict, None) or (lineno, None, error) for each non-blank line."""
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            if not raw.strip():
                continue
            try:
                obj = json.loads(raw)
            except ValueError as exc:
                yield lineno, None, "not valid JSON: %s" % exc
                continue
            if not isinstance(obj, dict):
                yield lineno, None, "each line must be one JSON object"
                continue
            yield lineno, obj, None


def _append_jsonl(path, obj):
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    line = json.dumps(obj, sort_keys=True, separators=(", ", ": ")) + "\n"
    prefix = ""
    if os.path.isfile(path) and os.path.getsize(path) > 0:
        with open(path, "rb") as fh:
            fh.seek(-1, os.SEEK_END)
            if fh.read(1) != b"\n":
                prefix = "\n"
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(prefix + line)


def parse_labelled_fields(text, spec):
    """Sections of a Markdown brief: `## Label` headings or `Label: value` lines.

    Returns ({canonical: body}, {canonical: lineno}). HTML comments are ignored."""
    text = _strip_html_comments(text)
    sections, current, label_line = {}, None, {}
    for lineno, raw in enumerate(text.splitlines(), 1):
        heading = re.match(r"^\s*#+\s*(.+?)\s*:?\s*$", raw)
        labelled = re.match(r"^\s*(?:[-*]\s*)?(?:\*\*)?([A-Za-z ]+?)(?:\*\*)?\s*:\s*(?:\*\*)?\s*(.*)$", raw)
        label, rest = "", ""
        if heading:
            label = heading.group(1).strip("* ").lower()
        elif labelled:
            label, rest = labelled.group(1).strip().lower(), labelled.group(2)
        matched = None
        for canon, names in spec:
            if label in names:
                matched = canon
        if matched:
            current = matched
            label_line[current] = lineno
            sections[current] = sections.get(current, "") + " " + rest
        elif heading:
            current = None
        elif current:
            sections[current] += " " + raw
    return sections, label_line


def _empty_field(body):
    body = (body or "").strip()
    return not body or bool(re.fullmatch(r"(?i)(tbd|todo|n/?a|-|\.\.\.)", body))


def experiment_ids(project):
    d = project.path(EXPERIMENTS_REL)
    if not os.path.isdir(d):
        return []
    return sorted(n for n in os.listdir(d) if os.path.isdir(os.path.join(d, n)) and not n.startswith("."))


def plan_field_findings(project, exp):
    rel = "%s/%s/plan.md" % (EXPERIMENTS_REL, exp)
    path = project.path(rel)
    if not os.path.isfile(path):
        return [Finding(rel, 1, "PLAN-FIELDS", "%s has no plan.md (create one with `uws research check plan new %s`)"
                        % (exp, exp))]
    sections, lines = parse_labelled_fields(read_text(path), PLAN_FIELDS)
    out = []
    for canon, _names in PLAN_FIELDS:
        if _empty_field(sections.get(canon)):
            out.append(Finding(rel, lines.get(canon, 1), "PLAN-FIELDS", "%s: '%s' is missing or empty" % (exp, canon)))
    claims = project.claims()
    for cid in sorted(set(CID_RE.findall(sections.get("hypothesis", "")))):
        item = claims.latest.get(cid)
        if item is None:
            out.append(Finding(rel, lines.get("hypothesis", 1), "PLAN-REF", "%s: %s is not in the claim ledger" % (exp, cid)))
        elif item[1].get("category") != "hypothesis":
            out.append(Finding(rel, lines.get("hypothesis", 1), "PLAN-REF",
                               "%s: %s is a %s, not a hypothesis" % (exp, cid, item[1].get("category"))))
    return out


def plan_results(project):
    """exp -> [(label, kind, key)]: number rows and run records that report results for it."""
    res = {}
    for nid, (_ln, row) in sorted(project.numbers().latest.items()):
        exp = row.get("exp")
        if isinstance(exp, str) and exp != EXPLORATORY:
            res.setdefault(exp, []).append((nid, "number", nid))
    for run_id, (rel, rec, _err) in sorted(project.runs().items()):
        exp = rec.get("exp") if rec else None
        if isinstance(exp, str) and exp != EXPLORATORY:
            res.setdefault(exp, []).append((run_id, "run", rel))
    return res


def _short(sha):
    return str(sha or "")[:12]


def check_plans(project, require_plan=False):
    """Pre-registration (design section 5, experiment_design and analysis rows)."""
    out = []
    plans = project.plans()
    out.extend(plans.parse_errors)
    out.extend(append_only_findings(project, plans.rel, "PLAN-APPEND"))
    decisions = pi_decision_ids(project)

    # Freeze-record schema.
    for exp, rows in sorted(plans.by_exp.items()):
        prev = None
        for i, (lineno, row) in enumerate(rows, 1):
            if not EXP_RE.match(exp):
                out.append(Finding(plans.rel, lineno, "PLAN-SCHEMA", "exp %r is not EXP-<name>" % exp))
            if row.get("rev") != i:
                out.append(Finding(plans.rel, lineno, "PLAN-SCHEMA", "%s: freeze rev should be %d (got %r)" % (exp, i, row.get("rev"))))
            if not re.match(r"^[0-9a-f]{64}$", str(row.get("sha256") or "")):
                out.append(Finding(plans.rel, lineno, "PLAN-SCHEMA", "%s: sha256 must be 64 hex digits" % exp))
            for key in ("plan", "frozen_at", "frozen_by"):
                if not row.get(key):
                    out.append(Finding(plans.rel, lineno, "PLAN-SCHEMA", "%s: missing '%s'" % (exp, key)))
            if prev is not None and row.get("previous_sha256") != prev.get("sha256"):
                out.append(Finding(plans.rel, lineno, "PLAN-SCHEMA", "%s@%d: previous_sha256 must name the freeze it replaces (%s)"
                                   % (exp, i, _short(prev.get("sha256")))))
            prev = row

    exps = experiment_ids(project)
    if require_plan and not exps:
        out.append(Finding(EXPERIMENTS_REL, 1, "PLAN-FREEZE", "no experiment plan: experiment_design produces at least one "
                           "research/experiments/EXP-<name>/plan.md (`uws research check plan new EXP-<name>`)"))
    results = plan_results(project)
    for exp in exps:
        if not EXP_RE.match(exp):
            out.append(Finding("%s/%s" % (EXPERIMENTS_REL, exp), 1, "PLAN-ID", "experiment directory must be named EXP-<name>"))
            continue
        out.extend(plan_field_findings(project, exp))
        plan_rel = "%s/%s/plan.md" % (EXPERIMENTS_REL, exp)
        if not os.path.isfile(project.path(plan_rel)):
            continue
        rows = plans.by_exp.get(exp)
        if not rows:
            out.append(Finding(plan_rel, 1, "PLAN-FREEZE", "%s is not frozen: run `uws research check plan freeze %s` "
                               "and commit it before collecting data" % (exp, exp)))
            continue
        current = sha256_file(project.path(plan_rel))
        latest = rows[-1][1]
        if latest.get("sha256") != current:
            if results.get(exp):
                how = ("results exist (%s), so the change is a deviation: `uws research check plan freeze %s "
                       "--reason \"...\" --pi-decision D-<n>` after the PI decides"
                       % (", ".join(r[0] for r in results[exp][:3]), exp))
            else:
                how = "no results exist yet, so re-freeze it: `uws research check plan freeze %s`" % exp
            out.append(Finding(plan_rel, 1, "PLAN-DRIFT", "%s changed after it was frozen (sha256 %s, frozen %s); %s"
                               % (exp, _short(current), _short(latest.get("sha256")), how)))
    known = set(exps)
    for exp, rows in sorted(plans.by_exp.items()):
        if exp not in known:
            out.append(Finding(plans.rel, rows[-1][0], "PLAN-FREEZE", "%s is frozen but %s/%s/plan.md is gone" % (exp, EXPERIMENTS_REL, exp)))

    # Every result is linked to a plan, or labelled exploratory.
    numbers = project.numbers()
    for nid in sorted(numbers.latest):
        lineno, row = numbers.latest[nid]
        if row.get("data_origin") == "literature":
            continue
        exp = row.get("exp")
        if exp is None:
            out.append(Finding(numbers.rel, lineno, "PLAN-LINK", "%s: set exp to the EXP-ID whose frozen plan it answers, "
                               "or to %r (then it is not a pre-registered result)" % (nid, EXPLORATORY)))
        elif exp != EXPLORATORY and exp not in known:
            out.append(Finding(numbers.rel, lineno, "PLAN-LINK", "%s: exp %s has no %s/%s/plan.md" % (nid, exp, EXPERIMENTS_REL, exp)))
    for run_id, (rel, rec, _err) in sorted(project.runs().items()):
        exp = rec.get("exp") if rec else None
        if isinstance(exp, str) and exp != EXPLORATORY and exp not in known:
            out.append(Finding(rel, 1, "PLAN-LINK", "%s: exp %s has no %s/%s/plan.md" % (run_id, exp, EXPERIMENTS_REL, exp)))

    out.extend(_plan_order(project, plans, results, decisions, known))
    return out


def _freeze_key(row):
    return (str(row.get("exp")), str(row.get("rev")), str(row.get("sha256")))


def _plan_order(project, plans, results, decisions, known):
    """Results must be committed after the plan's first freeze; later re-freezes need a PI decision."""
    out = []
    todo = [exp for exp in sorted(results) if exp in known and plans.by_exp.get(exp)]
    if not todo:
        return out
    if not in_git(project):
        for exp in todo:
            out.append(Finding(plans.rel, plans.by_exp[exp][0][0], "PLAN-ORDER",
                               "%s: not a git repository, so the freeze cannot be shown to precede its results" % exp))
        return out
    numbers = project.numbers()
    runs = project.runs()
    num_first = first_appearance(project, numbers.rel,
                                 lambda t: {o["id"] for o in _jsonl_objects(t) if isinstance(o.get("id"), str)})
    # Keyed on the frozen hash too: a freeze row edited in place counts from the commit
    # that introduced the edit, not from the commit of the original row.
    plan_first = first_appearance(project, plans.rel,
                                  lambda t: {_freeze_key(o) for o in _jsonl_objects(t)})
    path_first, blob_first = {}, {}

    def first_commit_of(rel):
        """The oldest commit in HEAD's history that has `rel` (by name; `--follow` is not
        used because it takes an unrelated file with the same content for a rename)."""
        if rel not in path_first:
            log = _git(project, ["log", "--format=%H", "--", rel])
            commits = (log or "").split()
            path_first[rel] = commits[-1] if commits else None
        return path_first[rel]

    def first_commit_with_content(rel, sha256):
        """The oldest commit in HEAD's history that holds the content of `rel` under any
        name, when that content is the recorded version (`sha256`). This covers a result
        committed under another name, or renamed, before the freeze."""
        path = project.path(rel)
        if not sha256 or not os.path.isfile(path) or sha256_file(path) != sha256:
            return None
        if rel not in blob_first:
            blob = (_git(project, ["hash-object", "--", rel]) or "").strip()
            log = _git(project, ["log", "--format=%H", "--find-object=%s" % blob]) if blob else None
            commits = (log or "").split()
            blob_first[rel] = commits[-1] if commits else None
        return blob_first[rel]

    def evidence(kind, key, label):
        """When the result existed: [(what, commit)], plus the commit its run executed on.

        A result exists from the earliest of: the ledger row (or run record), the first
        commit of the output file it names, and the first commit of its run record. Adding
        the ledger row after a fresh freeze therefore cannot hide results committed earlier."""
        items, run_id, run_rec = [], None, None
        if kind == "number":
            row = numbers.latest[key][1]
            items.append(("row", None, num_first.get(key)))
            out_rel = safe_rel(project, row.get("output"))
            if out_rel:
                items.append(("output", out_rel, first_commit_of(out_rel)))
                items.append(("output content", out_rel, first_commit_with_content(out_rel, row.get("output_sha256"))))
            if row.get("run") and str(row["run"]) in runs:
                run_id = str(row["run"])
        else:
            run_id = label
        if run_id in runs:
            rel, run_rec, _err = runs[run_id]
            items.append(("run record", rel, first_commit_of(rel)))
            for o in (run_rec or {}).get("outputs") or []:
                o_rel = safe_rel(project, o.get("path")) if isinstance(o, dict) else None
                if o_rel and (kind == "run" or not any(i[1] == o_rel for i in items)):
                    items.append(("output", o_rel, first_commit_of(o_rel)))
                    items.append(("output content", o_rel, first_commit_with_content(o_rel, o.get("sha256"))))
        return items, run_id, (run_rec or {}).get("git_commit")

    for exp in todo:
        rows = plans.by_exp[exp]
        res = [(label, kind) + evidence(kind, key, label) for label, kind, key in results[exp]]
        first_line, first_row = rows[0]
        f1 = plan_first.get(_freeze_key(first_row))
        if f1 is None:
            out.append(Finding(plans.rel, first_line, "PLAN-ORDER",
                               "%s: the freeze is not committed, but results exist (%s); commit the freeze first"
                               % (exp, ", ".join(r[0] for r in res[:3]))))
        else:
            for label, kind, items, run_id, run_commit in res:
                reported = set()
                for what, rel, c in items:
                    if c is None or c in reported or (c != f1 and is_ancestor(project, f1, c)):
                        continue
                    reported.add(c)
                    if what == "row" or (kind == "run" and what == "run record"):
                        msg = "%s was committed in %s" % (label, c[:12])
                    elif what == "output content":
                        msg = "%s: the content of its output %s was first committed in %s (under this or another " \
                              "name)" % (label, rel, c[:12])
                    else:
                        msg = "%s: its %s %s was first committed in %s" % (label, what, rel, c[:12])
                    out.append(Finding(plans.rel, first_line, "PLAN-ORDER",
                                       "%s: %s, not after the plan was frozen (%s); a plan written after its "
                                       "results is not a pre-registration" % (exp, msg, f1[:12])))
                if run_commit and not is_ancestor(project, f1, str(run_commit)):
                    who = run_id if kind == "run" else "%s (%s)" % (run_id, label)
                    out.append(Finding(plans.rel, first_line, "PLAN-ORDER",
                                       "%s: %s ran on commit %s, which does not contain the freeze (%s): the run "
                                       "happened before the plan was frozen" % (exp, who, str(run_commit)[:12], f1[:12])))
        res = [(label, c) for label, _k, items, _r, run_commit in res
               for c in [i[2] for i in items] + [run_commit] if c]
        dev_path = project.path("%s/%s/deviations.md" % (EXPERIMENTS_REL, exp))
        dev_text = read_text(dev_path) if os.path.isfile(dev_path) else ""
        for lineno, row in rows[1:]:
            ck = plan_first.get(_freeze_key(row))
            if ck is None:
                after = True
            else:
                after = any(c is not None and is_ancestor(project, c, ck) for _l, c in res)
            if not after:
                continue
            problems = []
            if not row.get("reason"):
                problems.append("a reason")
            did = str(row.get("pi_decision") or "")
            if not DID_RE.fullmatch(did) or did not in decisions:
                problems.append("a PI decision ID recorded in research/pi/decisions.md")
            dev = str(row.get("deviation") or "")
            if not DEV_RE.fullmatch(dev) or not re.search(r"(?m)^\|\s*%s\s*\|" % re.escape(dev), dev_text):
                problems.append("a DEV row in %s/%s/deviations.md" % (EXPERIMENTS_REL, exp))
            if problems:
                out.append(Finding(plans.rel, lineno, "PLAN-DEVIATION",
                                   "%s@%s re-froze the plan after results existed without %s"
                                   % (exp, row.get("rev"), ", ".join(problems))))
    return out


def plan_new(project, args):
    exp = args.exp
    if not exp or not EXP_RE.match(exp):
        print("refused: give an experiment ID such as EXP-LEAK", file=sys.stderr)
        return EXIT_FINDINGS
    rel = "%s/%s/plan.md" % (EXPERIMENTS_REL, exp)
    path = project.path(rel)
    if os.path.exists(path):
        print("refused: %s exists (plans are never overwritten)" % rel, file=sys.stderr)
        return EXIT_FINDINGS
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(PLAN_TEMPLATE.format(exp=exp))
    print("created %s; fill every section, then `uws research check plan freeze %s`" % (rel, exp))
    return EXIT_OK


def plan_freeze(project, args):
    exp = args.exp
    if not exp or not EXP_RE.match(exp):
        print("refused: give an experiment ID such as EXP-LEAK", file=sys.stderr)
        return EXIT_FINDINGS
    by = args.by or "methodologist"
    if not ROLE_RE.match(by):
        print("refused: --by must be a role name such as methodologist", file=sys.stderr)
        return EXIT_FINDINGS
    rel = "%s/%s/plan.md" % (EXPERIMENTS_REL, exp)
    if not os.path.isfile(project.path(rel)):
        print("refused: %s does not exist (`uws research check plan new %s`)" % (rel, exp), file=sys.stderr)
        return EXIT_FINDINGS
    incomplete = [f for f in plan_field_findings(project, exp) if f.level == "block"]
    if incomplete:
        emit(incomplete, False)
        print("refused: an incomplete plan cannot be pre-registered", file=sys.stderr)
        return EXIT_FINDINGS
    plans = project.plans()
    rows = plans.by_exp.get(exp, [])
    sha = sha256_file(project.path(rel))
    results = plan_results(project).get(exp, [])
    if rows and rows[-1][1].get("sha256") == sha:
        print("%s is already frozen at sha256 %s (rev %s); nothing to do" % (exp, _short(sha), rows[-1][1].get("rev")))
        return EXIT_OK
    row = {"exp": exp, "rev": len(rows) + 1, "plan": rel, "sha256": sha, "frozen_at": utc_now(), "frozen_by": by}
    dev_row = None
    if not rows:
        if results:
            print("refused: results for %s already exist (%s). A plan frozen now is not a pre-registration: label "
                  "those numbers exp \"%s\", or ask the PI." % (exp, ", ".join(r[0] for r in results[:5]), EXPLORATORY),
                  file=sys.stderr)
            return EXIT_FINDINGS
    else:
        row["previous_sha256"] = rows[-1][1].get("sha256")
        if args.reason:
            row["reason"] = args.reason
        if results:
            did = args.pi_decision or ""
            if not args.reason or not DID_RE.fullmatch(did) or did not in pi_decision_ids(project):
                print("refused: results for %s exist (%s), so changing the frozen plan is a deviation. It needs "
                      "--reason \"...\" and --pi-decision D-<n> recorded in research/pi/decisions.md "
                      "(apocalypt.md P5; design section 7.3)." % (exp, ", ".join(r[0] for r in results[:5])),
                      file=sys.stderr)
                return EXIT_FINDINGS
            dev_rel = "%s/%s/deviations.md" % (EXPERIMENTS_REL, exp)
            dev_path = project.path(dev_rel)
            existing = read_text(dev_path) if os.path.isfile(dev_path) else ""
            nums = [int(n) for n in re.findall(r"(?m)^\|\s*DEV-(\d+)\s*\|", existing)]
            dev_id = "DEV-%03d" % (max(nums) + 1 if nums else 1)
            row.update({"deviation": dev_id, "pi_decision": did})
            dev_row = (dev_path, existing, "| %s | %s | %s -> %s | %s | %s |\n" % (
                dev_id, row["frozen_at"], _short(row["previous_sha256"]), _short(sha),
                args.reason.replace("|", "/").replace("\n", " "), did))
    if dev_row:
        dev_path, existing, line = dev_row
        if not existing:
            existing = ("# Deviations from the frozen plan of %s\n\n<!-- Written by `uws research check plan freeze`. "
                        "One row per change made after results existed; each needs a PI decision. -->\n\n"
                        "| ID | Date (UTC) | Frozen sha256 before -> after | Reason | PI decision |\n"
                        "|---|---|---|---|---|\n" % exp)
        _atomic_write(dev_path, existing + line)
    _append_jsonl(plans.path, row)
    print("froze %s rev %d at sha256 %s%s" % (exp, row["rev"], _short(sha),
                                              " (deviation %s, %s)" % (row["deviation"], row["pi_decision"]) if dev_row else ""))
    print("commit it before collecting data: git add %s %s && git commit" % (PLANS_REL, rel))
    return EXIT_OK


# --------------------------------------------------------------------------- data manifest and run records

MANIFEST_REL = "research/data/manifest.jsonl"
RAW_DATA_REL = "research/data/raw"
MANIFEST_REQUIRED = ("path", "sha256", "size", "source", "version", "split", "origin")
RUN_REQUIRED = ("id", "command", "git_commit", "git_dirty", "started_at", "ended_at", "exit_code", "inputs", "outputs")


class Manifest(object):
    """research/data/manifest.jsonl: one row per registered version of a data file."""

    def __init__(self, project):
        self.rel = MANIFEST_REL
        self.path = project.path(self.rel)
        self.rows, self.parse_errors = [], []
        self.latest = {}
        if os.path.isfile(self.path):
            for lineno, obj, err in _read_jsonl(self.path):
                if err:
                    self.parse_errors.append(Finding(self.rel, lineno, "DATA-SCHEMA", err))
                    continue
                self.rows.append((lineno, obj))
                p = safe_rel(project, obj.get("path"))
                if p:
                    self.latest[p] = (lineno, obj)


def is_generated(row):
    return row.get("origin") in NON_MEASURED or bool(row.get("generator"))


def seed_recorded(seed):
    if seed is None or isinstance(seed, bool):
        return False
    return str(seed).strip().lower() not in UNRECORDED_SEEDS


_SEEDING_CALLS = {"seed", "manual_seed", "set_seed", "manual_seed_all"}
_RNG_CONSTRUCTORS = {"default_rng", "RandomState", "Random", "SeedSequence", "PCG64", "MT19937", "Philox", "SFC64"}


def seeding_calls(path):
    """(seeded, unseeded): calls that fix a seed, and RNGs constructed without one."""
    try:
        tree = ast.parse(read_text(path))
    except (SyntaxError, OSError, ValueError):
        return [], []
    seeded, unseeded = [], []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = _dotted(node.func)
        last = name.split(".")[-1]
        has_arg = bool(node.args) or any(kw.arg in ("seed", "a", "x", "entropy") for kw in node.keywords)
        if last in _SEEDING_CALLS or last in _RNG_CONSTRUCTORS:
            (seeded if has_arg else unseeded).append((node.lineno, name))
    return seeded, unseeded


def number_inputs(project, row):
    """Input paths of a number: its own `inputs` plus the inputs of its run record."""
    paths = []
    for p in row.get("inputs") or []:
        if isinstance(p, str):
            paths.append((safe_rel(project, p) or p, None))
    run = row.get("run")
    if run:
        _rel, rec, _err = project.runs().get(str(run), (None, None, None))
        for inp in (rec or {}).get("inputs") or []:
            if isinstance(inp, dict) and isinstance(inp.get("path"), str):
                paths.append((safe_rel(project, inp["path"]) or inp["path"], inp.get("sha256")))
            elif isinstance(inp, str):
                paths.append((safe_rel(project, inp) or inp, None))
    # One entry per path; a recorded hash (from the run) wins over a bare path. Code is not
    # data: a run's commit versions it (run records written before `--code` existed list
    # scripts among their inputs, so code is recognised by its extension too).
    merged = {}
    for p, sha in paths:
        if is_code_path(p):
            continue
        if p not in merged or (sha and not merged[p]):
            merged[p] = sha
    return sorted(merged.items())


def run_code_paths(rec):
    """Code files of a run record: its `code` list, plus code-extension paths among its
    inputs (records written before `--code` existed)."""
    out = []
    for item, declared in [(i, True) for i in rec.get("code") or []] + [(i, False) for i in rec.get("inputs") or []]:
        p = item.get("path") if isinstance(item, dict) else item
        if isinstance(p, str) and p and (declared or is_code_path(p)) and p not in out:
            out.append(p)
    return out


# A data manifest row's `split` is free text, or a structure the checker can test for
# leakage (independent units on both sides of a split; design 5 experiment_design row,
# Kapoor & Narayanan 2022 [src S15], scikit-learn grouped CV [src S16]):
#   {"train": <path>, "validation": <path>, "test": <path>, "group_key": "<column>"}
#       (at least two of train/validation/test, each a registered data file), or
#   {"column": "<split column>", "group_key": "<column>"}   (one file with a split column).
SPLIT_PARTS = ("train", "validation", "test")
SPLIT_KEYS = SPLIT_PARTS + ("group_key", "column")
# Free-text values that say the file is not split; they need no leakage warning.
NO_SPLIT = ("none", "n/a", "na", "no split", "not split", "unsplit", "-")
_MISSING = object()


def parse_split(value):
    """(structure or None, error or None) for a manifest `split` value."""
    if isinstance(value, dict):
        return value, None
    if isinstance(value, str) and value.strip().startswith("{"):
        try:
            obj = json.loads(value)
        except ValueError as exc:
            return None, "looks like JSON but does not parse: %s" % exc
        if not isinstance(obj, dict):
            return None, "must be a JSON object"
        return obj, None
    return None, None


def split_errors(project, split):
    """Structural problems of a declared split, as messages; empty when it can be checked."""
    errs = []
    unknown = sorted(set(split) - set(SPLIT_KEYS))
    if unknown:
        errs.append("unknown key(s) %s (allowed: %s)" % (", ".join(unknown), ", ".join(SPLIT_KEYS)))
    gk = split.get("group_key")
    if not isinstance(gk, str) or not gk.strip():
        errs.append("group_key must name the field that identifies an independent unit (e.g. scenario_id)")
    parts = [k for k in SPLIT_PARTS if k in split]
    if "column" in split:
        if parts:
            errs.append("give either column (one file with a split column) or train/validation/test files, not both")
        if not isinstance(split["column"], str) or not split["column"].strip():
            errs.append("column must name the split column")
    else:
        if len(parts) < 2:
            errs.append("name at least two of train, validation and test (or a split column)")
        for k in parts:
            rel = safe_rel(project, split[k]) if isinstance(split[k], str) else None
            if not rel or not os.path.isfile(project.path(rel)):
                errs.append("%s file %s is not a file inside the project" % (k, split[k]))
    return errs


def read_records(path):
    """Rows of a CSV/TSV, JSON Lines or JSON file (a list of objects, or an object whose
    only list of objects is the rows)."""
    if path.endswith((".csv", ".tsv")):
        with open(path, encoding="utf-8", newline="") as fh:
            return list(csv.DictReader(fh, delimiter="\t" if path.endswith(".tsv") else ","))
    if path.endswith(".jsonl"):
        return [obj for _l, obj, err in _read_jsonl(path) if not err]
    if path.endswith(".json"):
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if isinstance(data, list):
            return [r for r in data if isinstance(r, dict)]
        if isinstance(data, dict):
            lists = [v for v in data.values() if isinstance(v, list) and v and all(isinstance(r, dict) for r in v)]
            if len(lists) == 1:
                return lists[0]
            raise ValueError("%d lists of records in the JSON object; cannot tell which holds the rows" % len(lists))
    raise ValueError("cannot read rows from %s (use CSV, TSV, JSON Lines or JSON)" % os.path.basename(path))


def _field(rec, key):
    if key in rec:
        return rec[key]
    node = rec
    for part in key.split("."):
        if not isinstance(node, dict) or part not in node:
            return _MISSING
        node = node[part]
    return node


def _unit(value):
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value)


def check_split_leak(project, p, split):
    """DATA-SPLIT / DATA-LEAK findings for one manifest row with a structured split."""
    man = project.manifest()
    lineno = man.latest[p][0]
    gk = split["group_key"]
    groups, order = {}, []
    try:
        if "column" in split:
            col = split["column"]
            for i, rec in enumerate(read_records(project.path(p)), 1):
                name, g = _field(rec, col), _field(rec, gk)
                if name is _MISSING or g is _MISSING:
                    return [Finding(man.rel, lineno, "DATA-SPLIT", "%s: %s has no %s (row %d)"
                                    % (p, p, col if name is _MISSING else gk, i))]
                if _unit(name) not in groups:
                    order.append(_unit(name))
                groups.setdefault(_unit(name), set()).add(_unit(g))
        else:
            for part in SPLIT_PARTS:
                if part not in split:
                    continue
                f = safe_rel(project, split[part])
                if f not in man.latest:
                    return [Finding(man.rel, lineno, "DATA-SPLIT", "%s: the %s file %s is not registered in %s, so its "
                                    "content is not pinned" % (p, part, f, man.rel))]
                order.append(part)
                groups[part] = set()
                for i, rec in enumerate(read_records(project.path(f)), 1):
                    g = _field(rec, gk)
                    if g is _MISSING:
                        return [Finding(man.rel, lineno, "DATA-SPLIT", "%s: %s has no %s (row %d)" % (p, f, gk, i))]
                    groups[part].add(_unit(g))
    except (OSError, ValueError, csv.Error) as exc:
        return [Finding(man.rel, lineno, "DATA-SPLIT", "%s: cannot read the split: %s" % (p, exc))]
    out = []
    for i, a in enumerate(order):
        for b in order[i + 1:]:
            both = groups[a] & groups[b]
            if both:
                shown = sorted(both, key=lambda v: (len(v), v))
                out.append(Finding(man.rel, lineno, "DATA-LEAK", "%s: %d %s value(s) appear in both %s and %s (%s%s); "
                                   "the same unit on both sides of a split leaks into the evaluation"
                                   % (p, len(both), gk, a, b, ", ".join(shown[:5]), ", ..." if len(shown) > 5 else "")))
    return out


def check_data(project):
    """Data manifest, generated-data seeds, number inputs and run-record completeness (section 8)."""
    out = []
    man = project.manifest()
    out.extend(man.parse_errors)
    out.extend(append_only_findings(project, man.rel, "DATA-APPEND"))
    decisions = pi_decision_ids(project)

    history = {}
    for lineno, row in man.rows:
        p = safe_rel(project, row.get("path"))
        label = p or repr(row.get("path"))
        for key in MANIFEST_REQUIRED:
            if row.get(key) in (None, ""):
                out.append(Finding(man.rel, lineno, "DATA-SCHEMA", "%s: missing '%s'" % (label, key)))
        if not p:
            out.append(Finding(man.rel, lineno, "DATA-SCHEMA", "path %r must be a relative path inside the project" % row.get("path")))
            continue
        if row.get("origin") not in (None, "") and row.get("origin") not in DATA_ORIGINS:
            out.append(Finding(man.rel, lineno, "DATA-SCHEMA", "%s: origin %r is not one of %s" % (p, row.get("origin"), ", ".join(DATA_ORIGINS))))
        if row.get("sha256") and not re.match(r"^[0-9a-f]{64}$", str(row["sha256"])):
            out.append(Finding(man.rel, lineno, "DATA-SCHEMA", "%s: sha256 must be 64 hex digits" % p))
        if row.get("size") is not None and (isinstance(row["size"], bool) or not isinstance(row["size"], int) or row["size"] < 0):
            out.append(Finding(man.rel, lineno, "DATA-SCHEMA", "%s: size must be a byte count" % p))
        if row.get("labels") is not None and row["labels"] not in LABEL_ORIGINS:
            out.append(Finding(man.rel, lineno, "DATA-SCHEMA", "%s: labels %r is not one of %s" % (p, row["labels"], ", ".join(LABEL_ORIGINS))))
        prev = history.get(p)
        if prev is not None and prev.get("sha256") != row.get("sha256"):
            # A new version of a registered file: say which version it replaces and why.
            if row.get("supersedes_sha256") != prev.get("sha256") or not row.get("reason"):
                out.append(Finding(man.rel, lineno, "DATA-REPLACE", "%s: a new version must name supersedes_sha256 %s and a reason"
                                   % (p, _short(prev.get("sha256")))))
            if p.startswith(RAW_DATA_REL + "/"):
                did = str(row.get("pi_decision") or "")
                if not DID_RE.fullmatch(did) or did not in decisions:
                    out.append(Finding(man.rel, lineno, "DATA-REPLACE", "%s: raw data was replaced without a PI decision "
                                       "ID recorded in research/pi/decisions.md" % p))
        history[p] = row

    for p in sorted(man.latest):
        lineno, row = man.latest[p]
        path = project.path(p)
        if not os.path.isfile(path):
            out.append(Finding(man.rel, lineno, "DATA-MISSING", "%s is registered but missing: the data behind the results "
                               "is not archived" % p))
        else:
            if isinstance(row.get("size"), int) and os.path.getsize(path) != row["size"]:
                out.append(Finding(man.rel, lineno, "DATA-HASH", "%s: size is %d bytes, manifest says %d"
                                   % (p, os.path.getsize(path), row["size"])))
            if row.get("sha256") and sha256_file(path) != row["sha256"]:
                out.append(Finding(man.rel, lineno, "DATA-HASH", "%s changed after it was registered (sha256 %s, manifest %s); "
                                   "restore it, or register the new version with a reason"
                                   % (p, _short(sha256_file(path)), _short(row["sha256"]))))
            elif p.startswith(RAW_DATA_REL + "/") and os.stat(path).st_mode & (stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH):
                out.append(Finding(man.rel, lineno, "DATA-WRITABLE", "%s is writable; raw data should be read-only "
                                   "(chmod a-w; git does not keep this bit, so re-apply it after a clone)" % p, "warn"))
        if is_generated(row):
            gen = row.get("generator")
            gen_rel = safe_rel(project, gen) if gen else None
            if not gen:
                out.append(Finding(man.rel, lineno, "DATA-GEN", "%s is %s data but names no generator script" % (p, row.get("origin"))))
            elif not gen_rel or not os.path.isfile(project.path(gen_rel)):
                out.append(Finding(man.rel, lineno, "DATA-GEN", "%s: generator %s does not exist" % (p, gen)))
            if not seed_recorded(row.get("seed")):
                out.append(Finding(man.rel, lineno, "DATA-SEED", "%s was generated without a recorded seed (seed=%r); it "
                                   "cannot be regenerated" % (p, row.get("seed"))))
            if row.get("labels") is None:
                out.append(Finding(man.rel, lineno, "DATA-SCHEMA", "%s: generated data must declare labels (%s)"
                                   % (p, "|".join(LABEL_ORIGINS))))
            if gen_rel and gen_rel.endswith(".py") and os.path.isfile(project.path(gen_rel)):
                draws = _random_draws(project.path(gen_rel))
                seeded, unseeded = seeding_calls(project.path(gen_rel))
                for ln, name in unseeded:
                    out.append(Finding(man.rel, lineno, "DATA-SEED", "%s: its generator %s:%d creates %s() without a seed"
                                       % (p, gen_rel, ln, name)))
                if draws and not seeded:
                    out.append(Finding(man.rel, lineno, "DATA-SEED", "%s: its generator %s draws random values (%s() at line %d) "
                                       "but never sets a seed" % (p, gen_rel, draws[0][1], draws[0][0])))

        # Leakage between splits: checked when the split is declared as a structure.
        split, split_err = parse_split(row.get("split"))
        if split_err:
            out.append(Finding(man.rel, lineno, "DATA-SPLIT", "%s: split %s" % (p, split_err)))
        elif split is not None:
            errs = split_errors(project, split)
            for err in errs:
                out.append(Finding(man.rel, lineno, "DATA-SPLIT", "%s: split: %s" % (p, err)))
            if not errs and os.path.isfile(path):
                out.extend(check_split_leak(project, p, split))
        elif isinstance(row.get("split"), str) and row["split"].strip().lower() not in NO_SPLIT:
            out.append(Finding(man.rel, lineno, "DATA-LEAK", "%s: the split is free text, so leakage between splits "
                               "cannot be checked; declare it as {\"train\": <path>, \"test\": <path>, \"group_key\": "
                               "<unit field>} or {\"column\": <split column>, \"group_key\": <unit field>}" % p, "warn"))

    # Raw data must be registered.
    raw_dir = project.path(RAW_DATA_REL)
    if os.path.isdir(raw_dir):
        for dirpath, dirnames, filenames in os.walk(raw_dir):
            dirnames[:] = sorted(d for d in dirnames if not d.startswith("."))
            for name in sorted(filenames):
                if name.startswith("."):
                    continue
                rel = project.rel(os.path.join(dirpath, name)).replace(os.sep, "/")
                if rel not in man.latest:
                    out.append(Finding(rel, 1, "DATA-UNMANIFESTED", "raw data file is not in %s "
                                       "(`uws research check data add %s ...`)" % (man.rel, rel)))

    # Every number names its inputs, and every input is registered in the version it used.
    numbers = project.numbers()
    for nid in sorted(numbers.latest):
        lineno, row = numbers.latest[nid]
        if row.get("data_origin") == "literature":
            continue
        if not row.get("run") and row.get("inputs") is None:
            out.append(Finding(numbers.rel, lineno, "DATA-NOINPUT", "%s names no run and no inputs, so the data behind "
                               "it is unknown" % nid))
            continue
        for p, used_sha in number_inputs(project, row):
            entry = man.latest.get(p)
            if entry is None:
                out.append(Finding(numbers.rel, lineno, "DATA-UNMANIFESTED", "%s: input %s is not in %s; register it "
                                   "(path, sha256, source, version, split)" % (nid, p, man.rel)))
            elif used_sha and used_sha != entry[1].get("sha256"):
                out.append(Finding(numbers.rel, lineno, "DATA-RUNHASH", "%s: %s used %s version %s, but the manifest "
                                   "now registers %s" % (nid, row.get("run"), p, _short(used_sha), _short(entry[1].get("sha256")))))

    # Run records are complete.
    for run_id, (rel, rec, err) in sorted(project.runs().items()):
        if err:
            out.append(Finding(rel, 1, "RUN-SCHEMA", err))
            continue
        for key in RUN_REQUIRED:
            if key not in rec:
                out.append(Finding(rel, 1, "RUN-SCHEMA", "%s: missing '%s' (record runs with `uws research check run`)" % (run_id, key)))
        for key in ("inputs", "outputs", "code"):
            items = rec.get(key)
            if key in rec and (not isinstance(items, list) or
                               not all(isinstance(i, dict) and i.get("path") and "sha256" in i for i in items)):
                out.append(Finding(rel, 1, "RUN-SCHEMA", "%s: %s must be a list of {path, sha256}" % (run_id, key)))
        # The code a run executed must be in the commit it records, or no re-run can use it.
        commit = rec.get("git_commit")
        if commit and in_git(project) and _git_rc(project, ["cat-file", "-e", "%s^{commit}" % commit]) == 0:
            for p in run_code_paths(rec):
                p_rel = safe_rel(project, p)
                if p_rel and _git_rc(project, ["cat-file", "-e", "%s:./%s" % (commit, p_rel)]) != 0:
                    out.append(Finding(rel, 1, "RUN-CODE", "%s: code %s is not in commit %s (the run's git_commit), "
                                       "so a re-run cannot use it; commit it and record the run again"
                                       % (run_id, p_rel, str(commit)[:12])))
    return out


def data_add(project, args):
    rel = _project_rel_arg(project, args.path)
    if not rel or not os.path.isfile(project.path(rel)):
        print("refused: %s is not a file inside the project" % args.path, file=sys.stderr)
        return EXIT_FINDINGS
    if args.origin not in DATA_ORIGINS:
        print("refused: --origin must be one of %s" % ", ".join(DATA_ORIGINS), file=sys.stderr)
        return EXIT_FINDINGS
    for flag, value in (("--source", args.source), ("--version", args.version), ("--split", args.split)):
        if not value or not value.strip():
            print("refused: %s is required" % flag, file=sys.stderr)
            return EXIT_FINDINGS
    split, split_err = parse_split(args.split)
    if split_err:
        print("refused: --split %s" % split_err, file=sys.stderr)
        return EXIT_FINDINGS
    if split is not None:
        errs = split_errors(project, split)
        if errs:
            for err in errs:
                print("refused: --split: %s" % err, file=sys.stderr)
            return EXIT_FINDINGS
    generated = args.origin in NON_MEASURED or bool(args.generator)
    if generated:
        gen_rel = _project_rel_arg(project, args.generator) if args.generator else None
        if not gen_rel or not os.path.isfile(project.path(gen_rel)):
            print("refused: %s data needs --generator <script in the project>" % args.origin, file=sys.stderr)
            return EXIT_FINDINGS
        if args.seed is None:
            print("refused: generated data needs --seed <value> (use --seed unrecorded if the generator ran unseeded; "
                  "the data check will then report it)", file=sys.stderr)
            return EXIT_FINDINGS
        if args.labels not in LABEL_ORIGINS:
            print("refused: generated data needs --labels %s" % "|".join(LABEL_ORIGINS), file=sys.stderr)
            return EXIT_FINDINGS
    elif args.labels is not None and args.labels not in LABEL_ORIGINS:
        print("refused: --labels must be one of %s" % ", ".join(LABEL_ORIGINS), file=sys.stderr)
        return EXIT_FINDINGS
    path = project.path(rel)
    sha, size = sha256_file(path), os.path.getsize(path)
    man = project.manifest()
    prev = man.latest.get(rel)
    if prev and prev[1].get("sha256") == sha:
        print("%s is already registered at sha256 %s; nothing to do" % (rel, _short(sha)))
        return EXIT_OK
    row = {"path": rel, "sha256": sha, "size": size, "source": args.source, "version": args.version,
           "split": split if split is not None else args.split, "origin": args.origin, "registered_at": utc_now(),
           "registered_by": args.by or "engineer"}
    if args.license:
        row["license"] = args.license
    if args.labels is not None:
        row["labels"] = args.labels
    if generated:
        row["generator"] = gen_rel
        row["seed"] = args.seed
    if prev:
        if not args.reason:
            print("refused: %s is registered at sha256 %s; a new version needs --reason" % (rel, _short(prev[1].get("sha256"))),
                  file=sys.stderr)
            return EXIT_FINDINGS
        if rel.startswith(RAW_DATA_REL + "/"):
            did = args.pi_decision or ""
            if not DID_RE.fullmatch(did) or did not in pi_decision_ids(project):
                print("refused: replacing raw data needs --pi-decision D-<n> recorded in research/pi/decisions.md",
                      file=sys.stderr)
                return EXIT_FINDINGS
            row["pi_decision"] = did
        row["supersedes_sha256"] = prev[1].get("sha256")
        row["reason"] = args.reason
    _append_jsonl(man.path, row)
    if rel.startswith(RAW_DATA_REL + "/"):
        try:
            os.chmod(path, os.stat(path).st_mode & ~(stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH))
        except OSError as exc:
            print("warning: could not make %s read-only: %s" % (rel, exc), file=sys.stderr)
    print("registered %s (sha256 %s, %d bytes, %s)" % (rel, _short(sha), size, args.origin))
    if generated and not seed_recorded(args.seed):
        print("warning: seed %r is not a recorded seed; `uws research check data` reports it" % args.seed, file=sys.stderr)
    return EXIT_OK


def _project_rel_arg(project, value, must_exist=True):
    """A path argument as a project path, or None when it is outside the project.

    Relative paths are taken from the project root first (commands run there), then from
    the current directory. With must_exist, the first candidate that is a file wins."""
    if not value:
        return None
    if os.path.isabs(value):
        cands = [value]
    else:
        cands = [os.path.join(project.root, value), os.path.abspath(value)]
    for cand in cands:
        rel = safe_rel(project, os.path.relpath(cand, project.root))
        if rel and (not must_exist or os.path.isfile(project.path(rel))):
            return rel
    return None


# Files that are code, not data: a run's `--input` with one of these extensions is recorded
# under `code` (it is versioned by the run's git commit, not by the data manifest).
CODE_EXTS = (".py", ".pyw", ".ipynb", ".sh", ".bash", ".zsh", ".R", ".r", ".Rmd", ".jl", ".m", ".js", ".mjs",
             ".ts", ".java", ".scala", ".c", ".cc", ".cpp", ".h", ".hpp", ".go", ".rs", ".pl", ".rb", ".lua",
             ".do", ".sas")
# Environment locks recorded by hash when present (design 6.1: research/env/requirements.lock).
ENV_LOCK_CANDIDATES = ("research/env/requirements.lock", "requirements.lock", "poetry.lock", "Pipfile.lock",
                       "uv.lock", "pdm.lock", "conda-lock.yml", "environment.lock.yml", "renv.lock", "Manifest.toml")
GLOB_CHARS = ("*", "?", "[")
_PY_PROBE = ("import json, platform, sys; print(json.dumps({'version': platform.python_version(), "
             "'implementation': platform.python_implementation(), 'executable': sys.executable, "
             "'prefix': sys.prefix, 'base_prefix': getattr(sys, 'base_prefix', sys.prefix)}))")
# Interpreters asked for `--version`; any other program is recorded by path only, because
# running an unknown program with `--version` could do anything.
_VERSION_INTERPRETERS = ("Rscript", "R", "julia", "node", "perl", "ruby", "bash", "sh", "zsh")


def is_code_path(path):
    return str(path).endswith(CODE_EXTS)


def _which(name, env):
    if os.sep in name or (os.altsep and os.altsep in name):
        return None
    return shutil.which(name, path=env.get("PATH"))


def command_interpreter(project, cmd, env):
    """The interpreter a recorded command runs under (design 8: the environment of a run).

    The first word of the command is resolved the way the shell would (a path is taken from
    the project root, where the command runs; a name is looked up on PATH; `env A=B prog`
    is skipped over). A script with a `#!` line is followed to its interpreter. Python is
    asked for its version, executable and prefix (a venv shows up there); a few other known
    interpreters are asked for `--version`; anything else is recorded by path only."""
    words = list(cmd)
    if words and os.path.basename(words[0]) == "env":
        words = words[1:]
        while words and (words[0].startswith("-") or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0])):
            words = words[1:]
    if not words:
        return {"command": None, "error": "no command"}
    first = words[0]
    rec = {"command": first}
    path = os.path.join(project.root, first) if os.sep in first else _which(first, env)
    if not path or not os.path.isfile(path):
        rec["error"] = "not found"
        return rec
    path = os.path.realpath(path)
    rec["path"] = path
    name = os.path.basename(path)
    if not re.match(r"^(python|pypy)", name, re.I) and name not in _VERSION_INTERPRETERS:
        try:
            with open(path, "rb") as fh:
                head = fh.readline(256).decode("utf-8", "replace")
        except OSError:
            head = ""
        if head.startswith("#!"):
            parts = head[2:].split()
            if parts and os.path.basename(parts[0]) == "env" and len(parts) > 1:
                parts = [p for p in parts[1:] if not p.startswith("-")]
                interp = _which(parts[0], env) if parts else None
            else:
                interp = parts[0] if parts else None
            if interp and os.path.isfile(interp):
                rec["script"] = path
                path = os.path.realpath(interp)
                rec["path"] = path
                name = os.path.basename(path)
    if re.match(r"^(python|pypy)", name, re.I):
        rec["kind"] = "python"
        try:
            proc = subprocess.run([path, "-c", _PY_PROBE], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  env=env, timeout=30)
            info = json.loads(proc.stdout.decode("utf-8", "replace").strip().splitlines()[-1])
            rec.update(info)
        except (OSError, subprocess.TimeoutExpired, ValueError, IndexError) as exc:
            rec["error"] = "could not ask the interpreter for its version: %s" % exc
    elif name in _VERSION_INTERPRETERS:
        rec["kind"] = name
        try:
            proc = subprocess.run([path, "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                  env=env, timeout=30)
            lines = proc.stdout.decode("utf-8", "replace").strip().splitlines()
            rec["version"] = lines[0] if lines else ""
        except (OSError, subprocess.TimeoutExpired) as exc:
            rec["error"] = "could not ask for --version: %s" % exc
    else:
        rec["kind"] = "program"
    return rec


def env_locks(project, named):
    """[{path, sha256}] of the environment lock files: the ones named with --env-lock, else
    the usual lock files that exist in the project."""
    cands = named or [c for c in ENV_LOCK_CANDIDATES if os.path.isfile(project.path(c))]
    if not named:
        env_dir = project.path("research/env")
        if os.path.isdir(env_dir):
            for f in sorted(os.listdir(env_dir)):
                rel = "research/env/%s" % f
                if f.endswith(".lock") and rel not in cands:
                    cands.append(rel)
    out = []
    for c in cands:
        rel = _project_rel_arg(project, c)
        if not rel:
            raise EnvError("--env-lock %s is not a file inside the project" % c)
        out.append({"path": rel, "sha256": sha256_file(project.path(rel))})
    return sorted(out, key=lambda x: x["path"])


def _stat_key(path):
    st = os.stat(path)
    return (st.st_mtime_ns, st.st_size)


def _glob_rel(project, pattern):
    """Project paths of the files a glob pattern (relative to the project root) matches."""
    out = []
    for f in sorted(glob.glob(os.path.join(project.root, pattern), recursive=True)):
        rel = safe_rel(project, os.path.relpath(f, project.root))
        if rel and os.path.isfile(f):
            out.append(rel)
    return out


def _git_tracked_clean(project, rel):
    """None when `rel` is committed unchanged at HEAD, else why not."""
    if _git_rc(project, ["ls-files", "--error-unmatch", "--", rel]) != 0:
        return "is not committed (git does not track it)"
    if _git_rc(project, ["diff", "--quiet", "HEAD", "--", rel]) != 0:
        return "has uncommitted changes"
    return None


def cmd_run(project, args):
    """Run a command from the project root and write research/runs/<RUN-ID>/run.json (section 8)."""
    cmd = list(args.command or [])
    if cmd and cmd[0] == "--":
        cmd = cmd[1:]
    if not cmd:
        raise EnvError("usage: run [--exp EXP-ID|exploratory] [--input P]... [--code P]... [--output P|GLOB]... -- <command> [args]")
    runs_dir = project.path("research/runs")
    run_id = args.id
    if not run_id:
        existing = [int(m.group(1)) for n in (os.listdir(runs_dir) if os.path.isdir(runs_dir) else [])
                    for m in [re.match(r"^RUN-(\d+)$", n)] if m]
        run_id = "RUN-%04d" % (max(existing) + 1 if existing else 1)
    if not RUN_RE.match(run_id):
        print("refused: --id must look like RUN-0001", file=sys.stderr)
        return EXIT_FINDINGS
    run_dir = os.path.join(runs_dir, run_id)
    if os.path.exists(run_dir):
        print("refused: research/runs/%s exists (run records are never overwritten)" % run_id, file=sys.stderr)
        return EXIT_FINDINGS
    exp = args.exp
    if exp and exp != EXPLORATORY:
        if not EXP_RE.match(exp):
            print("refused: --exp must be EXP-<name> or %s" % EXPLORATORY, file=sys.stderr)
            return EXIT_FINDINGS
        if not project.plans().by_exp.get(exp):
            print("refused: %s has no frozen plan; freeze and commit it before running its experiment "
                  "(`uws research check plan freeze %s`)" % (exp, exp), file=sys.stderr)
            return EXIT_FINDINGS
        if in_git(project) and (_git(project, ["status", "--porcelain", "--", PLANS_REL]) or "").strip():
            print("warning: %s has uncommitted changes; commit the freeze before recording results, "
                  "or the plan check reports PLAN-ORDER" % PLANS_REL, file=sys.stderr)
    inputs, code = [], []
    for p, as_code in [(p, False) for p in args.input or []] + [(p, True) for p in args.code or []]:
        rel = _project_rel_arg(project, p)
        if not rel or not os.path.isfile(project.path(rel)):
            print("refused: %s %s is not a file inside the project" % ("code" if as_code else "input", p), file=sys.stderr)
            return EXIT_FINDINGS
        item = {"path": rel, "sha256": sha256_file(project.path(rel)), "size": os.path.getsize(project.path(rel))}
        if as_code or is_code_path(rel):
            if not as_code:
                print("note: %s is code (by its extension), recorded under `code`, not as data; use --code for code "
                      "and --input for data" % rel, file=sys.stderr)
            code.append(item)
        else:
            inputs.append(item)
    outputs, patterns = [], []
    for p in args.output or []:
        # Outputs may not exist yet; the command runs in the project root, so a relative
        # output path is relative to it. A glob (for names with a timestamp) is resolved
        # after the run to the files the command wrote.
        rel = _project_rel_arg(project, p, must_exist=False)
        if not rel:
            print("refused: output %s is not inside the project" % p, file=sys.stderr)
            return EXIT_FINDINGS
        (patterns if any(ch in rel for ch in GLOB_CHARS) else outputs).append(rel)
    env_vars = {}
    for item in args.env or []:
        if "=" not in item or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", item):
            print("refused: --env takes NAME=VALUE", file=sys.stderr)
            return EXIT_FINDINGS
        k, v = item.split("=", 1)
        env_vars[k] = v
    seeds = {}
    for item in args.seed or []:
        k, _, v = item.partition("=")
        if not v:
            k, v = "seed", item
        seeds[k] = v
    locks = env_locks(project, args.env_lock or [])

    commit = git_head(project) if in_git(project) else None
    dirty = None
    if commit:
        status = _git(project, ["status", "--porcelain", "--untracked-files=no"])
        dirty = bool(status and status.strip())
        if dirty:
            print("warning: the working tree has uncommitted changes; this run cannot be reproduced from commit %s "
                  "and `repro` will report it" % commit[:12], file=sys.stderr)
        for item in code:
            why = _git_tracked_clean(project, item["path"])
            if why:
                print("warning: code %s %s, so a re-run from commit %s cannot use it; commit it and run again"
                      % (item["path"], why.replace("is not committed (git does not track it)", "is not committed"),
                         commit[:12]), file=sys.stderr)
    else:
        print("warning: not a git repository; the run cannot be tied to a commit", file=sys.stderr)
    man = project.manifest()
    before = {}
    for rel in outputs:
        path = project.path(rel)
        if os.path.isfile(path):
            before[rel] = _stat_key(path)
    before_glob = {}
    for pat in patterns:
        before_glob[pat] = dict((rel, _stat_key(project.path(rel))) for rel in _glob_rel(project, pat))
    os.makedirs(run_dir)
    env = dict(os.environ)
    env.update(env_vars)
    interpreter = command_interpreter(project, cmd, env)
    started = utc_now()
    out_path, err_path = os.path.join(run_dir, "stdout.txt"), os.path.join(run_dir, "stderr.txt")
    rc = None
    note = None
    try:
        with open(out_path, "wb") as so, open(err_path, "wb") as se:
            proc = subprocess.run(cmd, cwd=project.root, env=env, stdout=so, stderr=se,
                                  timeout=args.timeout if args.timeout else None)
            rc = proc.returncode
    except FileNotFoundError:
        rc, note = 127, "command not found: %s" % cmd[0]
    except subprocess.TimeoutExpired:
        rc, note = 124, "timed out after %s s" % args.timeout
    ended = utc_now()
    out_records, missing, untouched, unmatched = [], [], [], []
    for rel in outputs:
        path = project.path(rel)
        if os.path.isfile(path):
            item = {"path": rel, "sha256": sha256_file(path), "size": os.path.getsize(path)}
            if before.get(rel) == _stat_key(path):
                # The file existed and was not rewritten: the command may not produce it.
                item["written_by_run"] = False
                untouched.append(rel)
            out_records.append(item)
        else:
            out_records.append({"path": rel, "sha256": None, "size": None})
            missing.append(rel)
    for pat in patterns:
        written = [rel for rel in _glob_rel(project, pat)
                   if before_glob[pat].get(rel) != _stat_key(project.path(rel))]
        if not written:
            unmatched.append(pat)
            missing.append("%s matched no file the command wrote" % pat)
        for rel in written:
            out_records.append({"path": rel, "pattern": pat, "sha256": sha256_file(project.path(rel)),
                                "size": os.path.getsize(project.path(rel))})
    rec = {
        "id": run_id, "exp": exp, "command": cmd, "cwd": ".",
        "git_commit": commit, "git_dirty": dirty,
        "started_at": started, "ended_at": ended, "exit_code": rc,
        "inputs": inputs, "code": code, "outputs": out_records, "seeds": seeds, "env_vars": env_vars,
        # `environment` is the machine; `interpreter` is what the command ran under (the
        # recorder's own Python can differ, e.g. when the command names a venv).
        "environment": {"python": platform.python_version(), "platform": platform.platform(),
                        "machine": platform.machine(), "cpu_count": os.cpu_count()},
        "interpreter": interpreter,
        "env_lock": locks,
        "manifest_sha256": sha256_file(man.path) if os.path.isfile(man.path) else None,
        "stdout": {"path": project.rel(out_path).replace(os.sep, "/"), "sha256": sha256_file(out_path)},
        "stderr": {"path": project.rel(err_path).replace(os.sep, "/"), "sha256": sha256_file(err_path)},
        "recorded_by": "research_check.py run",
    }
    if note:
        rec["note"] = note
    if unmatched:
        rec["unmatched_output_patterns"] = unmatched
    _atomic_write(os.path.join(run_dir, "run.json"), json.dumps(rec, indent=2, sort_keys=True) + "\n")
    print("research/runs/%s/run.json: exit %s, %d input(s), %d code file(s), %d output(s)%s"
          % (run_id, rc, len(inputs), len(code), len([o for o in out_records if o.get("path")]),
             " (%s)" % note if note else ""))
    if not locks:
        print("note: no environment lock found (research/env/requirements.lock or --env-lock); the run records "
              "no environment hash", file=sys.stderr)
    if untouched:
        print("warning: output(s) existed before the run and were not rewritten: %s; `repro` deletes outputs "
              "before re-running, so a command that does not write them fails there" % ", ".join(untouched),
              file=sys.stderr)
    if missing:
        print("error: declared output(s) not written: %s" % ", ".join(missing), file=sys.stderr)
        return rc if rc else EXIT_FINDINGS
    return rc if rc is not None else EXIT_ENV


# --------------------------------------------------------------------------- repro

REPRO_DIR_REL = "research/repro"


def repro_tolerance(row):
    tol = row.get("tolerance")
    if tol:
        return tol
    env = (os.environ.get("UWS_RESEARCH_TOLERANCE_DEFAULT") or "exact").strip()
    kind, _, value = env.partition(":")
    if kind in ("abs", "rel"):
        try:
            return {"kind": kind, "value": float(value)}
        except ValueError:
            raise EnvError("UWS_RESEARCH_TOLERANCE_DEFAULT must be exact, abs:<x> or rel:<x> (got %r)" % env)
    if kind != "exact":
        raise EnvError("UWS_RESEARCH_TOLERANCE_DEFAULT must be exact, abs:<x> or rel:<x> (got %r)" % env)
    return {"kind": "exact"}


def _extract_commit(project, commit, dest):
    """Write the tree of `commit` into dest (never touches the project's working tree).

    The whole repository is archived from its top level, so code outside a research project
    that lives in a subdirectory is there too; the project root inside dest is returned."""
    top = (_git(project, ["rev-parse", "--show-toplevel"]) or "").strip()
    if not top:
        raise ValueError("cannot find the top level of the git repository")
    tar_path = dest + ".tar"
    with open(tar_path, "wb") as fh:
        try:
            proc = subprocess.run(["git", "-C", top, "archive", "--format=tar", commit],
                                  stdout=fh, stderr=subprocess.PIPE, timeout=600)
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise ValueError("git archive failed: %s" % exc)
    if proc.returncode != 0:
        raise ValueError("git archive %s failed: %s" % (commit[:12], proc.stderr.decode("utf-8", "replace").strip()))
    os.makedirs(dest)
    with tarfile.open(tar_path) as tf:
        if hasattr(tarfile, "data_filter"):
            tf.extractall(dest, filter="data")
        else:
            tf.extractall(dest)
    os.unlink(tar_path)
    prefix = (_git(project, ["rev-parse", "--show-prefix"]) or "").strip()
    return os.path.join(dest, prefix) if prefix else dest


def _guarded_files(project, rows):
    paths = set()
    for _nid, row in rows:
        if row.get("output"):
            paths.add(row["output"])
    paths.update(project.manifest().latest)
    return {p: (sha256_file(project.path(p)) if os.path.isfile(project.path(p)) else None) for p in sorted(paths)}


def cmd_repro(project, args):
    if not in_git(project):
        raise EnvError("repro needs a git repository: it re-runs each run at its recorded commit")
    numbers = project.numbers()
    wanted = args.ids or []
    if not wanted:
        raise EnvError("usage: repro <N-ID ...|all>")
    if wanted == ["all"]:
        ids = [nid for nid in sorted(numbers.latest) if numbers.latest[nid][1].get("data_origin") != "literature"]
    else:
        unknown = [i for i in wanted if i not in numbers.latest]
        if unknown:
            raise EnvError("not in the number ledger: %s" % ", ".join(unknown))
        ids = sorted(set(wanted))
    if not ids:
        raise EnvError("no numbers to reproduce")
    timeout = args.timeout or int(os.environ.get("UWS_RESEARCH_REPRO_TIMEOUT", "3600") or 3600)
    rows = [(nid, numbers.latest[nid][1]) for nid in ids]
    before = _guarded_files(project, rows)
    results = {}
    by_run = {}
    for nid, row in rows:
        base = {"id": nid, "rev": _rev(row), "row_sha256": canonical_sha(row), "run": row.get("run"),
                "run_sha256": None, "expected": row.get("raw"), "observed": None,
                "tolerance": repro_tolerance(row), "byte_identical": None}
        results[nid] = base
        if not row.get("run"):
            base.update(status="fail", message="no run record: there is no recorded command to re-run")
            continue
        by_run.setdefault(str(row["run"]), []).append((nid, row))
    runs = project.runs()
    for run_id, members in sorted(by_run.items()):
        rel, rec, err = runs.get(run_id, (None, None, "research/runs/%s/run.json does not exist" % run_id))
        if rel:
            for nid, _row in members:
                results[nid]["run_sha256"] = sha256_file(project.path(rel))
        problem = err
        if not problem:
            if rec.get("exit_code") != 0:
                problem = "%s exited %r when it was recorded" % (run_id, rec.get("exit_code"))
            elif not rec.get("git_commit"):
                problem = "%s has no git_commit" % run_id
            elif rec.get("git_dirty") is not False:
                problem = ("%s was recorded on a working tree with uncommitted changes (git_dirty=%r), so the code "
                           "that produced it is not in any commit" % (run_id, rec.get("git_dirty")))
            elif not rec.get("command"):
                problem = "%s has no command" % run_id
            elif _git_rc(project, ["cat-file", "-e", "%s^{commit}" % rec["git_commit"]]) != 0:
                problem = "commit %s of %s is not in this repository" % (str(rec["git_commit"])[:12], run_id)
        if problem:
            for nid, _row in members:
                results[nid].update(status="fail", message=problem)
            continue
        outcome = _repro_run(project, run_id, rec, members, timeout, args.keep)
        for nid, info in outcome.items():
            results[nid].update(info)
    after = _guarded_files(project, rows)
    mutated = [p for p in before if before[p] != after.get(p)]
    if mutated:
        for nid in results:
            results[nid].update(status="fail", message="the re-run changed files in the original project (%s); "
                                "restore them from git" % ", ".join(mutated[:5]))
    report = {
        "created_at": utc_now(), "tool": "research_check.py repro", "git_head": git_head(project),
        "environment": {"python": platform.python_version(), "platform": platform.platform()},
        "selection": wanted, "results": [results[nid] for nid in ids],
        "summary": {"pass": sum(1 for r in results.values() if r.get("status") == "pass"),
                    "fail": sum(1 for r in results.values() if r.get("status") != "pass")},
    }
    rdir = project.path(REPRO_DIR_REL)
    os.makedirs(rdir, exist_ok=True)
    stamp = report["created_at"].replace("-", "").replace(":", "")
    name, n = "report-%s.json" % stamp, 1
    while os.path.exists(os.path.join(rdir, name)):
        n += 1
        name = "report-%s-%d.json" % (stamp, n)
    _atomic_write(os.path.join(rdir, name), json.dumps(report, indent=2, sort_keys=True) + "\n")
    findings = []
    for nid in ids:
        r = results[nid]
        line = numbers.latest[nid][0]
        if r.get("status") == "pass":
            print("%s pass %s: expected %r, observed %r (%s)%s"
                  % (nid, r["run"], r["expected"], r["observed"], _tol_text(r["tolerance"]),
                     "" if r.get("byte_identical") else "; output file differs byte-wise"))
        else:
            findings.append(Finding(numbers.rel, line, "REPRO", "%s: %s" % (nid, r.get("message"))))
    emit(findings, False)
    print("repro: %d pass, %d fail; report %s/%s" % (report["summary"]["pass"], report["summary"]["fail"], REPRO_DIR_REL, name),
          file=sys.stderr)
    return EXIT_FINDINGS if findings else EXIT_OK


def _tol_text(tol):
    return "exact" if tol.get("kind") == "exact" else "%s %s" % (tol.get("kind"), tol.get("value"))


def _repro_run(project, run_id, rec, members, timeout, keep):
    info = {}
    scratch = tempfile.mkdtemp(prefix="uws-repro-")
    try:
        try:
            root = _extract_commit(project, rec["git_commit"], os.path.join(scratch, "src"))
        except ValueError as exc:
            return {nid: {"status": "fail", "message": str(exc)} for nid, _r in members}
        # Code comes from the recorded commit only: a script that is not in it was never
        # committed, and a re-run with the current copy would not be the recorded run.
        for p in run_code_paths(rec):
            p_rel = safe_rel(project, p)
            if not p_rel or not os.path.isfile(os.path.join(root, p_rel)):
                return {nid: {"status": "fail", "message": "code %s is not in commit %s, so it cannot be re-run"
                              % (p, str(rec["git_commit"])[:12])} for nid, _r in members}
        # Inputs: the version the run recorded, from the commit or the project's archive.
        for inp in rec.get("inputs") or []:
            p = safe_rel(project, inp.get("path")) if isinstance(inp, dict) else None
            want = inp.get("sha256") if isinstance(inp, dict) else None
            if not p:
                return {nid: {"status": "fail", "message": "%s has an invalid input entry %r" % (run_id, inp)} for nid, _r in members}
            if is_code_path(p):
                continue
            dest = os.path.join(root, p)
            if os.path.isfile(dest) and (want is None or sha256_file(dest) == want):
                continue
            src = project.path(p)
            if not os.path.isfile(src) or (want and sha256_file(src) != want):
                found = _short(sha256_file(src)) if os.path.isfile(src) else "missing"
                return {nid: {"status": "fail", "message": "input %s is not available in the version %s used (recorded %s, "
                              "found %s)" % (p, run_id, _short(want), found)} for nid, _r in members}
            os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
            shutil.copyfile(src, dest)
        # Outputs are deleted first, so a command that does not write them cannot pass on a
        # committed copy.
        pattern_of = {}
        for out in rec.get("outputs") or []:
            p = safe_rel(project, out.get("path")) if isinstance(out, dict) else None
            if p and os.path.isfile(os.path.join(root, p)):
                os.unlink(os.path.join(root, p))
            if p and out.get("pattern"):
                pattern_of[p] = str(out["pattern"])
        # Outputs recorded through a glob (timestamped names): the re-run writes new names,
        # found as the files matching the pattern that the re-run created or rewrote.
        before = dict((pat, dict((r, _stat_key(os.path.join(root, r))) for r in _glob_under(root, pat)))
                      for pat in set(pattern_of.values()))
        cmd = rec["command"] if isinstance(rec["command"], list) else shlex.split(str(rec["command"]))
        env = dict(os.environ)
        env.update({k: str(v) for k, v in (rec.get("env_vars") or {}).items()})
        env["UWS_REPRO"] = "1"
        cwd = os.path.join(root, safe_rel(project, rec.get("cwd") or ".") or "") if rec.get("cwd") not in (None, ".") else root
        try:
            proc = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        except FileNotFoundError:
            return {nid: {"status": "fail", "message": "command not found: %s" % cmd[0]} for nid, _r in members}
        except subprocess.TimeoutExpired:
            return {nid: {"status": "fail", "message": "re-run timed out after %d s" % timeout} for nid, _r in members}
        tail = proc.stdout.decode("utf-8", "replace").strip().splitlines()[-3:]
        if proc.returncode != 0:
            return {nid: {"status": "fail", "message": "re-run of %s exited %d: %s" % (run_id, proc.returncode, " | ".join(tail))}
                    for nid, _r in members}
        written = dict((pat, [r for r in _glob_under(root, pat) if before[pat].get(r) != _stat_key(os.path.join(root, r))])
                       for pat in before)
        for nid, row in members:
            out_rel = safe_rel(project, row.get("output") or "")
            path = os.path.join(root, out_rel) if out_rel else None
            pat = pattern_of.get(out_rel)
            if pat:
                recorded = sorted(r for r, q in pattern_of.items() if q == pat)
                if len(written[pat]) != len(recorded):
                    info[nid] = {"status": "fail", "message": "the re-run wrote %d file(s) matching %s; the recorded run "
                                 "wrote %d" % (len(written[pat]), pat, len(recorded))}
                    continue
                # Files of one pattern pair up in name order (timestamps sort by time).
                path = os.path.join(root, written[pat][recorded.index(out_rel)])
            if not path or not os.path.isfile(path):
                info[nid] = {"status": "fail", "message": "the re-run did not write %s" % row.get("output")}
                continue
            try:
                value = resolve_pointer(path, str(row.get("pointer") or ""))
            except (ValueError, IndexError, KeyError, OSError) as exc:
                info[nid] = {"status": "fail", "message": "pointer %s in the re-run output: %s" % (row.get("pointer"), exc)}
                continue
            tol = repro_tolerance(row)
            ok = within_tolerance(row.get("raw"), value, tol)
            info[nid] = {"status": "pass" if ok else "fail", "observed": value,
                         "byte_identical": sha256_file(path) == row.get("output_sha256")}
            if not ok:
                info[nid]["message"] = "re-run gives %r, ledger raw is %r (tolerance %s)" % (value, row.get("raw"), _tol_text(tol))
        return info
    finally:
        if keep:
            print("scratch copy kept at %s" % scratch, file=sys.stderr)
        else:
            _rmtree(scratch)


def _glob_under(base, pattern):
    """Paths relative to `base` of the files `pattern` matches under it."""
    out = []
    for f in sorted(glob.glob(os.path.join(base, pattern), recursive=True)):
        if os.path.isfile(f):
            out.append(os.path.relpath(f, base).replace(os.sep, "/"))
    return out


def _rmtree(path):
    """Remove a scratch tree, including read-only files a re-run may have created."""
    def retry(func, p, _exc):
        try:
            os.chmod(p, stat.S_IWUSR | stat.S_IRUSR | stat.S_IXUSR)
            func(p)
        except OSError:
            pass
    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=retry)   # `onerror` is deprecated from 3.12
    else:
        shutil.rmtree(path, onerror=retry)


def load_repro_reports(project):
    out, findings = [], []
    d = project.path(REPRO_DIR_REL)
    if not os.path.isdir(d):
        return out, findings
    for name in sorted(os.listdir(d)):
        if not (name.startswith("report-") and name.endswith(".json")):
            continue
        rel = "%s/%s" % (REPRO_DIR_REL, name)
        try:
            with open(os.path.join(d, name), encoding="utf-8") as fh:
                rep = json.load(fh)
        except (OSError, ValueError) as exc:
            findings.append(Finding(rel, 1, "REPRO", "not valid JSON: %s" % exc))
            continue
        if not isinstance(rep, dict) or parse_utc(rep.get("created_at")) is None or not isinstance(rep.get("results"), list):
            findings.append(Finding(rel, 1, "REPRO", "not a repro report (created_at and results are required)"))
            continue
        # Reports written in the same second get -2, -3 ... suffixes; order by that
        # sequence, never by file modification time.
        m = re.match(r"^report-.+?(?:-(\d+))?\.json$", name)
        seq = int(m.group(1)) if m and m.group(1) else 1
        out.append((rep["created_at"], seq, rel, rep))
    out.sort(key=lambda t: (t[0], t[1], t[2]))
    return [(created, rel, rep) for created, _seq, rel, rep in out], findings


def check_repro_current(project):
    """Every non-literature number has a passing repro entry for its current row and run record."""
    reports, out = load_repro_reports(project)
    numbers = project.numbers()
    runs = project.runs()
    max_age = os.environ.get("UWS_RESEARCH_REPRO_MAX_AGE_DAYS", "0").strip()
    max_age = int(max_age) if max_age.isdigit() else 0
    now = datetime.datetime.now(datetime.timezone.utc)
    for nid in sorted(numbers.latest):
        lineno, row = numbers.latest[nid]
        if row.get("data_origin") == "literature":
            continue
        entry = None
        for created, rel, rep in reports:
            for r in rep["results"]:
                if isinstance(r, dict) and r.get("id") == nid:
                    entry = (created, rel, r)
        if entry is None:
            out.append(Finding(numbers.rel, lineno, "REPRO", "%s has never been reproduced (`uws research check repro all`)" % nid))
            continue
        created, rel, r = entry
        if r.get("status") != "pass":
            out.append(Finding(rel, 1, "REPRO", "%s failed its latest repro: %s" % (nid, r.get("message"))))
            continue
        if r.get("row_sha256") != canonical_sha(row):
            out.append(Finding(numbers.rel, lineno, "REPRO", "%s changed after its latest repro (%s); re-run the repro job" % (nid, rel)))
            continue
        run_rel = runs.get(str(row.get("run")), (None,))[0] if row.get("run") else None
        if run_rel and r.get("run_sha256") != sha256_file(project.path(run_rel)):
            out.append(Finding(run_rel, 1, "REPRO", "%s: %s changed after the latest repro (%s)" % (nid, row.get("run"), rel)))
            continue
        if max_age:
            age = (now - parse_utc(created)).days
            if age > max_age:
                out.append(Finding(rel, 1, "REPRO", "%s was last reproduced %d days ago (limit %d, "
                                   "UWS_RESEARCH_REPRO_MAX_AGE_DAYS)" % (nid, age, max_age)))
    return out


# --------------------------------------------------------------------------- manuscript hash (red team)

def manuscript_files(project):
    files = set(project.prose_files())
    for rel in (project.config.get("numbers_tex") or "paper/generated/numbers.tex",):
        if os.path.isfile(project.path(rel)):
            files.add(project.path(rel))
    refs = project.references_path()
    if refs and os.path.isfile(refs):
        files.add(refs)
    return sorted(set(os.path.normpath(project.rel(f)).replace(os.sep, "/") for f in files))


def manuscript_hash(project):
    lines = ["%s  %s\n" % (sha256_file(project.path(rel)), rel) for rel in manuscript_files(project)]
    return hashlib.sha256("".join(lines).encode("utf-8")).hexdigest(), lines


REVIEW_HASH_RE = re.compile(r"(?im)^\s*(?:[-*]\s*)?(?:\*\*)?manuscript(?:[ _-]?sha256)?(?:\*\*)?\s*:\s*(?:\*\*)?\s*`?(?:sha256:)?([0-9a-f]{64})")


def check_review_hash(project):
    """The red team reviewed the manuscript as it is now (edits after review re-open review)."""
    current, _lines = manuscript_hash(project)
    d = project.path("research/reviews")
    reviewed = []
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            if name.startswith("REV-") and name.endswith(".md"):
                m = REVIEW_HASH_RE.search(read_text(os.path.join(d, name)))
                reviewed.append((name, m.group(1) if m else None))
    if not reviewed:
        return [Finding("research/reviews", 1, "GATE-REVIEW-HASH", "no red-team review (research/reviews/REV-*.md) exists")]
    if any(h == current for _n, h in reviewed):
        return []
    seen = ", ".join("%s: %s" % (n, _short(h) if h else "no Manuscript line") for n, h in reviewed)
    return [Finding("research/reviews", 1, "GATE-REVIEW-HASH",
                    "no red-team review covers the current manuscript (sha256:%s); reviews name %s. The manuscript "
                    "changed after review: dispatch the red team again" % (_short(current), seen))]


def cmd_manuscript_hash(project, args):
    digest, lines = manuscript_hash(project)
    if not lines:
        raise EnvError("no manuscript files found (.tex, paper/**/*.md, numbers macros, references.bib)")
    if args.files:
        for line in lines:
            print(line.rstrip("\n"))
    print("sha256:%s" % digest)
    return EXIT_OK


# --------------------------------------------------------------------------- retractions

RETRACTIONS_REL = "research/sources/retractions.jsonl"
CROSSREF_API = "https://api.crossref.org"
DOI_RE = re.compile(r"^10\.\d{4,9}/\S+$")


def bib_doi(project, stem):
    """The DOI of bib_sources/<stem>.bib: its doi field, else the DOI it was fetched by."""
    path = project.path("bib_sources/%s.bib" % stem)
    try:
        entry = validate_fetched_bib(read_text(path))
        doi = entry.fields.get("doi")
    except (BibError, OSError):
        doi = None
    if not doi:
        meta_path = path[:-4] + ".meta.json"
        try:
            with open(meta_path, encoding="utf-8") as fh:
                meta = json.load(fh)
            if meta.get("id_type") == "doi":
                doi = meta.get("identifier")
        except (OSError, ValueError):
            doi = None
    if not doi:
        return None
    doi = re.sub(r"^(?:https?://(?:dx\.)?doi\.org/|doi:)", "", doi.strip(), flags=re.I)
    return doi if DOI_RE.match(doi) else None


def load_retractions(project):
    path = project.path(RETRACTIONS_REL)
    latest, findings = {}, []
    if not os.path.isfile(path):
        return latest, findings
    for lineno, obj, err in _read_jsonl(path):
        if err:
            findings.append(Finding(RETRACTIONS_REL, lineno, "RETRACTION", err))
            continue
        key = obj.get("citekey")
        if not key:
            continue
        # An unreachable attempt does not hide an earlier answer; its age is still reported.
        prev = latest.get(key)
        if obj.get("status") == "unreachable" and prev is not None and prev[1].get("status") != "unreachable":
            continue
        latest[key] = (lineno, obj)
    return latest, findings


def _curl_json(url, timeout):
    """GET url with curl. Returns (http_status or None, parsed JSON or None, error or None)."""
    curl = os.environ.get("UWS_RESEARCH_CURL") or os.environ.get("UWS_BIB_CURL") or "curl"
    agent = "uws-research-check/1.0 (+https://github.com/Yash-Sukhdeve/universal-workflow-system)"
    mailto = os.environ.get("UWS_RESEARCH_MAILTO", "").strip()
    if mailto:
        agent += " (mailto:%s)" % mailto
    fd, tmp = tempfile.mkstemp(prefix="uws-crossref-")
    os.close(fd)
    try:
        try:
            proc = subprocess.run([curl, "-sS", "-L", "--max-time", str(timeout), "-A", agent,
                                   "-H", "Accept: application/json", "-o", tmp, "-w", "%{http_code}", url],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout + 15)
        except (OSError, subprocess.TimeoutExpired) as exc:
            return None, None, "curl could not run: %s" % exc
        if proc.returncode != 0:
            return None, None, "curl exit %d: %s" % (proc.returncode, proc.stderr.decode("utf-8", "replace").strip()[:200])
        code = proc.stdout.decode("ascii", "replace").strip()
        status = int(code) if code.isdigit() else None
        body = open(tmp, "rb").read()
        if status != 200:
            return status, None, None
        try:
            return status, json.loads(body.decode("utf-8")), None
        except (UnicodeDecodeError, ValueError):
            return status, None, "HTTP 200 but the body is not JSON"
    finally:
        os.unlink(tmp)


def _norm_type(t):
    return str(t or "").strip().lower().replace("-", "_").replace(" ", "_")


def retraction_status(project, doi, timeout):
    """Look a DOI up in Crossref. Never claims 'no notice' unless both lookups succeeded.

    Crossref documents that retractions (including those from the Retraction Watch database)
    appear in the `update-to` field of the notice, with `source` publisher or retraction-watch
    (https://www.crossref.org/documentation/retrieve-metadata/retraction-watch/); the
    retracted work lists them under `updated-by` (observed 2026-09-30 for
    10.1016/S0140-6736(97)11096-0). Both are read here."""
    base = os.environ.get("UWS_RESEARCH_CROSSREF_API", CROSSREF_API).rstrip("/")
    enc = url_quote(doi, safe="/:;()._-")
    work_url = "%s/works/%s" % (base, enc)
    rec = {"doi": doi, "checked_at": utc_now(), "endpoint": work_url, "updates": []}
    status, work, err = _curl_json(work_url, timeout)
    rec["http_status"] = status
    if err or status is None:
        rec.update(status="unreachable", error=err or "no HTTP status")
        return rec
    if status == 404:
        rec["status"] = "not-in-crossref"
        return rec
    if status != 200 or not isinstance(work, dict) or not isinstance(work.get("message"), dict):
        rec.update(status="unreachable", error="HTTP %s from Crossref" % status)
        return rec
    updates = []
    for u in work["message"].get("updated-by") or []:
        if isinstance(u, dict):
            updates.append({"notice_doi": u.get("DOI"), "type": _norm_type(u.get("type")), "source": u.get("source"),
                            "date": (u.get("updated") or {}).get("date-time")})
    notices_url = "%s/works?filter=updates:%s&rows=100" % (base, enc)
    status2, notices, err2 = _curl_json(notices_url, timeout)
    if err2 or status2 != 200 or not isinstance(notices, dict):
        rec.update(status="unreachable", error=err2 or "HTTP %s from Crossref (notice search)" % status2)
        return rec
    for item in (notices.get("message") or {}).get("items") or []:
        for u in item.get("update-to") or []:
            if isinstance(u, dict) and str(u.get("DOI", "")).lower() == doi.lower():
                updates.append({"notice_doi": item.get("DOI"), "type": _norm_type(u.get("type")), "source": u.get("source"),
                                "date": (u.get("updated") or {}).get("date-time")})
    seen, uniq = set(), []
    for u in updates:
        key = (str(u.get("notice_doi")).lower(), u.get("type"))
        if key not in seen:
            seen.add(key)
            uniq.append(u)
    rec["updates"] = uniq
    types = {u["type"] for u in uniq}
    if types & set(RETRACTED_TYPES):
        rec["status"] = "retracted"
    elif types & set(CONCERN_TYPES):
        rec["status"] = "concern"
    elif types:
        rec["status"] = "corrected"
    else:
        rec["status"] = "no-notice"
    return rec


def cmd_retraction_online(project, args):
    """Look up every bib_sources DOI in Crossref and append the answers to the cache.

    Exit 0 when every lookup got an answer, 2 when any was unreachable (network down,
    rate limit): an unreachable row never replaces an earlier answer in the cache view."""
    stems = [os.path.basename(p)[:-4] for p in bib_source_files(project)]
    if args.key:
        missing = [k for k in args.key if k not in stems]
        if missing:
            raise EnvError("no bib_sources entry for %s" % ", ".join(missing))
        stems = [s for s in stems if s in args.key]
    if not stems:
        raise EnvError("bib_sources/ has no entries to check")
    timeout = args.timeout or 20
    counts = {}
    for stem in stems:
        doi = bib_doi(project, stem)
        if doi is None:
            rec = {"doi": None, "checked_at": utc_now(), "status": "no-doi", "updates": []}
        else:
            rec = retraction_status(project, doi, timeout)
        rec["citekey"] = stem
        rec["tool"] = "research_check.py retraction --online"
        _append_jsonl(project.path(RETRACTIONS_REL), rec)
        counts[rec["status"]] = counts.get(rec["status"], 0) + 1
        detail = ", ".join("%s %s" % (u["type"], u.get("notice_doi")) for u in rec.get("updates") or [])
        print("%s: %s%s%s" % (stem, rec["status"], " (%s)" % doi if doi else "", "; " + detail if detail else ""))
    print("retraction lookup: %s; cached in %s" % (", ".join("%d %s" % (v, k) for k, v in sorted(counts.items())), RETRACTIONS_REL),
          file=sys.stderr)
    return EXIT_ENV if counts.get("unreachable") else EXIT_OK


RETRACT_WORD_RE = re.compile(r"\bretract\w*", re.I)


def check_retractions(project):
    """Offline: read the cache. Unchecked sources are warnings, never a pass by silence."""
    latest, out = load_retractions(project)
    stems = [os.path.basename(p)[:-4] for p in bib_source_files(project)]
    max_age = os.environ.get("UWS_RESEARCH_RETRACTION_MAX_AGE_DAYS", "180").strip()
    max_age = int(max_age) if max_age.isdigit() else 180
    now = datetime.datetime.now(datetime.timezone.utc)
    bad = {}
    for stem in stems:
        item = latest.get(stem)
        where = "bib_sources/%s.bib" % stem
        if item is None:
            out.append(Finding(where, 1, "RETRACTION", "%s: retraction status never checked "
                               "(`uws research check retraction --online`)" % stem, "warn"))
            continue
        lineno, rec = item
        st = rec.get("status")
        if st in ("unreachable", "no-doi", "not-in-crossref"):
            why = {"unreachable": "Crossref was unreachable (%s)" % rec.get("error"),
                   "no-doi": "it has no DOI to look up",
                   "not-in-crossref": "its DOI %s is not registered with Crossref" % rec.get("doi")}[st]
            out.append(Finding(RETRACTIONS_REL, lineno, "RETRACTION", "%s: retraction status unknown: %s" % (stem, why), "warn"))
            continue
        checked = parse_utc(rec.get("checked_at"))
        if checked and max_age and (now - checked).days > max_age:
            out.append(Finding(RETRACTIONS_REL, lineno, "RETRACTION", "%s: retraction status last checked %d days ago"
                               % (stem, (now - checked).days), "warn"))
        if st in ("retracted", "concern", "corrected"):
            bad[stem] = (lineno, rec)
    if not bad:
        return out
    claims = project.claims()
    for cid in sorted(claims.latest):
        lineno, row = claims.latest[cid]
        for src in row.get("sources") or []:
            key = src.get("citekey") if isinstance(src, dict) else None
            if key not in bad:
                continue
            rec = bad[key][1]
            notice = ", ".join("%s %s" % (u.get("type"), u.get("notice_doi")) for u in rec.get("updates") or [])
            if rec["status"] == "retracted" and row.get("status") == "verified":
                out.append(Finding(claims.rel, lineno, "RETRACTION", "%s rests on %s, which Crossref lists as retracted (%s); "
                                   "append a revision with status 'retracted' or find another source" % (cid, key, notice)))
            elif row.get("status") == "verified":
                out.append(Finding(claims.rel, lineno, "RETRACTION", "%s rests on %s, which has a %s notice (%s); check the "
                                   "claim against it" % (cid, key, rec["status"], notice), "warn"))
    retracted = {k for k, (_l, r) in bad.items() if r["status"] == "retracted"}
    if retracted:
        cite_re = re.compile(r"\\(?:no)?cite[a-zA-Z]*\*?(?:\[[^\]]*\]){0,2}\{([^}]*)\}")
        for path in project.tex_files():
            doc = project.doc(path)
            for _start, sent, _cids, line_of in doc.sentences():
                for m in cite_re.finditer(sent):
                    keys = {k.strip() for k in m.group(1).split(",")}
                    for key in sorted(keys & retracted):
                        if not RETRACT_WORD_RE.search(sent):
                            out.append(Finding(doc.rel, line_of(m.start()), "RETRACTION",
                                               "\\cite{%s}: Crossref lists this source as retracted, and the sentence "
                                               "does not say so" % key))
    return out


# --------------------------------------------------------------------------- ledger rows (add)

def _fill_number(project, row):
    """Fields the tool fills from the files instead of letting anyone type them: the output
    hash, the raw value at the pointer, and the printed form under the rounding rule. A value
    that was given is never replaced; the checks below then compare it with the file."""
    filled = []
    out_rel = safe_rel(project, row.get("output"))
    path = project.path(out_rel) if out_rel else None
    if path and os.path.isfile(path):
        if not row.get("output_sha256"):
            row["output_sha256"] = sha256_file(path)
            filled.append("output_sha256")
        if row.get("raw") is None and isinstance(row.get("pointer"), str) and row["pointer"]:
            try:
                value = resolve_pointer(path, row["pointer"])
            except (ValueError, IndexError, KeyError, OSError):
                value = None   # the pointer check reports it
            if value is not None and not isinstance(value, (dict, list)):
                row["raw"] = value
                filled.append("raw")
    if row.get("printed") in (None, "") and row.get("raw") is not None and row.get("rounding"):
        try:
            row["printed"] = apply_rounding(row["raw"], row["rounding"], row.get("scale"))
            filled.append("printed")
        except (ValueError, InvalidOperation):
            pass   # the rounding check reports it
    return filled


def cmd_ledger_add(project, kind, text):
    """`numbers add` / `claims add`: append one row after validating it; existing rows are
    never touched. Missing id, rev and supersedes are filled (a new ID, or the next revision
    of an existing one); number rows also get the output hash, raw value and printed form."""
    led = project.numbers() if kind == "numbers" else project.claims()
    if text == "-":
        text = sys.stdin.read()
    if not text or not text.strip():
        raise EnvError("usage: %s add '<one JSON object>' (or - to read it from stdin)" % kind)
    try:
        row = json.loads(text)
    except ValueError as exc:
        print("refused: not valid JSON: %s" % exc, file=sys.stderr)
        return EXIT_FINDINGS
    if not isinstance(row, dict):
        print("refused: the row must be one JSON object", file=sys.stderr)
        return EXIT_FINDINGS
    filled = []
    if row.get("id") is None:
        nums = [int(m.group(1)) for k in led.latest for m in [re.match(r"^%s-(\d+)$" % led.prefix, k)] if m]
        row["id"] = "%s-%04d" % (led.prefix, max(nums) + 1 if nums else 1)
        filled.append("id")
    rid = row["id"]
    prev = led.latest.get(rid) if isinstance(rid, str) else None
    if "rev" not in row:
        row["rev"] = _rev(prev[1]) + 1 if prev else 1
        filled.append("rev")
    if "supersedes" not in row and isinstance(row.get("rev"), int):
        row["supersedes"] = "%s@%d" % (rid, row["rev"] - 1) if row["rev"] > 1 else None
    if kind == "numbers":
        filled.extend(_fill_number(project, row))
    view, lineno = led.appended(row)
    findings = [f for f in _check_revisions(view) if f.line == lineno]
    project._links = None
    if kind == "numbers":
        project._numbers = view
        run_rel = "research/runs/%s/run.json" % row.get("run") if row.get("run") else None
        findings.extend(f for f in check_numbers(project, [rid]) if f.rule != "NUM-MACRO" and
                        ((f.path == led.rel and f.line == lineno) or (run_rel and f.path == run_rel)))
        if row.get("data_origin") != "literature":
            exp = row.get("exp")
            if exp is None:
                findings.append(Finding(led.rel, lineno, "PLAN-LINK", "%s: set exp to the EXP-ID whose frozen plan it "
                                        "answers, or to %r" % (rid, EXPLORATORY)))
            elif exp != EXPLORATORY and exp not in experiment_ids(project):
                findings.append(Finding(led.rel, lineno, "PLAN-LINK", "%s: exp %s has no %s/%s/plan.md"
                                        % (rid, exp, EXPERIMENTS_REL, exp)))
            if not row.get("run") and row.get("inputs") is None:
                findings.append(Finding(led.rel, lineno, "DATA-NOINPUT", "%s names no run and no inputs" % rid))
    else:
        project._claims = view
        findings.extend(_check_claim(project, view, project.numbers(), lineno, row))
    emit(findings, False)
    if any(f.level == "block" for f in findings):
        print("refused: the row was not appended to %s" % led.rel, file=sys.stderr)
        return EXIT_FINDINGS
    _append_jsonl(led.path, row)
    print("appended %s rev %d to %s%s" % (rid, row["rev"], led.rel,
                                          " (filled in by the tool: %s)" % ", ".join(filled) if filled else ""))
    if kind == "numbers" and row.get("macro"):
        print("next: `uws research check macros` defines %s in the generated macro file" % row["macro"])
    return EXIT_OK


# --------------------------------------------------------------------------- macros

def cmd_macros(project, args):
    """Write the macro file from the valid rows; report and skip the invalid ones (a row with
    a schema error, or a macro name that another row also uses). Exit 1 when any is skipped,
    so the gap is visible, but the valid macros are written either way."""
    rel = args.out or project.config.get("numbers_tex") or "paper/generated/numbers.tex"
    numbers = project.numbers()
    emit(numbers.parse_errors, False)
    skipped = {}
    for f in _check_number_shapes(numbers):
        if f.level != "block":
            continue
        nid = f.msg.split(":", 1)[0]
        skipped.setdefault(nid, []).append(f.msg.split(": ", 1)[1] if ": " in f.msg else f.msg)
    owners = {}
    for nid in sorted(numbers.latest):
        macro = numbers.latest[nid][1].get("macro")
        if isinstance(macro, str) and macro:
            owners.setdefault(macro, []).append(nid)
    for macro, nids in owners.items():
        if len(nids) > 1:
            for nid in nids:
                skipped.setdefault(nid, []).append("macro %s is used by %s" % (macro, ", ".join(nids)))
    lines = ["% Generated from research/ledger/numbers.jsonl by `uws research check macros`. Do not edit by hand.\n"]
    for nid in sorted(numbers.latest):
        row = numbers.latest[nid][1]
        if row.get("macro") and nid not in skipped:
            lines.append("\\newcommand{%s}{%s}\n" % (row["macro"], row.get("printed")))
    path = project.path(rel)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    _atomic_write(path, "".join(lines))
    for nid in sorted(skipped):
        print("skipped %s: %s" % (nid, "; ".join(skipped[nid])))
    print("%s (%d macros%s)" % (rel, len(lines) - 1, ", %d invalid row(s) skipped" % len(skipped) if skipped else ""))
    return EXIT_FINDINGS if skipped or numbers.parse_errors else EXIT_OK


# --------------------------------------------------------------------------- gate

def _strip_html_comments(text):
    """Remove <!-- ... --> but keep the line count, so reported line numbers stay right."""
    return re.sub(r"<!--.*?-->", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)


QUESTION_FIELDS = (
    ("objective", ("objective", "question", "research question")),
    ("success criteria", ("success criteria", "success criterion")),
    ("available evidence", ("available evidence", "evidence")),
    ("constraints", ("constraints",)),
    ("consequences of failure", ("consequences of failure", "consequence of failure")),
)


def check_question(project):
    rel = "research/QUESTION.md"
    path = project.path(rel)
    if not os.path.isfile(path):
        return [Finding(rel, 1, "GATE-QUESTION", "missing: state the objective, success criteria, available "
                        "evidence, constraints and consequences of failure (apocalypt.md P1)")]
    sections, label_line = parse_labelled_fields(read_text(path), QUESTION_FIELDS)
    out = []
    for canon, _names in QUESTION_FIELDS:
        if _empty_field(sections.get(canon)):
            out.append(Finding(rel, label_line.get(canon, 1), "GATE-QUESTION", "'%s' is missing or empty" % canon))
    doc = project.doc(path)
    for _s, sent, _c, line_of in doc.sentences():
        m = s1_match(sent)
        if m and "candidate contribution" not in sent.lower():
            out.append(Finding(rel, line_of(m.start()), "S1", "%r in the question: say 'candidate contribution' "
                               "until novelty is established (apocalypt.md P2)" % m.group(0)))
    return out


def check_lit_verified(project):
    out = []
    claims = project.claims()
    for cid in sorted(claims.latest):
        lineno, row = claims.latest[cid]
        if row.get("category") in ("established_fact", "reported_finding"):
            if row.get("status") != "verified" or row.get("verified_by") not in LIT_VERIFIER_ROLES:
                out.append(Finding(claims.rel, lineno, "GATE-LIT",
                                   "%s (%s) is %s; it must be verified by the verifier role"
                                   % (cid, row.get("category"), row.get("status"))))
    return out


def check_search_log(project):
    rel = "research/lit/search_log.md"
    path = project.path(rel)
    if not os.path.isfile(path):
        return [Finding(rel, 1, "GATE-SEARCHLOG", "missing: record queries, databases, dates and inclusion/exclusion counts")]
    body = [ln for ln in _strip_html_comments(read_text(path)).splitlines()
            if ln.strip() and not ln.lstrip().startswith("#")]
    if not body:
        return [Finding(rel, 1, "GATE-SEARCHLOG", "has no entries")]
    return []


def read_reviews(project):
    """Findings rows from research/reviews/REV-*.md tables: | F-001 | severity | status | ..."""
    d = project.path("research/reviews")
    rows = []
    if not os.path.isdir(d):
        return rows
    for name in sorted(os.listdir(d)):
        if not (name.startswith("REV-") and name.endswith(".md")):
            continue
        path = os.path.join(d, name)
        for lineno, raw in enumerate(read_text(path).splitlines(), 1):
            cells = [c.strip() for c in raw.strip().strip("|").split("|")]
            if len(cells) >= 3 and re.match(r"^F-\d+$", cells[0]):
                rows.append((project.rel(path), lineno, cells[0], cells[1].lower(), cells[2]))
    return rows


def check_reviews(project, strict_major):
    out = []
    for rel, lineno, fid, severity, status in read_reviews(project):
        st = status.lower()
        if severity not in ("blocking", "major", "minor"):
            out.append(Finding(rel, lineno, "GATE-REVIEW", "%s: severity %r is not blocking|major|minor" % (fid, severity)))
            continue
        closed = st.startswith(("fixed", "resolved", "withdrawn"))
        if severity == "blocking" and not closed:
            out.append(Finding(rel, lineno, "GATE-REVIEW", "%s: blocking finding is %s" % (fid, status or "open")))
        if strict_major and severity == "major" and not closed and not DID_RE.search(status):
            out.append(Finding(rel, lineno, "GATE-REVIEW", "%s: major finding needs a fix or a PI decision ID (D-...)" % fid))
    return out


def check_pi_approval(project):
    rel = "research/pi/decisions.md"
    path = project.path(rel)
    text = read_text(path) if os.path.isfile(path) else ""
    m = re.search(r"^\s*PUBLICATION-APPROVAL:\s*(CR-[\w-]+)", text, re.M)
    if not m:
        return [Finding(rel, 1, "GATE-PI", "no `PUBLICATION-APPROVAL: CR-...` line: the PI approves publication")]
    cr = m.group(1)
    crs = project.path(".uws/crs")
    if os.path.isdir(crs):
        if os.path.isdir(os.path.join(crs, cr)):
            return [Finding(rel, text.count("\n", 0, m.start()) + 1, "GATE-PI", "%s is still pending review" % cr)]
        if not os.path.isdir(os.path.join(crs, "ARCHIVED_" + cr)):
            return [Finding(rel, text.count("\n", 0, m.start()) + 1, "GATE-PI", "%s was not approved with review.sh" % cr)]
    return []


def kb_note(project):
    """Section 9: the KB is advisory. Say what `uws kb stats` says (so the two never
    disagree: it exits 0 and prints "No KB yet ..." when the project has no KB); never fail."""
    here = os.path.dirname(os.path.abspath(__file__))
    uws = os.path.join(os.path.dirname(here), "bin", "uws")
    advisory = "(advisory; the gate does not depend on it)"
    if not os.path.isfile(os.path.join(here, "kb.sh")) or not os.path.isfile(uws):
        return "KB unavailable %s: the kb command is not installed next to this checker" % advisory
    try:
        proc = subprocess.run([uws, "kb", "stats"], cwd=project.root, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=15)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return "KB unavailable %s: `uws kb stats` did not run (%s)" % (advisory, exc)
    first = (proc.stdout.decode("utf-8", "replace").strip().splitlines() or [""])[0].strip()
    if proc.returncode != 0:
        err = (proc.stderr.decode("utf-8", "replace").strip().splitlines() or [""])[0].strip()
        return "KB unavailable %s: `uws kb stats` failed: %s" % (advisory, err or "exit %d" % proc.returncode)
    if not first or first.lower().startswith("no kb"):
        return "No KB yet %s: `uws kb stats` says: %s" % (advisory, first or "(nothing)")
    return ("KB available (advisory): `uws kb stats` says: %s; check `uws kb search <terms>` for disputed items "
            "and raise them as Q-IDs" % first)


# Rules of design section 6.5 that no check implements yet. The gates say so instead of
# passing silently.
NOT_CHECKED = ("slop rules S3 (fabricated precision), S5 (padding), S7 ('significant' without a test), "
               "C2 (untested path) and C4 (fragile paths); the research/INVENTORY.md report")


def run_gate(project, phase, allow_missing_cache=None):
    if phase not in PHASES:
        raise EnvError("unknown phase %r (one of %s)" % (phase, ", ".join(PHASES)))
    findings = []
    findings.extend(check_ledger(project))
    idx = PHASES.index(phase)
    if phase == "hypothesis":
        findings.extend(check_question(project))
    if idx >= PHASES.index("literature_review"):
        findings.extend(check_bib(project))
        findings.extend(check_quotes(project, allow_missing_cache))
        findings.extend(check_retractions(project))
    if phase == "literature_review":
        findings.extend(check_lit_verified(project))
        findings.extend(check_search_log(project))
    if idx >= PHASES.index("experiment_design"):
        # Pre-registration: fields, frozen hash, freeze committed before any result,
        # deviations after results carry a PI decision.
        findings.extend(check_plans(project, require_plan=True))
    if phase == "experiment_design":
        findings.extend(check_reviews(project, strict_major=False))
    if idx >= PHASES.index("data_collection"):
        findings.extend(check_data(project))
    if phase == "data_collection":
        findings.extend(check_slop(project, prose=False, code=True))
    if idx >= PHASES.index("analysis"):
        findings.extend(check_numbers(project))
        findings.extend(check_slop(project))
        findings.extend(check_repro_current(project))
    if idx >= PHASES.index("peer_review"):
        findings.extend(check_reviews(project, strict_major=True))
        findings.extend(check_review_hash(project))
    if phase == "publication":
        findings.extend(check_pi_approval(project))
    findings = dedupe(findings)
    notes = []
    if idx >= PHASES.index("analysis"):
        notes.append("not checked yet: " + NOT_CHECKED)
    if phase in ("literature_review", "analysis"):
        notes.append(kb_note(project))
    return findings, notes


# --------------------------------------------------------------------------- role-exit (SubagentStop)

def _report_text(hook):
    """The subagent's final report: last_assistant_message, else its SubagentHandback message."""
    texts = [hook.get("last_assistant_message") or ""]
    tpath = hook.get("agent_transcript_path") or ""
    if tpath:
        tpath = os.path.expanduser(tpath)
    if tpath and os.path.isfile(tpath):
        try:
            with open(tpath, encoding="utf-8", errors="replace") as fh:
                for raw in fh:
                    if "SubagentHandback" not in raw:
                        continue
                    try:
                        obj = json.loads(raw)
                    except ValueError:
                        continue
                    content = ((obj.get("message") or {}).get("content")) or []
                    for part in content if isinstance(content, list) else []:
                        if isinstance(part, dict) and part.get("type") == "tool_use" and part.get("name") == "SubagentHandback":
                            texts.append(str((part.get("input") or {}).get("message") or ""))
        except OSError:
            pass
    return "\n".join(t for t in texts if t)


def role_of(agent_type):
    """uws-rt-verifier or uws:uws-rt-verifier -> verifier."""
    name = (agent_type or "").split(":")[-1]
    m = re.match(r"^uws-rt-([a-z]+)$", name)
    return m.group(1) if m else None


def role_exit(project, hook, retries):
    agent_type = hook.get("agent_type") or ""
    role = role_of(agent_type)
    if role is None:
        return EXIT_OK, ""
    problems = []
    claims = project.claims()
    for cid in sorted(claims.latest):
        _ln, row = claims.latest[cid]
        if row.get("verified_by") and row.get("verified_by") == row.get("author"):
            problems.append("%s is marked verified by its own author (%s). Append a new revision of %s with "
                            "status 'unverified' and no verified_by; only a different role may verify it."
                            % (cid, row.get("author"), cid))
    changed = _git(project, ["status", "--porcelain", "--", "research/data/raw"])
    if changed:
        touched = [ln[3:] for ln in changed.splitlines() if ln[:2].strip() and not ln.startswith("??")]
        if touched:
            problems.append("raw data was modified or deleted (%s). Restore it with `git checkout -- research/data/raw`; "
                            "raw data is read-only." % ", ".join(touched[:5]))
    report = _report_text(hook)
    if report and "open questions for the orchestrator" not in report.lower():
        problems.append("your final report has no 'Open questions for the orchestrator' section. Add it "
                        "(write 'None' if there are none); you cannot ask the user.")
    counter_dir = os.path.join(tempfile.gettempdir(), "uws-research-hook-%s" % hashlib.sha256(project.root.encode()).hexdigest()[:12])
    wf = project.path(".workflow")
    if os.path.isdir(wf):
        counter_dir = os.path.join(wf, "tmp", "research_hook")
    agent_id = re.sub(r"[^\w.-]", "_", hook.get("agent_id") or agent_type or "unknown")
    counter = os.path.join(counter_dir, agent_id + ".count")
    if not problems:
        if os.path.exists(counter):
            os.unlink(counter)
        return EXIT_OK, ""
    os.makedirs(counter_dir, exist_ok=True)
    count = 0
    if os.path.isfile(counter):
        try:
            count = int(read_text(counter).strip() or 0)
        except ValueError:
            count = 0
    count += 1
    with open(counter, "w", encoding="utf-8") as fh:
        fh.write(str(count))
    if count > retries:
        os.unlink(counter)
        return EXIT_ROLE_EXHAUSTED, ("research exit check failed %d times for %s: %s"
                                     % (count, agent_type, " | ".join(problems)))
    return EXIT_ROLE_BLOCK, ("UWS research exit check (attempt %d of %d) - fix before stopping:\n- %s"
                             % (count, retries, "\n- ".join(problems)))


# --------------------------------------------------------------------------- init

QUESTION_TEMPLATE = """# Research brief

<!-- apocalypt.md P1. Fill every field; the hypothesis gate fails while one is empty.
     Novelty words are allowed only as "candidate contribution" (P2). -->

## Objective

## Success criteria

## Available evidence

## Constraints

## Consequences of failure
"""


def cmd_init(project):
    created = []
    for d in ("research/ledger", "research/lit", "research/pi", "research/reviews",
              "research/sources/cache", "research/experiments", "research/data/raw",
              "research/runs", "research/repro", "bib_sources"):
        p = project.path(d)
        if not os.path.isdir(p):
            os.makedirs(p)
            created.append(d + "/")
    files = {
        "research/ledger/claims.jsonl": "",
        "research/ledger/numbers.jsonl": "",
        "research/ledger/plans.jsonl": "",
        "research/data/manifest.jsonl": "",
        "research/sources/index.jsonl": "",
        "research/QUESTION.md": QUESTION_TEMPLATE,
        "research/pi/decisions.md": "# PI decisions\n\n<!-- One record per decision: `D-001 | raised <date> by <role> | phase <phase>`, then\n"
                                    "     CONCERN / EVIDENCE / RISK / ALTERNATIVE / RECOMMENDATION / COST / PI DECISION. -->\n",
        "research/pi/questions.md": "# Open questions for the PI\n\n<!-- Q-001 | raised by <role> | blocking: yes/no | options | assumption otherwise made -->\n",
    }
    for rel, content in files.items():
        p = project.path(rel)
        if not os.path.exists(p):
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(content)
            created.append(rel)
    # git does not store empty directories: a .gitkeep lets the scaffold be committed
    # (research/sources/cache is gitignored on purpose, so it gets none).
    for d in ("research/lit", "research/pi", "research/reviews", "research/experiments", "research/data/raw",
              "research/runs", "research/repro", "bib_sources"):
        p = project.path(d)
        if os.path.isdir(p) and not os.listdir(p):
            with open(os.path.join(p, ".gitkeep"), "w", encoding="utf-8"):
                pass
            created.append(d + "/.gitkeep")
    gi = project.path(".gitignore")
    line = "research/sources/cache/"
    existing = read_text(gi).splitlines() if os.path.isfile(gi) else []
    if line not in existing and "/" + line not in existing:
        with open(gi, "a", encoding="utf-8") as fh:
            if existing and existing[-1].strip():
                fh.write("\n")
            fh.write("# UWS research team: cached full texts are not committed (PI decision 7)\n%s\n" % line)
        created.append(".gitignore (research/sources/cache/)")
    for c in created:
        print("created %s" % c)
    if not created:
        print("research/ already set up; nothing changed")
    return EXIT_OK


# --------------------------------------------------------------------------- main

def emit(findings, as_json, notes=None):
    if as_json:
        print(json.dumps({"findings": [f.as_dict() for f in findings], "notes": notes or []}, indent=2))
    else:
        for f in findings:
            print(f.render())
        for n in notes or []:
            print("note: %s" % n)


def find_root(start):
    d = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(d, "research", "ledger")) or os.path.isdir(os.path.join(d, ".workflow")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return os.path.abspath(start)
        d = parent


def build_parser():
    p = argparse.ArgumentParser(prog="research_check.py", description=__doc__.split("\n\n")[0])
    p.add_argument("--root", help="project root (default: nearest directory with research/ledger or .workflow)")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    sub = p.add_subparsers(dest="cmd")
    s = sub.add_parser("ledger", help="claim and number ledger rules")
    s.add_argument("--base", action="append", help="git ref to compare for append-only (repeatable; default HEAD and HEAD~1)")
    sub.add_parser("bib", help="bib_sources provenance and references.bib equality")
    s = sub.add_parser("quotes", help="quotes are verbatim in the cached source text")
    s.add_argument("--allow-missing-cache", action="store_true", help="report a missing cache as a warning (CI without caches)")
    s = sub.add_parser("numbers", help="number provenance and hand-typed numbers; `add '<json>'` appends a row")
    s.add_argument("action", nargs="?", default="check", choices=("check", "add"))
    s.add_argument("row", nargs="?", help="for add: one JSON object (or - for stdin); id, rev, output_sha256, raw "
                   "and printed are filled in when missing")
    s.add_argument("--id", action="append", help="check only these N-IDs (repeatable)")
    s = sub.add_parser("claims", help="claim ledger rules (as `ledger`); `add '<json>'` appends a validated row")
    s.add_argument("action", nargs="?", default="check", choices=("check", "add"))
    s.add_argument("row", nargs="?", help="for add: one JSON object (or - for stdin); id and rev are filled in")
    s = sub.add_parser("slop", help="S1 S2 S4 S6 C1 C3 C5 C6")
    s.add_argument("files", nargs="*", help="limit to these files")
    s = sub.add_parser("plan", help="pre-registration: check plans, or `new`/`freeze <EXP-ID>`")
    s.add_argument("action", nargs="?", default="check", choices=("check", "new", "freeze"))
    s.add_argument("exp", nargs="?", help="experiment ID (EXP-<name>) for new/freeze")
    s.add_argument("--by", help="role that freezes the plan (default methodologist)")
    s.add_argument("--reason", help="why the frozen plan changed")
    s.add_argument("--pi-decision", help="PI decision ID (D-<n>) approving a change after results exist")
    s = sub.add_parser("data", help="data manifest: check, or `add <path>`")
    s.add_argument("action", nargs="?", default="check", choices=("check", "add"))
    s.add_argument("path", nargs="?", help="file to register (for add)")
    s.add_argument("--source", help="where the file came from (URL, instrument, or the generating command)")
    s.add_argument("--version", help="dataset version or release")
    s.add_argument("--split", help="split definition: free text, or JSON {\"train\": path, \"test\": path, "
                   "\"group_key\": field} / {\"column\": field, \"group_key\": field} so leakage can be checked")
    s.add_argument("--origin", help="measured | simulated | synthetic-generated | literature")
    s.add_argument("--generator", help="script that generated the file (required for generated data)")
    s.add_argument("--seed", help="seed the generator used (required for generated data; 'unrecorded' if unknown)")
    s.add_argument("--labels", help="where labels come from: generator-rule | annotation | measurement | none")
    s.add_argument("--license", help="license of the data")
    s.add_argument("--by", help="role registering the file (default engineer)")
    s.add_argument("--reason", help="why a registered file has a new version")
    s.add_argument("--pi-decision", help="PI decision ID (D-<n>) for replacing raw data")
    s = sub.add_parser("run", help="run a command and record research/runs/RUN-*/run.json")
    s.add_argument("--id", help="run ID (default: next RUN-<nnnn>)")
    s.add_argument("--exp", help="experiment the run belongs to (EXP-<name>, or exploratory)")
    s.add_argument("--input", action="append", help="data file the command reads (repeatable; hashed before the "
                   "run; code files given here are recorded as code)")
    s.add_argument("--code", action="append", help="code file the command runs (repeatable; versioned by the "
                   "run's commit, not by the data manifest)")
    s.add_argument("--output", action="append", help="output file, or a glob such as 'out/results_*.json' for "
                   "timestamped names (repeatable; resolved and hashed after the run)")
    s.add_argument("--env-lock", action="append", help="environment lock file to record by hash (repeatable; "
                   "default: research/env/*.lock and common lock files that exist)")
    s.add_argument("--seed", action="append", help="seed the command uses, NAME=VALUE (repeatable; recorded)")
    s.add_argument("--env", action="append", help="environment variable NAME=VALUE set for the run and its re-runs")
    s.add_argument("--timeout", type=int, help="seconds before the command is stopped")
    s.add_argument("command", nargs=argparse.REMAINDER, help="-- <command> [args]")
    s = sub.add_parser("repro", help="re-run recorded commands in a scratch copy and compare numbers")
    s.add_argument("ids", nargs="*", help="N-IDs, or all")
    s.add_argument("--timeout", type=int, help="seconds per re-run (default UWS_RESEARCH_REPRO_TIMEOUT or 3600)")
    s.add_argument("--keep", action="store_true", help="keep the scratch copy for inspection")
    s = sub.add_parser("retraction", help="retraction notices for bib_sources (offline from the cache, or --online)")
    s.add_argument("--online", action="store_true", help="look up Crossref now and append to the cache")
    s.add_argument("--key", action="append", help="only these citekeys (repeatable)")
    s.add_argument("--timeout", type=int, help="seconds per request (default 20)")
    s = sub.add_parser("manuscript-hash", help="hash of the manuscript files a red-team review must name")
    s.add_argument("--files", action="store_true", help="also list the files and their hashes")
    s = sub.add_parser("macros", help="write the generated number macros from the ledger")
    s.add_argument("--out", help="output file (default: numbers_tex in research/checks.json)")
    s = sub.add_parser("gate", help="evidence gate for a phase")
    s.add_argument("phase")
    s.add_argument("--allow-missing-cache", action="store_true")
    s = sub.add_parser("role-exit", help="SubagentStop hook check; hook JSON on stdin")
    s.add_argument("--retries", type=int, default=None)
    sub.add_parser("init", help="scaffold research/ and bib_sources/")
    s = sub.add_parser("bib-ingest", help="internal: validate and store a downloaded entry")
    s.add_argument("--body", required=True)
    s.add_argument("--url", required=True)
    s.add_argument("--id-type", required=True, choices=BIB_ID_TYPES)
    s.add_argument("--identifier", required=True)
    s.add_argument("--http-status", default="")
    s.add_argument("--content-type", default="")
    s.add_argument("--key")
    s.add_argument("--pi-decision")
    s.add_argument("--refetch", action="store_true")
    s = sub.add_parser("bib-build", help="internal: write references.bib from bib_sources/")
    s.add_argument("--out")
    s = sub.add_parser("bib-parse", help="internal: exit 0 if a file is exactly one BibTeX entry")
    s.add_argument("file")
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    if not args.cmd:
        build_parser().print_help()
        return EXIT_ENV
    root = os.path.abspath(args.root) if args.root else find_root(os.getcwd())
    try:
        if not os.path.isdir(root):
            raise EnvError("project root %s does not exist" % root)
        project = Project(root)
        if args.cmd == "init":
            return cmd_init(project)
        if args.cmd == "bib-ingest":
            return bib_ingest(project, args)
        if args.cmd == "bib-build":
            return bib_build(project, args)
        if args.cmd == "bib-parse":
            try:
                entry = validate_fetched_bib(read_text(args.file))
            except BibError as exc:
                print("refused: %s" % exc, file=sys.stderr)
                return EXIT_FINDINGS
            print(entry.key)
            return EXIT_OK
        if args.cmd == "role-exit":
            try:
                hook = json.load(sys.stdin)
            except ValueError as exc:
                raise EnvError("hook input is not JSON: %s" % exc)
            retries = args.retries
            if retries is None:
                env = os.environ.get("UWS_RESEARCH_HOOK_RETRIES", "2")
                retries = int(env) if env.isdigit() else 2
            code, msg = role_exit(project, hook, retries)
            if msg:
                print(msg, file=sys.stderr if code == EXIT_ROLE_BLOCK else sys.stdout)
            return code
        if not os.path.isdir(project.path("research/ledger")):
            raise EnvError("research/ledger/ not found under %s (run: research_check.py init)" % root)
        notes = []
        if args.cmd == "plan" and args.action == "new":
            return plan_new(project, args)
        if args.cmd == "plan" and args.action == "freeze":
            return plan_freeze(project, args)
        if args.cmd == "data" and args.action == "add":
            if not args.path:
                raise EnvError("usage: data add <path> --source ... --version ... --split ... --origin ...")
            return data_add(project, args)
        if args.cmd == "run":
            return cmd_run(project, args)
        if args.cmd == "repro":
            return cmd_repro(project, args)
        if args.cmd == "manuscript-hash":
            return cmd_manuscript_hash(project, args)
        if args.cmd == "macros":
            return cmd_macros(project, args)
        if args.cmd in ("numbers", "claims") and args.action == "add":
            return cmd_ledger_add(project, args.cmd, args.row)
        if args.cmd in ("numbers", "claims") and args.row:
            raise EnvError("a row is only taken by `%s add`" % args.cmd)
        if args.cmd == "ledger":
            findings = check_ledger(project, args.base)
        elif args.cmd == "claims":
            findings = check_ledger(project)
        elif args.cmd == "bib":
            findings = check_bib(project)
        elif args.cmd == "quotes":
            findings = check_quotes(project, True if args.allow_missing_cache else None)
        elif args.cmd == "numbers":
            findings = check_numbers(project, args.id)
        elif args.cmd == "slop":
            files = [os.path.abspath(f) for f in args.files] if args.files else None
            for f in files or []:
                if not os.path.isfile(f):
                    raise EnvError("no such file: %s" % f)
            findings = check_slop(project, files)
        elif args.cmd == "plan":
            findings = check_plans(project)
        elif args.cmd == "data":
            findings = check_data(project)
        elif args.cmd == "retraction":
            if args.online:
                return cmd_retraction_online(project, args)
            findings = check_retractions(project)
        elif args.cmd == "gate":
            findings, notes = run_gate(project, args.phase, True if args.allow_missing_cache else None)
        else:
            raise EnvError("unknown command %s" % args.cmd)
    except EnvError as exc:
        print("research_check: error: %s" % exc, file=sys.stderr)
        return EXIT_ENV
    except (OSError, UnicodeDecodeError) as exc:
        print("research_check: error: %s" % exc, file=sys.stderr)
        return EXIT_ENV
    findings = dedupe(findings)
    findings.sort(key=lambda f: (f.path, f.line, f.rule))
    emit(findings, args.json, notes)
    blocking = [f for f in findings if f.level == "block"]
    if not args.json:
        label = args.cmd if args.cmd != "gate" else "gate %s" % args.phase
        if blocking:
            print("%s: FAIL (%d blocking, %d warning)" % (label, len(blocking), len(findings) - len(blocking)), file=sys.stderr)
        else:
            print("%s: PASS (%d warning)" % (label, len(findings)), file=sys.stderr)
    return EXIT_FINDINGS if blocking else EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
