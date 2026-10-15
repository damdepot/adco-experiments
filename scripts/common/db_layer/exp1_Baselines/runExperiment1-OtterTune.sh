#!/bin/bash
set -e

dbms=$1
benchmark=$2
iterations=$3
warmup=$4

case "${dbms}" in
    postgres|postgresql) dbms_sec="postgres" ;;
    mysql)                dbms_sec="mysql" ;;
    *) echo "Invalid dbms: ${dbms}. Supported: postgres, mysql." >&2; exit 1 ;;
esac

exp_path="$(cd "$(dirname "$0")/../../../.." && pwd)"
env_file="${exp_path}/.env"

if [ -f "${env_file}" ]; then
    set -a
    . "${env_file}"
    set +a
fi

DB_USER="${POSTGRES_USER:-postgres}"
DB_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
DB_NAME="${benchmark}"
CONTAINER_NAME="${PG_CONTAINER_NAME:-adcoexp-db}"

log_dir="${exp_path}/results/${benchmark}/ottertune/logs"
record_dir="${exp_path}/results/${benchmark}/ottertune/record/${benchmark}"
output_dir="${exp_path}/results/${benchmark}/ottertune"

rm -rf "${record_dir}"
mkdir -p "${log_dir}" "${record_dir}" "${output_dir}/benchmarks"

echo "-------------------<< Running OtterTune Bayesian Optimization for ${benchmark} >>-------------------"

if ! docker image inspect ottertune-tuner:latest >/dev/null 2>&1; then
    echo "ERROR: image 'ottertune-tuner:latest' not found; build it first via ./run/setup/db-setup-baselines.sh (or: docker build -t ottertune-tuner baselines/OtterTune)." >&2
    exit 1
fi

# Inspect the network of the database container to attach to the same bridge network
DB_NETWORK=$(docker inspect "${CONTAINER_NAME}" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || echo "adco-experiments_default")

if [ -f /.dockerenv ] || grep -qa 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then
    CURRENT_CONTAINER="$(hostname)"
    VOLUMES_ARGS=(--volumes-from "${CURRENT_CONTAINER}")
    RESULTS_OUT="/app/results/${benchmark}/ottertune/record/${benchmark}"
    TUNER_PYTHONPATH="/app/baselines/OtterTune/server"
    TUNER_ENTRYPOINT_ARGS=(--entrypoint python)
    TUNER_SCRIPT_ARGS=(/app/baselines/OtterTune/ottertune_tuner.py)
else
    VOLUMES_ARGS=(-v "${exp_path}/baselines/OtterTune:/ottertune:ro" -v "${record_dir}:/results")
    RESULTS_OUT="/results"
    TUNER_PYTHONPATH="/ottertune/server"
    TUNER_ENTRYPOINT_ARGS=()
    TUNER_SCRIPT_ARGS=()
fi

# Construct micro-workload command executed by ottertune-tuner during tuning iterations
TARGET_EXP_CONTAINER="${ADCOEXP_CONTAINER:-adcoexp}"
WORKLOAD_WARMUP_ARGS=()
if [ "${benchmark}" == "smallbank" ]; then
    WORKLOAD_CMD="docker exec ${TARGET_EXP_CONTAINER} bash -c 'cd /app/workload/apps/smallbank && (source venv/bin/activate 2>/dev/null || true) && python main.py run --driver postgres --accounts ${ACCOUNTS:-5000000} --transactions ${TRANSACTIONS:-60000} --host ${CONTAINER_NAME}'"
    WORKLOAD_WARMUP_CMD="docker exec ${TARGET_EXP_CONTAINER} bash -c 'cd /app/workload/apps/smallbank && (source venv/bin/activate 2>/dev/null || true) && python main.py run --driver postgres --accounts ${ACCOUNTS:-5000000} --transactions ${OTTERTUNE_WARMUP_TRANSACTIONS:-10000} --host ${CONTAINER_NAME}'"
    WORKLOAD_WARMUP_ARGS=(--workload-warmup-cmd "${WORKLOAD_WARMUP_CMD}")
elif [ "${benchmark}" == "tpcc" ]; then
    WORKLOAD_CMD="docker exec ${TARGET_EXP_CONTAINER} bash -c 'cd /app/workload/apps/tpcc && (source venv/bin/activate 2>/dev/null || true) && python tpcc.py postgres --config=/app/workload/apps/tpcc/db.config --warehouses ${WAREHOUSES:-32} --clients ${CLIENTS:-8} --duration ${OTTERTUNE_DURATION:-60} --no-load'"
    WORKLOAD_WARMUP_CMD="docker exec ${TARGET_EXP_CONTAINER} bash -c 'cd /app/workload/apps/tpcc && (source venv/bin/activate 2>/dev/null || true) && python tpcc.py postgres --config=/app/workload/apps/tpcc/db.config --warehouses ${WAREHOUSES:-32} --clients ${CLIENTS:-8} --duration ${OTTERTUNE_WARMUP_SECS:-30} --no-load'"
    WORKLOAD_WARMUP_ARGS=(--workload-warmup-cmd "${WORKLOAD_WARMUP_CMD}")
else
    WORKLOAD_CMD=""
fi

docker run --rm \
    --network "${DB_NETWORK}" \
    "${VOLUMES_ARGS[@]}" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e "PYTHONPATH=${TUNER_PYTHONPATH}" \
    "${TUNER_ENTRYPOINT_ARGS[@]}" \
    ottertune-tuner:latest \
        "${TUNER_SCRIPT_ARGS[@]}" \
        --db-host "${CONTAINER_NAME}" \
        --db-port "5432" \
        --db-name "${DB_NAME}" \
        --db-user "${DB_USER}" \
        --db-password "${DB_PASSWORD}" \
        --workload-name "${benchmark}" \
        --workload-cmd "${WORKLOAD_CMD}" \
        "${WORKLOAD_WARMUP_ARGS[@]}" \
        --restart-cmd "docker restart ${CONTAINER_NAME}" \
        --memory-gb "${MEMORY_GB:-4}" \
        --cpu-cores "${CPU_CORES:-2}" \
        --knob-catalog "" \
        --output-dir "${RESULTS_OUT}" \
        --iterations "${iterations}" \
        --warmup "${warmup}"

echo "-------------------<< OtterTune Optimization Finished for ${benchmark} >>-------------------"
