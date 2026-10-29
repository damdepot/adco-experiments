#!/usr/bin/env python3
"""Correctness checks for TPC-C app-layer rewrite arms (aco, adco, py-dbridge, naive-llm).

Pure checker logic (no DB writes, no subprocesses): static diff guard (T0),
smoke CSV/log gate (T1), TPC-C invariant verdicts (T2), checksum drift (T3,
informational only). The DB-touching orchestration lives in run/tpcc/run_verify.sh.
"""

import argparse
import ast
import csv
import difflib
import io
import json
import os
from collections import Counter

REQUIRED_TXNS = ("NEW_ORDER", "PAYMENT", "ORDER_STATUS", "DELIVERY", "STOCK_LEVEL")

# Rewrites must not change workload shape or driver config. Transaction
# boundaries are compared separately (see _commit_sites): dropping a
# commit/rollback FAILs, adding one only WARNs (needs human review).
SHAPE_TOKENS = ("loadConfig", "stop_on_error", "--warehouses", "--clients")


def _commit_sites(tree):
    """(func_name, kind) for every .commit()/.rollback() call in the tree."""
    sites = []
    stack = []

    class V(ast.NodeVisitor):
        def visit_FunctionDef(self, node):
            stack.append(node.name)
            self.generic_visit(node)
            stack.pop()

        visit_AsyncFunctionDef = visit_FunctionDef

        def visit_Call(self, node):
            f = node.func
            if isinstance(f, ast.Attribute) and f.attr in ("commit", "rollback"):
                sites.append((stack[-1] if stack else "<module>", f.attr))
            self.generic_visit(node)

    V().visit(tree)
    return sites


def check_static(source_text, baseline_text=None):
    """T0: syntax must parse; workload shape must not change; transaction
    boundaries may only gain commits (WARN) — losing one FAILs."""
    try:
        tree = ast.parse(source_text)
    except SyntaxError as e:
        return {"status": FAIL, "issues": [f"syntax error line {e.lineno}: {e.msg}"]}
    if baseline_text is None:
        return {"status": WARN, "issues": ["no baseline: diff check skipped"]}
    issues = []
    fail = False
    diff = difflib.unified_diff(baseline_text.splitlines(), source_text.splitlines(),
                                lineterm="")
    for line in diff:
        if not line or line[:3] in ("---", "+++", "@@ "):
            continue
        if line[0] not in ("+", "-"):
            continue
        for tok in SHAPE_TOKENS:
            if tok in line:
                issues.append(f"workload-shape symbol {tok!r} in diff line: {line[1:].strip()[:100]}")
                fail = True
                break
    try:
        base_counts = Counter(k for _, k in _commit_sites(ast.parse(baseline_text)))
    except SyntaxError:
        base_counts = None
    if base_counts is not None:
        src_sites = _commit_sites(tree)
        src_counts = Counter(k for _, k in src_sites)
        for kind in ("commit", "rollback"):
            if src_counts[kind] < base_counts[kind]:
                issues.append(f"dropped .{kind}() calls: baseline has {base_counts[kind]}, rewrite has {src_counts[kind]}")
                fail = True
            elif src_counts[kind] > base_counts[kind]:
                fns = sorted({fn for fn, k in src_sites if k == kind})
                issues.append(f"added .{kind}() calls (review needed): {', '.join(fns)}")
    if fail:
        return {"status": FAIL, "issues": issues}
    if issues:
        return {"status": WARN, "issues": issues}
    return {"status": PASS, "issues": []}

PASS, FAIL, WARN = "PASS", "FAIL", "WARN"
MATCH, DRIFT = "MATCH", "DRIFT"


def check_smoke(csv_text, log_text=""):
    """T1: CSV has all 5 txns + TOTAL with executed>0; log has no Traceback."""
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
    if issues:
        return {"status": FAIL, "issues": issues}
    return {"status": PASS, "issues": []}


def check_invariants(condition_rows):
    """T2: every consistency condition must return zero rows. Fail-closed."""
    if not condition_rows:
        return {"status": FAIL, "issues": ["no invariant results supplied"]}
    issues = []
    for cond, rows in condition_rows.items():
        if rows is None:
            issues.append(f"{cond}: malformed result (query failed)")
        elif len(rows) > 0:
            issues.append(f"{cond} violated ({len(rows)} rows, e.g. {rows[0]!r})")
    if issues:
        return {"status": FAIL, "issues": issues}
    return {"status": PASS, "issues": []}


def check_history(payment_executed, history_count):
    """T2/C4: each Payment inserts exactly one HISTORY row (tolerance 0)."""
    if payment_executed is None or history_count is None:
        return {"status": FAIL, "issues": ["C4: missing payment count or history count"]}
    if history_count != payment_executed:
        return {"status": FAIL,
                "issues": [f"C4 violated: HISTORY rows={history_count} != PAYMENT executed={payment_executed}"]}
    return {"status": PASS, "issues": []}


def check_checksum(baseline, arm, tolerance=0.05):
    """T3: informational drift only — never FAIL (concurrency makes exact
    cross-arm equality impossible)."""
    if not baseline or not arm:
        return {"status": DRIFT, "issues": ["empty checksum input"]}
    issues = []
    for key, bval in baseline.items():
        if key not in arm:
            issues.append(f"missing key {key!r} in arm checksum")
            continue
        aval = arm[key]
        try:
            b, a = float(bval), float(aval)
        except (TypeError, ValueError):
            issues.append(f"non-numeric {key!r}: baseline={bval!r} arm={aval!r}")
            continue
        denom = abs(b) if b != 0 else 1.0
        if abs(a - b) / denom > tolerance:
            issues.append(f"{key}: baseline={b:g} arm={a:g} (rel. diff {abs(a-b)/denom:.1%})")
    if issues:
        return {"status": DRIFT, "issues": issues}
    return {"status": MATCH, "issues": []}


def aggregate(checks):
    """Overall FAIL if any check FAILs; WARN/DRIFT never fail. UNVERIFIED only
    when the arm was skipped (no checks ran)."""
    if not checks:
        return "UNVERIFIED"
    if any(c.get("status") == FAIL for c in checks.values()):
        return FAIL
    return PASS


def load_verify_statuses(results_dir, workload, systems):
    """Read results/<workload>/verify_<sys>.json -> {sys: PASS|FAIL|UNVERIFIED}."""
    statuses = {}
    for sys in systems:
        path = os.path.join(results_dir, workload, f"verify_{sys}.json")
        try:
            with open(path, encoding="utf-8") as f:
                st = str(json.load(f).get("status", "")).upper()
            statuses[sys] = st if st in (PASS, FAIL) else "UNVERIFIED"
        except (OSError, ValueError):
            statuses[sys] = "UNVERIFIED"
    return statuses


def verify_warning_lines(statuses, display_names=None):
    """Terminal/report warning lines for failed or unverified arms."""
    names = display_names or {}
    lines = []
    for sys, st in statuses.items():
        disp = names.get(sys, sys)
        if st == FAIL:
            lines.append(f"SUSPECT: arm '{disp}' failed correctness verification "
                         f"(see results/*/verify_{sys}.json) -- treat its speedup with caution.")
        elif st == "UNVERIFIED":
            lines.append(f"UNVERIFIED: no correctness result for arm '{disp}' -- run run/tpcc/run_verify.sh.")
    return lines


def main():
    ap = argparse.ArgumentParser(description="Verify one TPC-C app-layer arm.")
    ap.add_argument("--arm", required=True)
    ap.add_argument("--csv", default=None, help="smoke-run result CSV")
    ap.add_argument("--log", default=None, help="smoke-run console log")
    ap.add_argument("--source", default=None, help="rewritten driver .py under test")
    ap.add_argument("--baseline-source", default=None, help="pristine driver .py")
    ap.add_argument("--invariants", default=None, help="JSON file {condition: [rows]}")
    ap.add_argument("--payment-executed", type=int, default=None)
    ap.add_argument("--history-count", type=int, default=None,
                    help="HISTORY growth during the smoke run (after - before)")
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
        if args.payment_executed is not None or args.history_count is not None:
            checks["history"] = check_history(args.payment_executed, args.history_count)
    if args.invariants:
        with open(args.invariants, encoding="utf-8") as f:
            checks["invariants"] = check_invariants(json.load(f))

    status = aggregate(checks)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump({"arm": args.arm, "status": status, "checks": checks}, f, indent=2)
    print(f"verify {args.arm}: {status} -> {args.output}")
    return 0 if status != FAIL else 1


if __name__ == "__main__":
    raise SystemExit(main())
