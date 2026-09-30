#!/usr/bin/env python3
"""Build a small vector-memory SQLite fixture for tests/integration/test_kb_import.bats.

The schema copies the vector-memory MCP server (cornebidouil/vector-memory-mcp,
src/memory_store.py `_init_database`): the `memory_metadata` table and its
indexes, plus a `memory_vectors` entry declared as a `vec0` virtual table, as in
the real databases. The vec0 module is not available here, so the virtual table
is written straight into sqlite_master (PRAGMA writable_schema); opening the file
without the extension then behaves as it does for the importer on a real store.

Usage: make_vector_db.py <local|global> <output.db>
The rows are synthetic; none come from a real memory store.
"""

import json
import sqlite3
import sys

SCHEMA = """
CREATE TABLE memory_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_hash TEXT UNIQUE NOT NULL,
    content TEXT NOT NULL,
    category TEXT NOT NULL,
    tags TEXT NOT NULL,  -- JSON array
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    access_count INTEGER DEFAULT 0
);
CREATE INDEX idx_category ON memory_metadata(category);
CREATE INDEX idx_created_at ON memory_metadata(created_at);
CREATE INDEX idx_hash ON memory_metadata(content_hash);
CREATE INDEX idx_access_count ON memory_metadata(access_count);
"""

AWS_SHAPE = "AKIA" + "ABCDEFGHIJKLMNOP"   # an AWS key shape, split so scanners ignore this file

LOCAL = [
    ("PHASE 1 requirements | DOMAIN: workflow | CATEGORY: phase-summary | OUTCOME: the kb.sh "
     "script keeps one Markdown file per item", "learning", ["phase-1", "workflow"]),
    ("PHASE 2 implementation | DOMAIN: testing | CATEGORY: verification | VERIFIED: all 608 BATS "
     "tests passing", "other", ["phase-2", "verification"]),
    ("PHASE 2 implementation | DOMAIN: tooling | CATEGORY: bug-resolution | BUG: grep -c with "
     "|| echo 0 prints 0 twice ROOT_CAUSE: grep prints its own 0 FIX: use || true in scripts/kb.sh",
     "bug-fix", ["phase-2", "bug"]),
    # the same memory as row 1, stored again with another CATEGORY prefix (defect 2.2-1)
    ("PHASE 1 requirements | DOMAIN: workflow | CATEGORY: decision-adr | OUTCOME: the kb.sh "
     "script keeps one Markdown file per item", "architecture", ["phase-1", "workflow"]),
    # test data written into the live store (defect 2.2-5): names nothing in the project
    ("PHASE 2 implementation | DOMAIN: training | configured Docker in deploy/Dockerfile, pinned CUDA "
     "in docker/compose.gpu.yml and set batch_size to 64 in configs/train_resnet.yaml", "learning",
     ["phase-2", "training"]),
    ("PHASE 2 implementation | DOMAIN: secrets | the staging key is " + AWS_SHAPE, "other",
     ["phase-2"]),
    ("PHASE 3 validation | DOMAIN: workflow | " + ("A long lesson about checkpoints. " * 12).strip(),
     "learning", ["phase-3"]),
]

GLOBAL = [
    ("GIT: git stash pop silently drops changes when merge conflicts occur, so the stash entry "
     "is kept", "bug-fix", ["git"]),
    ("VECTOR-MEMORY: the server stores memories in memories.db under the working directory",
     "tool-usage", ["vector-memory"]),
    ("BASH: macOS ships bash 3.2, so declare -A and mapfile are unavailable", "bug-fix", ["bash"]),
    ("UWS: the lab notes live in /home/someone/project/notes.md", "other", ["uws"]),
]


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("local", "global"):
        sys.stderr.write(__doc__)
        return 2
    rows = LOCAL if sys.argv[1] == "local" else GLOBAL
    conn = sqlite3.connect(sys.argv[2])
    conn.executescript(SCHEMA)
    conn.execute("PRAGMA writable_schema = ON")
    conn.execute(
        "INSERT INTO sqlite_master (type, name, tbl_name, rootpage, sql) VALUES "
        "('table', 'memory_vectors', 'memory_vectors', 0, "
        "'CREATE VIRTUAL TABLE memory_vectors USING vec0(embedding float[384])')")
    conn.execute("PRAGMA writable_schema = OFF")
    for i, (content, category, tags) in enumerate(rows, start=1):
        ts = "2026-02-17T10:%02d:00.000000+00:00" % i
        conn.execute(
            "INSERT INTO memory_metadata (content_hash, content, category, tags, created_at, "
            "updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            ("h%04d" % i, content, category, json.dumps(tags), ts, ts))
    conn.commit()
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
