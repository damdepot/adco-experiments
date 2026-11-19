#!/usr/bin/env bash
#
# Read-only artifact check for the TPC-C arms. Reports, per arm, whether the
# artifacts a benchmark needs exist, and flags stale results (benchmark CSVs
# with no artifacts behind them) plus silently-untuned knob state (an arm whose
# saved auto.conf overrides nothing, i.e. it measured default config).
#
# Never takes bench_lock and never writes: safe to run during or after a run.
# Exit 1 if any arm is MISSING or STALE; warnings alone do not fail.
#
# Overrides (for inspecting copies of results/ and out/):
#   RESULTS_BASE  default <root>/results/tpcc
#   OUT_BASE      default <root>/out  (rewrite trees live under app_layer/;
#                 a copy of out/app_layer itself is also accepted)
#   MODEL         default gemini-3.5-flash-lite
#
# Usage: check_artifacts.sh [-h|--help] [arm ...]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"

RESULTS_BASE="${RESULTS_BASE:-${ROOT}/results/tpcc}"
OUT_BASE="${OUT_BASE:-${ROOT}/out}"
MODEL="${MODEL:-gemini-3.5-flash-lite}"

ALL=(baseline py-dbridge naive-llm aco ottertune gptuner agenttune naive-llm-agenttune agenttune-naive-llm dco adco)

usage() {
    cat <<'EOF'
Usage: check_artifacts.sh [-h|--help] [arm ...]

Read-only report of TPC-C benchmark artifacts (rewrites, knob caches, reps,
verify status). Default: every arm in run_all.sh order.

Exit: 0 when every arm is ok or warn-only; 1 if any arm is MISSING or STALE.
Env: RESULTS_BASE (results/tpcc), OUT_BASE (out), MODEL (gemini-3.5-flash-lite)
EOF
}

if [ "$#" -gt 0 ]; then
    case "$1" in
        -h|--help) usage; exit 0 ;;
    esac
fi

ARMS=("${ALL[@]}")
if [ "$#" -gt 0 ]; then
    for a in "$@"; do
        case " ${ALL[*]} " in
            *" ${a} "*) ;;
            *) echo "ERROR: unknown arm '${a}'" >&2; usage >&2; exit 2 ;;
        esac
    done
    ARMS=("$@")
fi

# A plain copy of out/app_layer keeps no app_layer segment; accept both.
APP="${OUT_BASE}/app_layer"
[ -d "${APP}" ] || APP="${OUT_BASE}"

printf '%-22s | %-15s | %9s | %4s | %-10s | %s\n' \
    "ARM" "WAREHOUSE" "KNOBS" "REPS" "VERIFY" "STATUS"

n_ok=0
n_missing=0
n_stale=0

for arm in "${ARMS[@]}"; do
    rewrite=""
    knobs_dir=""
    knobs_name=""
    case "${arm}" in
        baseline) ;;
        aco) rewrite="${APP}/ACo-results/Rewrite/postgres/tpcc-${MODEL}/drivers/postgresdriver.py" ;;
        naive-llm) rewrite="${APP}/NaiveLLM-results/Rewrite/postgres/tpcc-NaiveLLM/drivers/postgresdriver.py" ;;
        py-dbridge) rewrite="${APP}/Py-DBridge-results/Rewrite/postgres/tpcc-Py-DBridge/drivers/postgresdriver.py" ;;
        dco) knobs_dir="${RESULTS_BASE}/dco/state"; knobs_name="dco" ;;
        adco)
            rewrite="${APP}/ADCo-results/Rewrite/postgres/tpcc-${MODEL}/drivers/postgresdriver.py"
            knobs_dir="${RESULTS_BASE}/adco/state"; knobs_name="adco" ;;
        agenttune|gptuner|ottertune)
            knobs_dir="${RESULTS_BASE}/${arm}/state"; knobs_name="${arm}" ;;
        naive-llm-agenttune|agenttune-naive-llm)
            rewrite="${APP}/NaiveLLM-results/${arm}/Rewrite/postgres/tpcc-NaiveLLM/drivers/postgresdriver.py"
            knobs_dir="${RESULTS_BASE}/${arm}/state"; knobs_name="agenttune" ;;
    esac

    if [ -z "${rewrite}" ]; then
        warehouse="-"
    elif [ -f "${rewrite}" ]; then
        warehouse="rewrite ok"
    else
        warehouse="rewrite MISSING"
    fi

    knobs="-"
    knobs_count=""
    knobs_hit=0
    if [ -n "${knobs_dir}" ]; then
        if bench_knob_cache_hit "${knobs_dir}" "${knobs_name}"; then
            knobs_hit=1
            knobs_count="$(grep -cE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*=' \
                "${knobs_dir}/${knobs_name}.auto.conf" || true)"
            knobs_count="${knobs_count:-0}"
            knobs="${knobs_count} knobs"
        else
            knobs="MISSING"
        fi
    fi

    bench_dir="${RESULTS_BASE}/${arm}/benchmarks"
    reps=0
    if [ -d "${bench_dir}" ]; then
        reps="$(find "${bench_dir}" -maxdepth 1 -type f -name "${arm}_r*.csv" 2>/dev/null | wc -l | tr -d ' ')"
        if [ "${reps}" -eq 0 ] && [ -f "${bench_dir}/${arm}.csv" ]; then
            reps=1
        fi
    fi

    verify=""
    verify_file="${RESULTS_BASE}/verify_${arm}.json"
    if [ -f "${verify_file}" ]; then
        verify="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([A-Z]*\)".*/\1/p' "${verify_file}" | head -n 1)"
    fi
    if [ -z "${verify}" ]; then
        # A rewrite arm with no verdict is 'none'; others are never verified.
        if [ -n "${rewrite}" ]; then verify="none"; else verify="-"; fi
    fi

    missing=""
    if [ -n "${rewrite}" ] && [ ! -f "${rewrite}" ]; then
        missing="rewrite"
    fi
    if [ -n "${knobs_dir}" ] && [ "${knobs_hit}" -eq 0 ]; then
        missing="${missing:+${missing}+}knobs"
    fi

    if [ -n "${missing}" ]; then
        if [ "${reps}" -gt 0 ]; then
            status="STALE"
            n_stale=$((n_stale + 1))
        else
            status="MISSING"
            n_missing=$((n_missing + 1))
        fi
    else
        warnings=""
        if [ -n "${knobs_dir}" ] && [ "${knobs_count}" -eq 0 ]; then
            warnings="0 knobs"
        fi
        if [ "${reps}" -eq 0 ]; then
            warnings="${warnings:+${warnings}; }no results"
        fi
        if [ -n "${rewrite}" ] && [ "${verify}" != "PASS" ]; then
            warnings="${warnings:+${warnings}; }verify ${verify}"
        fi
        if [ -n "${warnings}" ]; then
            status="warn: ${warnings}"
        else
            status="ok"
            n_ok=$((n_ok + 1))
        fi
    fi

    printf '%-22s | %-15s | %9s | %4s | %-10s | %s\n' \
        "${arm}" "${warehouse}" "${knobs}" "${reps}" "${verify}" "${status}"
done

printf '\n%d arm(s) ok, %d missing, %d stale\n' "${n_ok}" "${n_missing}" "${n_stale}"
echo "hint: MISSING arms need their runner first; STALE CSVs have no artifacts behind them."

if [ "${n_missing}" -ne 0 ] || [ "${n_stale}" -ne 0 ]; then
    exit 1
fi
