#!/usr/bin/env python3
"""Read-only readers behind `uws kb import` (docs/design/knowledge-base.md sections 7 and 18).

Python 3 standard library only. The sources are never written:

- A vector-memory database is opened through a read-only URI connection
  (`mode=ro`) and copied into memory with SQLite's backup API. When that is not
  possible (for example a WAL database without its -shm file), the database
  file and any -journal/-wal/-shm files are copied byte for byte into a
  temporary directory and the copy is opened. Only the `memory_metadata` table
  is read, so the `vec0` extension of the vector index is not needed.
- Auto-memory topic files are only read. MEMORY.md, the index Claude Code
  loads every session, is not opened unless --include-index asks for its
  entries (each top-level list item or paragraph, except lines that only link a
  topic file); it is never written: UWS never edits it (decision D2).

kb.sh (`cmd_import`) turns the output into candidate items; this script never
touches the knowledge base. Output: one record per line, tab-separated, with
backslash, tab, newline and carriage return escaped as \\ \t \n \r:

  R <ref> <type> <tags> <flags> <flag-detail> <text> <meta> <original>
  S <ref> <reason>
  I <note>

  ref       row id (vector) or file name (automemory)
  type      fact | decision | lesson | anti-pattern (a guess from the category)
  tags      comma-separated tags ("-" when none)
  flags     "suspected-fixture" or "-"
  text      the text the claim is made from (vector: the row without its
            "PHASE n | DOMAIN: d | CATEGORY: c |" prefix; automemory: the description)
  meta      "key=value; ..." facts about the source row for the item body
  original  the source text, verbatim

The suspected-fixture rule (project imports only): the text names at least one
concrete thing (a path, a file name with an extension, a snake_case identifier
or a `backticked` term) and none of them occurs in the project: not as a tracked
path, directory or file name, and not in the contents of tracked files other
than prose (Markdown, text, TeX) and test fixtures, which may quote a stray
memory without the project containing the thing. Such rows are reported for
the PI's review; nothing is retired because of the flag.

Exit codes: 0 ok, 2 bad arguments or unreadable source.
"""

import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import urllib.parse

MAX_REFS_SHOWN = 5

# Vector-memory CATEGORY: prefixes (vector-memory skill) and server categories -> KB type
PREFIX_TYPE = {
    "decision-adr": "decision",
    "bug-resolution": "lesson",
    "anti-pattern": "anti-pattern",
    "tool-gotcha": "lesson",
    "design-lesson": "lesson",
    "workflow-improvement": "lesson",
    "library-compat": "lesson",
    "phase-summary": "fact",
    "verification": "fact",
    "agent-handoff": "fact",
    "environment": "fact",
}
SERVER_TYPE = {
    "bug-fix": "lesson",
    "debugging": "lesson",
    "code-solution": "lesson",
    "tool-usage": "lesson",
    "performance": "lesson",
    "security": "lesson",
    "learning": "fact",
    "other": "fact",
}

EXTENSIONS = (
    "py|sh|bash|bats|zsh|ya?ml|json|jsonl|md|toml|cfg|ini|txt|tex|bib|js|ts|tsx|go|rs|java|"
    "c|h|cc|cpp|hpp|sql|db|lock|env|conf|csv|tsv|ipynb|html|css|xml|gradle|mk|dockerfile"
)
# Where a mention does not make a thing part of the project: prose (a design note can quote a
# stray memory, as knowledge-base.md section 2.2 does) and test fixtures. File names still
# count from every tracked path.
PROSE_AND_FIXTURES = (
    "**/*.md", "**/*.markdown", "**/*.txt", "**/*.rst", "**/*.adoc", "**/*.tex",
    "**/fixtures/**", "**/fixture/**", "CHANGELOG*", "README*",
)
RE_BACKTICK = re.compile(r"`([^`\n]{2,80})`")
RE_FILE = re.compile(r"(?<![\w./-])(\.?[A-Za-z0-9_][\w.-]*\.(?:" + EXTENSIONS + r"))(?![\w/-])", re.I)
RE_PATH = re.compile(r"(?<![\w:/.-])(\.{0,2}/?[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+/?)")
RE_SNAKE = re.compile(r"(?<![\w./-])([a-z][a-z0-9]*(?:_[a-z0-9]+)+)(?![\w-]|\.\w)")
RE_URL = re.compile(r"[a-z][a-z0-9+.-]*://\S+", re.I)


def esc(value):
    s = "" if value is None else str(value)
    s = s.replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n").replace("\r", "\\r")
    return s if s != "" else "-"


def emit(*fields):
    sys.stdout.write("\t".join(esc(f) for f in fields) + "\n")


def fail(msg):
    sys.stderr.write("kb_import: %s\n" % msg)
    sys.exit(2)


def clean_tag(tag):
    t = re.sub(r"[^A-Za-z0-9._:+/-]+", "-", str(tag).strip()).strip("-")
    return t[:40]


# ── Project context for the suspected-fixture rule ─────────────────────────


class Project:
    """Tracked file names and a content search, from git (None when not a git work tree)."""

    def __init__(self, root):
        self.root = root
        self.paths = None
        self.names = set()
        self.dirs = set()
        if not root:
            return
        try:
            out = subprocess.run(
                ["git", "-C", root, "ls-files", "-z"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=60,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return
        paths = set(p for p in out.decode("utf-8", "replace").split("\0") if p)
        self.paths = paths
        for p in paths:
            self.names.add(p.rsplit("/", 1)[-1])
            parts = p.split("/")
            for i in range(1, len(parts)):
                self.dirs.add("/".join(parts[:i]))

    @property
    def usable(self):
        return self.paths is not None

    def found_in_contents(self, terms):
        """The subset of terms that occur (fixed strings) in tracked file contents."""
        if not terms:
            return set()
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".pat", delete=False) as fh:
            fh.write("\n".join(sorted(terms)) + "\n")
            patfile = fh.name
        try:
            res = subprocess.run(
                ["git", "-C", self.root, "grep", "-I", "-F", "-o", "-h", "--no-color", "-f", patfile, "--", "."]
                + [":(exclude,glob)" + g for g in PROSE_AND_FIXTURES],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=120,
            )
            hits = set(res.stdout.decode("utf-8", "replace").splitlines())
        except (OSError, subprocess.SubprocessError):
            hits = set()
        finally:
            os.unlink(patfile)
        return set(t for t in terms if t in hits)

    def path_known(self, ref):
        r = ref.strip("/")
        while r.startswith("./"):
            r = r[2:]
        if not r:
            return True
        return r in self.paths or r in self.dirs or r.rsplit("/", 1)[-1] in self.names


def refs_of(text):
    """Concrete things a text names: paths, file names, snake_case identifiers, `terms`."""
    body = RE_URL.sub(" ", text)
    refs = []
    for m in RE_BACKTICK.finditer(body):
        refs.append(m.group(1).strip())
    for rx in (RE_PATH, RE_FILE, RE_SNAKE):
        for m in rx.finditer(body):
            refs.append(m.group(1).rstrip(".,;:"))
    seen, out = set(), []
    for r in refs:
        r = r.strip()
        if len(r) < 3 or r in seen or re.fullmatch(r"[\d.,/:-]+", r):
            continue
        seen.add(r)
        out.append(r)
    return out


def fixture_flags(project, text):
    """("suspected-fixture", detail) when every concrete reference is absent, else ("-", "-")."""
    if project is None or not project.usable:
        return "-", "-"
    refs = refs_of(text)
    if not refs:
        return "-", "-"
    path_like = [r for r in refs if "/" in r or RE_FILE.fullmatch(r)]
    known = set(r for r in path_like if project.path_known(r))
    rest = [r for r in refs if r not in known]
    known |= project.found_in_contents(rest)
    if known:
        return "-", "-"
    shown = ", ".join(refs[:MAX_REFS_SHOWN]) + (", ..." if len(refs) > MAX_REFS_SHOWN else "")
    return "suspected-fixture", "names things absent from this project: " + shown


# ── Vector-memory database ──────────────────────────────────────────────────


def open_readonly_copy(path):
    """An in-memory (or temporary) copy of the database; the source is only read."""
    uri = "file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(path))
    try:
        src = sqlite3.connect(uri, uri=True, timeout=5)
        try:
            mem = sqlite3.connect(":memory:")
            src.backup(mem)
            return mem, None
        finally:
            src.close()
    except sqlite3.Error:
        pass
    tmp = tempfile.mkdtemp(prefix="uws-kb-import.")
    dst = os.path.join(tmp, "copy.db")
    try:
        shutil.copyfile(path, dst)
        for suffix in ("-journal", "-wal", "-shm"):
            if os.path.exists(path + suffix):
                shutil.copyfile(path + suffix, dst + suffix)
        return sqlite3.connect(dst), tmp
    except (OSError, sqlite3.Error) as exc:
        shutil.rmtree(tmp, ignore_errors=True)
        fail("cannot read %s: %s" % (path, exc))
    return None, None


def split_prefix(content):
    """Remove the vector-memory prefix; returns (text, tags, category-from-prefix)."""
    segments = [s.strip() for s in re.split(r"\s+\|\s+", content.strip())]
    tags, category, i = [], "", 0
    while i < len(segments) - 1:
        seg = segments[i]
        m = re.fullmatch(r"PHASE\s+(\d+)(?:\s+([A-Za-z_-]+))?", seg)
        if m:
            tags.append("phase-" + m.group(1))
            if m.group(2):
                tags.append(m.group(2))
            i += 1
            continue
        m = re.fullmatch(r"DOMAIN:\s*(.+)", seg)
        if m:
            tags.append(m.group(1))
            i += 1
            continue
        m = re.fullmatch(r"CATEGORY:\s*(.+)", seg)
        if m:
            category = m.group(1).strip().lower()
            i += 1
            continue
        break
    return " | ".join(segments[i:]), tags, category


def kb_type(prefix_category, server_category, scope):
    if prefix_category in PREFIX_TYPE:
        return PREFIX_TYPE[prefix_category]
    if server_category == "architecture":
        # project stores record decisions there; the global store records design lessons
        return "decision" if scope == "project" else "lesson"
    return SERVER_TYPE.get(server_category, "fact")


def read_vector(args):
    if not os.path.isfile(args.db):
        fail("no such database file: %s" % args.db)
    conn, tmp = open_readonly_copy(args.db)
    try:
        try:
            cols = [r[1] for r in conn.execute("PRAGMA table_info(memory_metadata)")]
        except sqlite3.Error as exc:
            fail("cannot read %s: %s" % (args.db, exc))
        need = {"id", "content", "category", "tags", "created_at"}
        if not need.issubset(cols):
            fail("%s is not a vector-memory database (no memory_metadata table with %s)"
                 % (args.db, ", ".join(sorted(need))))
        rows = conn.execute(
            "SELECT id, content, category, tags, created_at FROM memory_metadata ORDER BY id"
        ).fetchall()
    finally:
        conn.close()
        if tmp:
            shutil.rmtree(tmp, ignore_errors=True)
    project = Project(args.project) if args.scope == "project" else None
    if args.scope == "project" and not (project and project.usable):
        emit("I", "suspected-fixture rule not applied: the project is not a git work tree")
    if args.scope == "global":
        emit("I", "suspected-fixture rule not applied: a global import has no project to compare with")
    emit("I", "%d row(s) in memory_metadata" % len(rows))
    for rid, content, category, tags_json, created in rows:
        content = content or ""
        text, tags, pcat = split_prefix(content)
        if not text.strip():
            emit("S", rid, "empty text")
            continue
        try:
            raw_tags = json.loads(tags_json or "[]")
            if not isinstance(raw_tags, list):
                raw_tags = []
        except ValueError:
            raw_tags = []
        all_tags = []
        for t in ["import", args.label] + tags + [str(x) for x in raw_tags]:
            c = clean_tag(t)
            if c and c not in all_tags:
                all_tags.append(c)
        flags, detail = fixture_flags(project, text)
        meta = "row=%s; category=%s%s; stored=%s" % (
            rid, category or "-", (" (CATEGORY: %s)" % pcat) if pcat else "", created or "-")
        emit("R", rid, kb_type(pcat, (category or "").lower(), args.scope), ",".join(all_tags[:10]),
             flags, detail, text, meta, content)


# ── Claude Code auto-memory ─────────────────────────────────────────────────


def front_matter(text):
    """(fields, body) of a Markdown file with a flat or one-level-nested YAML header."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text
    fields, parent = {}, None
    for i in range(1, len(lines)):
        line = lines[i]
        if line.strip() == "---":
            return fields, "\n".join(lines[i + 1:])
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m:
            parent = m.group(1)
            fields[parent] = m.group(2).strip().strip("\"'")
            continue
        m = re.match(r"^\s+([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m and parent:
            fields[parent + "." + m.group(1)] = m.group(2).strip().strip("\"'")
    return None, text


RE_INDEX_LINK = re.compile(r"^\s*[-*+]\s*\[[^\]]*\]\([^)\s]+\.md\)")


def index_entries(text):
    """(line number, heading, block) for each top-level list item or paragraph of MEMORY.md.

    Nested (indented) lines belong to the item above them; headings name the section.
    """
    entries, block, state = [], [], {"heading": "", "start": 0}

    def flush():
        if block:
            entries.append((state["start"], state["heading"], "\n".join(block)))
            del block[:]

    for no, line in enumerate(text.splitlines(), start=1):
        s = line.rstrip()
        if not s.strip():
            flush()
            continue
        m = re.match(r"^#{1,6}\s+(.*)$", s)
        if m:
            flush()
            state["heading"] = m.group(1).strip()
            continue
        if re.match(r"^[-*+]\s+", s):
            flush()
        if not block:
            state["start"] = no
        block.append(s)
    flush()
    return entries


def plain(block):
    """One line of text from a Markdown block: list, quote and bold markers removed."""
    parts = []
    for line in block.splitlines():
        parts.append(re.sub(r"^\s*(?:>\s*)*(?:[-*+]\s+)?", "", line))
    return re.sub(r"\*\*|__", "", " ".join(p for p in parts if p))


def read_index(args, project, path):
    """MEMORY.md entries as candidates (only with --include-index; the file is only read)."""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError as exc:
        emit("S", "MEMORY.md", "unreadable: %s" % exc)
        return
    for no, heading, block in index_entries(text):
        ref = "MEMORY.md:L%d" % no
        if RE_INDEX_LINK.match(block) and "\n" not in block:
            emit("S", ref, "an index line pointing to a topic file (imported on its own)")
            continue
        claim = plain(block)
        if len(claim) < 12:
            emit("S", ref, "too short to be a fact")
            continue
        tags = []
        for t in ["import", "automemory", "index", heading.lower()[:40]]:
            c = clean_tag(t)
            if c and c not in tags:
                tags.append(c)
        flags, detail = fixture_flags(project, block)
        meta = "file=MEMORY.md; line=%d%s" % (no, ("; section=%s" % heading) if heading else "")
        emit("R", ref, "fact", ",".join(tags), flags, detail, claim, meta, block)


def read_automemory(args):
    if not os.path.isdir(args.dir):
        fail("no such directory: %s" % args.dir)
    project = Project(args.project)
    if not project.usable:
        emit("I", "suspected-fixture rule not applied: the project is not a git work tree")
    names = sorted(n for n in os.listdir(args.dir) if n.endswith(".md"))
    emit("I", "%d Markdown file(s) in the directory" % len(names))
    for name in names:
        ref = re.sub(r"[^A-Za-z0-9._-]+", "-", name)
        if name == "MEMORY.md":
            if args.include_index:
                read_index(args, project, os.path.join(args.dir, name))
            else:
                emit("S", ref, "the auto-memory index: not read (--include-index imports its entries; "
                               "UWS never edits it)")
            continue
        path = os.path.join(args.dir, name)
        if not os.path.isfile(path):
            emit("S", ref, "not a regular file")
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            emit("S", ref, "unreadable: %s" % exc)
            continue
        fields, body = front_matter(text)
        if fields is None:
            emit("S", ref, "no front matter: not an auto-memory topic file")
            continue
        mtype = (fields.get("type") or fields.get("metadata.type") or "").lower()
        if mtype in ("user", "feedback"):
            emit("S", ref, "a %s memory (preference or correction): it stays in auto-memory" % mtype)
            continue
        if mtype not in ("project", "reference"):
            emit("S", ref, "memory type '%s' is not a project fact" % (mtype or "none"))
            continue
        claim = fields.get("description", "")
        if not claim:
            claim = next((l.strip().lstrip("#").strip() for l in body.splitlines() if l.strip()), "")
        if not claim:
            emit("S", ref, "no description and an empty body")
            continue
        tags = []
        for t in ["import", "automemory", fields.get("name", "")]:
            c = clean_tag(t)
            if c and c not in tags:
                tags.append(c)
        flags, detail = fixture_flags(project, claim + "\n" + body)
        meta = "file=%s; memory type=%s%s" % (
            ref, mtype, ("; modified=%s" % fields["metadata.modified"]) if fields.get("metadata.modified") else "")
        emit("R", ref, "fact", ",".join(tags), flags, detail, claim, meta, body.strip("\n"))


def main():
    ap = argparse.ArgumentParser(prog="kb_import.py", description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="kind", required=True)
    v = sub.add_parser("vector")
    v.add_argument("--db", required=True)
    v.add_argument("--scope", choices=("project", "global"), default="project")
    v.add_argument("--label", default="vector-local")
    v.add_argument("--project", default="")
    a = sub.add_parser("automemory")
    a.add_argument("--dir", required=True)
    a.add_argument("--project", default="")
    a.add_argument("--include-index", action="store_true")
    args = ap.parse_args()
    if args.kind == "vector":
        read_vector(args)
    else:
        read_automemory(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
