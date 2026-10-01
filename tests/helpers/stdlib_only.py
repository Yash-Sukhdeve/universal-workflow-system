#!/usr/bin/env python3
"""Fail when a Python file imports a module outside the Python standard library.

Usage: stdlib_only.py <file.py>...

Reads each file's import statements with `ast` (nothing is run or compiled to disk) and
checks the top-level module names against `sys.stdlib_module_names` (Python 3.10+); older
Pythons use the fixed list below. Prints one `<file>:<line>: <module>` per offending import
and exits 1, else exits 0 silently. Used by tests/integration/test_kb_import.bats and the CI
lint job for scripts/kb_import.py and tests/fixtures/kb/make_vector_db.py, which run on
users' and CI machines with a bare python3.
"""

import ast
import sys

# Standard-library modules for Pythons without sys.stdlib_module_names (before 3.10)
FALLBACK = {
    "__future__", "abc", "argparse", "ast", "base64", "bisect", "codecs", "collections",
    "contextlib", "copy", "csv", "dataclasses", "datetime", "difflib", "enum", "errno",
    "fnmatch", "functools", "glob", "gzip", "hashlib", "heapq", "html", "io", "itertools",
    "json", "logging", "math", "operator", "os", "pathlib", "platform", "pprint", "random",
    "re", "shlex", "shutil", "signal", "socket", "sqlite3", "stat", "string", "struct",
    "subprocess", "sys", "tempfile", "textwrap", "time", "traceback", "types", "typing",
    "unicodedata", "urllib", "uuid", "warnings", "zlib",
}


def imported_modules(path):
    """(line, module) for every absolute import in the file."""
    with open(path, encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), path)
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                yield node.lineno, alias.name
        elif isinstance(node, ast.ImportFrom) and not node.level:
            yield node.lineno, node.module or ""


def main(paths):
    if not paths:
        sys.stderr.write(__doc__)
        return 2
    stdlib = set(getattr(sys, "stdlib_module_names", ())) or FALLBACK
    bad = 0
    for path in paths:
        for line, module in imported_modules(path):
            if module.split(".")[0] not in stdlib:
                print("%s:%d: %s" % (path, line, module))
                bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
