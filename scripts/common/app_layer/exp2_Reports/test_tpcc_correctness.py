"""Unit tests for tpcc_correctness.py — pure logic only, no DB/arm dirs/network."""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from tpcc_correctness import (  # noqa: E402
    aggregate,
    check_checksum,
    check_history,
    check_invariants,
    check_smoke,
    check_static,
    load_verify_statuses,
    verify_warning_lines,
)

GOOD_CSV = """transaction,executed,execution_time,transaction_rate
DELIVERY,100,1000.0,10.0
NEW_ORDER,1000,2000.0,20.0
ORDER_STATUS,100,500.0,30.0
PAYMENT,900,1500.0,40.0
STOCK_LEVEL,100,800.0,50.0
TOTAL,2200,5800.0,60.0
"""

BASE_SRC = "import x\nTXN_QUERIES = {'A': 'SELECT 1'}\ndef run():\n    return 1\n"


def test_static_clean_passes():
    r = check_static(BASE_SRC, BASE_SRC)
    assert r["status"] == "PASS"


def test_static_syntax_error_names_line():
    r = check_static("def broken(:\n", BASE_SRC)
    assert r["status"] == "FAIL" and "line 1" in r["issues"][0]


def test_static_query_only_diff_passes():
    src = BASE_SRC.replace("SELECT 1", "SELECT 2")
    assert check_static(src, BASE_SRC)["status"] == "PASS"


def test_static_dropped_commit_fails_and_names_it():
    base = "def run():\n    conn.commit()\n"
    src = "def run():\n    pass\n"
    r = check_static(src, base)
    assert r["status"] == "FAIL" and any("commit" in i for i in r["issues"])


def test_static_added_commit_warns_with_func():
    src = BASE_SRC.replace("    return 1", "    conn.commit()\n    return 1")
    r = check_static(src, BASE_SRC)
    assert r["status"] == "WARN" and any("run" in i for i in r["issues"])


def test_static_shape_token_fails():
    src = BASE_SRC + "# --warehouses handled\n"
    r = check_static(src, BASE_SRC)
    assert r["status"] == "FAIL" and any("--warehouses" in i for i in r["issues"])


def test_static_no_baseline_warn_only():
    r = check_static("conn.commit()\n")
    assert r["status"] == "WARN"


def test_smoke_good_passes():
    assert check_smoke(GOOD_CSV, "some log")["status"] == "PASS"


def test_smoke_missing_txn_lists_it():
    csv = GOOD_CSV.replace("DELIVERY,100,1000.0,10.0\n", "")
    r = check_smoke(csv)
    assert r["status"] == "FAIL" and any("DELIVERY" in i for i in r["issues"])


def test_smoke_zero_executed_fails():
    csv = GOOD_CSV.replace("PAYMENT,900,", "PAYMENT,0,")
    assert check_smoke(csv)["status"] == "FAIL"


def test_smoke_traceback_fails():
    log = "line1\nTraceback (most recent call last):\n  File x\nValueError: boom"
    r = check_smoke(GOOD_CSV, log)
    assert r["status"] == "FAIL" and any("Traceback" in i for i in r["issues"])


def test_smoke_empty_fails():
    assert check_smoke("")["status"] == "FAIL"


def test_invariants_empty_rows_pass():
    assert check_invariants({"C1": [], "C2": [], "C3": []})["status"] == "PASS"


def test_invariants_violation_names_condition():
    r = check_invariants({"C1": [], "C2": [[1, 2]]})
    assert r["status"] == "FAIL" and any("C2" in i for i in r["issues"])


def test_invariants_malformed_fails_closed():
    assert check_invariants({"C1": None})["status"] == "FAIL"
    assert check_invariants({})["status"] == "FAIL"


def test_history_equal_passes():
    assert check_history(900, 900)["status"] == "PASS"


def test_history_mismatch_fails():
    assert check_history(900, 850)["status"] == "FAIL"


def test_checksum_match_and_drift_never_fail():
    base = {"warehouse": 32, "w_ytd": 1000.0}
    assert check_checksum(base, dict(base))["status"] == "MATCH"
    r = check_checksum(base, {"warehouse": 32, "w_ytd": 5000.0})
    assert r["status"] == "DRIFT"


def test_aggregate_fail_wins_warn_drift_pass():
    assert aggregate({}) == "UNVERIFIED"
    assert aggregate({"a": {"status": "PASS"}, "b": {"status": "WARN"}}) == "PASS"
    assert aggregate({"a": {"status": "DRIFT"}, "b": {"status": "FAIL"}}) == "FAIL"


def test_verify_statuses_missing_is_unverified(tmp_path):
    sts = load_verify_statuses(str(tmp_path), "tpcc", ["aco"])
    assert sts == {"aco": "UNVERIFIED"}


def test_verify_statuses_roundtrip(tmp_path):
    d = tmp_path / "tpcc"
    d.mkdir()
    (d / "verify_aco.json").write_text('{"status": "FAIL"}')
    assert load_verify_statuses(str(tmp_path), "tpcc", ["aco"]) == {"aco": "FAIL"}


def test_warning_lines_fail_vs_unverified():
    lines = verify_warning_lines({"a": "FAIL", "b": "UNVERIFIED", "c": "PASS"})
    assert any("SUSPECT" in ln and "a" in ln for ln in lines)
    assert any("UNVERIFIED" in ln and "b" in ln for ln in lines)
    assert not any("'c'" in ln for ln in lines)
