#!/usr/bin/env python3
"""Classify a rewrite tree against its source tree.

    check_rewrite.py <generated-tree> <source-tree> [file ...]

Compares the driver and entry file (defaults below). Exit codes:
  0  substantive change (AST differs)
  1  unchanged (no differing file)
  2  cosmetic only (files differ, ASTs identical: comments/format/whitespace)
  3  no comparable file or unparseable code
"""

import ast
import sys
from pathlib import Path

FILES = ("drivers/postgresdriver.py", "tpcc.py")


def parse(path):
    return ast.parse(path.read_text(encoding="utf-8"))


def main():
    generated, source = Path(sys.argv[1]), Path(sys.argv[2])
    files = sys.argv[3:] or FILES
    compared = 0
    differ = 0
    cosmetic = 0
    for rel in files:
        new, old = generated / rel, source / rel
        if not new.is_file() or not old.is_file():
            continue
        compared += 1
        if new.read_bytes() == old.read_bytes():
            continue
        differ += 1
        try:
            if ast.dump(parse(new)) == ast.dump(parse(old)):
                cosmetic += 1
        except (SyntaxError, ValueError, OSError):
            return 3
    if not compared:
        return 3
    if not differ:
        return 1
    return 2 if cosmetic == differ else 0


if __name__ == "__main__":
    raise SystemExit(main())
