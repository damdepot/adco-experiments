#!/usr/bin/env bash

# ── Canonical TPC-C measurement protocol (shared by every runner) ──
# This file lives at <root>/scripts/_lib/bench_lib.sh.
# BENCH_ROOT resolves to the adco-experiments root via scripts/_lib/../.. .
BENCH_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH_ROOT="$(cd "${BENCH_SCRIPTS_DIR}/../.." && pwd)"
# Default docker op; override via env. Resolves to <root>/scripts/_lib/docker.sh.
BENCH_CMDDOCKER="${BENCH_CMDDOCKER:-${BENCH_SCRIPTS_DIR}/docker.sh}"
# Overridable by callers; no hardcoded dependency on a bundled tpcc.sh.
BENCH_CMDRUNTPCC="${BENCH_CMDRUNTPCC:-${BENCH_SCRIPTS_DIR}/tpcc.sh}"
BENCH_DB_CONTAINER="${BENCH_DB_CONTAINER:-adcoexp-db}"
BENCH_DB_SERVICE="${BENCH_DB_SERVICE:-pgdb}"

# Fixed resource + workload contract. Exported so docker compose (CPU_CORES /
# MEMORY_GB) and tpcc.sh (REPS / DURATION / WARMUP / WAREHOUSES / CLIENTS) read
# the exact values the runners measure with.
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-2}"
export DURATION="${DURATION:-180}"
export WARMUP="${WARMUP:-30}"
export WAREHOUSES="${WAREHOUSES:-32}"
export CLIENTS="${CLIENTS:-8}"
export SETTLE_SECS="${SETTLE_SECS:-5}"

# Fresh default config + empty DB; CPU_CORES/MEMORY_GB already exported so the
# compose limits and docker.sh's limit verification use the contract values.
bench_reset() {
    "${BENCH_CMDDOCKER}" Down "${BENCH_DB_CONTAINER}"
    "${BENCH_CMDDOCKER}" Up "${BENCH_DB_CONTAINER}" "${BENCH_DB_SERVICE}"
    "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
}

# Wait (bounded to 60s) for autovacuum workers to quiesce, then hold SETTLE_SECS
# so both arms are measured from a comparably settled dataset.
bench_settle() {
    local elapsed=0
    local n=1
    while [ "${elapsed}" -lt 60 ]; do
        n="$(docker exec -u postgres "${BENCH_DB_CONTAINER}" psql -tA -c "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'autovacuum worker';" 2>/dev/null || echo 1)"
        [ "${n}" = "0" ] && break
        sleep 2
        elapsed=$((elapsed + 2))
    done
    sleep "${SETTLE_SECS:-5}"
}

# Load the shared baseline dataset via the original app, vacuum, checkpoint,
# settle. Optional $2 (db name): VACUUM (ANALYZE) so the snapshot inherits
# clean visibility maps + planner stats and in-run autovacuum stays quiet.
bench_load() {
    local file="$1"
    local db="${2:-}"
    PHASE=load "${BENCH_CMDRUNTPCC}" baseline "${file}"
    if [ -n "${db}" ]; then
        psql -d "${db}" -c "VACUUM (ANALYZE);"
    fi
    "${BENCH_CMDDOCKER}" Checkpoint "${BENCH_DB_CONTAINER}"
    bench_settle
}

# Measure one arm. <dir> is 'baseline' or an out/<dir> rewritten app. Reps and
# workload shape come from the exported contract above.
bench_measure() {
    local dir="$1"
    local file="$2"
    "${BENCH_CMDRUNTPCC}" "${dir}" "${file}"
}

# Run one arm via the canonical symmetric protocol. Both baseline and optimized
# arms execute the identical sequence; optimized arms merely inject a tool.
#   baseline:  reset -> load -> restart -> wait -> clean reload -> measure
#   optimized: reset -> load -> tool -> restart -> wait -> clean reload -> measure
# <tag> names the load/measure CSVs (fixed names; each baseline runs once
# into a wiped method dir, so no run stamp is needed). <optimized_dir>
# is 'baseline' or an out/<dir> rewritten app. The optional <tool_fn> is a shell
# function name invoked between the initial and clean loads; a non-zero return
# aborts the run via errexit. Baseline passes no <tool_fn>.
bench_arm() {
    local tag="$1"
    local optimized_dir="$2"
    local tool_fn="${3:-}"

    bench_reset
    bench_load "load_${tag}.csv"
    if [ -n "${tool_fn}" ]; then
        "${tool_fn}"
    fi
    "${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
    "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    bench_load "load_clean_${tag}.csv"
    bench_measure "${optimized_dir}" "${tag}.csv"
}

# Snapshot a pristine dataset once so multi-arm runs load only once.
# bench_snapshot <db> <seed>: CREATE DATABASE <seed> TEMPLATE <db>.
#   Caller (bench_seed_once) runs bench_load first, which ends with
#   CHECKPOINT + settle and no writes after — so no checkpoint here.
#   The template stays untouched; per-arm restores recreate <db> from
#   it in seconds.
# bench_restore <db> <seed>: DROP + recreate <db> from <seed>, then
#   checkpoint and settle so measurement starts from identical data.
# Knob settings (postgresql.auto.conf) are cluster-level and survive both.
bench_snapshot() {
    local db="$1"
    local seed="$2"
    psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname IN ('${db}', '${seed}') AND pid <> pg_backend_pid();"
    psql -d postgres -c "DROP DATABASE IF EXISTS \"${seed}\" WITH (FORCE);"
    psql -d postgres -c "CREATE DATABASE \"${seed}\" TEMPLATE \"${db}\";"
    local size
    size="$(docker exec -u postgres "${BENCH_DB_CONTAINER}" psql -tA -c "SELECT pg_size_pretty(pg_database_size('${seed}'));" 2>/dev/null || echo "unknown size")"
    echo "-------------------<< Database snapshot saved: '${seed}' (${size}) from '${db}' >>-------------------"
}

bench_restore() {
    local db="$1"
    local seed="$2"
    psql -d postgres -c "DROP DATABASE IF EXISTS \"${db}\" WITH (FORCE);"
    psql -d postgres -c "CREATE DATABASE \"${db}\" TEMPLATE \"${seed}\";"
    echo "-------------------<< Database restored: '${db}' from snapshot '${seed}' >>-------------------"
    "${BENCH_CMDDOCKER}" Checkpoint "${BENCH_DB_CONTAINER}"
    bench_settle
}

# Load the dataset exactly once for a whole run, then snapshot it for fast
# per-arm restores. Replaces N slow loader passes with one.
# bench_seed_once <db> <seed>
bench_seed_once() {
    local db="$1"
    local seed="$2"
    bench_reset
    bench_load "load_seed.csv" "${db}"
    bench_snapshot "${db}" "${seed}"
}

# Reuse the seed DB if present, else load once. RESEED=1 forces a reload.
# bench_ensure_seed <db> <seed>
bench_ensure_seed() {
    local db="$1"
    local seed="$2"
    if [ "${RESEED:-0}" = "1" ]; then
        bench_seed_once "${db}" "${seed}"
        return
    fi
    if ! docker exec -u postgres "${BENCH_DB_CONTAINER}" pg_isready -U postgres >/dev/null 2>&1; then
        "${BENCH_CMDDOCKER}" Up "${BENCH_DB_CONTAINER}" "${BENCH_DB_SERVICE}"
        "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    fi
    local exists
    exists="$(psql -d postgres -tA -c "SELECT 1 FROM pg_database WHERE datname='${seed}'" 2>/dev/null || true)"
    if [[ "${exists}" == *1* ]]; then
        echo "Reusing existing seed database '${seed}'."
        return 0
    fi
    bench_seed_once "${db}" "${seed}"
}

# Measure one arm from an already-snapshotted seed (see bench_seed_once).
# bench_arm_from_seed <tag> <dir> <db> <seed> [tool_fn]
# Same symmetry as bench_arm (identical data + cold buffers per arm) with
# restore -> [tool -> restore] -> restart -> measure instead of reset ->
# load -> tool -> restart -> clean reload -> measure. The post-tool restore
# keeps tool screening writes out of measurement.
bench_arm_from_seed() {
    local tag="$1"
    local optimized_dir="$2"
    local db="$3"
    local seed="$4"
    local tool_fn="${5:-}"

    bench_restore "${db}" "${seed}"
    if [ -n "${tool_fn}" ]; then
        restore_defaults
        bench_assert_fresh_knobs
        "${tool_fn}"
        bench_restore "${db}" "${seed}"
    fi
    "${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
    "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    bench_measure "${optimized_dir}" "${tag}.csv"
}

# Mutual exclusion for DB-destructive runs. bench_lock <root> takes a
# non-blocking lock on <root>/.bench.lock (held until the script exits);
# a second concurrent run fails fast instead of Down/Restart-ing the
# database out from under the first one mid-load or mid-measure.
# Uses flock(1) when available (Linux); falls back to a portable mkdir
# lock dir on systems without flock (e.g. macOS).
bench_lock() {
    local root="$1"
    if command -v flock >/dev/null 2>&1; then
        exec 9>"${root}/.bench.lock"
        if ! flock -n 9; then
            echo "ERROR: another benchmark run holds ${root}/.bench.lock; refusing to run concurrently." >&2
            exit 1
        fi
    else
        if ! mkdir "${root}/.bench.lock.dir" 2>/dev/null; then
            echo "ERROR: another benchmark run holds ${root}/.bench.lock.dir; refusing to run concurrently." >&2
            exit 1
        fi
        # NB: double quotes so ${root} expands now (function-local $root
        # is out of scope when the EXIT trap fires; single quotes + set -u
        # would fail and leave a stale lock dir behind).
        trap "rmdir \"${root}/.bench.lock.dir\" 2>/dev/null || true" EXIT
    fi
}

psql() {
    docker exec -i -u postgres "${BENCH_DB_CONTAINER}" psql -v ON_ERROR_STOP=1 -q "$@"
}

total_of() {
    awk -F, '
        $1 ~ /TOTAL/ { v = $NF }
        END {
            if (v == "" || v !~ /^-?[0-9]+([.][0-9]+)?$/) {
                print "no parseable TOTAL row in " FILENAME > "/dev/stderr"
                exit 1
            }
            print v
        }
    ' "$1"
}

median_of() {
    printf '%s\n' "$@" | sort -n |
        awk '{a[NR]=$1} END{print (NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2}'
}

median_of_values() { median_of "$@"; }

band_field() {
    "${PYTHON}" -c '
import json, sys
band = json.load(open(sys.argv[1]))
for key in ("mde_pct", "ci95_pct", "spread_pct"):
    if key in band:
        print(key)
        print(float(band[key]))
        break
else:
    print("none")
    print("0")
' "$1"
}

restore_defaults() {
    # Load-bearing: failures must abort loudly (no suppression), so a
    # half-reset can never pass silently into a measurement.
    psql -d "${DB:-postgres}" -c "ALTER SYSTEM RESET ALL;"
    psql -d "${DB:-postgres}" -c "SELECT pg_reload_conf();"
    if [ "${RESTORE_RESTART:-1}" = "1" ]; then
        "${CMDDOCKER:-${BENCH_CMDDOCKER}}" Restart "${BENCH_DB_CONTAINER}"
        "${CMDDOCKER:-${BENCH_CMDDOCKER}}" WaitFor "${BENCH_DB_CONTAINER}"
    fi
}

bench_assert_seed() {
    local seed="${1:-}"
    local got
    got="$(psql -d postgres -tA -c "SELECT 1 FROM pg_database WHERE datname='${seed}'" 2>/dev/null || true)"
    if [ "${got}" != "1" ]; then
        echo "ERROR: seed database '${seed}' not found; run the baseline first (or RESEED=1)." >&2
        exit 1
    fi
}

bench_assert_fresh_knobs() {
    # Tuner pollution lands in postgresql.auto.conf, which always sets
    # sourcefile (PG17 reports auto.conf entries as source='configuration
    # file'). The 7 permanent source='override' rows with NULL sourcefile
    # (file-location GUCs + image-level transaction_* defaults) are
    # environmental constants, present even on a fresh container — ignored.
    local n
    n="$(psql -d postgres -tA -c "SELECT count(*) FROM pg_settings WHERE sourcefile LIKE '%postgresql.auto.conf'" 2>/dev/null || true)"
    if [ "${n}" != "0" ]; then
        echo "ERROR: stale knobs from a previous arm persist (auto.conf override count=${n}); re-run (reset failed)." >&2
        exit 1
    fi
}

bench_assert_rows() {
    local db="${1:-}"
    local table="${2:-}"
    local expected="${3:-}"
    local actual
    actual="$(psql -d "${db}" -tA -c "SELECT count(*) FROM \"${table}\"" 2>/dev/null || true)"
    if ! [ "${actual:-0}" -eq "${expected}" ] 2>/dev/null; then
        echo "ERROR: row count mismatch in '${db}.${table}': expected ${expected}, got ${actual}; RESEED=1 to reload." >&2
        exit 1
    fi
}

usage() {
    echo "Usage: $(basename "$0") <dir_name> <db_type> <db_name> <cpu_cores> <memory_gb>" >&2
}

validate_tuning_args() {
    if [ -z "$dir_name" ] || [ -z "$db_type" ] || [ -z "$db_name" ] || [ -z "$cpu_cores" ] || [ -z "$memory_gb" ]; then
        echo "ERROR: missing required arguments." >&2
        usage
        exit 2
    fi

    if ! [[ "$cpu_cores" =~ ^[1-9][0-9]*$ ]]; then
        echo "ERROR: <cpu_cores> must be a positive integer (got '${cpu_cores}')." >&2
        usage
        exit 2
    fi

    if ! [[ "$memory_gb" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk "BEGIN{exit !(${memory_gb} > 0)}"; then
        echo "ERROR: <memory_gb> must be a positive number (got '${memory_gb}')." >&2
        usage
        exit 2
    fi
}
