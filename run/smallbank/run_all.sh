#!/usr/bin/env bash
#
# Run all SmallBank baselines in canonical order, skipping any whose results
# already exist on disk. Logs each baseline's console output and records
# per-baseline success/fail/skipped in result.json.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_timer "smallbank/run_all" "results/smallbank" "run_all"

WORKLOAD="smallbank"
BASELINES=(baseline aco py-dbridge dco adco agenttune ottertune gptuner naive-llm)

RUN_TS="$(date '+%Y-%m-%d-%H-%M-%S')"
LOG_DIR="${ROOT}/out/logs/${WORKLOAD}"
RESULT_JSON="${ROOT}/results/${WORKLOAD}/result.json"
mkdir -p "${LOG_DIR}" "$(dirname "${RESULT_JSON}")"

LOG="${LOG_DIR}/${RUN_TS}.log"
: > "${LOG}"

# Fresh status file; rewritten as arms finish so a killed run leaves partial
# statuses behind.
python3 - "${RESULT_JSON}" "${RUN_TS}" "${BASELINES[@]}" <<'PY'
import json, sys
path, run_ts, names = sys.argv[1], sys.argv[2], sys.argv[3:]
data = {"run_started": run_ts}
data.update({name: "pending" for name in names})
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY

record_status() {
    python3 - "${RESULT_JSON}" "$1" "$2" <<'PY'
import json, sys
path, name, status = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data[name] = status
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
}

# An arm is "done" when its results dir already holds result CSVs. Mirrors the
# arm discovery in run_reports.sh (results/<workload>/<arm>/**/*.csv).
arm_done() {
    local dir="${ROOT}/results/${WORKLOAD}/$1"
    [ -d "${dir}" ] || return 1
    [ -n "$(find "${dir}" -type f -name '*.csv' 2>/dev/null | head -n 1)" ]
}

for name in "${BASELINES[@]}"; do
    if arm_done "${name}"; then
        echo "----------------->> ${name}: skipped (results already present) <<-----------------" | tee -a "${LOG}"
        record_status "${name}" "skipped"
        continue
    fi
    script="./run/${WORKLOAD}/run_${name}.sh"
    echo "----------------->> ${name} (started $(date '+%Y-%m-%d %H:%M:%S')) <<-----------------" | tee -a "${LOG}"
    if "${script}" 2>&1 | tee -a "${LOG}"; then
        status="success"
    else
        status="fail"
    fi
    echo "----------------->> ${name}: ${status} <<-----------------" | tee -a "${LOG}"
    record_status "${name}" "${status}"
done

echo "All baselines done; statuses in ${RESULT_JSON}" | tee -a "${LOG}"
