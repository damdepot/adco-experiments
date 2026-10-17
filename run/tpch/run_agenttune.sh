#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpch/run_agenttune" "results/tpch/agenttune" "agenttune"
cd "${ROOT}"
bench_snapshot_seed tpch tpch_seed ./run/setup/tpch-prepare-postgres-remote.sh

# clean agenttune results
rm -rf results/tpch/agenttune
mkdir -p results/tpch/agenttune/benchmarks

rm -rf out/query_layer/AgentTune-results
mkdir -p out/query_layer/AgentTune-results

export iteration=2
export result_dir="results/tpch/agenttune"
export result_benchmark_path="results/tpch/agenttune/benchmarks"
export result_output_path="out/query_layer/AgentTune-results"

CMDAgentTune=./scripts/common/db_layer/exp1_Baselines/runExperiment1-AgentTune.sh
CMDMeasure=./scripts/common/query_layer/exp2_Baselines/runExperiment2-TunedBaseline.sh
CMDDocker=./scripts/common/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"

# Dedicated QueryDir with just the 22 TPCH queries: workload/.../tpch/ also
# holds schema/index/import helpers, which run_sql_queries must not execute
# (it runs every *.sql under QueryDir).
QUERYDIR="${ROOT}/out/query_layer/AgentTune-tpch-queries"
mkdir -p "${QUERYDIR}"
cp "${ROOT}/workload/databases/PostgreSQL/tpch/query"*.sql "${QUERYDIR}"/

### AgentTune (knob-only tuning on TPCH)
### *****************************
run_agenttune_tune() {
    echo '-------------------<< Running AgentTune tuning for TPCH dataset >>-------------------'
    # run/setup/db-update-configs.sh resets config.ini to agenttune/SYSBENCH,
    # so pin the tpch/JOB values here at launch, after any setup step.
    QUERYDIR="${QUERYDIR}" python3 - "${ROOT}/baselines/AgentTune/config.ini" <<'PY'
import configparser, os, sys
cfg = sys.argv[1]
c = configparser.ConfigParser()
c.optionxform = str
c.read(cfg)
rec = c['configuration recommender']
rec['DB_Name'] = 'tpch'
rec['QueryDir'] = os.environ['QUERYDIR']
rec['benchmark'] = 'JOB'
with open(cfg, 'w') as f:
    c.write(f)
print('AgentTune config.ini: DB_Name=%s QueryDir=%s benchmark=%s'
      % (rec['DB_Name'], rec['QueryDir'], rec['benchmark']))
PY
    $CMDAgentTune postgres tpch
}

bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"
python3 "${ROOT}/tools/check_knobs.py"
if run_agenttune_tune; then
    echo '-------------------<< Restarting DB after AgentTune tuning >>-------------------'
    $CMDDocker Restart ${db_container}
    $CMDDocker WaitFor ${db_container}
    echo '-------------------<< Running workload for TPCH dataset (AgentTune tuned knobs) >>-------------------'
    $CMDMeasure tpch PostgreSQL agenttune ${model}
else
    echo 'WARNING: AgentTune tuning failed; skipping its workload measurement.' >&2
fi
$CMDDocker Restart ${db_container}
$CMDDocker WaitFor ${db_container}
