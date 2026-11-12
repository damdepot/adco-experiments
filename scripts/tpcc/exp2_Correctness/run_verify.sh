#!/usr/bin/env bash
# Verify TPC-C app-layer rewrite arms (aco, adco, py-dbridge, naive-llm + baseline).
# Tiny single-client smoke per arm on the pristine seed, then static + smoke +
# TPC-C invariant checks via scripts/common/app_layer/exp2_Reports/tpcc_correctness.py.
# Writes results/tpcc/verify_<arm>.json (consumed by report.py). Never deletes
# real results: per-arm benchmark dirs are moved aside during the smoke run.
# VERIFY_REWRITE_ROOT=<repo-relative tree>: verify that tree under any arm name
# (used by the prompt-search winner gate); VERIFY_OUTPUT overrides the JSON path.
set -euo pipefail

export BENCH_SKIP_SETTLE="${BENCH_SKIP_SETTLE:-0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TREE_NAME="${TREE_NAME:-tpcc-NaiveLLM}"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

if [ "${BENCH_LOCK_HELD:-0}" != "1" ]; then
    bench_lock "${ROOT}"
fi
bench_timer "tpcc/run_verify" "results/tpcc" "run_verify"

DBMS="${1:-postgres}"
ARMS_CSV="${2:-baseline,aco,adco,py-dbridge,naive-llm,naive-llm-agenttune,agenttune-naive-llm}"
# Forgiving CLI: `./run_verify.sh aco` means "verify arm aco", not dbms=aco.
case "${DBMS}" in
    postgres|mysql) ;;
    *)
        if [ -z "${2:-}" ]; then
            ARMS_CSV="${DBMS}"
            DBMS="postgres"
        else
            echo "Usage: $0 [dbms] [arm,...] (dbms must be postgres|mysql, got '${DBMS}')" >&2
            exit 2
        fi
        ;;
esac
model="${MODEL:-gemini-3.5-flash-lite}"
SEED_DB_TPCC="tpcc_seed"
DB="tpcc"
VERIFY_SEED_DB="${VERIFY_SEED_DB:-$SEED_DB_TPCC}"
VERIFY_WAREHOUSES="${VERIFY_WAREHOUSES:-$TPCC_WAREHOUSES}"
echo "----------------->> Verify seed/scale: seed='${VERIFY_SEED_DB}' warehouses='${VERIFY_WAREHOUSES}' <<-----------------"
CHECKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tpcc_correctness.py"
BASELINE_DRIVER="${ROOT}/workload/apps/tpcc/drivers/postgresdriver.py"

# bench_ensure_seed loads the seed via BENCH_CMDRUNTPCC (bench_lib default points
# at a nonexistent scripts/_lib/tpcc.sh); point it at the canonical DB runner.
export BENCH_CMDRUNTPCC="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"

# Bound libpq connects: a DB that is still restarting must fail, not block.
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
# Never let a restore/check query wait forever on a lock or a stalled server.
export PGOPTIONS="${PGOPTIONS:--c statement_timeout=300000 -c lock_timeout=60000}"

# Tiny-scale smoke on the existing seed (same scale as full runs; reseeding at a
# smaller scale would destroy the shared seed). Warmup off, one rep.
export VERIFY_DURATION="${VERIFY_DURATION:-20}"
export TPCC_CLIENTS=1 TPCC_DURATION="${VERIFY_DURATION:-20}" REPS=1 TPCC_WARMUP=0 PHASE=execute

# A caller holding the benchmark lock (search/robustness orchestrators) has
# already ensured and asserted the seed; skip the redundant Docker/psql probe.
if [ "${VERIFY_SKIP_SEED:-0}" != "1" ] && [ "${BENCH_LOCK_HELD:-0}" != "1" ]; then
    echo "----------------->> Seed tpcc (reuse snapshot) <<-----------------"
    bench_ensure_seed "${DB}" "${VERIFY_SEED_DB}"
    bench_assert_seed "${VERIFY_SEED_DB}"
else
    echo "----------------->> Seed tpcc: parent ensured; per-run restore follows <<-----------------"
fi

# Per-arm: runner script | runner args | rewrite driver | smoke CSV (REPS=1 paths).
# With VERIFY_REWRITE_ROOT set, any arm name maps to that Naive-LLM-style tree.
arm_spec() {
    if [ -n "${VERIFY_REWRITE_ROOT:-}" ]; then
        echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh|${DBMS} ${VERIFY_WAREHOUSES} 1 tpcc ${1} ${VERIFY_REWRITE_ROOT}|${ROOT}/${VERIFY_REWRITE_ROOT}/Rewrite/${DBMS}/${TREE_NAME}/drivers/postgresdriver.py|${VERIFY_CSV}"
        return 0
    fi
    case "$1" in
        baseline) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-App.sh|${DBMS}|${BASELINE_DRIVER}|results/tpcc/baseline/benchmarks/runExperiment1-tpcc-${DBMS}" ;;
        aco) echo "scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh|${model} ${DBMS} ${TPCC_WAREHOUSES} 1 tpcc aco|${ROOT}/out/app_layer/ACo-results/Rewrite/${DBMS}/tpcc-${model}/drivers/postgresdriver.py|results/tpcc/aco/benchmarks/aco.csv" ;;
        adco) echo "scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh|${model} ${DBMS} ${TPCC_WAREHOUSES} 1 tpcc adco|${ROOT}/out/app_layer/ADCo-results/Rewrite/${DBMS}/tpcc-${model}/drivers/postgresdriver.py|results/tpcc/adco/benchmarks/adco.csv" ;;
        py-dbridge) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Py-DBridge.sh|${DBMS} ${TPCC_WAREHOUSES} 1 tpcc|${ROOT}/out/app_layer/Py-DBridge-results/Rewrite/${DBMS}/tpcc-Py-DBridge/drivers/postgresdriver.py|results/tpcc/py-dbridge/benchmarks/py-dbridge.csv" ;;
        naive-llm) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh|${DBMS} ${TPCC_WAREHOUSES} 1 tpcc|${ROOT}/out/app_layer/NaiveLLM-results/Rewrite/${DBMS}/tpcc-NaiveLLM/drivers/postgresdriver.py|results/tpcc/naive-llm/benchmarks/naive-llm.csv" ;;
        naive-llm-agenttune) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh|${DBMS} ${TPCC_WAREHOUSES} 1 tpcc naive-llm-agenttune out/app_layer/NaiveLLM-results/naive-llm-agenttune|${ROOT}/out/app_layer/NaiveLLM-results/naive-llm-agenttune/Rewrite/${DBMS}/tpcc-NaiveLLM/drivers/postgresdriver.py|results/tpcc/naive-llm-agenttune/benchmarks/naive-llm-agenttune.csv" ;;
        agenttune-naive-llm) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh|${DBMS} ${TPCC_WAREHOUSES} 1 tpcc agenttune-naive-llm out/app_layer/NaiveLLM-results/agenttune-naive-llm|${ROOT}/out/app_layer/NaiveLLM-results/agenttune-naive-llm/Rewrite/${DBMS}/tpcc-NaiveLLM/drivers/postgresdriver.py|results/tpcc/agenttune-naive-llm/benchmarks/agenttune-naive-llm.csv" ;;
        *) echo "UNKNOWN" ;;
    esac
}

CC1_SQL="SELECT w.w_id FROM warehouse w JOIN (SELECT d_w_id, SUM(d_ytd) AS s FROM district GROUP BY 1) s ON s.d_w_id = w.w_id WHERE ABS(w.w_ytd - s.s) > 0.01;"
CC2_SQL="SELECT d.d_w_id, d.d_id FROM district d WHERE d.d_next_o_id - 1 <> (SELECT MAX(o.o_id) FROM orders o WHERE o.o_w_id = d.d_w_id AND o.o_d_id = d.d_id) OR (EXISTS (SELECT 1 FROM new_order n WHERE n.no_w_id = d.d_w_id AND n.no_d_id = d.d_id) AND (SELECT MAX(o.o_id) FROM orders o WHERE o.o_w_id = d.d_w_id AND o.o_d_id = d.d_id) <> (SELECT MAX(n.no_o_id) FROM new_order n WHERE n.no_w_id = d.d_w_id AND n.no_d_id = d.d_id));"
CC3_SQL="SELECT no_w_id, no_d_id FROM (SELECT no_w_id, no_d_id, MAX(no_o_id) - MIN(no_o_id) + 1 AS rng, COUNT(*) AS cnt FROM new_order GROUP BY 1, 2) s WHERE rng <> cnt;"
CC6_SQL="SELECT o.o_w_id, o.o_d_id, o.o_id FROM orders o JOIN district d ON d.d_w_id = o.o_w_id AND d.d_id = o.o_d_id WHERE o.o_id > d.d_next_o_id - 500 AND o.o_ol_cnt <> (SELECT COUNT(*) FROM order_line ol WHERE ol.ol_w_id = o.o_w_id AND ol.ol_d_id = o.o_d_id AND ol.ol_o_id = o.o_id);"
# Spec Clause 3.3 additions (official consistency conditions CC1-CC12;
# CC6/CC7 run on a recent-orders window, the rest are full checks). Money comparisons use 0.01: PyTPCC passes
# Python floats for exact-numeric columns, leaving ~1e-9 noise; real bugs are
# dollars. Carrier sentinel: PyTPCC stores 0 (NULL_CARRIER_ID), not SQL NULL,
# so CC5/CC7 match on COALESCE(carrier,0)=0; NULL and 0 both mean undelivered.
CC4_SQL="SELECT d.d_w_id, d.d_id FROM district d WHERE (SELECT COALESCE(SUM(o.o_ol_cnt),0) FROM orders o WHERE o.o_w_id = d.d_w_id AND o.o_d_id = d.d_id) <> (SELECT COUNT(*) FROM order_line ol WHERE ol.ol_w_id = d.d_w_id AND ol.ol_d_id = d.d_id);"
CC5_SQL="SELECT o.o_w_id, o.o_d_id, o.o_id FROM orders o WHERE (COALESCE(o.o_carrier_id,0) = 0) <> (EXISTS (SELECT 1 FROM new_order n WHERE n.no_w_id = o.o_w_id AND n.no_d_id = o.o_d_id AND n.no_o_id = o.o_id)) LIMIT 100;"
CC7_SQL="SELECT o.o_w_id, o.o_d_id, o.o_id FROM orders o JOIN district d ON d.d_w_id = o.o_w_id AND d.d_id = o.o_d_id WHERE o.o_id > d.d_next_o_id - 500 AND EXISTS (SELECT 1 FROM order_line ol WHERE ol.ol_w_id = o.o_w_id AND ol.ol_d_id = o.o_d_id AND ol.ol_o_id = o.o_id AND ol.ol_delivery_d IS NULL) AND EXISTS (SELECT 1 FROM order_line ol WHERE ol.ol_w_id = o.o_w_id AND ol.ol_d_id = o.o_d_id AND ol.ol_o_id = o.o_id AND ol.ol_delivery_d IS NOT NULL) LIMIT 100;"
CC8_SQL="SELECT w.w_id FROM warehouse w WHERE ABS(w.w_ytd - (SELECT COALESCE(SUM(h.h_amount),0) FROM history h WHERE h.h_w_id = w.w_id)) > 0.01;"
CC9_SQL="SELECT d.d_w_id, d.d_id FROM district d WHERE ABS(d.d_ytd - (SELECT COALESCE(SUM(h.h_amount),0) FROM history h WHERE h.h_w_id = d.d_w_id AND h.h_d_id = d.d_id)) > 0.01;"
# CC10/CC12 (Clauses 3.3.2.10/12) on a deterministic customer sample (~1/150):
# "delivered" means carrier<>0, NOT delivery_d NOT NULL: PyTPCC stamps the
# entry timestamp as delivery_d at order creation (baseline driver line ~355),
# so dates cannot distinguish delivered lines — only the carrier flag can.
# These two are WARN-grade, not FAIL-grade (see --warn-keys below): remote
# payments read one customer's row but post to another's (reads use
# entry-district keys, writes use home keys — shared PyTPCC quirk, proven by
# statement-log forensics), so per-customer value equations can break without
# any rewrite defect. Genuine omissions ALWAYS trip the global CC8/CC9 sums
# too, so: CC10/CC12-alone means quirk-suspect; CC10/CC12 plus CC8/CC9 means
# real defect (aggregate FAILs on CC8/CC9 regardless).
CC10_SQL="SELECT c.c_w_id, c.c_d_id, c.c_id FROM customer c WHERE (c.c_w_id * 1000000 + c.c_d_id * 10000 + c.c_id) % 150 = 42 AND ABS(c.c_balance - (COALESCE((SELECT SUM(ol.ol_amount) FROM orders o JOIN order_line ol ON ol.ol_w_id = o.o_w_id AND ol.ol_d_id = o.o_d_id AND ol.ol_o_id = o.o_id WHERE o.o_w_id = c.c_w_id AND o.o_d_id = c.c_d_id AND o.o_c_id = c.c_id AND COALESCE(o.o_carrier_id,0) <> 0),0) - COALESCE((SELECT SUM(h.h_amount) FROM history h WHERE h.h_c_w_id = c.c_w_id AND h.h_c_d_id = c.c_d_id AND h.h_c_id = c.c_id),0))) > 0.01 LIMIT 100;"
CC12_SQL="SELECT c.c_w_id, c.c_d_id, c.c_id FROM customer c WHERE (c.c_w_id * 1000000 + c.c_d_id * 10000 + c.c_id) % 150 = 42 AND ABS(c.c_balance + c.c_ytd_payment - COALESCE((SELECT SUM(ol.ol_amount) FROM orders o JOIN order_line ol ON ol.ol_w_id = o.o_w_id AND ol.ol_d_id = o.o_d_id AND ol.ol_o_id = o.o_id WHERE o.o_w_id = c.c_w_id AND o.o_d_id = c.c_d_id AND o.o_c_id = c.c_id AND COALESCE(o.o_carrier_id,0) <> 0),0)) > 0.01 LIMIT 100;"
# Spec Clause 1.5 integrity rules. The schema enforces PK/NOT NULL, so these
# are belt-and-braces: a rewrite cannot break them without DDL changes, but a
# violation would mean silent corruption. HISTORY has no PK per spec (exempt).
IR1_SQL="SELECT 'warehouse' WHERE EXISTS (SELECT 1 FROM warehouse GROUP BY w_id HAVING COUNT(*) > 1) UNION ALL SELECT 'district' WHERE EXISTS (SELECT 1 FROM district GROUP BY d_w_id, d_id HAVING COUNT(*) > 1) UNION ALL SELECT 'customer' WHERE EXISTS (SELECT 1 FROM customer GROUP BY c_w_id, c_d_id, c_id HAVING COUNT(*) > 1) UNION ALL SELECT 'stock' WHERE EXISTS (SELECT 1 FROM stock GROUP BY s_w_id, s_i_id HAVING COUNT(*) > 1) UNION ALL SELECT 'orders' WHERE EXISTS (SELECT 1 FROM orders GROUP BY o_w_id, o_d_id, o_id HAVING COUNT(*) > 1) UNION ALL SELECT 'new_order' WHERE EXISTS (SELECT 1 FROM new_order GROUP BY no_w_id, no_d_id, no_o_id HAVING COUNT(*) > 1) UNION ALL SELECT 'order_line' WHERE EXISTS (SELECT 1 FROM order_line GROUP BY ol_w_id, ol_d_id, ol_o_id, ol_number HAVING COUNT(*) > 1) UNION ALL SELECT 'item' WHERE EXISTS (SELECT 1 FROM item GROUP BY i_id HAVING COUNT(*) > 1);"
IR2_SQL="SELECT 'warehouse' WHERE EXISTS (SELECT 1 FROM warehouse WHERE w_ytd IS NULL) UNION ALL SELECT 'district' WHERE EXISTS (SELECT 1 FROM district WHERE d_ytd IS NULL OR d_next_o_id IS NULL) UNION ALL SELECT 'customer' WHERE EXISTS (SELECT 1 FROM customer WHERE c_balance IS NULL OR c_ytd_payment IS NULL) UNION ALL SELECT 'stock' WHERE EXISTS (SELECT 1 FROM stock WHERE s_quantity IS NULL OR s_ytd IS NULL) UNION ALL SELECT 'orders' WHERE EXISTS (SELECT 1 FROM orders WHERE o_ol_cnt IS NULL OR o_c_id IS NULL) UNION ALL SELECT 'order_line' WHERE EXISTS (SELECT 1 FROM order_line WHERE ol_amount IS NULL OR ol_quantity IS NULL OR ol_i_id IS NULL) UNION ALL SELECT 'item' WHERE EXISTS (SELECT 1 FROM item WHERE i_price IS NULL) UNION ALL SELECT 'history' WHERE EXISTS (SELECT 1 FROM history WHERE h_amount IS NULL OR h_date IS NULL);"

verify_one_arm() {
    local arm="$1"
    local out="${VERIFY_OUTPUT:-results/tpcc/verify_${arm}.json}"
    local out_stem="${out%.json}"
    if [ "${REVERIFY:-0}" != "1" ] && [ -f "${out}" ] && [ -z "$(find "${out}" -mmin +1440 2>/dev/null)" ]; then
        echo "----------------->> ${arm}: skipped (fresh ${out}) <<-----------------"
        return 0
    fi

    local spec runner rargs driver csv bdir bak tmp inv_json smoke_csv
    spec="$(arm_spec "${arm}")"
    if [ "${spec}" = "UNKNOWN" ]; then
        echo "WARNING: unknown arm '${arm}'; skipping." >&2
        return 0
    fi
    runner="${spec%%|*}"; rest="${spec#*|}"
    rargs="${rest%%|*}"; rest="${rest#*|}"
    driver="${rest%%|*}"; csv="${rest#*|}"
    if [ -z "${csv}" ]; then
        echo "ERROR: no smoke CSV for arm '${arm}'; set VERIFY_CSV in tree mode." >&2
        return 1
    fi
    bdir="$(dirname "${csv}")"

    if [ "${arm}" != "baseline" ] && [ ! -f "${driver}" ]; then
        echo "----------------->> ${arm}: UNVERIFIED (no rewrite at ${driver}) <<-----------------"
        printf '{"arm": "%s", "status": "UNVERIFIED", "checks": {}}\n' "${arm}" >"${out}"
        return 0
    fi

    bench_verify_arm "${arm}" "${DB}" "${VERIFY_SEED_DB}" "${VERIFY_WAREHOUSES}"

    # Pristine-state canary: a restore must yield loader-fresh data (d_next =
    # 3001 everywhere, one history row per customer). A silent restore failure
    # would otherwise measure layered dirty state and blame the rewrite.
    if [ "$(psql -d "${DB}" -tA -c "SELECT count(*) FROM district WHERE d_next_o_id <> 3001;" 2>/dev/null)" != "0" ]; then
        echo "ERROR: non-pristine '${DB}' after restore (d_next_o_id already advanced); refusing to measure." >&2
        return 1
    fi
    if [ "$(psql -d "${DB}" -tA -c "SELECT count(*) FROM history;" 2>/dev/null)" != "$((30000 * VERIFY_WAREHOUSES))" ]; then
        echo "ERROR: non-pristine '${DB}' after restore (history count off); refusing to measure." >&2
        return 1
    fi

    # Move real results aside so the smoke run cannot clobber them.
    bak=""
    if [ -d "${bdir}" ]; then
        bak="${bdir}.verify-bak"
        rm -rf "${bak}"
        mv "${bdir}" "${bak}"
    fi
    mkdir -p "${bdir}"
    # Generic tree mode passes an absolute VERIFY_CSV while the runner writes
    # under BENCH_RESULTS_DIR, which is not necessarily the CSV's directory.
    if [ -n "${BENCH_RESULTS_DIR:-}" ]; then
        mkdir -p "${BENCH_RESULTS_DIR}"
    fi
    tmp="$(mktemp -d)"
    # RP — read-probe equivalence: identical deterministic reads (ORDER_STATUS,
    # STOCK_LEVEL) through baseline and rewrite code on this same snapshot.
    probe_base="${tmp}/probe_base.json"
    probe_arm="${tmp}/probe_arm.json"
    VENV_PY="${ROOT}/workload/apps/tpcc/venv/bin/python"
    [ -x "${VENV_PY}" ] || VENV_PY="python3"
    PROBE="${ROOT}/scripts/tpcc/exp2_Correctness/read_probe.py"
    DBCONFIG="${ROOT}/workload/apps/tpcc/db.config"
    echo "----------------->> ${arm}: read-probe equivalence <<-----------------"
    (cd "${ROOT}/workload/apps/tpcc" && timeout "${PROBE_TIMEOUT:-120}" "${VENV_PY}" "${PROBE}" --dbms "${DBMS}" --config "${DBCONFIG}" >"${probe_base}" 2>"${tmp}/probe_base.err") || echo "WARNING: baseline read probe failed for '${arm}'." >&2
    if [ "${arm}" = "baseline" ]; then
        cp "${probe_base}" "${probe_arm}" 2>/dev/null || : >"${probe_arm}"
    else
        arm_tree="$(cd "$(dirname "${driver}")/.." && pwd)"
        (cd "${arm_tree}" && timeout "${PROBE_TIMEOUT:-120}" "${VENV_PY}" "${PROBE}" --dbms "${DBMS}" --config "${DBCONFIG}" >"${probe_arm}" 2>"${tmp}/probe_arm.err") || echo "WARNING: rewrite read probe failed for '${arm}'." >&2
    fi
    echo "----------------->> ${arm}: smoke (${VERIFY_DURATION:-20}s, 1 client) <<-----------------"
    # shellcheck disable=SC2086
    timeout "$(( ${VERIFY_DURATION:-20} + 240 ))" ./"${runner}" ${rargs} >"${tmp}/smoke.log" 2>&1 || echo "WARNING: smoke run failed for '${arm}' (see ${out})." >&2
    smoke_csv="${csv}"
    if [ ! -f "${smoke_csv}" ] && [ -n "${BENCH_RESULTS_DIR:-}" ]; then
        smoke_csv="${BENCH_RESULTS_DIR}/$(basename "${csv}")"
    fi
    [ -f "${smoke_csv}" ] && cp "${smoke_csv}" "${tmp}/smoke.csv" || : >"${tmp}/smoke.csv"
    cp "${tmp}/smoke.log" "${tmp}/smoke.log.keep" 2>/dev/null || true

    # Official consistency conditions (Spec Clause 3.3) on post-smoke state.
    echo "----------------->> ${arm}: consistency conditions + verdict <<-----------------"
    # CC6/CC7 run on a recent-orders window and CC10/CC12 on a deterministic
    # customer sample; the rest are full checks. CC11 is intentionally absent:
    # every delivery legitimately grows orders-minus-new_orders, so it only
    # holds at load time, never after a workload run.
    psql -d "${DB}" -tA -F'|' -c "${CC1_SQL}" >"${tmp}/CC1.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC1.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC2_SQL}" >"${tmp}/CC2.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC2.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC3_SQL}" >"${tmp}/CC3.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC3.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC6_SQL}" >"${tmp}/CC6.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC6.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC4_SQL}" >"${tmp}/CC4.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC4.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC5_SQL}" >"${tmp}/CC5.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC5.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC7_SQL}" >"${tmp}/CC7.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC7.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC8_SQL}" >"${tmp}/CC8.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC8.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC9_SQL}" >"${tmp}/CC9.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC9.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC10_SQL}" >"${tmp}/CC10.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC10.txt"
    psql -d "${DB}" -tA -F'|' -c "${CC12_SQL}" >"${tmp}/CC12.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/CC12.txt"
    psql -d "${DB}" -tA -F'|' -c "${IR1_SQL}" >"${tmp}/IR1.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/IR1.txt"
    psql -d "${DB}" -tA -F'|' -c "${IR2_SQL}" >"${tmp}/IR2.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/IR2.txt"

    # Restore real results before writing anything (but keep this run's
    # smoke CSV as evidence alongside the verdict JSON — after the restore,
    # since the verdict dir itself may be the dir moved aside above).
    rm -rf "${bdir}"
    if [ -n "${bak}" ]; then
        mv "${bak}" "${bdir}"
    else
        rmdir "${bdir}" 2>/dev/null || true
    fi
    cp "${tmp}/smoke.csv" "${out_stem}.smoke.csv" 2>/dev/null || true

    python3 - "${tmp}" "${tmp}/invariants.json" <<'PY'
import json, sys
tmp, dest = sys.argv[1], sys.argv[2]
conds = {}
for c in ("CC1", "CC2", "CC3", "CC6", "CC4", "CC5", "CC7", "CC8", "CC9", "CC10", "CC12", "IR1", "IR2"):
    try:
        with open(f"{tmp}/{c}.txt") as f:
            body = f.read().strip()
    except OSError:
        conds[c] = None
        continue
    conds[c] = None if body == "__QUERY_FAILED__" else [ln for ln in body.splitlines() if ln.strip()]
with open(dest, "w") as f:
    json.dump(conds, f)
PY
    inv_json="${tmp}/invariants.json"

    set +e
    python3 "${CHECKER}" --arm "${arm}" --csv "${tmp}/smoke.csv" --log "${tmp}/smoke.log.keep" \
        --source "${driver}" --baseline-source "${BASELINE_DRIVER}" \
        --invariants "${inv_json}" --warn-keys "CC10,CC12" \
        --probe-baseline "${probe_base}" --probe-arm "${probe_arm}" \
        --output "${out}"
    rc=$?
    set -e
    # Keep the smoke log next to the verdict for post-mortems (tmp goes away).
    cp "${tmp}/smoke.log.keep" "${out_stem}.smoke.log" 2>/dev/null || true
    rm -rf "${tmp}"
    [ "${rc}" -eq 0 ]
}

overall=0
IFS=',' read -ra ARM_LIST <<<"${ARMS_CSV}"
for arm in "${ARM_LIST[@]}"; do
    arm="$(echo "${arm}" | tr -d '[:space:]')"
    [ -z "${arm}" ] && continue
    if ! verify_one_arm "${arm}"; then
        overall=1
    fi
done
echo "----------------->> Verify done (statuses in results/tpcc/verify_*.json) <<-----------------"
exit "${overall}"
