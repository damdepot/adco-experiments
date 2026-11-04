#!/usr/bin/env bash
# Verify TPC-C app-layer rewrite arms (aco, adco, py-dbridge, naive-llm + baseline).
# Tiny single-client smoke per arm on the pristine seed, then static + smoke +
# TPC-C invariant checks via scripts/common/app_layer/exp2_Reports/tpcc_correctness.py.
# Writes results/tpcc/verify_<arm>.json (consumed by report.py). Never deletes
# real results: per-arm benchmark dirs are moved aside during the smoke run.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

bench_lock "${ROOT}"
bench_timer "tpcc/run_verify" "results/tpcc" "run_verify"

DBMS="${1:-postgres}"
ARMS_CSV="${2:-baseline,aco,adco,py-dbridge,naive-llm}"
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
CHECKER="${ROOT}/scripts/common/app_layer/exp2_Reports/tpcc_correctness.py"
BASELINE_DRIVER="${ROOT}/workload/apps/tpcc/drivers/postgresdriver.py"

# bench_ensure_seed loads the seed via BENCH_CMDRUNTPCC (bench_lib default points
# at a nonexistent scripts/_lib/tpcc.sh); point it at the canonical DB runner.
export BENCH_CMDRUNTPCC="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"

# Tiny-scale smoke on the existing seed (same scale as full runs; reseeding at a
# smaller scale would destroy the shared seed). Warmup off, one rep.
export TPCC_CLIENTS=1 TPCC_DURATION="${VERIFY_DURATION:-20}" REPS=1 TPCC_WARMUP=0 PHASE=execute

echo "----------------->> Seed tpcc (reuse snapshot) <<-----------------"
bench_ensure_seed "${DB}" "${SEED_DB_TPCC}"
bench_assert_seed "${SEED_DB_TPCC}"

# Per-arm: runner script | runner args | rewrite driver | smoke CSV (REPS=1 paths).
arm_spec() {
    case "$1" in
        baseline) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-App.sh|${DBMS}|${BASELINE_DRIVER}|results/tpcc/baseline/benchmarks/runExperiment1-tpcc-${DBMS}" ;;
        aco) echo "scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh|${model} ${DBMS} ${TPCC_WAREHOUSES} 1 tpcc aco|${ROOT}/out/app_layer/ACo-results/Rewrite/${DBMS}/tpcc-${model}/drivers/postgresdriver.py|results/tpcc/aco/benchmarks/aco.csv" ;;
        adco) echo "scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh|${model} ${DBMS} ${TPCC_WAREHOUSES} 1 tpcc adco|${ROOT}/out/app_layer/ADCo-results/Rewrite/${DBMS}/tpcc-${model}/drivers/postgresdriver.py|results/tpcc/adco/benchmarks/adco.csv" ;;
        py-dbridge) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Py-DBridge.sh|${DBMS} ${TPCC_WAREHOUSES} 1 tpcc|${ROOT}/out/app_layer/Py-DBridge-results/Rewrite/${DBMS}/tpcc-Py-DBridge/drivers/postgresdriver.py|results/tpcc/py-dbridge/benchmarks/py-dbridge.csv" ;;
        naive-llm) echo "scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh|${DBMS} ${TPCC_WAREHOUSES} 1 tpcc|${ROOT}/out/app_layer/NaiveLLM-results/Rewrite/${DBMS}/tpcc-NaiveLLM/drivers/postgresdriver.py|results/tpcc/naive-llm/benchmarks/naive-llm.csv" ;;
        *) echo "UNKNOWN" ;;
    esac
}

C1_SQL="SELECT w.w_id FROM warehouse w JOIN (SELECT d_w_id, SUM(d_ytd) AS s FROM district GROUP BY 1) s ON s.d_w_id = w.w_id WHERE ABS(w.w_ytd - s.s) > 0.01;"
C2_SQL="SELECT d_w_id, d_id FROM district d WHERE d_next_o_id - 1 <> (SELECT MAX(o_id) FROM orders WHERE o_w_id = d.d_w_id AND o_d_id = d.d_id);"
C3_SQL="SELECT no_w_id, no_d_id FROM (SELECT no_w_id, no_d_id, MAX(no_o_id) - MIN(no_o_id) + 1 AS rng, COUNT(*) AS cnt FROM new_order GROUP BY 1, 2) s WHERE rng <> cnt;"
C5_SQL="SELECT o.o_w_id, o.o_d_id, o.o_id FROM orders o JOIN district d ON d.d_w_id = o.o_w_id AND d.d_id = o.o_d_id WHERE o.o_id > d.d_next_o_id - 500 AND o.o_ol_cnt <> (SELECT COUNT(*) FROM order_line ol WHERE ol.ol_w_id = o.o_w_id AND ol.ol_d_id = o.o_d_id AND ol.ol_o_id = o.o_id);"

verify_one_arm() {
    local arm="$1"
    local out="results/tpcc/verify_${arm}.json"
    if [ "${REVERIFY:-0}" != "1" ] && [ -f "${out}" ] && [ -z "$(find "${out}" -mmin +1440 2>/dev/null)" ]; then
        echo "----------------->> ${arm}: skipped (fresh ${out}) <<-----------------"
        return 0
    fi

    local spec runner rargs driver csv bdir bak tmp inv_json
    spec="$(arm_spec "${arm}")"
    if [ "${spec}" = "UNKNOWN" ]; then
        echo "WARNING: unknown arm '${arm}'; skipping." >&2
        return 0
    fi
    runner="${spec%%|*}"; rest="${spec#*|}"
    rargs="${rest%%|*}"; rest="${rest#*|}"
    driver="${rest%%|*}"; csv="${rest#*|}"
    bdir="$(dirname "${csv}")"

    if [ "${arm}" != "baseline" ] && [ ! -f "${driver}" ]; then
        echo "----------------->> ${arm}: UNVERIFIED (no rewrite at ${driver}) <<-----------------"
        printf '{"arm": "%s", "status": "UNVERIFIED", "checks": {}}\n' "${arm}" >"${out}"
        return 0
    fi

    bench_verify_arm "${arm}" "${DB}" "${SEED_DB_TPCC}" "${TPCC_WAREHOUSES}"

    # C4 needs the HISTORY delta: the seed already holds one HISTORY row per
    # customer (loader-inserted), so only growth during smoke must equal PAYMENTs.
    history_before="$(psql -d "${DB}" -tA -c "SELECT count(*) FROM history;" 2>/dev/null || echo "")"

    # Move real results aside so the smoke run cannot clobber them.
    bak=""
    if [ -d "${bdir}" ]; then
        bak="${bdir}.verify-bak"
        rm -rf "${bak}"
        mv "${bdir}" "${bak}"
    fi
    mkdir -p "${bdir}"
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2086
    ./"${runner}" ${rargs} >"${tmp}/smoke.log" 2>&1 || echo "WARNING: smoke run failed for '${arm}' (see ${out})." >&2
    [ -f "${csv}" ] && cp "${csv}" "${tmp}/smoke.csv" || : >"${tmp}/smoke.csv"
    cp "${tmp}/smoke.log" "${tmp}/smoke.log.keep" 2>/dev/null || true

    # TPC-C invariants on the post-smoke DB state.
    psql -d "${DB}" -tA -F'|' -c "${C1_SQL}" >"${tmp}/C1.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/C1.txt"
    psql -d "${DB}" -tA -F'|' -c "${C2_SQL}" >"${tmp}/C2.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/C2.txt"
    psql -d "${DB}" -tA -F'|' -c "${C3_SQL}" >"${tmp}/C3.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/C3.txt"
    psql -d "${DB}" -tA -F'|' -c "${C5_SQL}" >"${tmp}/C5.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/C5.txt"
    history_after="$(psql -d "${DB}" -tA -c "SELECT count(*) FROM history;" 2>/dev/null || echo "")"
    history_count=""
    if [[ "${history_before}" =~ ^[0-9]+$ ]] && [[ "${history_after}" =~ ^[0-9]+$ ]]; then
        history_count=$((history_after - history_before))
    fi
    payment_executed="$(awk -F, '$1=="PAYMENT" {print int($2)}' "${tmp}/smoke.csv" 2>/dev/null || echo "")"

    # Restore real results before writing anything.
    rm -rf "${bdir}"
    if [ -n "${bak}" ]; then
        mv "${bak}" "${bdir}"
    else
        rmdir "${bdir}" 2>/dev/null || true
    fi

    python3 - "${tmp}" "${tmp}/invariants.json" <<'PY'
import json, sys
tmp, dest = sys.argv[1], sys.argv[2]
conds = {}
for c in ("C1", "C2", "C3", "C5"):
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
    if [ -n "${history_count}" ] && [ -n "${payment_executed}" ]; then
        python3 "${CHECKER}" --arm "${arm}" --csv "${tmp}/smoke.csv" --log "${tmp}/smoke.log.keep" \
            --source "${driver}" --baseline-source "${BASELINE_DRIVER}" \
            --invariants "${inv_json}" --history-count "${history_count}" \
            --payment-executed "${payment_executed}" --output "${out}"
    else
        python3 "${CHECKER}" --arm "${arm}" --csv "${tmp}/smoke.csv" --log "${tmp}/smoke.log.keep" \
            --source "${driver}" --baseline-source "${BASELINE_DRIVER}" \
            --invariants "${inv_json}" --output "${out}"
    fi
    rc=$?
    set -e
    # Keep the smoke log next to the verdict for post-mortems (tmp goes away).
    cp "${tmp}/smoke.log.keep" "results/tpcc/verify_${arm}.smoke.log" 2>/dev/null || true
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
