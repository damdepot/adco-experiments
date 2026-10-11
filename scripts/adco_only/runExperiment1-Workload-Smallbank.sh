#!/usr/bin/env bash
set -euo pipefail

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workload_path="${exp_path}/workload/apps/smallbank"
docker_script="${BENCH_CMDDOCKER:-${exp_path}/scripts/_lib/docker.sh}"
db_container="${DB_CONTAINER:-${BENCH_DB_CONTAINER:-adcoexp-db}}"

# Benchmarks-scale defaults, env-overridable.
load_threads="${LOAD_THREADS:-8}"

# Dispatch: new bench protocol (<dir> <file> [reps], optionally with
# PHASE=load|execute) vs legacy (<dbms> <accounts> <txns>).
is_bench=0
if [ "${PHASE:-}" = "load" ] || [ "${PHASE:-}" = "execute" ]; then
    is_bench=1
elif [ $# -ge 2 ]; then
    case "${1:-}" in
        baseline) is_bench=1 ;;
        *)
            case "${2:-}" in
                *.csv) is_bench=1 ;;
            esac
            case "${1:-}" in
                */*) is_bench=1 ;;
            esac
            ;;
    esac
fi

if [ "${is_bench}" -eq 1 ]; then
    dir="${1:-}"
    file_name="${2:-}"
    # Repetitions: positional arg wins over env. Load phase always runs once.
    reps="${3:-${REPS:-3}}"

    if [ -z "${dir}" ] || [ -z "${file_name}" ]; then
        echo "Usage: $(basename "$0") <dir> <file_name> [reps]" >&2
        exit 2
    fi
    if ! [[ "${reps}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Usage: reps must be a positive integer (got '${reps}')" >&2
        exit 2
    fi

    phase="${PHASE:-execute}"
    case "${phase}" in
        load|execute) ;;
        *)
            echo "Usage: PHASE must be 'load' or 'execute' (got '${phase}')" >&2
            exit 2
            ;;
    esac

    dbms="${DBMS:-postgres}"
    # Data size and workload. `load` seeds the DB (so the tuner can inspect
    # it), `run` measures against that loaded data. Same load-once /
    # measure-reps shape as benchmarks/scripts/smallbank.sh.
    accounts="${ACCOUNTS:-1000000}"
    transactions="${TRANSACTIONS:-60000}"
    results_dir="${RESULTS_DIR:-${exp_path}/results/adco_only/baseline/benchmarks}"

    cd "${workload_path}"
    source venv/bin/activate

    if [ "${dir}" != "baseline" ]; then
        workdir="${exp_path}/out/${dir}"
        echo "------->>${workdir}<<-------"
    else
        workdir="${workload_path}"
    fi

    if [ "${phase}" = "load" ]; then
        # Creates the schema and loads accounts so the tuner can inspect the
        # target DB.
        python main.py load \
            --driver "${dbms}" \
            --threads "${load_threads}" \
            --accounts "${accounts}" \
            --reset
    else
        mkdir -p "${results_dir}"
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then
                rep_file="${file_name}"
            elif [[ "${file_name}" == *.* ]]; then
                rep_file="${file_name%.*}_r${rep}.${file_name##*.}"
            else
                rep_file="${file_name}_r${rep}"
            fi
            log_fname="${results_dir}/${rep_file}"
            echo "----------------->> SMALLBANK rep ${rep}/${reps} (${rep_file}) <<-----------------"
            "${docker_script}" Checkpoint "${db_container}"
            cd "${workdir}"
            python main.py run \
                --driver "${dbms}" \
                --accounts "${accounts}" \
                --transactions "${transactions}" \
                --output-path "${log_fname}"
        done
    fi
    exit 0
fi

# Legacy CLI: <dbms> <accounts> <txns> (old callers keep working; args map to
# env, benchmarks scale when absent).
dbms="${1:-${DBMS:-postgres}}"
accounts="${2:-${ACCOUNTS:-1000000}}"
transactions="${3:-${TRANSACTIONS:-60000}}"

log_fname="${exp_path}/results/adco_only/baseline/benchmarks/runExperiment1-smallbank-${dbms}"

cd "${workload_path}"
source venv/bin/activate

CMD="python main.py test \
                    --driver ${dbms} \
                    --threads ${load_threads} \
                    --accounts ${accounts} \
                    --transactions ${transactions} \
                    --output-path ${log_fname}"
$CMD
