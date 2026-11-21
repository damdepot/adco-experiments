#!/usr/bin/env python3
"""Correctness checks for SmallBank app-layer rewrite arms.

Pure checker logic (no DB, no subprocesses): static diff guard, smoke CSV/log
gate, invariant verdicts and deterministic BALANCE read equivalence. The
DB-touching orchestration lives in run_verify.sh.

SmallBank has no official consistency-condition suite like TPC-C; the oracle
here is derived from SmallBank's own semantics: the six transaction functions
must survive, the driver must not take over transaction boundaries, every
baseline write must still happen, all six transaction types must run without a
failure storm, the ACCOUNTS/SAVINGS/CHECKING mapping must stay intact, and
BALANCE must return identical values through baseline and rewrite code.
"""

import argparse
import ast
import csv
import io
import json
import os
import re

REQUIRED_TXNS = (
    "AMALGAMATE",
    "BALANCE",
    "DEPOSIT_CHECKING",
    "SEND_PAYMENT",
    "TRANSACT_SAVINGS",
    "WRITE_CHECK",
)

# Module-level driver functions the client dispatches to (client.py registers
# these by name). A rewrite must keep all of them.
REQUIRED_FUNCS = (
    "amalgamate",
    "balance",
    "deposit_checking",
    "send_payment",
    "transact_savings",
    "write_check",
)

PASS, FAIL, WARN = "PASS", "FAIL", "WARN"

# ── static diff guard ─────────────────────────────────────────────────────

def _expr_name(node):
    """Best-effort name for an f-string/format placeholder expression."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return "?"


def _render(node, consts=None, depth=0):
    """Render a str/JoinedStr/Name/BinOp SQL expression to source text.

    f-string substitutions keep their placeholder name ({tablename_savings}) so
    constants can be resolved afterwards. Unknown expressions become {?}.
    """
    if depth > 8:
        return None
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.JoinedStr):
        parts = []
        for value in node.values:
            if isinstance(value, ast.Constant):
                parts.append(str(value.value))
            elif isinstance(value, ast.FormattedValue):
                parts.append("{%s}" % _expr_name(value.value))
            else:
                return None
        return "".join(parts)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _render(node.left, consts, depth + 1)
        right = _render(node.right, consts, depth + 1)
        if left is not None and right is not None:
            return left + right
        return None
    if isinstance(node, ast.Name) and consts:
        return _render_constant(node.id, consts, depth + 1)
    return None


def _render_constant(name, consts, depth):
    """Resolve a module/function-scope string constant by name."""
    if depth > 8 or name not in consts:
        return None
    return _render(consts[name], consts, depth + 1)


def _string_consts(tree):
    """name -> value AST for every string assignment in the file."""
    consts = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and isinstance(
                    node.value, (ast.Constant, ast.JoinedStr, ast.BinOp)
                ):
                    consts[target.id] = node.value
        elif isinstance(node, ast.AnnAssign):
            if isinstance(node.target, ast.Name) and node.value is not None:
                if isinstance(node.value, (ast.Constant, ast.JoinedStr, ast.BinOp)):
                    consts[node.target.id] = node.value
    return consts


def _resolve_placeholders(text, consts):
    """Expand {name} placeholders from known string constants."""
    for _ in range(8):
        def repl(match):
            return _render_constant(match.group(1), consts, 1) or match.group(0)

        new = re.sub(r"\{([A-Za-z_]\w*)\}", repl, text)
        if new == text:
            break
        text = new
    return text


def _canon_sql(text):
    """Normalize SQL for comparison: case, constants, params, whitespace."""
    t = text.lower()
    # Table-name constants may be inlined or imported (with or without braces).
    t = re.sub(r"\{?\btablename_(accounts|savings|checking)\b\}?", r"\1", t)
    # Parameter placeholders are formatting, not semantics.
    t = re.sub(r"%(?:\([a-z0-9_]+\))?[sd]|\?", "?", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def _sql_signature(text):
    """(op, table, assignment/column set) for one write statement, else None."""
    t = _canon_sql(text).rstrip(";")
    # UPDATE <table> [<alias>] SET ... ; an alias is an implementation choice.
    m = re.match(
        r"update\s+([a-z_]\w*)(?:\s+(?!set\b)(?:as\s+)?[a-z_]\w*)?\s+set\s+(.+)",
        t,
    )
    if m:
        table, rest = m.group(1), m.group(2)
        assignments = re.split(r"\s+(?:where|from)\s+", rest, 1)[0].strip()
        # Column qualifiers (c.bal) and literal SET values (bal = 0.0) are
        # implementation choices; the target column and shape are what matter.
        assignments = re.sub(r"\b[a-z_]\w*\.(?=[a-z_])", "", assignments)
        assignments = re.sub(r"(?<![\w.])-?\d+(?:\.\d+)?", "?", assignments)
        return ("update", table, assignments)
    m = re.match(r"insert\s+into\s+([a-z_]\w*)\s*(\([^)]*\))?", t)
    if m:
        return ("insert", m.group(1), (m.group(2) or "").strip())
    m = re.match(r"delete\s+from\s+([a-z_]\w*)", t)
    if m:
        return ("delete", m.group(1), "")
    return None


def _assignment_pairs(detail):
    """Split a normalized SET clause into (column, rhs) pairs.

    Only top-level commas split, so coalesce(bal, 0) stays one assignment.
    """
    chunks, depth, start = [], 0, 0
    for i, ch in enumerate(detail):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        elif ch == "," and depth == 0:
            chunks.append(detail[start:i])
            start = i + 1
    chunks.append(detail[start:])
    pairs = []
    for chunk in chunks:
        m = re.match(r"^\s*([a-z_]\w*)\s*=\s*(.+?)\s*$", chunk, re.S)
        if m:
            pairs.append((m.group(1), m.group(2)))
    return pairs


def _delta(assignment):
    """(column, first operator) when the RHS adjusts its own column in SQL."""
    column, rhs = assignment
    if not re.search(r"\b%s\b" % re.escape(column), rhs):
        return None
    # "=" inside a CASE is a comparison, not arithmetic.
    m = re.search(r"[+\-*/]", rhs)
    if m is None:
        return None
    return (column, m.group(0))


def _covers(base_sig, src_sigs):
    """True when a rewrite statement still performs the baseline write.

    A baseline delta (bal = bal + ?) may change shape as long as some rewrite
    assignment adjusts the same column with the same operator: merged CASE,
    casts and coalesce() are formatting. Absolute writes must still match.
    """
    if base_sig in src_sigs:
        return True
    op, table, detail = base_sig
    if op != "update":
        return False
    pairs = _assignment_pairs(detail)
    deltas = {_delta(p) for p in pairs} - {None}
    if not deltas:
        return False
    absolutes = {p for p in pairs if _delta(p) is None}
    for sig in src_sigs:
        if sig[0] != "update" or sig[1] != table:
            continue
        src_pairs = _assignment_pairs(sig[2])
        if deltas <= {_delta(p) for p in src_pairs} and absolutes <= set(src_pairs):
            return True
    return False


def _driver_sites(tree):
    """Per-function write signatures and commit/rollback call sites."""
    consts = _string_consts(tree)
    writes = {}
    commits = []
    stack = []

    class V(ast.NodeVisitor):
        def visit_FunctionDef(self, node):
            stack.append(node.name)
            self.generic_visit(node)
            stack.pop()

        visit_AsyncFunctionDef = visit_FunctionDef

        def visit_Call(self, node):
            func = node.func
            scope = stack[-1] if stack else "<module>"
            if isinstance(func, ast.Attribute) and func.attr in (
                "commit", "rollback"
            ):
                commits.append((scope, func.attr))
            if (
                isinstance(func, ast.Attribute)
                and func.attr in ("execute", "executemany")
                and node.args
            ):
                text = _render(node.args[0], consts)
                if text:
                    # One execute() may carry several statements; every write
                    # counts, otherwise merged updates look like dropped writes.
                    for stmt in _resolve_placeholders(text, consts).split(";"):
                        sig = _sql_signature(stmt)
                        if sig is not None:
                            writes.setdefault(scope, set()).add(sig)
            self.generic_visit(node)

    V().visit(tree)
    return writes, commits


def check_static(source_text, baseline_text=None):
    """Transaction functions, boundaries and write coverage must survive.

    The baseline driver has no commit/rollback: the client owns transaction
    boundaries, so any commit/rollback that appears inside the rewrite's
    driver functions is a FAIL (it changes where work becomes visible).
    """
    try:
        tree = ast.parse(source_text)
    except SyntaxError as e:
        return {"status": FAIL, "issues": [f"syntax error line {e.lineno}: {e.msg}"]}
    if baseline_text is None:
        return {"status": WARN, "issues": ["no baseline: diff check skipped"]}
    try:
        base_tree = ast.parse(baseline_text)
    except SyntaxError as e:
        return {"status": FAIL, "issues": [f"baseline syntax error line {e.lineno}: {e.msg}"]}

    issues = []
    funcs = {
        n.name for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
    }
    for name in REQUIRED_FUNCS:
        if name not in funcs:
            issues.append(f"missing transaction function: {name}()")

    base_writes, base_commits = _driver_sites(base_tree)
    src_writes, src_commits = _driver_sites(tree)

    base_kinds = {kind for _, kind in base_commits}
    for scope, kind in src_commits:
        if kind not in base_kinds or len(src_commits) > len(base_commits):
            issues.append(
                f"driver takes over transaction boundary: .{kind}() in {scope}() "
                "(baseline keeps commits in the client)"
            )
            break

    for func in REQUIRED_FUNCS:
        for sig in sorted(base_writes.get(func, ())):
            if not _covers(sig, src_writes.get(func, set())):
                op, table, detail = sig
                issues.append(
                    f"write coverage: {func}() lost {op} on {table}"
                    + (f" ({detail})" if detail else "")
                )

    if issues:
        return {"status": FAIL, "issues": issues}
    return {"status": PASS, "issues": []}


# ── smoke gate ────────────────────────────────────────────────────────────

_ERROR_COUNT_RE = re.compile(r"^\s*ERROR\s+(\d+)\b", re.MULTILINE)


def check_smoke(csv_text, log_text=""):
    """All six transaction types + TOTAL ran; no traceback or failure storm.

    SmallBank's runner buckets failures as ERROR (business aborts are ABORT and
    are expected: AMALGAMATE zeroes a checking balance, so later SEND_PAYMENTs
    can legitimately abort). Failed attempts are printed as an ERROR row in the
    console table but excluded from the CSV, so the log is the signal. Mirror
    the TPC-C threshold: at most 1% failed/executed.
    """
    if not csv_text or not csv_text.strip():
        return {"status": FAIL, "issues": ["empty CSV"]}
    try:
        rows = list(csv.reader(io.StringIO(csv_text)))
    except csv.Error as e:
        return {"status": FAIL, "issues": [f"unparseable CSV: {e}"]}
    seen = {}
    for row in rows:
        if len(row) < 4:
            continue
        name = row[0].strip().upper()
        if name == "TRANSACTION":
            continue
        try:
            seen[name] = float(row[1].strip())
        except ValueError:
            return {"status": FAIL, "issues": [f"non-numeric executed for {name}: {row[1]!r}"]}

    issues = []
    missing = [t for t in list(REQUIRED_TXNS) + ["TOTAL"] if t not in seen]
    if missing:
        issues.append(f"missing transactions: {', '.join(missing)}")
    zero = [t for t, v in seen.items() if v <= 0]
    if zero:
        issues.append(f"zero executed: {', '.join(zero)}")
    if log_text and "Traceback" in log_text:
        tail = [ln for ln in log_text.splitlines() if ln.strip()][-3:]
        issues.append("Traceback in log: " + " | ".join(t.strip()[:120] for t in tail))
    if log_text:
        failed = sum(int(n) for n in _ERROR_COUNT_RE.findall(log_text))
        total = seen.get("TOTAL", sum(seen.values()))
        if total > 0 and failed / total > 0.01:
            issues.append(
                "failure storm: %d failed txns in log vs %d executed (%.1f%%)"
                % (failed, total, 100.0 * failed / total)
            )
    if issues:
        return {"status": FAIL, "issues": issues}
    return {"status": PASS, "issues": []}


# ── invariants ────────────────────────────────────────────────────────────

def check_invariants(condition_rows):
    """Every SmallBank invariant must return zero rows. Fail-closed."""
    if not condition_rows:
        return {"status": FAIL, "issues": ["no invariant results supplied"]}
    issues = []
    for cond, rows in condition_rows.items():
        if rows is None:
            issues.append("%s: malformed result (query failed)" % cond)
        elif len(rows) > 0:
            issues.append(
                "%s violated (%d rows, e.g. %r)" % (cond, len(rows), rows[0])
            )
    if issues:
        return {"status": FAIL, "issues": issues}
    return {"status": PASS, "issues": []}


# ── read equivalence ──────────────────────────────────────────────────────

def normalize_value(v):
    """Normalize BALANCE results: floats/Decimal rounded, containers recursed.

    BALANCE returns checking+savings as a float. Rounding to 4 decimals kills
    float-repr noise between drivers without hiding real money differences.
    """
    import decimal

    if isinstance(v, decimal.Decimal):
        return round(float(v), 4)
    if isinstance(v, float):
        return round(v, 4)
    if isinstance(v, (list, tuple)):
        return [normalize_value(x) for x in v]
    if isinstance(v, dict):
        return {k: normalize_value(x) for k, x in v.items()}
    if isinstance(v, (bytes, bytearray)):
        return bytes(v).decode("utf-8", "replace")
    return v


def check_read_equivalence(baseline, arm):
    """BALANCE must return identical values through baseline and rewrite code.

    Read-only transactions leave no trace a post-hoc data check can see, so a
    rewrite can silently return wrong balances. Probes the baseline itself
    cannot run are skipped; a rewrite-only error or a different value FAILs.
    """
    for label, doc in (("baseline", baseline), ("arm", arm)):
        if not isinstance(doc, dict) or "probes" not in doc:
            return {"status": FAIL, "issues": ["no %s probe results" % label]}
    wanted = {p["name"]: p for p in arm["probes"]}
    issues = []
    for bp in baseline["probes"]:
        name = bp["name"]
        ap = wanted.get(name)
        if ap is None:
            issues.append("missing probe %s in rewrite results" % name)
            continue
        if "error" in bp:
            continue
        if "error" in ap:
            issues.append(
                "probe %s errored in rewrite: %s" % (name, ap["error"][:120])
            )
            continue
        if normalize_value(bp.get("result")) != normalize_value(ap.get("result")):
            issues.append("probe %s diverged" % name)
    if issues:
        return {"status": FAIL, "issues": issues}
    return {"status": PASS, "issues": []}


# ── verdicts ──────────────────────────────────────────────────────────────

def aggregate(checks):
    """Overall FAIL if any check FAILs; UNVERIFIED only when nothing ran."""
    if not checks:
        return "UNVERIFIED"
    if any(c.get("status") == FAIL for c in checks.values()):
        return FAIL
    return PASS


def main():
    ap = argparse.ArgumentParser(description="Verify one SmallBank app-layer arm.")
    ap.add_argument("--arm", required=True)
    ap.add_argument("--csv", default=None, help="smoke-run result CSV")
    ap.add_argument("--log", default=None, help="smoke-run console log")
    ap.add_argument("--source", default=None, help="rewritten driver .py under test")
    ap.add_argument("--baseline-source", default=None, help="pristine driver .py")
    ap.add_argument("--invariants", default=None, help="JSON file {condition: [rows]}")
    ap.add_argument("--probe-baseline", default=None, help="read_probe.py JSON for baseline code")
    ap.add_argument("--probe-arm", default=None, help="read_probe.py JSON for rewrite code")
    ap.add_argument("--output", required=True, help="verify_<arm>.json to write")
    args = ap.parse_args()

    checks = {}
    if args.source:
        with open(args.source, encoding="utf-8") as f:
            src = f.read()
        base = None
        if args.baseline_source:
            with open(args.baseline_source, encoding="utf-8") as f:
                base = f.read()
        checks["static"] = check_static(src, base)
    if args.csv:
        with open(args.csv, encoding="utf-8") as f:
            csv_text = f.read()
        log_text = ""
        if args.log and os.path.exists(args.log):
            with open(args.log, encoding="utf-8", errors="replace") as f:
                log_text = f.read()
        checks["smoke"] = check_smoke(csv_text, log_text)
    if args.invariants:
        with open(args.invariants, encoding="utf-8") as f:
            checks["invariants"] = check_invariants(json.load(f))
    if args.probe_baseline or args.probe_arm:
        try:
            with open(args.probe_baseline, encoding="utf-8") as f:
                base_doc = json.load(f)
            with open(args.probe_arm, encoding="utf-8") as f:
                arm_doc = json.load(f)
            checks["reads"] = check_read_equivalence(base_doc, arm_doc)
        except (OSError, ValueError) as e:
            checks["reads"] = {
                "status": FAIL,
                "issues": ["unreadable probe results: %s" % e],
            }

    status = aggregate(checks)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump({"arm": args.arm, "status": status, "checks": checks}, f, indent=2)
    print(f"verify {args.arm}: {status} -> {args.output}")
    return 0 if status != FAIL else 1


if __name__ == "__main__":
    raise SystemExit(main())
