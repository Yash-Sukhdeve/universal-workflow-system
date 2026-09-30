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
                        hand-typed decimals
    slop                S1 S2 S4 S6 (prose) and C1 C3 C5 (code / disclosure)
    gate <phase>        the evidence gate for one research phase
    role-exit           SubagentStop hook check (reads the hook JSON on stdin)
    init                scaffold research/ and bib_sources/ (never overwrites)
Internal (called by scripts/research_bib.sh):
    bib-ingest          validate a downloaded BibTeX body and store it with .meta.json
    bib-build           write references.bib from bib_sources/ only

Output: one line per finding, `file:line RULE-ID message` (`[warn]` marks a finding that
does not fail the check). Exit codes: 0 pass, 1 findings, 2 environment error.
"""

import argparse
import ast
import csv
import datetime
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import tokenize
import unicodedata
from decimal import Decimal, InvalidOperation, ROUND_CEILING, ROUND_DOWN, ROUND_FLOOR, ROUND_HALF_EVEN, ROUND_HALF_UP

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


def _check_number_shapes(numbers):
    out = []
    required = ("macro", "printed", "raw", "rounding", "metric", "output", "pointer",
                "output_sha256", "data_origin")
    for nid in sorted(numbers.latest):
        lineno, row = numbers.latest[nid]
        for key in required:
            if row.get(key) in (None, ""):
                out.append(Finding(numbers.rel, lineno, "NUM-SCHEMA", "%s: missing '%s'" % (nid, key)))
        if row.get("data_origin") not in (None, "") and row.get("data_origin") not in DATA_ORIGINS:
            out.append(Finding(numbers.rel, lineno, "NUM-SCHEMA", "%s: data_origin %r is not one of %s"
                               % (nid, row.get("data_origin"), ", ".join(DATA_ORIGINS))))
        macro = row.get("macro")
        if macro and not re.match(r"^\\[A-Za-z]+$", str(macro)):
            out.append(Finding(numbers.rel, lineno, "NUM-SCHEMA", "%s: macro must look like \\\\Name" % nid))
    return out


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
    out = []
    if not led.exists:
        return out
    if _git(project, ["rev-parse", "--is-inside-work-tree"]) is None:
        return out
    current = set()
    with open(led.path, encoding="utf-8") as fh:
        for raw in fh:
            if raw.strip():
                current.add(raw.rstrip("\n"))
    for ref in (bases or ["HEAD", "HEAD~1"]):
        old = _git(project, ["show", "%s:./%s" % (ref, led.rel)])
        if old is None:
            continue
        for oldline in old.splitlines():
            if not oldline.strip() or oldline in current:
                continue
            label = "?"
            try:
                obj = json.loads(oldline)
                label = "%s@%s" % (obj.get("id"), obj.get("rev", 1))
            except ValueError:
                pass
            out.append(Finding(led.rel, 1, "LEDGER-APPEND",
                               "%s was removed or edited compared with %s; ledgers are append-only "
                               "(restore it from git and append a new revision instead)" % (label, ref)))
    return out


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

    for rel, lineno, key in cites:
        if key not in stems:
            findings.append(Finding(rel, lineno, "BIB-MISSING", "\\cite{%s} has no bib_sources/%s.bib" % (key, key)))
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
        self.in_abstract = []
        self.in_tabular = []
        self.section = []    # current \section title per line
        self.captions = {}   # float env id -> caption text
        self._scan()

    def _scan(self):
        stack, float_id, floats = [], 0, []
        section = ""
        in_md_comment = False
        for raw in self.lines:
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
            for m in re.finditer(r"\\(begin|end)\{([^}]+)\}", code):
                kind, name = m.group(1), m.group(2).rstrip("*")
                if kind == "begin":
                    if name in ("table", "figure"):
                        float_id += 1
                        floats.append(float_id)
                    stack.append(name)
                elif stack and stack[-1].rstrip("*") == name:
                    stack.pop()
                    if name in ("table", "figure") and floats:
                        floats.pop()
            sm = re.search(r"\\(?:sub)*section\*?\{([^}]*)\}", code) if self.is_tex else re.match(r"^#+\s+(.*)", code)
            if sm:
                section = sm.group(1)
            cur_float = floats[-1] if floats else None
            if cur_float is not None and "\\caption" in code:
                self.captions[cur_float] = self.captions.get(cur_float, "") + " " + code
            self.code.append(code)
            self.comment.append(comment)
            self.cids.append(set(CID_RE.findall(comment)))
            self.env.append(cur_float)
            self.in_abstract.append("abstract" in stack or bool(re.search(r"\\begin\{abstract\}", code)))
            self.in_tabular.append(any(s.startswith(("tabular", "longtable", "array")) for s in stack))
            self.section.append(section)
        # a caption may appear after the content it describes; extend per float
        if self.captions:
            for fid in list(self.captions):
                self.captions[fid] = self.captions[fid].strip()

    def sentences(self):
        """Yield (start_line, text, cids, line_of(offset)) for each sentence."""
        para, offsets = [], []
        results = []

        def flush():
            if not para:
                return
            text = ""
            spans = []
            for lineno, code in para:
                start = len(text)
                text += code + " "
                spans.append((start, len(text), lineno))
            for m in re.finditer(r"[^.!?]*(?:[.!?]+(?=\s|$)|$)", text):
                s = m.group(0)
                if not s.strip():
                    continue
                a, b = m.start() + (len(s) - len(s.lstrip())), m.end()
                s = s.strip()
                lines = [ln for (st, en, ln) in spans if st < b and en > a]
                if not lines:
                    continue
                cids = set()
                for ln in lines:
                    cids |= self.cids[ln - 1]

                def line_of(off, _a=a, _spans=spans):
                    pos = _a + off
                    for st, en, ln in _spans:
                        if st <= pos < en:
                            return ln
                    return _spans[-1][2]
                results.append((lines[0], s, cids, line_of))
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
        return results


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
# A decimal such as 0.913 (a sentence-ending period may follow); version strings such as
# 3.2.1 and identifiers such as v1.2 are not matched.
DECIMAL_RE = re.compile(r"(?<![\w.\\-])-?\d+\.\d+(?:x|×)?(?!\w|\.\w)")
NUM_PREFIX_EXEMPT = re.compile(
    r"(?:Section|Sec\.|Sections|§|Table|Tab\.|Fig\.|Figure|Eq\.|Equation|Algorithm|Alg\.|Appendix|"
    r"Chapter|Theorem|Lemma|Definition|v|version|Version|Python|release|RFC|ISO|IEEE)\s*~?\s*$")
NUM_SUFFIX_EXEMPT = re.compile(r"^\s*\\?(?:textwidth|linewidth|columnwidth|textheight|cm|mm|pt|em|ex|in|bp|pc)\b")
LITERAL_RE = re.compile(r"uws:literal\b(.*)")


def _decimal_scope(doc, idx):
    rel = doc.rel.lower()
    name = os.path.basename(rel)
    if doc.in_abstract[idx] or doc.in_tabular[idx] or doc.env[idx] is not None:
        return True
    if re.search(r"(abstract|result|conclusion)", name) or "/tables/" in "/" + rel:
        return True
    return bool(re.search(r"(result|conclusion|abstract)", doc.section[idx], re.I))


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
            try:
                want = apply_rounding(row["raw"], row["rounding"], row.get("scale"))
            except (ValueError, InvalidOperation) as exc:
                where(str(exc), "NUM-ROUND")
            else:
                pm = re.match(r"^\s*(-?\d+(?:\.\d+)?)", str(row["printed"]))
                if not pm or pm.group(1) != want:
                    where("printed %r is not %s applied to raw %r (expected %s)"
                          % (row["printed"], row["rounding"], row["raw"], want), "NUM-ROUND")
        run = row.get("run")
        if run:
            findings.extend(_check_run(project, numbers.rel, lineno, nid, run))
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
        findings.extend(_hand_typed_decimals(project, macro_rel))
    return findings


def _check_run(project, rel, lineno, nid, run):
    out = []
    path = project.path("research/runs/%s/run.json" % run)
    if not re.match(r"^RUN-[\w-]+$", str(run)):
        return [Finding(rel, lineno, "NUM-RUN", "%s: run %r is not a RUN-ID" % (nid, run))]
    if not os.path.isfile(path):
        return [Finding(rel, lineno, "NUM-RUN", "%s: %s has no run record" % (nid, run))]
    try:
        with open(path, encoding="utf-8") as fh:
            rec = json.load(fh)
    except (OSError, ValueError) as exc:
        return [Finding(project.rel(path), 1, "NUM-RUN", "not valid JSON: %s" % exc)]
    if rec.get("exit_code") != 0:
        out.append(Finding(project.rel(path), 1, "NUM-RUN", "%s: exit_code is %r, not 0" % (run, rec.get("exit_code"))))
    commit = rec.get("git_commit")
    if not commit:
        out.append(Finding(project.rel(path), 1, "NUM-RUN", "%s: git_commit is missing" % run))
    elif _git(project, ["rev-parse", "--is-inside-work-tree"]) is not None:
        if _git(project, ["merge-base", "--is-ancestor", commit, "HEAD"]) is None:
            out.append(Finding(project.rel(path), 1, "NUM-RUN", "%s: commit %s is not an ancestor of HEAD" % (run, commit)))
    return out


def _hand_typed_decimals(project, macro_rel):
    out = []
    for path in project.tex_files():
        rel = project.rel(path)
        if rel == macro_rel:
            continue
        doc = Doc(project, path)
        for idx, code in enumerate(doc.code):
            lit = LITERAL_RE.search(doc.comment[idx])
            if lit:
                if not lit.group(1).strip():
                    out.append(Finding(rel, idx + 1, "NUM-LITERAL", "uws:literal needs a reason"))
                continue
            if not _decimal_scope(doc, idx):
                continue
            stripped = NUM_STRIP_RE.sub(" ", code)
            for m in DECIMAL_RE.finditer(stripped):
                if NUM_PREFIX_EXEMPT.search(stripped[:m.start()]) or NUM_SUFFIX_EXEMPT.match(stripped[m.end():]):
                    continue
                out.append(Finding(rel, idx + 1, "NUM-LITERAL",
                                   "hand-typed number %s: use a generated macro from the number ledger, "
                                   "or mark the line `%% uws:literal <reason>`" % m.group(0)))
    return out


# --------------------------------------------------------------------------- slop

S1_RE = re.compile(r"\b(novel(?:ty)?|state[- ]of[- ]the[- ]art|breakthroughs?|unprecedented|"
                   r"outperform(?:s|ed|ing)?|best|(?:the|a) first|first to|first time)\b", re.I)
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
        prose_files = [f for f in (files or project.prose_files()) if f.endswith((".tex", ".md"))]
        for path in prose_files:
            findings.extend(_slop_prose(project, Doc(project, path)))
        if not files:
            findings.extend(_slop_latex_logs(project))
    if code:
        code_files = [f for f in (files or project.code_files()) if f.endswith((".py", ".sh", ".R", ".r", ".jl"))]
        for path in code_files:
            findings.extend(_slop_code(project, path))
        findings.extend(_c3_measured_random(project))
    return findings


def _slop_prose(project, doc):
    out = []
    numbers = project.numbers()
    macro_origin = {}
    for nid, (_ln, row) in numbers.latest.items():
        if row.get("macro"):
            macro_origin[row["macro"]] = (nid, row.get("data_origin"))

    # S4 placeholders: line level, including comments for the TODO family.
    for idx, code in enumerate(doc.code):
        for m in S4_TEXT_RE.finditer(code):
            out.append(Finding(doc.rel, idx + 1, "S4", "placeholder %r" % m.group(0)))
        for m in S4_TAG_RE.finditer(doc.comment[idx]):
            out.append(Finding(doc.rel, idx + 1, "S4", "placeholder %r in a comment" % m.group(0)))
    out.extend(_empty_cells(doc))

    for start, sent, cids, line_of in doc.sentences():
        rows = [(c, _claim_row(project, c)) for c in sorted(cids)]
        # S1 novelty or superlative words need a verified, non-hypothesis claim.
        m = S1_RE.search(sent)
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
        # C3 disclosure: non-measured numbers or claims need a disclosure word nearby.
        disclosed = bool(DISCLOSURE_RE.search(sent))
        if not disclosed:
            fid = doc.env[start - 1]
            if fid is not None and DISCLOSURE_RE.search(doc.captions.get(fid, "")):
                disclosed = True
        if not disclosed:
            for mm in MACRO_USE_RE.finditer(sent):
                info = macro_origin.get("\\" + mm.group(1))
                if info and info[1] in NON_MEASURED:
                    out.append(Finding(doc.rel, line_of(mm.start()), "C3",
                                       "\\%s (%s) is %s data but the sentence/caption does not say so"
                                       % (mm.group(1), info[0], info[1])))
            for c, r in rows:
                if r and r.get("data_origin") in NON_MEASURED:
                    out.append(Finding(doc.rel, start, "C3",
                                       "%s rests on %s data but the sentence does not say so" % (c, r.get("data_origin"))))
    return out


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
        if any(not c.strip() for c in cells):
            if LITERAL_RE.search(doc.comment[idx]):
                continue
            out.append(Finding(doc.rel, idx + 1, "S4", "empty table cell"))
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
                    cmd = json.load(fh).get("command") or ""
            except (OSError, ValueError):
                cmd = ""
            if isinstance(cmd, list):
                cmd = " ".join(cmd)
            scripts.extend(re.findall(r"[\w./-]+\.py\b", str(cmd)))
        for script in scripts:
            spath = project.path(script)
            if not os.path.isfile(spath):
                continue
            for sline, name in _random_draws(spath):
                out.append(Finding(numbers.rel, lineno, "C3",
                                   "%s is labelled measured, but %s:%d draws %s(); label it simulated or remove the draw"
                                   % (nid, script, sline, name)))
    return out


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
    text = _strip_html_comments(read_text(path))
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
        for canon, names in QUESTION_FIELDS:
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
    out = []
    for canon, _names in QUESTION_FIELDS:
        body = sections.get(canon, "").strip()
        if not body or re.fullmatch(r"(?i)(tbd|todo|n/?a|-|\.\.\.)", body):
            out.append(Finding(rel, label_line.get(canon, 1), "GATE-QUESTION", "'%s' is missing or empty" % canon))
    doc = Doc(project, path)
    for _s, sent, _c, line_of in doc.sentences():
        m = S1_RE.search(sent)
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
    """Section 9: the KB is advisory. Report whether it can be consulted; never fail."""
    here = os.path.dirname(os.path.abspath(__file__))
    uws = os.path.join(os.path.dirname(here), "bin", "uws")
    if not os.path.isfile(os.path.join(here, "kb.sh")) or not os.path.isfile(uws):
        return "KB unavailable (advisory; the gate does not depend on it)"
    try:
        proc = subprocess.run([uws, "kb", "stats"], cwd=project.root, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return "KB unavailable (advisory; the gate does not depend on it)"
    if proc.returncode != 0:
        return "KB unavailable (advisory; the gate does not depend on it)"
    return "KB available (advisory): check `uws kb search <terms>` for disputed items and raise them as Q-IDs"


GATE_NOT_YET = {
    "experiment_design": "EXP plan fields, frozen_sha256 and power analysis are checked from increment 2",
    "data_collection": "MANIFEST.tsv hashes, read-only raw files and run-record completeness are checked from increment 2",
    "analysis": "the repro job is checked from increment 2",
    "peer_review": "the red-team manuscript hash is checked from increment 2",
    "publication": "the data manifest and repro job are checked from increment 2",
}


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
    if phase == "literature_review":
        findings.extend(check_lit_verified(project))
        findings.extend(check_search_log(project))
    if phase == "experiment_design":
        findings.extend(check_reviews(project, strict_major=False))
    if phase == "data_collection":
        findings.extend(check_slop(project, prose=False, code=True))
    if idx >= PHASES.index("analysis"):
        findings.extend(check_numbers(project))
        findings.extend(check_slop(project))
    if idx >= PHASES.index("peer_review"):
        findings.extend(check_reviews(project, strict_major=True))
    if phase == "publication":
        findings.extend(check_pi_approval(project))
    notes = []
    if phase in GATE_NOT_YET:
        notes.append("not checked yet: " + GATE_NOT_YET[phase])
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
              "research/sources/cache", "bib_sources"):
        p = project.path(d)
        if not os.path.isdir(p):
            os.makedirs(p)
            created.append(d + "/")
    files = {
        "research/ledger/claims.jsonl": "",
        "research/ledger/numbers.jsonl": "",
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
    s = sub.add_parser("numbers", help="number provenance and hand-typed decimals")
    s.add_argument("--id", action="append", help="check only these N-IDs (repeatable)")
    s = sub.add_parser("slop", help="S1 S2 S4 S6 C1 C3 C5")
    s.add_argument("files", nargs="*", help="limit to these files")
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
        if args.cmd == "ledger":
            findings = check_ledger(project, args.base)
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
