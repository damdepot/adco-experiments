#!/usr/bin/env bash
#
# DCo (tune-only) wrapper — canonical flag surface mirroring
# benchmarks/scripts/dco.sh, keeping <codebase> <model> <dbms> <benchmark> order.
#
# Canonical caps (env-overridable, same defaults as benchmarks/scripts/dco.sh):
#   SCREEN_TOTAL_ROWS=0 SCREEN_MAX_ROWS=5000000 SCREENING_BENCHMARK=sysbench
#   MEASURE_REPS=10 MEASURE_SECONDS=10 MEASURE_WARMUP_SECONDS=2
#   EARLY_STOP_MIN_REPS=4 MAX_ATTEMPTS=30 MAX_SET_KNOBS=20
#   CPU_CORES=2 MEMORY_GB=8 (--cpu-cores/--memory)
#   --apply-mode=live is passed when the local CLI supports it; otherwise the
#   local live equivalent --production-db is used (this fork's knob_tuner has
#   no --apply-mode flag yet). Extra SCREEN_*/MEASURE_*/MAX_* CLI flags are
#   forwarded only when supported (probed via --help) and always exported as
#   env for forward-compat.
#
set -euo pipefail

codebase_path="${1:-}"
llm_model="${2:-gemini-3.5-flash-lite}"
dbms="${3:-postgres}"
benchmark="${4:-smallbank}"

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
db_config_path="${exp_path}/baselines/ADCo/db.config"
bench_lib="${exp_path}/scripts/_lib/bench_lib.sh"

# Map to bench_lib's validate_tuning_args names.
dir_name="${benchmark}"
db_type="${dbms}"
db_name="${benchmark}"
cpu_cores="${CPU_CORES:-2}"
memory_gb="${MEMORY_GB:-8}"

if [ -f "${bench_lib}" ]; then
    # shellcheck disable=SC1090
    source "${bench_lib}"
    validate_tuning_args
else
    [ -n "${dir_name}" ] && [ -n "${db_type}" ] && [ -n "${db_name}" ] \
        && [ -n "${cpu_cores}" ] && [ -n "${memory_gb}" ] || {
        echo "ERROR: missing required arguments." >&2
        echo "Usage: $(basename "$0") <codebase> <model> <dbms> <benchmark>" >&2
        exit 2
    }
fi

output_path="${exp_path}/out/db_layer/DCo-results/Knob-Tune/${dbms}/${benchmark}-${llm_model}"
mkdir -p "${output_path}"

# Screening / measurement / loop caps (canonical defaults from dco.sh).
screen_total_rows="${SCREEN_TOTAL_ROWS:-0}"
screen_max_rows="${SCREEN_MAX_ROWS:-5000000}"
screening_benchmark="${SCREENING_BENCHMARK:-sysbench}"
measure_reps="${MEASURE_REPS:-10}"
measure_seconds="${MEASURE_SECONDS:-10}"
measure_warmup_seconds="${MEASURE_WARMUP_SECONDS:-2}"
early_stop_min_reps="${EARLY_STOP_MIN_REPS:-4}"
max_attempts="${MAX_ATTEMPTS:-30}"
max_set_knobs="${MAX_SET_KNOBS:-20}"
export SCREEN_TOTAL_ROWS="${screen_total_rows}" SCREEN_MAX_ROWS="${screen_max_rows}"
export SCREENING_BENCHMARK="${screening_benchmark}"
export MEASURE_REPS="${measure_reps}" MEASURE_SECONDS="${measure_seconds}"
export MEASURE_WARMUP_SECONDS="${measure_warmup_seconds}"
export EARLY_STOP_MIN_REPS="${early_stop_min_reps}"
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
# --apply-mode=live is canonical; local equivalent is --production-db.
if supports_flag "--apply-mode"; then
    extra_args+=(--apply-mode=live)
else
    extra_args+=(--production-db)
fi
if supports_flag "--screen-total-rows"; then extra_args+=(--screen-total-rows="${screen_total_rows}"); fi
if supports_flag "--screen-max-rows"; then extra_args+=(--screen-max-rows="${screen_max_rows}"); fi
if supports_flag "--screening-benchmark"; then extra_args+=(--screening-benchmark="${screening_benchmark}"); fi
if supports_flag "--measure-reps"; then extra_args+=(--measure-reps="${measure_reps}"); fi
if supports_flag "--measure-seconds"; then extra_args+=(--measure-seconds="${measure_seconds}"); fi
if supports_flag "--measure-warmup-seconds"; then extra_args+=(--measure-warmup-seconds="${measure_warmup_seconds}"); fi
if supports_flag "--early-stop-min-reps"; then extra_args+=(--early-stop-min-reps="${early_stop_min_reps}"); fi
if supports_flag "--max-attempts"; then extra_args+=(--max-attempts="${max_attempts}"); fi
if supports_flag "--max-set-knobs"; then extra_args+=(--max-set-knobs="${max_set_knobs}"); fi
if supports_flag "--db-config"; then extra_args+=(--db-config="${db_config_path}"); fi

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
