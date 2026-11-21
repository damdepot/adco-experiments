"""Unit tests for the SmallBank correctness oracle (no DB, no arm dirs).

SmallBank has no official consistency-condition suite; the tests cover the
oracle derived from its semantics: static guard (transaction functions,
boundaries, write coverage), smoke gate (all six transaction types, failure
storm), invariant verdicts, BALANCE read equivalence and status aggregation.
"""

import json
import os
import sys
import tempfile
from decimal import Decimal
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

from smallbank_correctness import (  # noqa: E402
    aggregate,
    check_invariants,
    check_read_equivalence,
    check_smoke,
    check_static,
    normalize_value,
)

ROOT = Path(__file__).resolve().parents[3]
BASE = (ROOT / "workload/apps/smallbank/drivers/postgresdriver.py").read_text()

_DEPOSIT_SQL = (
    'f"UPDATE {TABLENAME_CHECKING} SET bal = bal + %s WHERE custid = %s"'
)


# ── static guard ──────────────────────────────────────────────────────────

def test_static_baseline_passes():
    assert check_static(BASE, BASE)["status"] == "PASS"


def test_static_missing_transaction_function_fails():
    src = BASE.replace("def balance(", "def get_balance(")
    r = check_static(src, BASE)
    assert r["status"] == "FAIL"
    assert any("missing transaction function: balance()" in i for i in r["issues"])


def test_static_added_commit_inside_driver_fails():
    # The client owns transaction boundaries; a commit in the driver changes
    # when work becomes visible even if every statement is unchanged.
    old = "def balance(conn, cust_name: str) -> float:\n    cursor = conn.cursor()\n"
    src = BASE.replace(old, old + "    conn.commit()\n")
    r = check_static(src, BASE)
    assert r["status"] == "FAIL"
    assert any("transaction boundary" in i and "balance" in i for i in r["issues"])


def test_static_added_rollback_inside_driver_fails():
    old = "def balance(conn, cust_name: str) -> float:\n    cursor = conn.cursor()\n"
    src = BASE.replace(old, old + "    conn.rollback()\n")
    assert check_static(src, BASE)["status"] == "FAIL"


def test_static_dropped_write_fails():
    # deposit_checking no longer credits the account: faster, but wrong.
    src = BASE.replace(
        _DEPOSIT_SQL,
        'f"UPDATE {TABLENAME_CHECKING} SET bal = bal WHERE custid = %s"',
        1,
    )
    r = check_static(src, BASE)
    assert r["status"] == "FAIL"
    assert any("deposit_checking() lost update on checking" in i for i in r["issues"])


def test_static_dropped_amalgamate_zeroing_fails():
    src = BASE.replace(
        'f"UPDATE {TABLENAME_CHECKING} SET bal = 0.0 WHERE custid = %s"',
        '"SELECT 1"',
        1,
    )
    r = check_static(src, BASE)
    assert r["status"] == "FAIL"
    assert any("amalgamate() lost update on checking" in i for i in r["issues"])


def test_static_merged_multi_statement_execute_passes():
    # Two writes collapsed into one execute() string: every statement counts.
    pair = (
        '    cursor.execute(\n'
        '        f"UPDATE {TABLENAME_CHECKING} SET bal = 0.0 WHERE custid = %s",\n'
        '        (cust_id_0,),\n'
        '    )\n'
        '    cursor.execute(\n'
        '        f"UPDATE {TABLENAME_SAVINGS} SET bal = bal - %s WHERE custid = %s",\n'
        '        (total, cust_id_1),\n'
        '    )'
    )
    merged = (
        '    cursor.execute(\n'
        '        f"UPDATE {TABLENAME_CHECKING} SET bal = 0.0 WHERE custid = %s;"\n'
        '        f"UPDATE {TABLENAME_SAVINGS} SET bal = bal - %s WHERE custid = %s",\n'
        '        (cust_id_0, total, cust_id_1),\n'
        '    )'
    )
    assert pair in BASE
    assert check_static(BASE.replace(pair, merged, 1), BASE)["status"] == "PASS"


def test_static_merged_case_delta_passes():
    # Two UPDATEs merged into one in-SQL CASE delta: no Python-side
    # read-modify-write, and the same column/operator adjustment survives.
    old = (
        '    # Debt\n'
        '    cursor.execute(\n'
        '        f"UPDATE {TABLENAME_CHECKING} SET bal = bal + %s WHERE custid = %s",\n'
        '        (amount * -1, send_acct),\n'
        '    )\n'
        '    # Credit\n'
        '    cursor.execute(\n'
        '        f"UPDATE {TABLENAME_CHECKING} SET bal = bal + %s WHERE custid = %s",\n'
        '        (amount, dest_acct),\n'
        '    )'
    )
    new = (
        '    cursor.execute(\n'
        '        f"UPDATE {TABLENAME_CHECKING} SET bal = bal + CASE WHEN custid = %s'
        ' THEN %s ELSE %s END WHERE custid IN (%s, %s)",\n'
        '        (send_acct, amount * -1, amount, send_acct, dest_acct),\n'
        '    )'
    )
    assert old in BASE
    assert check_static(BASE.replace(old, new, 1), BASE)["status"] == "PASS"


def test_static_absolute_balance_write_fails():
    # Overwriting the balance loses the delta; an assignment shape is not a
    # delta just because it targets the same column.
    src = BASE.replace(
        _DEPOSIT_SQL,
        'f"UPDATE {TABLENAME_CHECKING} SET bal = %s WHERE custid = %s"',
        1,
    )
    r = check_static(src, BASE)
    assert r["status"] == "FAIL"
    assert any("deposit_checking() lost update on checking" in i for i in r["issues"])


def test_static_delta_sign_flip_fails():
    # bal - ? is still an in-SQL delta, but it moves money the wrong way.
    src = BASE.replace(
        _DEPOSIT_SQL,
        'f"UPDATE {TABLENAME_CHECKING} SET bal = bal - %s WHERE custid = %s"',
        1,
    )
    r = check_static(src, BASE)
    assert r["status"] == "FAIL"
    assert any("lost update on checking" in i for i in r["issues"])


def test_static_update_from_returning_passes():
    # SELECT+UPDATE fused into UPDATE ... FROM ... RETURNING with an alias:
    # same write target and shape, one round trip instead of two.
    old = (
        '    cursor.execute(\n'
        '        f"UPDATE {TABLENAME_CHECKING} SET bal = bal + %s WHERE custid = %s",\n'
        '        (amount, cust_id),\n'
        '    )'
    )
    new = (
        '    cursor.execute(\n'
        '        f"""UPDATE {TABLENAME_CHECKING} c SET bal = c.bal + %s\n'
        '        FROM {TABLENAME_ACCOUNTS} a\n'
        '        WHERE a.name = %s AND c.custid = a.custid RETURNING c.custid""",\n'
        '        (amount, cust_name),\n'
        '    )'
    )
    assert old in BASE
    assert check_static(BASE.replace(old, new, 1), BASE)["status"] == "PASS"


def test_static_write_in_module_constant_still_counts():
    # SQL hoisted to a module-level f-string constant and executed by name.
    src = BASE.replace(_DEPOSIT_SQL, "DEPOSIT_CHECKING_SQL", 1)
    src = src.replace(
        "class InsufficientFunds(Exception):",
        "DEPOSIT_CHECKING_SQL = " + _DEPOSIT_SQL + "\n\n\nclass InsufficientFunds(Exception):",
        1,
    )
    assert check_static(src, BASE)["status"] == "PASS"


def test_static_inlined_table_name_still_counts():
    src = BASE.replace(
        _DEPOSIT_SQL,
        '"UPDATE CHECKING SET bal = bal + %s WHERE custid = %s"',
        1,
    )
    assert check_static(src, BASE)["status"] == "PASS"


def test_static_comment_only_change_passes():
    src = BASE.replace("    # Get Account Information\n", "")
    assert check_static(src, BASE)["status"] == "PASS"


def test_static_syntax_error_fails():
    r = check_static(BASE + "\ndef broken(\n", BASE)
    assert r["status"] == "FAIL"
    assert any("syntax error" in i for i in r["issues"])


# ── smoke gate ────────────────────────────────────────────────────────────

_SMOKE_CSV = """transaction,executed,execution_time,transaction_rate
AMALGAMATE,300,10.0,30.0
BALANCE,300,10.0,30.0
DEPOSIT_CHECKING,300,10.0,30.0
SEND_PAYMENT,500,10.0,50.0
TRANSACT_SAVINGS,300,10.0,30.0
WRITE_CHECK,300,10.0,30.0
TOTAL,2000,60.0,200.0
"""


def test_smoke_all_six_transactions_passes():
    assert check_smoke(_SMOKE_CSV)["status"] == "PASS"


def test_smoke_missing_transaction_fails():
    src = "\n".join(ln for ln in _SMOKE_CSV.splitlines()
                    if not ln.startswith("AMALGAMATE"))
    r = check_smoke(src)
    assert r["status"] == "FAIL"
    assert any("AMALGAMATE" in i for i in r["issues"])


def test_smoke_zero_executed_fails():
    src = _SMOKE_CSV.replace("BALANCE,300", "BALANCE,0")
    r = check_smoke(src)
    assert r["status"] == "FAIL"
    assert any("zero executed: BALANCE" in i for i in r["issues"])


def test_smoke_empty_csv_fails():
    assert check_smoke("")["status"] == "FAIL"
    assert check_smoke("   \n")["status"] == "FAIL"


def test_smoke_failure_storm_fails():
    # SmallBank prints failed attempts as an ERROR row in the console table.
    log = "  ERROR                       30            -            -\n"
    r = check_smoke(_SMOKE_CSV, log)
    assert r["status"] == "FAIL"
    assert any("failure storm" in i for i in r["issues"])


def test_smoke_odd_error_passes():
    log = "  ERROR                        1            -            -\n"
    assert check_smoke(_SMOKE_CSV, log)["status"] == "PASS"


def test_smoke_traceback_fails():
    log = "Traceback (most recent call last):\n  ...\nRuntimeError: boom\n"
    r = check_smoke(_SMOKE_CSV, log)
    assert r["status"] == "FAIL"
    assert any("Traceback" in i for i in r["issues"])


# ── invariants ────────────────────────────────────────────────────────────

_INVARIANTS = {
    "accounts_count": [],
    "savings_count": [],
    "checking_count": [],
    "savings_mapping": [],
    "checking_mapping": [],
    "balance_sanity": [],
    "dup_custid": [],
}


def test_invariants_all_clean_pass():
    assert check_invariants(_INVARIANTS)["status"] == "PASS"


def test_invariants_violation_fails_named():
    conds = dict(_INVARIANTS, savings_mapping=[["7", ""]])
    r = check_invariants(conds)
    assert r["status"] == "FAIL"
    assert any("savings_mapping violated" in i for i in r["issues"])


def test_invariants_failed_query_fails_closed():
    conds = dict(_INVARIANTS, balance_sanity=None)
    r = check_invariants(conds)
    assert r["status"] == "FAIL"
    assert any("balance_sanity" in i for i in r["issues"])


def test_invariants_missing_results_fail_closed():
    assert check_invariants({})["status"] == "FAIL"


# ── read equivalence ──────────────────────────────────────────────────────

def _probes(*entries):
    return {"probes": [{"name": n, "result": r} for n, r in entries]}


def test_reads_identical_pass():
    doc = _probes(("0000000000000000000000000000000000000000000000000000000000000001", 1234.5))
    assert check_read_equivalence(doc, doc)["status"] == "PASS"


def test_reads_float_repr_noise_passes():
    base = _probes(("name", 5537.360000000001))
    arm = _probes(("name", 5537.36))
    assert check_read_equivalence(base, arm)["status"] == "PASS"


def test_reads_divergence_names_probe():
    base = _probes(("0000000000000000000000000000000000000000000000000000000000000001", 100.0))
    arm = _probes(("0000000000000000000000000000000000000000000000000000000000000001", 200.0))
    r = check_read_equivalence(base, arm)
    assert r["status"] == "FAIL"
    assert any("diverged" in i for i in r["issues"])


def test_reads_rewrite_error_fails():
    base = _probes(("name", 10.0))
    arm = {"probes": [{"name": "name", "error": "TypeError: boom"}]}
    assert check_read_equivalence(base, arm)["status"] == "FAIL"


def test_reads_baseline_error_skips_probe():
    base = {"probes": [{"name": "name", "error": "InvalidAccount: x"}]}
    arm = _probes(("name", 10.0))
    assert check_read_equivalence(base, arm)["status"] == "PASS"


def test_reads_missing_results_fail_closed():
    assert check_read_equivalence({}, {})["status"] == "FAIL"
    assert check_read_equivalence({"probes": []}, {})["status"] == "FAIL"


def test_normalize_rounds_numbers_and_recurses():
    assert normalize_value(Decimal("10.50")) == 10.5
    assert normalize_value(1.00001) == 1.0
    assert normalize_value((1, 2)) == [1, 2]


# ── status helpers / report contract ──────────────────────────────────────

def test_aggregate_policies():
    assert aggregate({}) == "UNVERIFIED"
    assert aggregate({"static": {"status": "PASS"}}) == "PASS"
    assert aggregate({"static": {"status": "PASS"},
                      "smoke": {"status": "FAIL"}}) == "FAIL"


def test_verdict_schema_is_consumed_by_report_loader():
    # report.py reads results/<workload>/verify_<sys>.json through the generic
    # TPC-C loader; the SmallBank verdict must satisfy that contract.
    tpcc_dir = str(ROOT / "scripts/tpcc/exp2_Correctness")
    sys.path.insert(0, tpcc_dir)
    try:
        from tpcc_correctness import load_correctness_statuses
    except ImportError:
        return  # sibling layer absent; contract is covered by the report run
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "smallbank"
        out.mkdir()
        (out / "verify_aco.json").write_text(json.dumps({
            "arm": "aco",
            "status": "PASS",
            "checks": {"static": {"status": "PASS", "issues": []}},
        }))
        info = load_correctness_statuses(tmp, "smallbank", ["aco"])["aco"]
    assert info["status"] == "PASS"
    assert info["fallback"] is True


def _run_all():
    tests = [(n, f) for n, f in sorted(globals().items())
             if n.startswith("test_") and callable(f)]
    for name, fn in tests:
        fn()
    print("OK: %d tests passed" % len(tests))


if __name__ == "__main__":
    _run_all()
