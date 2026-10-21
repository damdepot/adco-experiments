#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpch/run_dco" "results/tpch/dco" "dco"
cd "${ROOT}"
bench_snapshot_seed tpch tpch_seed ./run/setup/tpch-prepare-postgres-remote.sh

# clean original results
rm -rf results/tpch/dco
mkdir -p results/tpch/dco/benchmarks

rm -rf out/query_layer/DCo-results
mkdir -p out/query_layer/DCo-results

export iteration=2
export result_dir="results/tpch/dco"
export result_benchmark_path="results/tpch/dco/benchmarks"
export result_output_path="out/query_layer/DCo-results"

CMDTune=./scripts/common/db_layer/exp0_ADCo/runExperiment0.sh
CMDMeasure=./scripts/common/query_layer/exp2_Baselines/runExperiment2-TunedBaseline.sh
CMDDocker=./scripts/common/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"


### DCo (Knob-tune-only)
### ******************
# workload/apps/* is gitignored, so a fresh checkout/container has no
# workload/apps/tpch and the ADCo CLI exits 2 ("target is not a directory").
# Recreate the scan-only shim when missing.
ensure_tpch_app_shim() {
    shim_dir="${ROOT}/workload/apps/tpch"
    if [ -d "${shim_dir}" ]; then
        return 0
    fi
    mkdir -p "${shim_dir}"
    cat > "${shim_dir}/main.py" <<'EOF'
"""TPCH workload entry point for DCo/ADCo knob tuning.

Scanned (isdir-gated) by intent analysis / knob tuner to recognise the tpch
database workload. Never executed in --mode=tune-only.
"""

DATABASE = "tpch"
BENCHMARK = "tpch"

# TPC-H tables in the tpch database (anchor: lineitem row-count guard).
TABLES = (
    "customer",
    "lineitem",
    "nation",
    "orders",
    "part",
    "partsupp",
    "region",
    "supplier",
)


def main():
    print("tpch workload shim: database=%s tables=%d" % (DATABASE, len(TABLES)))


if __name__ == "__main__":
    main()
EOF
}

dco_pipeline() {
    echo '-------------------<< Tuning knobs for TPCH dataset (DCo) >>-------------------'
    ensure_tpch_app_shim || return 1
    python3 "${ROOT}/tools/check_knobs.py" || return 1
    CPU_CORES="${CPU_CORES}" MEMORY_GB="${MEMORY_GB}" $CMDTune DCo ${model} postgres tpch || return 1
    python3 "${ROOT}/tools/check_knobs.py" || return 1
}

# Fresh data + default knobs BEFORE tuning; never bench_fresh_db/restore_defaults
# between tune and measure (knobs survive DB restore, not restore_defaults).
bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"
if dco_pipeline; then
    echo '-------------------<< Activating postmaster knobs for TPCH dataset (DCo) >>-------------------'
    $CMDDocker Restart ${db_container}
    $CMDDocker WaitFor ${db_container}
    echo '-------------------<< Running workload for TPCH dataset (DCo) >>-------------------'
    $CMDMeasure tpch PostgreSQL dco ${model}
    $CMDDocker Restart ${db_container}
    $CMDDocker WaitFor ${db_container}
else
    echo 'WARNING: DCo tuning pipeline failed; skipping its workload measurement.' >&2
fi
