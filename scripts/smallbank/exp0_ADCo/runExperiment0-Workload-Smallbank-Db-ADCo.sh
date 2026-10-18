#!/usr/bin/env bash
#
# Canonical SmallBank workload runner (ADCo/DCo).
#
# Canonical (bench_lib): <dir> <file> [reps], PHASE=load|execute (default execute).
# Legacy: <model> <dbms> <accounts> <transactions> <benchmark> <dir_name>
#   (all positional args optional; env overrides win for scale).
# Scale defaults to benchmarks scale, env-overridable:
#   ACCOUNTS=5000000 TRANSACTIONS=60000 LOAD_THREADS=4 REPS=2
#
set -euo pipefail

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/smallbank"

ACCOUNTS="${ACCOUNTS:-5000000}"
TRANSACTIONS="${TRANSACTIONS:-60000}"
LOAD_THREADS="${LOAD_THREADS:-4}"
REPS_DEFAULT="${REPS:-2}"

if [[ "${2:-}" == *.csv* ]]; then
    dir="${1}"
    file_name="${2}"
    reps="${3:-${REPS_DEFAULT}}"
    phase="${PHASE:-execute}"
    dbms="${DBMS:-postgres}"
    accounts="${ACCOUNTS}"
    transactions="${TRANSACTIONS}"

    case "${phase}" in
        load|execute) ;;
        *) echo "Usage: PHASE must be 'load' or 'execute' (got '${phase}')" >&2; exit 2 ;;
    esac

    results_dir="${RESULTS_DIR:-${result_benchmark_path:-${exp_path}/results/smallbank/adco/benchmarks}}"
    mkdir -p "${results_dir}"

    cd "${workload_path}"
    # shellcheck disable=SC1091
    source venv/bin/activate

    if [ "${phase}" = "load" ]; then
        python main.py load \
            --driver "${dbms}" \
            --threads "${LOAD_THREADS}" \
            --accounts "${accounts}" \
            --reset
        exit 0
    fi

    if [ "${dir}" != "baseline" ]; then
        workdir="${exp_path}/out/${dir}"
        [ -d "${workdir}" ] || workdir="${workload_path}"
    else
        workdir="${workload_path}"
    fi
    echo "------->>${workdir}<<-------"

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
        cd "${workdir}"
        if [ "${WARMUP_TRANSACTIONS:-0}" -gt 0 ]; then
            echo "----------------->> Smallbank warmup (rep ${rep}/${reps}) <<-----------------"
            python main.py run --driver "${dbms}" \
                --accounts "${WARMUP_ACCOUNTS:-${accounts}}" \
                --transactions "${WARMUP_TRANSACTIONS}"
        fi
        python main.py run \
            --driver "${dbms}" \
            --accounts "${accounts}" \
            --transactions "${transactions}" \
            --output-path "${log_fname}"
        cd "${workload_path}"
    done
    exit 0
fi

# ── Legacy positional CLI (preserved) ─────────────────────────────────────
llm_model="${1:-${MODEL:-gemini-3.5-flash-lite}}"
dbms="${2:-${DBMS:-postgres}}"
accounts="${3:-${ACCOUNTS}}"
transactions="${4:-${TRANSACTIONS}}"
benchmark="${5:-smallbank}"
dir_name="${6:-${ADCO_TOOL:-adco}}"
phase="${PHASE:-test}"

results_dir="${result_benchmark_path:-${exp_path}/results/smallbank/${dir_name}/benchmarks}"
mkdir -p "${results_dir}"
log_fname="${results_dir}/runExperiment1-${benchmark}-${dbms}-${llm_model}"

cd "${workload_path}"
# shellcheck disable=SC1091
source venv/bin/activate

reps="${REPS_DEFAULT}"
case "${phase}" in
    load)
        python main.py load \
            --driver "${dbms}" \
            --threads "${LOAD_THREADS}" \
            --accounts "${accounts}" \
            --reset
        ;;
    execute)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then
                out="${log_fname}"
            else
                out="${log_fname}_r${rep}"
            fi
            if [ "${WARMUP_TRANSACTIONS:-0}" -gt 0 ]; then
                echo "----------------->> Smallbank warmup (rep ${rep}/${reps}) <<-----------------"
                python main.py run --driver "${dbms}" \
                    --accounts "${WARMUP_ACCOUNTS:-${accounts}}" \
                    --transactions "${WARMUP_TRANSACTIONS}"
            fi
            python main.py run \
                --driver "${dbms}" \
                --accounts "${accounts}" \
                --transactions "${transactions}" \
                --output-path "${out}"
        done
        if [ "${reps}" -gt 1 ]; then
            cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true
        fi
        ;;
    test)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then
                out="${log_fname}"
            else
                out="${log_fname}_r${rep}"
            fi
            python main.py test \
                --driver "${dbms}" \
                --threads "${LOAD_THREADS}" \
                --accounts "${accounts}" \
                --transactions "${transactions}" \
                --output-path "${out}"
        done
        if [ "${reps}" -gt 1 ]; then
            cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true
        fi
        ;;
    *)
        echo "Usage: PHASE must be 'load', 'execute' or 'test' (got '${phase}')" >&2
        exit 2
        ;;
esac
