"""TPC-C compliant correctness tests (Standard Spec v5.11, Clause 3.3).

One test per official consistency condition in Clause 3.3.2: a consistent
state returns no rows (PASS); any returned row is a violation (FAIL naming
the condition). CC6/CC7 run on a recent-orders window (sampled); the rest
are full checks. Fail-closed: missing results or a failed query is a
FAILURE, never a pass.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from tpcc_correctness import check_invariants  # noqa: E402
from tpcc_correctness import check_read_equivalence, normalize_value  # noqa: E402
from tpcc_correctness import check_smoke  # noqa: E402 — T1 gate below, not spec


def _fails_on_rows(key, row):
    assert check_invariants({key: []})["status"] == "PASS"
    r = check_invariants({key: [row]})
    assert r["status"] == "FAIL" and any(key in i for i in r["issues"])


def test_cc1_warehouse_ytd_equals_district_sum():
    # Clause 3.3.2.1: W_YTD = SUM(D_YTD) per warehouse.
    _fails_on_rows("CC1", ["1"])


def test_cc2_next_order_id_matches_max_ids():
    # Clause 3.3.2.2: D_NEXT_O_ID - 1 = MAX(O_ID) = MAX(NO_O_ID) per district.
    _fails_on_rows("CC2", ["1", "5"])


def test_cc3_new_order_ids_have_no_gaps():
    # Clause 3.3.2.3: MAX(NO_O_ID) - MIN(NO_O_ID) + 1 = row count per district.
    _fails_on_rows("CC3", ["2", "3"])


def test_cc4_order_line_count_matches_order_totals():
    # Clause 3.3.2.4: SUM(O_OL_CNT) = ORDER_LINE row count per district.
    _fails_on_rows("CC4", ["1", "1"])


def test_cc5_carrier_null_iff_new_order_exists():
    # Clause 3.3.2.5: O_CARRIER_ID null/0 iff a NEW_ORDER row exists.
    _fails_on_rows("CC5", ["1", "2", "3050"])


def test_cc6_line_count_matches_per_order():
    # Clause 3.3.2.6 (sampled, recent window): O_OL_CNT = line count per order.
    _fails_on_rows("CC6", ["1", "2", "3012"])


def test_cc7_delivery_date_iff_carrier_set():
    # Clause 3.3.2.7 (sampled, recent window): OL_DELIVERY_D null iff
    # O_CARRIER_ID null/0.
    _fails_on_rows("CC7", ["1", "2", "3010"])


def test_cc8_warehouse_ytd_equals_history_sum():
    # Clause 3.3.2.8: W_YTD = SUM(H_AMOUNT) per warehouse.
    _fails_on_rows("CC8", ["2"])


def test_cc9_district_ytd_equals_history_sum():
    # Clause 3.3.2.9: D_YTD = SUM(H_AMOUNT) per district.
    _fails_on_rows("CC9", ["2", "4"])


def test_cc10_customer_balance_reconciles():
    # Clause 3.3.2.10: C_BALANCE = SUM(delivered OL_AMOUNT) - SUM(H_AMOUNT).
    _fails_on_rows("CC10", ["1", "1", "42"])


def test_cc12_balance_plus_payments_reconciles():
    # Clause 3.3.2.12: C_BALANCE + C_YTD_PAYMENT = SUM(delivered OL_AMOUNT).
    _fails_on_rows("CC12", ["1", "1", "42"])


def test_all_twelve_conditions_pass_together():
    # NOTE: CC11 (orders-minus-new_orders = 2100) is intentionally absent: it
    # holds at load only, since every delivery legitimately grows the gap.
    conds = {k: [] for k in
             ("CC1", "CC2", "CC3", "CC4", "CC5", "CC6",
              "CC7", "CC8", "CC9", "CC10", "CC12",
              "IR1", "IR2")}
    assert check_invariants(conds)["status"] == "PASS"


def test_ir1_duplicate_primary_key_fails():
    # Clause 1.5.1: PK values unique in every table (HISTORY exempt, no PK).
    r = check_invariants({"IR1": [["order_line"]]})
    assert r["status"] == "FAIL" and any("IR1" in i for i in r["issues"])


def test_ir2_ill_formed_row_fails():
    # Clause 1.5.2: no NULLs in required attributes.
    r = check_invariants({"IR2": [["customer"]]})
    assert r["status"] == "FAIL" and any("IR2" in i for i in r["issues"])


def test_missing_results_fail_closed():
    assert check_invariants({})["status"] == "FAIL"


def test_failed_query_fails_closed():
    assert check_invariants({"CC1": None})["status"] == "FAIL"


def test_warn_keys_downgrade_to_warn():
    # CC10/CC12 are WARN-grade: remote payments read one customer's row but
    # post to another's (shared PyTPCC quirk), so per-customer value equations
    # can break without any rewrite defect. Genuine omissions trip CC8/CC9.
    from tpcc_correctness import check_invariants as ci
    r = ci({"CC10": [["1", "2", "3"]]}, {"CC10"})
    assert r["status"] == "WARN" and any("CC10" in i for i in r["issues"])


def test_warn_keys_do_not_hide_real_failures():
    from tpcc_correctness import check_invariants as ci
    r = ci({"CC1": [["1"]], "CC10": [["2"]]}, {"CC10"})
    assert r["status"] == "FAIL"
    assert any("CC1 violated" in i for i in r["issues"])
    assert any("CC10" in i for i in r["issues"])


# Read-probe equivalence (hole-1 fix, not a spec clause): identical
# deterministic reads through baseline and rewrite code must return identical
# results. Read-only txns leave no post-hoc trace, so CC1-CC12 cannot see
# them lie — only side-by-side comparison can.
def _probes(*entries):
    return {"probes": [{"name": n, "result": r} for n, r in entries]}


def test_reads_identical_pass():
    doc = _probes(("stock_level:1:1:10", [3]), ("order_status_id:1:1:1", ["x"]))
    assert check_read_equivalence(doc, doc)["status"] == "PASS"


def test_reads_divergence_names_probe():
    base = _probes(("stock_level:1:1:10", [3]))
    arm = _probes(("stock_level:1:1:10", [4]))
    r = check_read_equivalence(base, arm)
    assert r["status"] == "FAIL" and any("stock_level:1:1:10" in i for i in r["issues"])


def test_reads_rewrite_error_fails():
    base = _probes(("stock_level:1:1:10", [3]))
    arm = {"probes": [{"name": "stock_level:1:1:10", "error": "TypeError: boom"}]}
    assert check_read_equivalence(base, arm)["status"] == "FAIL"


def test_reads_baseline_error_skips_probe():
    base = {"probes": [{"name": "stock_level:1:1:10", "error": "Exception: x"}]}
    arm = _probes(("stock_level:1:1:10", [3]))
    assert check_read_equivalence(base, arm)["status"] == "PASS"


def test_reads_missing_results_fail_closed():
    assert check_read_equivalence({}, {})["status"] == "FAIL"
    assert check_read_equivalence({"probes": []}, {})["status"] == "FAIL"


def test_normalize_kills_float_repr_noise():
    import datetime
    import decimal
    assert normalize_value(5537.360000000001) == normalize_value(5537.36)
    assert normalize_value(decimal.Decimal("10.50")) == 10.5
    assert normalize_value((1, 2)) == [1, 2]
    assert normalize_value(0) == normalize_value(0.0)


def test_normalize_datetime_to_spec_second_resolution():
    import datetime
    full = datetime.datetime(2026, 11, 3, 23, 1, 48, 25310)
    trunc = datetime.datetime(2026, 11, 3, 23, 1, 48)
    assert normalize_value(full) == normalize_value("2026-11-03T23:01:48.02531")
    assert normalize_value(full) == normalize_value(trunc)
    assert normalize_value("not a date") == "not a date"
    other = datetime.datetime(2026, 11, 3, 23, 1, 49)
    assert normalize_value(full) != normalize_value(other)


def test_reads_datetime_format_only_difference_passes():
    base = {"probes": [{"name": "p", "result": ["2026-11-03T23:01:48.025310"]}]}
    arm = {"probes": [{"name": "p", "result": ["2026-11-03T23:01:48.02531"]}]}
    assert check_read_equivalence(base, arm)["status"] == "PASS"


def test_sort_probe_lines_ignores_row_order():
    from tpcc_correctness import sort_probe_lines
    rows = ["cust", "order", [[1, "y"], [1, "x"]]]
    assert sort_probe_lines("doOrderStatus", rows)[2] == [[1, "x"], [1, "y"]]
    other = ["c", "o", [3, 1, 2]]
    assert sort_probe_lines("doStockLevel", other) == other


# T1 smoke-gate coverage (harness tier, not spec): failed-txn warnings above
# 1% of executed mean a failure storm, since the legitimate 1% invalid-item
# rollback path never warns.
_SMOKE_CSV = """transaction,executed,execution_time,transaction_rate
DELIVERY,100,1000.0,10.0
NEW_ORDER,1000,2000.0,20.0
ORDER_STATUS,100,500.0,30.0
PAYMENT,900,1500.0,40.0
STOCK_LEVEL,100,800.0,50.0
TOTAL,2200,5800.0,60.0
"""


def test_smoke_failure_storm_fails():
    log = "\n".join("WARNING: Failed to execute Transaction 'PAYMENT': x"
                    for _ in range(30))
    r = check_smoke(_SMOKE_CSV, log)
    assert r["status"] == "FAIL" and any("failure storm" in i for i in r["issues"])


def test_smoke_odd_warning_passes():
    log = "WARNING: Failed to execute Transaction 'PAYMENT': x\n"
    assert check_smoke(_SMOKE_CSV, log)["status"] == "PASS"


# T0 undefined-name gate (harness tier, not spec): typo-slips FAIL fast so a
# generate-verify-retry loop can reject broken rewrites without DB time.
_BASE = "new_orders = {}\n"


