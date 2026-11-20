#!/usr/bin/env bash
# Clear one workload's benchmark outputs so the next run starts empty.
#
# WORKLOAD=tpcc|smallbank (default tpcc). Shared by both run/ wrappers.
#
# Scope: deletes the *contents* of results/<workload>/<arm>/benchmarks/ only
# (the dir itself is recreated empty).
#
# Never touched: results/<workload>/<arm>/state/ (knob caches), out/ rewrite
# trees, results/<workload>/verify_*.json, results/<workload>/*.json.
#
# Usage: clear_benchmark_results.sh [arm ...]
#   no args  -> every arm under results/tpcc that has a benchmarks/ dir
#   args     -> only the named arms (missing ones are skipped, not fatal)
#   DRY_RUN=1 -> print what would be removed, change nothing
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXP_PATH="${ROOT}"
cd "${ROOT}"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

# shellcheck disable=SC1090
source "${LIB}"

WORKLOAD="${WORKLOAD:-tpcc}"
BASE="results/${WORKLOAD}"
DRY_RUN="${DRY_RUN:-0}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "usage: $0 [arm ...]   (DRY_RUN=1 to preview)"
    exit 0
fi

# Single-writer: refuse to delete results while a benchmark holds the lock.
bench_lock "${ROOT}"

# Arm names must be plain dir names: blocks .., absolute paths, subpaths.
safe_arm() {
    case "$1" in
        "" | .* | */*) return 1 ;;
        *) return 0 ;;
    esac
}

arms=()
skipped=0
if [ "$#" -gt 0 ]; then
    for arm in "$@"; do
        if ! safe_arm "${arm}"; then
            echo "refuse (unsafe arm name): ${arm}" >&2
            skipped=$((skipped + 1))
            continue
        fi
        dir="${BASE}/${arm}/benchmarks"
        case "${dir}" in
            "${BASE}"/*/benchmarks) ;;
            *)
                echo "refuse (outside ${BASE}/<arm>/benchmarks): ${dir}" >&2
                skipped=$((skipped + 1))
                continue
                ;;
        esac
        if [ ! -d "${dir}" ]; then
            echo "skip (no benchmarks dir): ${arm}"
            skipped=$((skipped + 1))
            continue
        fi
        arms+=("${arm}")
    done
else
    for d in "${BASE}"/*/benchmarks; do
        [ -d "${d}" ] || continue
        arms+=("$(basename "$(dirname "$d")")")
    done
fi

cleared=0
if [ "${#arms[@]}" -gt 0 ]; then
    for arm in "${arms[@]}"; do
        dir="${BASE}/${arm}/benchmarks"
        n="$(find "${dir}" -type f | wc -l | tr -d ' ')"
        if [ "${DRY_RUN}" = "1" ]; then
            echo "${arm}: would remove ${n} file(s) (dry run)"
        else
            echo "${arm}: removing ${n} file(s)"
            rm -rf "${dir}"
            mkdir -p "${dir}"
        fi
        cleared=$((cleared + 1))
    done
fi

if [ "${DRY_RUN}" = "1" ]; then
    echo "summary: would clear ${cleared} arm(s), skipped ${skipped}; state/ and rewrite trees left intact."
else
    echo "summary: cleared ${cleared} arm(s), skipped ${skipped}; state/ and rewrite trees left intact."
fi
