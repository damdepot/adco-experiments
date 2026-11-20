#!/usr/bin/env bash
# Verify SmallBank app-layer rewrite arms (baseline, naive-llm, aco, adco,
# py-dbridge). Tiny single-client smoke per arm on the verify seed
# (smallbank_verify_seed at SMALLBANK_VERIFY_ACCOUNTS, default 100000), then
# static + smoke + SmallBank invariant checks + BALANCE read equivalence via
# scripts/smallbank/exp2_Correctness/smallbank_correctness.py.
# Writes results/smallbank/verify_<arm>.json (consumed by report.py). Never
# deletes real results: per-arm benchmark dirs are moved aside during the smoke
# run and restored afterwards.
# VERIFY_REWRITE_ROOT=<repo-relative tree>: verify that tree under any arm name
# (used by the robustness harness); VERIFY_OUTPUT overrides the JSON path.
# The performance seed 'smallbank_seed' is refused unless VERIFY_ALLOW_PERF_SEED=1
# (full-scale robustness only).
set -euo pipefail

export BENCH_SKIP_SETTLE="${BENCH_SKIP_SETTLE:-0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TREE_NAME="${TREE_NAME:-smallbank-NaiveLLM}"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

if [ "${BENCH_LOCK_HELD:-0}" != "1" ]; then
    bench_lock "${ROOT}"
fi
bench_timer "smallbank/run_verify" "results/smallbank" "run_verify"

DBMS="${1:-postgres}"
ARMS_CSV="${2:-baseline,naive-llm,naive-llm-agenttune,agenttune-naive-llm,aco,adco,py-dbridge}"
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
SEED_DB_SMALLBANK="smallbank_seed"
DB="smallbank"
VERIFY_SEED_DB="${VERIFY_SEED_DB:-smallbank_verify_seed}"
if [ "${VERIFY_SEED_DB}" = "${SEED_DB_SMALLBANK}" ] && [ "${VERIFY_ALLOW_PERF_SEED:-0}" != "1" ]; then
    echo "ERROR: refusing VERIFY_SEED_DB='${SEED_DB_SMALLBANK}': verification must not reuse the performance seed (set VERIFY_ALLOW_PERF_SEED=1 for full-scale robustness)." >&2
    exit 2
fi
VERIFY_ACCOUNTS="${VERIFY_ACCOUNTS:-${SMALLBANK_VERIFY_ACCOUNTS:-100000}}"
VERIFY_DURATION="${VERIFY_DURATION:-20}"
VERIFY_WARMUP="${VERIFY_WARMUP:-0}"
echo "----------------->> Verify seed/scale: seed='${VERIFY_SEED_DB}' accounts='${VERIFY_ACCOUNTS}' duration='${VERIFY_DURATION}s' warmup='${VERIFY_WARMUP}s' <<-----------------"
CHECKER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/smallbank_correctness.py"
BASELINE_DRIVER="${ROOT}/workload/apps/smallbank/drivers/postgresdriver.py"

# bench_ensure_seed loads via BENCH_CMDRUNTPCC (bench_lib's default points at a
# nonexistent scripts/_lib/tpcc.sh); point it at the canonical DB runner.
export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Db.sh"

# Bound libpq connects: a DB that is still restarting must fail, not block.
export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"
# Never let a restore/check query wait forever on a lock or a stalled server.
export PGOPTIONS="${PGOPTIONS:--c statement_timeout=300000 -c lock_timeout=60000}"

# Time-based tiny smoke: one client, one rep, no warmup, verify-scale data.
VERIFY_CLIENTS="${VERIFY_CLIENTS:-1}"
export SMALLBANK_ACCOUNTS="${VERIFY_ACCOUNTS}" \
    SMALLBANK_DURATION="${VERIFY_DURATION}" \
    SMALLBANK_WARMUP="${VERIFY_WARMUP}" \
    SMALLBANK_CLIENTS="${VERIFY_CLIENTS}" \
    REPS=1 PHASE=execute

# Keep the verify seed separate from the performance seed. Creating it loads
# 'smallbank' at the reduced account count and snapshots it; RESEED=1 rebuilds.
if [ "${VERIFY_SKIP_SEED:-0}" = "1" ]; then
    echo "----------------->> Seed smallbank: skipped (VERIFY_SKIP_SEED=1) <<-----------------"
elif [ "${BENCH_LOCK_HELD:-0}" != "1" ] || [ "${VERIFY_SEED_DB}" != "${SEED_DB_SMALLBANK}" ]; then
    echo "----------------->> Seed smallbank verify snapshot (reuse unless RESEED=1) <<-----------------"
    bench_ensure_seed "${DB}" "${VERIFY_SEED_DB}"
    bench_assert_seed "${VERIFY_SEED_DB}"
else
    echo "----------------->> Seed smallbank: parent ensured; per-run restore follows <<-----------------"
fi

# Per-arm: runner script | runner args | rewrite driver | smoke CSV (REPS=1 paths).
# With VERIFY_REWRITE_ROOT set, any arm name maps to that tree.
arm_spec() {
    if [ -n "${VERIFY_REWRITE_ROOT:-}" ]; then
        echo "scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-NaiveLLM.sh|${DBMS} ${VERIFY_ACCOUNTS} ${VERIFY_DURATION} smallbank ${1} ${VERIFY_REWRITE_ROOT}|${ROOT}/${VERIFY_REWRITE_ROOT}/Rewrite/${DBMS}/${TREE_NAME}/drivers/postgresdriver.py|${VERIFY_CSV}"
        return 0
    fi
    case "$1" in
        baseline) echo "scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-App.sh|${DBMS} ${VERIFY_ACCOUNTS} ${VERIFY_DURATION}|${BASELINE_DRIVER}|results/smallbank/baseline/benchmarks/runExperiment1-smallbank-${DBMS}" ;;
        aco) echo "scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh|${model} ${DBMS} ${VERIFY_ACCOUNTS} ${VERIFY_DURATION} smallbank aco|${ROOT}/out/app_layer/ACo-results/Rewrite/${DBMS}/smallbank-${model}/drivers/postgresdriver.py|results/smallbank/aco/benchmarks/aco.csv" ;;
        adco) echo "scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh|${model} ${DBMS} ${VERIFY_ACCOUNTS} ${VERIFY_DURATION} smallbank adco|${ROOT}/out/app_layer/ADCo-results/Rewrite/${DBMS}/smallbank-${model}/drivers/postgresdriver.py|results/smallbank/adco/benchmarks/adco.csv" ;;
        py-dbridge) echo "scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Py-DBridge.sh|${DBMS} ${VERIFY_ACCOUNTS} ${VERIFY_DURATION} smallbank|${ROOT}/out/app_layer/Py-DBridge-results/Rewrite/${DBMS}/smallbank-Py-DBridge/drivers/postgresdriver.py|results/smallbank/py-dbridge/benchmarks/py-dbridge.csv" ;;
        naive-llm) echo "scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-NaiveLLM.sh|${DBMS} ${VERIFY_ACCOUNTS} ${VERIFY_DURATION} smallbank naive-llm|${ROOT}/out/app_layer/NaiveLLM-results/Rewrite/${DBMS}/smallbank-NaiveLLM/drivers/postgresdriver.py|results/smallbank/naive-llm/benchmarks/naive-llm.csv" ;;
        naive-llm-agenttune|agenttune-naive-llm) echo "scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-NaiveLLM.sh|${DBMS} ${VERIFY_ACCOUNTS} ${VERIFY_DURATION} smallbank ${1} out/app_layer/NaiveLLM-results/${1}|${ROOT}/out/app_layer/NaiveLLM-results/${1}/Rewrite/${DBMS}/smallbank-NaiveLLM/drivers/postgresdriver.py|results/smallbank/${1}/benchmarks/${1}.csv" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# SmallBank invariants: row scale and the ACCOUNTS/SAVINGS/CHECKING 1:1 mapping
# after the smoke run. Each query returns rows only when violated.
ACCOUNTS_COUNT_SQL="SELECT count(*) FROM accounts HAVING count(*) <> ${VERIFY_ACCOUNTS};"
SAVINGS_COUNT_SQL="SELECT count(*) FROM savings HAVING count(*) <> (SELECT count(*) FROM accounts);"
CHECKING_COUNT_SQL="SELECT count(*) FROM checking HAVING count(*) <> (SELECT count(*) FROM accounts);"
SAVINGS_MAPPING_SQL="SELECT a.custid, s.custid FROM accounts a FULL JOIN savings s ON a.custid = s.custid WHERE a.custid IS NULL OR s.custid IS NULL LIMIT 100;"
CHECKING_MAPPING_SQL="SELECT a.custid, c.custid FROM accounts a FULL JOIN checking c ON a.custid = c.custid WHERE a.custid IS NULL OR c.custid IS NULL LIMIT 100;"
BALANCE_SANITY_SQL="SELECT 'savings', custid, bal FROM savings WHERE bal IS NULL OR bal::text IN ('NaN','Infinity','-Infinity') UNION ALL SELECT 'checking', custid, bal FROM checking WHERE bal IS NULL OR bal::text IN ('NaN','Infinity','-Infinity') LIMIT 100;"
DUP_CUSTID_SQL="SELECT 'accounts', custid, count(*) FROM accounts GROUP BY custid HAVING count(*) > 1 UNION ALL SELECT 'savings', custid, count(*) FROM savings GROUP BY custid HAVING count(*) > 1 UNION ALL SELECT 'checking', custid, count(*) FROM checking GROUP BY custid HAVING count(*) > 1 LIMIT 100;"

verify_one_arm() {
    local arm="$1"
    local out="${VERIFY_OUTPUT:-results/smallbank/verify_${arm}.json}"
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

    # Pristine restore: verify seed -> smallbank, default knobs, expected scale.
    if [ "${VERIFY_SKIP_SEED_ASSERT:-0}" != "1" ]; then
        bench_assert_seed "${VERIFY_SEED_DB}"
    fi
    bench_restore "${DB}" "${VERIFY_SEED_DB}"
    if [ "${VERIFY_KEEP_KNOBS:-0}" = "1" ]; then
        echo "----------------->> ${arm}: keeping tuned knobs <<-----------------"
    else
        restore_defaults
        bench_assert_fresh_knobs
    fi
    bench_assert_rows "${DB}" "accounts" "${VERIFY_ACCOUNTS}"
    # Pristine-state canary: every account must have its savings/checking row.
    bench_assert_rows "${DB}" "savings" "${VERIFY_ACCOUNTS}"
    bench_assert_rows "${DB}" "checking" "${VERIFY_ACCOUNTS}"

    # Move real results aside so the smoke run cannot clobber them.
    bak=""
    if [ -d "${bdir}" ]; then
        bak="${bdir}.verify-bak"
        rm -rf "${bak}"
        mv "${bdir}" "${bak}"
    fi
    mkdir -p "${bdir}"
    if [ -n "${BENCH_RESULTS_DIR:-}" ]; then
        mkdir -p "${BENCH_RESULTS_DIR}"
    fi
    tmp="$(mktemp -d)"
    # RD — read equivalence: identical BALANCE calls through baseline and rewrite
    # code on this same snapshot, before the smoke run mutates anything.
    probe_base="${tmp}/probe_base.json"
    probe_arm="${tmp}/probe_arm.json"
    VENV_PY="${ROOT}/workload/apps/smallbank/venv/bin/python"
    [ -x "${VENV_PY}" ] || VENV_PY="python3"
    PROBE="${ROOT}/scripts/smallbank/exp2_Correctness/read_probe.py"
    DBCONFIG="${ROOT}/workload/apps/smallbank/db.config"
    echo "----------------->> ${arm}: BALANCE read-probe equivalence <<-----------------"
    (cd "${ROOT}/workload/apps/smallbank" && timeout "${PROBE_TIMEOUT:-180}" "${VENV_PY}" "${PROBE}" --dbms "${DBMS}" --config "${DBCONFIG}" >"${probe_base}" 2>"${tmp}/probe_base.err") || echo "WARNING: baseline read probe failed for '${arm}'." >&2
    if [ "${arm}" = "baseline" ]; then
        cp "${probe_base}" "${probe_arm}" 2>/dev/null || : >"${probe_arm}"
    else
        arm_tree="$(cd "$(dirname "${driver}")/.." && pwd)"
        (cd "${arm_tree}" && timeout "${PROBE_TIMEOUT:-180}" "${VENV_PY}" "${PROBE}" --dbms "${DBMS}" --config "${DBCONFIG}" >"${probe_arm}" 2>"${tmp}/probe_arm.err") || echo "WARNING: rewrite read probe failed for '${arm}'." >&2
    fi
    echo "----------------->> ${arm}: smoke (${VERIFY_DURATION}s, ${VERIFY_CLIENTS} client(s)) <<-----------------"
    # shellcheck disable=SC2086
    timeout "${VERIFY_SMOKE_TIMEOUT:-600}" ./"${runner}" ${rargs} >"${tmp}/smoke.log" 2>&1 || echo "WARNING: smoke run failed for '${arm}' (see ${out})." >&2
    smoke_csv="${csv}"
    if [ ! -f "${smoke_csv}" ] && [ -n "${BENCH_RESULTS_DIR:-}" ]; then
        smoke_csv="${BENCH_RESULTS_DIR}/$(basename "${csv}")"
    fi
    [ -f "${smoke_csv}" ] && cp "${smoke_csv}" "${tmp}/smoke.csv" || : >"${tmp}/smoke.csv"
    cp "${tmp}/smoke.log" "${tmp}/smoke.log.keep" 2>/dev/null || true

    # SmallBank invariants on post-smoke state.
    echo "----------------->> ${arm}: invariants + verdict <<-----------------"
    psql -d "${DB}" -tA -F'|' -c "${ACCOUNTS_COUNT_SQL}" >"${tmp}/accounts_count.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/accounts_count.txt"
    psql -d "${DB}" -tA -F'|' -c "${SAVINGS_COUNT_SQL}" >"${tmp}/savings_count.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/savings_count.txt"
    psql -d "${DB}" -tA -F'|' -c "${CHECKING_COUNT_SQL}" >"${tmp}/checking_count.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/checking_count.txt"
    psql -d "${DB}" -tA -F'|' -c "${SAVINGS_MAPPING_SQL}" >"${tmp}/savings_mapping.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/savings_mapping.txt"
    psql -d "${DB}" -tA -F'|' -c "${CHECKING_MAPPING_SQL}" >"${tmp}/checking_mapping.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/checking_mapping.txt"
    psql -d "${DB}" -tA -F'|' -c "${BALANCE_SANITY_SQL}" >"${tmp}/balance_sanity.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/balance_sanity.txt"
    psql -d "${DB}" -tA -F'|' -c "${DUP_CUSTID_SQL}" >"${tmp}/dup_custid.txt" 2>/dev/null || echo __QUERY_FAILED__ >"${tmp}/dup_custid.txt"

    # Restore real results before writing anything (but keep this run's smoke
    # CSV as evidence alongside the verdict JSON).
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
for name in ("accounts_count", "savings_count", "checking_count",
             "savings_mapping", "checking_mapping", "balance_sanity",
             "dup_custid"):
    try:
        with open(f"{tmp}/{name}.txt") as f:
            body = f.read().strip()
    except OSError:
        conds[name] = None
        continue
    conds[name] = None if body == "__QUERY_FAILED__" else [
        ln for ln in body.splitlines() if ln.strip()]
with open(dest, "w") as f:
    json.dump(conds, f)
PY
    inv_json="${tmp}/invariants.json"

    set +e
    python3 "${CHECKER}" --arm "${arm}" --csv "${tmp}/smoke.csv" --log "${tmp}/smoke.log.keep" \
        --source "${driver}" --baseline-source "${BASELINE_DRIVER}" \
        --invariants "${inv_json}" \
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
echo "----------------->> Verify done (statuses in results/smallbank/verify_*.json) <<-----------------"
exit "${overall}"
