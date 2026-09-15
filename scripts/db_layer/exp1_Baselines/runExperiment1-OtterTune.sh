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

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
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

log_dir="${exp_path}/results/db_layer/ottertune/logs"
record_dir="${exp_path}/results/db_layer/ottertune/record/${benchmark}"
output_dir="${exp_path}/results/db_layer/ottertune"

rm -rf "${record_dir}"
mkdir -p "${log_dir}" "${record_dir}" "${output_dir}/benchmarks"

echo "-------------------<< Running OtterTune Bayesian Optimization for ${benchmark} >>-------------------"

# Inspect the network of the database container to attach to the same bridge network
DB_NETWORK=$(docker inspect "${CONTAINER_NAME}" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || echo "adco-experiments_default")

if [ -f /.dockerenv ] || grep -qa 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then
    CURRENT_CONTAINER="$(hostname)"
    VOLUMES_ARG="--volumes-from ${CURRENT_CONTAINER}"
    RESULTS_OUT="/app/results/db_layer/ottertune/record/${benchmark}"
else
    VOLUMES_ARG="-v ${exp_path}/baselines/ottertune:/ottertune:ro -v ${record_dir}:/results"
    RESULTS_OUT="/results"
fi

# Construct micro-workload command executed by ottertune-tuner during tuning iterations
TARGET_EXP_CONTAINER="${ADCOEXP_CONTAINER:-adcoexp}"
if [ "${benchmark}" == "smallbank" ]; then
    WORKLOAD_CMD="docker exec ${TARGET_EXP_CONTAINER} bash -c 'cd /app/workload/apps/smallbank && (source venv/bin/activate 2>/dev/null || true) && python main.py run --driver postgres --accounts 100000 --transactions 2000 --host ${CONTAINER_NAME}'"
elif [ "${benchmark}" == "tpcc" ]; then
    WORKLOAD_CMD="docker exec ${TARGET_EXP_CONTAINER} bash -c 'cd /app/workload/apps/tpcc && (source venv/bin/activate 2>/dev/null || true) && python tpcc.py postgres --config=/app/workload/apps/tpcc/db.config --warehouses 2 --clients 4 --duration 10 --no-load'"
else
    WORKLOAD_CMD=""
fi

docker run --rm \
    --network "${DB_NETWORK}" \
    ${VOLUMES_ARG} \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -e PYTHONPATH=/ottertune/server \
    ottertune-tuner:latest \
        --db-host "${CONTAINER_NAME}" \
        --db-port "5432" \
        --db-name "${DB_NAME}" \
        --db-user "${DB_USER}" \
        --db-password "${DB_PASSWORD}" \
        --workload-name "${benchmark}" \
        --workload-cmd "${WORKLOAD_CMD}" \
        --restart-cmd "docker restart ${CONTAINER_NAME}" \
        --output-dir "${RESULTS_OUT}" \
        --iterations "${iterations}" \
        --warmup "${warmup}"

echo "-------------------<< OtterTune Optimization Finished for ${benchmark} >>-------------------"
