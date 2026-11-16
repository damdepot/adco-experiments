#!/usr/bin/env bash
# TPC-C robustness for rewrite arms: generate -> verify -> record, N times.
#
# Usage: run_arm_robustness.sh <arm> [runs] [dbms=postgres] [model]
#   arm: naive-llm | aco | adco | py-dbridge
#
# Defaults: naive-llm 10 runs, aco 10, adco 10, py-dbridge 1.
# Uses only the small verify seed (default 1 warehouse), created once and
# reused. RESEED=1 rebuilds it. The performance seed (tpcc_seed) is never
# touched here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"
# shellcheck disable=SC1091
source "${ROOT}/scripts/_lib/bench_lib.sh"

ARM="${1:-}"
DBMS="${3:-postgres}"

NEEDS_TUNE=0
case "${ARM}" in
    naive-llm) DEFAULT_RUNS=10; TREE_NAME="tpcc-NaiveLLM" ;;
    naive-llm-agenttune|agenttune-naive-llm)
        DEFAULT_RUNS=10; TREE_NAME="tpcc-NaiveLLM"; NEEDS_TUNE=1 ;;
    aco) DEFAULT_RUNS=10; TREE_NAME="ACo" ;;
    adco) DEFAULT_RUNS=10; TREE_NAME="ADCo" ;;
    py-dbridge) DEFAULT_RUNS=1; TREE_NAME="Py-DBridge" ;;
    *)
        echo "Usage: $(basename "$0") <naive-llm|naive-llm-agenttune|agenttune-naive-llm|aco|adco|py-dbridge> [runs] [dbms=postgres] [model]" >&2
        exit 2
        ;;
esac
FULL_SCALE="${FULL_SCALE:-0}"
if [ "${FULL_SCALE}" = "1" ]; then
    DEFAULT_RUNS=1
fi
RUNS="${2:-${DEFAULT_RUNS}}"
MODEL_ARG="${4:-${MODEL:-gemini-3.5-flash-lite}}"
# Sampling temperature for the rewrite (naive-llm only); unset = CLI default 0.
TEMP="${TEMP:-}"
if [ -n "${TEMP}" ] && ! [[ "${TEMP}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "ERROR: TEMP must be a non-negative number (got '${TEMP}')." >&2
    exit 2
fi
VERBOSE="${VERBOSE:-0}"
SMOKE_SECS="${SMOKE_SECS:-10}"
GEN_TIMEOUT="${GEN_TIMEOUT:-1800}"
TUNE_TIMEOUT="${TUNE_TIMEOUT:-3600}"
AGENTTUNE_ITERATIONS="${AGENTTUNE_ITERATIONS:-}"
TUNING="none"
TUNE_SECONDS=0
TUNED_OVERRIDES=0
if [ "${NEEDS_TUNE}" = "1" ]; then
    TUNING="agenttune"
fi
if [ "${FULL_SCALE}" = "1" ]; then
    MODE_DIR="robustness-full-scale"
    VERIFY_SEED_DB="${VERIFY_SEED_DB:-tpcc_seed}"
    VERIFY_WAREHOUSES="${VERIFY_WAREHOUSES:-${TPCC_WAREHOUSES}}"
    VERIFY_DURATION="${VERIFY_DURATION:-${TPCC_DURATION}}"
    VERIFY_CLIENTS="${VERIFY_CLIENTS:-${TPCC_CLIENTS}}"
    VERIFY_WARMUP="${VERIFY_WARMUP:-${TPCC_WARMUP}}"
    VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-1800}"
else
    MODE_DIR="robustness"
    VERIFY_SEED_DB="${VERIFY_SEED_DB:-tpcc_verify_seed}"
    VERIFY_WAREHOUSES="${VERIFY_WAREHOUSES:-1}"
    VERIFY_DURATION="${VERIFY_DURATION:-10}"
    VERIFY_CLIENTS="${VERIFY_CLIENTS:-1}"
    VERIFY_WARMUP="${VERIFY_WARMUP:-0}"
    VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-300}"
fi
REPORT_DIR="${ROBUSTNESS_REPORT_DIR:-results/tpcc/${MODE_DIR}/${ARM}}"

if [ "${VERIFY_SEED_DB}" = "tpcc_seed" ] && [ "${FULL_SCALE}" != "1" ]; then
    echo "ERROR: the robustness sweep must use the verify seed (e.g. tpcc_verify_seed), not the performance seed 'tpcc_seed'." >&2
    exit 2
fi
if ! [[ "${RUNS}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: runs must be a positive integer (got '${RUNS}')." >&2
    exit 2
fi

if { [ "${ARM}" = "naive-llm" ] || [ "${NEEDS_TUNE}" = "1" ]; } \
    && [ ! -x "${ROOT}/baselines/NaiveLLM/venv/bin/python" ]; then
    echo "ERROR: NaiveLLM venv missing; run ./run/setup/app-setup-baselines.sh" >&2
    exit 1
fi
if { [ "${ARM}" = "aco" ] || [ "${ARM}" = "adco" ]; } \
    && [ ! -x "${ROOT}/baselines/ADCo/venv/bin/python" ] \
    && [ ! -x "${ROOT}/baselines/ADCo/.venv/bin/python" ]; then
    echo "ERROR: ADCo venv missing; run ./run/setup/app-setup-baselines.sh" >&2
    exit 1
fi
if [ "${NEEDS_TUNE}" = "1" ] && [ ! -x "${ROOT}/baselines/AgentTune/venv/bin/python" ]; then
    echo "ERROR: AgentTune venv missing; run ./run/setup/app-setup-baselines.sh" >&2
    exit 1
fi
if [ "${ARM}" = "py-dbridge" ] && [ ! -x "${ROOT}/baselines/Py-DBridge/venv/bin/python" ]; then
    echo "ERROR: Py-DBridge venv missing; run ./run/setup/app-setup-baselines.sh" >&2
    exit 1
fi
if [ ! -x "${ROOT}/workload/apps/tpcc/venv/bin/python" ]; then
    echo "ERROR: TPC-C workload venv missing; run ./run/setup/app-setup-workloads.sh" >&2
    exit 1
fi
if ! grep -q "VERIFY_SKIP_SEED_ASSERT" "${ROOT}/scripts/_lib/bench_lib.sh"; then
    echo "ERROR: scripts/_lib/bench_lib.sh is outdated (missing VERIFY_SKIP_SEED_ASSERT)." >&2
    echo "Sync the repo before running the robustness sweep." >&2
    exit 1
fi

bench_lock "${ROOT}"
export BENCH_CMDRUNTPCC="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"
export SMOKE_SECS SMOKE_CLIENTS=1
export TREE_NAME

# --- one verify seed -------------------------------------------------------
echo "----------------->> Seed ${VERIFY_SEED_DB} (${VERIFY_WAREHOUSES} warehouses) <<-----------------"
# Everything below runs at the verify scale: the arm's own smoke/benchmark and
# the verifier both hit the 1-warehouse database, so the scale must match.
export TPCC_WAREHOUSES="${VERIFY_WAREHOUSES}"
_seed_exists="$(psql -d postgres -tA -c "SELECT 1 FROM pg_database WHERE datname='${VERIFY_SEED_DB}'" 2>/dev/null || true)"
if [ "${RESEED:-0}" = "1" ] || [[ "${_seed_exists}" != *1* ]]; then
    echo "Loading ${VERIFY_WAREHOUSES}-warehouse seed ..."
    bench_seed_once tpcc "${VERIFY_SEED_DB}"
else
    echo "Reusing existing seed database '${VERIFY_SEED_DB}'."
fi
bench_assert_rows "${VERIFY_SEED_DB}" warehouse "${VERIFY_WAREHOUSES}"
unset _seed_exists

# --- loop ------------------------------------------------------------------
STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
OUT_TS="out/app_layer/${MODE_DIR}/${ARM}/${STAMP}"
REPORT_JSON="${REPORT_DIR}/latest.json"
RECORDS="${OUT_TS}/runs.tsv"
mkdir -p "${OUT_TS}"

# Stacked arms tune once; the rewrites then verify under those knobs.
if [ "${NEEDS_TUNE}" = "1" ]; then
    echo "----------------->> AgentTune: tuning once <<-----------------"
    # Pin the shared config.ini (a TPC-H run leaves a different benchmark there).
    python3 - "${ROOT}/baselines/AgentTune/config.ini" "${AGENTTUNE_ITERATIONS}" <<'PY'
import configparser, sys
cfg, iterations = sys.argv[1], sys.argv[2]
c = configparser.ConfigParser()
c.optionxform = str
c.read(cfg)
rec = c['configuration recommender']
rec['DB_Name'] = 'tpcc'
rec['benchmark'] = 'SYSBENCH'
if iterations:
    rec['iteration'] = iterations
with open(cfg, 'w') as f:
    c.write(f)
PY
    bench_restore "tpcc" "${VERIFY_SEED_DB}"
    tune_start="$(date +%s)"
    if ! timeout --kill-after=5 "${TUNE_TIMEOUT}" \
        bash "./scripts/common/db_layer/exp1_Baselines/runExperiment1-AgentTune.sh" \
            "${DBMS}" tpcc >"${OUT_TS}/tune.log" 2>&1; then
        echo "ERROR: AgentTune tuning failed (see ${OUT_TS}/tune.log)." >&2
        exit 1
    fi
    TUNE_SECONDS=$(( $(date +%s) - tune_start ))
    mkdir -p "${OUT_TS}/tuned"
    _pgdata="$(docker exec "${BENCH_DB_CONTAINER}" printenv PGDATA)"
    docker exec -u postgres "${BENCH_DB_CONTAINER}" \
        cat "${_pgdata:-/var/lib/postgresql/data}/postgresql.auto.conf" \
        >"${OUT_TS}/tuned/postgresql.auto.conf"
    unset _pgdata
    TUNED_OVERRIDES="$(psql -d postgres -tA \
        -c "SELECT count(*) FROM pg_settings WHERE sourcefile LIKE '%postgresql.auto.conf'" \
        2>/dev/null || true)"
    echo "Tuned knobs: ${TUNED_OVERRIDES:-0} overrides in ${TUNE_SECONDS}s"
fi

: >"${RECORDS}"
{
    printf 'timestamp\t%s\n' "${STAMP}"
    printf 'arm\t%s\n' "${ARM}"
    printf 'model\t%s\n' "${MODEL_ARG}"
    printf 'temperature\t%s\n' "${TEMP:-0.0}"
    printf 'tree_name\t%s\n' "${TREE_NAME}"
    printf 'runs\t%s\n' "${RUNS}"
    printf 'verify_seed_db\t%s\n' "${VERIFY_SEED_DB}"
    printf 'verify_warehouses\t%s\n' "${VERIFY_WAREHOUSES}"
    printf 'verify_clients\t%s\n' "${VERIFY_CLIENTS}"
    printf 'verify_warmup\t%s\n' "${VERIFY_WARMUP}"
    printf 'verify_duration\t%s\n' "${VERIFY_DURATION}"
    printf 'full_scale\t%s\n' "${FULL_SCALE}"
    printf 'tuning\t%s\n' "${TUNING}"
    printf 'tune_seconds\t%s\n' "${TUNE_SECONDS}"
    printf 'tuned_overrides\t%s\n' "${TUNED_OVERRIDES:-0}"
} >"${OUT_TS}/config.tsv"

verify_tree() {
    local arm="$1" rewrite_root="$2" out_rel="$3"
    mkdir -p "${ROOT}/${out_rel}/smoke/benchmarks"
    echo "----------------->> verifying ${arm} <<-----------------"
    BENCH_LOCK_HELD=1 REVERIFY=1 \
        VERIFY_SKIP_SEED=1 \
        VERIFY_SKIP_SEED_ASSERT=1 \
        VERIFY_SEED_DB="${VERIFY_SEED_DB}" \
        VERIFY_WAREHOUSES="${VERIFY_WAREHOUSES}" \
        VERIFY_DURATION="${VERIFY_DURATION}" \
        VERIFY_CLIENTS="${VERIFY_CLIENTS}" \
        VERIFY_WARMUP="${VERIFY_WARMUP}" \
        VERIFY_KEEP_KNOBS="${NEEDS_TUNE}" \
        RESTORE_RESTART=0 \
        BENCH_SKIP_SETTLE=1 \
        VERIFY_REWRITE_ROOT="${rewrite_root}" \
        VERIFY_CSV="${ROOT}/${out_rel}/smoke/${arm}.csv" \
        BENCH_RESULTS_DIR="${ROOT}/${out_rel}/smoke/benchmarks" \
        VERIFY_OUTPUT="${ROOT}/${out_rel}/verify.json" \
        timeout --kill-after=5 "${VERIFY_TIMEOUT}" \
        bash "./scripts/tpcc/exp2_Correctness/run_verify.sh" "${DBMS}" "${arm}" \
        2>&1 | tee "${ROOT}/${out_rel}/verify.log" || true
}

verify_status_of() {
    python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        document = json.load(handle)
except (OSError, ValueError):
    print("UNVERIFIED")
    raise SystemExit
print(str(document.get("status") or "UNVERIFIED").upper())
PY
}

# Generate a fresh tree for this arm into <run>/Rewrite/<dbms>/<tree>.
# Echoes nothing; returns nonzero when generation failed.
generate_tree() {
    local rel_run="$1" abs_run="$2" out_dir="" src="" rc=0 rc_gen=0
    case "${ARM}" in
        naive-llm|naive-llm-agenttune|agenttune-naive-llm)
            TEMPERATURE="${TEMP}" NAIVE_REWRITE_ROOT="${rel_run}" \
                timeout --kill-after=5 "${GEN_TIMEOUT}" \
                bash "./scripts/common/app_layer/exp1_Baselines/runExperiment1-NaiveLLM.sh" \
                    workload/apps/tpcc "${DBMS}" tpcc "${MODEL_ARG}" \
                >"${abs_run}/rewrite.log" 2>&1 || rc=$?
            rc_gen="${rc}"
            ;;
        aco|adco)
            out_dir="out/app_layer/${TREE_NAME}-results"
            rm -rf "${ROOT}/${out_dir}"
            local op="ACo"
            [ "${ARM}" = "adco" ] && op="ADCo"
            timeout --kill-after=5 "${GEN_TIMEOUT}" \
                bash "./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh" \
                    "${op}" "${MODEL_ARG}" "${DBMS}" tpcc \
                >"${abs_run}/rewrite.log" 2>&1 || rc=$?
            rc_gen="${rc}"
            src="${ROOT}/${out_dir}/Rewrite/${DBMS}/tpcc-${MODEL_ARG}"
            ;;
        py-dbridge)
            out_dir="out/app_layer/Py-DBridge-results"
            rm -rf "${ROOT}/${out_dir}"
            timeout --kill-after=5 "${GEN_TIMEOUT}" \
                bash "./scripts/common/app_layer/exp1_Baselines/runExperiment1-Py-DBridge.sh" \
                    workload/apps/tpcc drivers/postgresdriver.py "${DBMS}" tpcc \
                >"${abs_run}/rewrite.log" 2>&1 || rc=$?
            rc_gen="${rc}"
            src="${ROOT}/${out_dir}/Rewrite/${DBMS}/tpcc-Py-DBridge"
            ;;
    esac

    if [ "${rc_gen}" -ne 0 ]; then
        return "${rc_gen}"
    fi
    case "${ARM}" in
        naive-llm|naive-llm-agenttune|agenttune-naive-llm) : ;;
        *)
            if [ ! -d "${src}" ]; then
                return 1
            fi
            mkdir -p "${abs_run}/Rewrite/${DBMS}/${TREE_NAME}"
            cp -a "${src}/." "${abs_run}/Rewrite/${DBMS}/${TREE_NAME}/"
            ;;
    esac
    return 0
}

for ((i = 1; i <= RUNS; i++)); do
    idx="$(printf '%02d' "${i}")"
    rel_run="${OUT_TS}/r${idx}"
    abs_run="${ROOT}/${rel_run}"
    tree_rel="${rel_run}/Rewrite/${DBMS}/${TREE_NAME}"
    mkdir -p "${abs_run}/smoke/benchmarks"
    echo "=================>> Run ${i}/${RUNS}: ${ARM} generate + verify <<================="

    # Fresh, consistent database for generation; never the performance seed.
    BENCH_SKIP_SETTLE=1 RESTORE_RESTART=0 \
        bench_restore tpcc "${VERIFY_SEED_DB}" >"${abs_run}/restore.log" 2>&1 || true
    restore_defaults >>"${abs_run}/restore.log" 2>&1 || true

    started="$(date +%s)"
    rc=0
    generate_tree "${rel_run}" "${abs_run}" || rc=$?
    gen_seconds=$(( $(date +%s) - started ))
    if [ "${VERBOSE}" = "1" ] && [ -s "${abs_run}/rewrite.log" ]; then
        sed 's/^/    rewrite | /' "${abs_run}/rewrite.log"
    fi

    changed=""; restored=""
    parsed="$(sed -nE 's/.*files changed: ([0-9]+), restored: ([0-9]+).*/\1 \2/p' "${abs_run}/rewrite.log" | tail -1 || true)"
    [ -n "${parsed}" ] && read -r changed restored <<<"${parsed}"
    rw_status="ok"; [ "${rc}" -ne 0 ] && rw_status="failed"
    sha=""
    if [ -f "${ROOT}/${tree_rel}/drivers/postgresdriver.py" ]; then
        sha="$(cat "${ROOT}/${tree_rel}/drivers/postgresdriver.py" "${ROOT}/${tree_rel}/tpcc.py" 2>/dev/null | sha256sum | awk '{print $1}')"
        verify_tree "${ARM}-r${idx}" "${rel_run}" "${rel_run}"
        echo "run ${i}/${RUNS}: $(verify_status_of "${ROOT}/${rel_run}/verify.json") (${gen_seconds}s)"
    else
        echo "WARNING: run ${i}: no ${ARM} tree (generation exit ${rc})" >&2
        echo "run ${i}/${RUNS}: UNVERIFIED (${gen_seconds}s)"
        rw_status="missing"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${i}" "${sha}" "${rw_status}" "${changed}" "${restored}" "${rel_run}/verify.json" "${gen_seconds}" \
        >>"${RECORDS}"
done

# --- report ----------------------------------------------------------------
python3 - "${OUT_TS}" "${REPORT_DIR}" "${ARM}" <<'PY'
import json, os, shutil, sys

ts_dir, report_dir, arm = sys.argv[1:4]


def kv(path):
    out = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if line:
                k, _, v = line.partition("\t")
                out[k] = v
    return out


def failed_checks(path):
    try:
        with open(path) as f:
            doc = json.load(f)
    except (OSError, ValueError):
        return "UNVERIFIED", ["verify output missing"]
    status = str(doc.get("status") or "UNVERIFIED").upper()
    out = []
    for name, check in (doc.get("checks") or {}).items():
        state = str((check or {}).get("status") or "").upper()
        if state in ("FAIL", "WARN"):
            issues = (check or {}).get("issues") or []
            out.append(name + (": " + str(issues[0]) if issues else ""))
    return status, out


cfg = kv(os.path.join(ts_dir, "config.tsv"))
runs = []
with open(os.path.join(ts_dir, "runs.tsv")) as f:
    for line in f:
        parts = (line.rstrip("\n").split("\t") + [""] * 7)[:7]
        run, sha, rw, changed, restored, vjson, seconds = parts
        status, failures = failed_checks(vjson) if vjson else ("UNVERIFIED", ["no rewrite tree"])
        runs.append({"run": int(run), "verify_status": status, "rewrite_status": rw,
                     "changed": changed or None, "restored": restored or None,
                     "sha256": sha or None, "generation_seconds": int(seconds) if seconds else None,
                     "failed_checks": failures, "verify_json": vjson or None})

counts = {k: sum(1 for r in runs if r["verify_status"] == v) for k, v in
          (("pass", "PASS"), ("fail", "FAIL"), ("warn", "WARN"), ("unverified", "UNVERIFIED"))}
if counts["fail"]:
    status = "FAIL"
elif counts["warn"]:
    status = "WARN"
elif counts["pass"]:
    status = "PASS"
else:
    status = "UNVERIFIED"
failures = [{"run": r["run"], "status": r["verify_status"],
             "failed_checks": r["failed_checks"]}
            for r in runs if r["verify_status"] in ("FAIL", "WARN", "UNVERIFIED")]

summary = {
    "arm": arm,
    "workload": "tpcc",
    "timestamp": cfg.get("timestamp", ""),
    "model": cfg.get("model", ""),
    "temperature": cfg.get("temperature", ""),
    "tree_name": cfg.get("tree_name", ""),
    "runs_completed": len(runs),
    "counts": counts,
    "status": status,
    "failures": failures,
    "verify_seed_db": cfg.get("verify_seed_db", ""),
    "verify_warehouses": int(cfg.get("verify_warehouses") or 0),
    "verify_clients": int(cfg.get("verify_clients") or 0),
    "verify_warmup": int(cfg.get("verify_warmup") or 0),
    "verify_duration": int(cfg.get("verify_duration") or 0),
    "full_scale": cfg.get("full_scale") == "1",
    "tuning": cfg.get("tuning", ""),
    "tune_seconds": int(cfg.get("tune_seconds") or 0),
    "tuned_overrides": int(cfg.get("tuned_overrides") or 0),
    "runs": runs,
}
with open(os.path.join(ts_dir, "summary.json"), "w") as f:
    json.dump(summary, f, indent=2)
    f.write("\n")
os.makedirs(report_dir, exist_ok=True)
shutil.copyfile(os.path.join(ts_dir, "summary.json"), os.path.join(report_dir, "latest.json"))

headline = (f"PASS {counts['pass']}/{len(runs)}  FAIL {counts['fail']}/{len(runs)}  "
            f"UNVERIFIED {counts['unverified']}/{len(runs)}  (seed {summary['verify_seed_db']}, "
            f"{summary['verify_warehouses']} warehouses)")
lines = [f"# {arm} TPC-C robustness — {summary['timestamp']}", "", headline, "",
         "| run | rewrite | verify | seconds | failed checks |",
         "| --- | --- | --- | --- | --- |"]
for r in runs:
    lines.append(f"| {r['run']} | {r['rewrite_status']} | {r['verify_status']} | "
                 f"{r['generation_seconds'] if r['generation_seconds'] is not None else '-'} | "
                 f"{'; '.join(r['failed_checks']) or '-'} |")
lines.append("")
with open(os.path.join(ts_dir, "summary.md"), "w") as f:
    f.write("\n".join(lines))
print(headline)
for fail in failures:
    print(f"  run {fail['run']}: {fail['status']} {', '.join(fail['failed_checks'])}")
PY

echo
if [ "${NEEDS_TUNE}" = "1" ]; then
    echo "----------------->> Restoring default knobs <<-----------------"
    restore_defaults
fi

echo "runs:   ${OUT_TS}"
echo "latest: ${REPORT_JSON}"
echo "report: ${OUT_TS}/summary.md"
