#!/usr/bin/env bash
set -euo pipefail

codebase_path="${1:-}"
llm_model="${2:-gemini-3.5-flash-lite}"
dbms="${3:-postgres}"
benchmark="${4:-smallbank}"
cpu_cores="${5:-${CPU_CORES:-2}}"
memory_gb="${6:-${MEMORY_GB:-8}}"

if [ -z "${codebase_path}" ]; then
    echo "Usage: $(basename "$0") <codebase> <model> <dbms> <benchmark> [cpu_cores memory_gb]" >&2
    exit 2
fi

if ! [[ "${cpu_cores}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: <cpu_cores> must be a positive integer (got '${cpu_cores}')." >&2
    exit 2
fi

if ! [[ "${memory_gb}" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk "BEGIN{exit !(${memory_gb} > 0)}"; then
    echo "ERROR: <memory_gb> must be a positive number (got '${memory_gb}')." >&2
    exit 2
fi

exp_path="$(cd "$(dirname "$0")/../.." && pwd)"

output_path="${exp_path}/out/adco_only/DCo-results/Knob-Tune/${dbms}/${benchmark}-${llm_model}"
mkdir -p "${output_path}"

# Screening dataset sizing. Raise SCREEN_MAX_ROWS when the target's working
# set exceeds the instance memory: otherwise the proxy dataset stays
# cache-resident and the gate is blind to memory-knob improvements.
screen_total_rows="${SCREEN_TOTAL_ROWS:-0}"
screen_max_rows="${SCREEN_MAX_ROWS:-5000000}"

# Screening gate measurement: sysbench OLTP (default) or pgbench sort/hash.
screening_benchmark="${SCREENING_BENCHMARK:-sysbench}"

# Measurement timing. Defaults match the tuner CLI (10/10/2/4).
measure_reps="${MEASURE_REPS:-10}"
measure_seconds="${MEASURE_SECONDS:-10}"
measure_warmup_seconds="${MEASURE_WARMUP_SECONDS:-2}"
early_stop_min_reps="${EARLY_STOP_MIN_REPS:-4}"

# Tuner loop caps. Defaults match the tuner (30/20).
max_attempts="${MAX_ATTEMPTS:-30}"
max_set_knobs="${MAX_SET_KNOBS:-20}"

# Tuner loop caps. This fork's CLI has no --max-*/--measure-* flags (see
# probe below); caps are exported as env for forward-compat.
max_attempts="${MAX_ATTEMPTS:-30}"
max_set_knobs="${MAX_SET_KNOBS:-20}"
export MAX_ATTEMPTS="${max_attempts}" MAX_SET_KNOBS="${max_set_knobs}"

# Upstream ADCo regression: optimizer tools resolve sandbox-relative paths
# against CWD (state["sandbox"] unset). Run from the sandbox root so
# relative paths resolve; invoke the project venv python directly with
# PYTHONPATH instead of `uv run` (which would mutate/recreate .venv).
adco_venv="${exp_path}/baselines/ADCo/.venv/bin/python"
[ -x "${adco_venv}" ] || adco_venv="${exp_path}/baselines/ADCo/venv/bin/python"
mkdir -p "${output_path}"
cd "${output_path}"

# Probe which flags the local CLI accepts (best-effort; never fails the run).
adco_help="$(PYTHONPATH="${exp_path}/baselines/ADCo" "${adco_venv}" -m src.adco --help 2>/dev/null || true)"
supports_flag() { grep -q -- "$1" <<<"${adco_help}"; }

extra_args=()
if supports_flag "--apply-mode"; then
    extra_args+=(--apply-mode=live)
else
    extra_args+=(--production-db)
fi
if supports_flag "--db-config"; then extra_args+=(--db-config="${exp_path}/baselines/ADCo/db.config"); fi
if supports_flag "--screen-total-rows"; then extra_args+=(--screen-total-rows="${screen_total_rows}"); fi
if supports_flag "--screen-max-rows"; then extra_args+=(--screen-max-rows="${screen_max_rows}"); fi
if supports_flag "--screening-benchmark"; then extra_args+=(--screening-benchmark="${screening_benchmark}"); fi
if supports_flag "--measure-reps"; then extra_args+=(--measure-reps="${measure_reps}"); fi
if supports_flag "--measure-seconds"; then extra_args+=(--measure-seconds="${measure_seconds}"); fi
if supports_flag "--measure-warmup-seconds"; then extra_args+=(--measure-warmup-seconds="${measure_warmup_seconds}"); fi
if supports_flag "--early-stop-min-reps"; then extra_args+=(--early-stop-min-reps="${early_stop_min_reps}"); fi
if supports_flag "--max-attempts"; then extra_args+=(--max-attempts="${max_attempts}"); fi
if supports_flag "--max-set-knobs"; then extra_args+=(--max-set-knobs="${max_set_knobs}"); fi

PYTHONPATH="${exp_path}/baselines/ADCo" "${adco_venv}" -m src.adco "${codebase_path}" \
    --model="${llm_model}" \
    --mode=tune-only \
    --db-type="${dbms}" \
    --db-name="${benchmark}" \
    --cpu-cores="${cpu_cores}" \
    --memory="${memory_gb}" \
    "${extra_args[@]}" \
    --log-file="${output_path}/adco_tune.log" \
    --output-path="${output_path}/result.json" \
    --verbose

if [ ! -s "${output_path}/result.json" ]; then
    echo "ERROR: DCo tuning failed to produce valid result.json at ${output_path}/result.json" >&2
    exit 1
fi
