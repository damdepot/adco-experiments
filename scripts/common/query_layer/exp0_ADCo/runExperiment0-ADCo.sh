#!/bin/bash

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../../.." && pwd)"
output_path="${exp_path}/out/query_layer/ADCo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"
mkdir -p ${output_path}
db_config_path="${exp_path}/baselines/ADCo/db.config"

# src.adco wants lowercase engine names; callers use workload-style names.
case "${dbms}" in
    PostgreSQL) adco_dbms="postgres" ;;
    MySQL) adco_dbms="mysql" ;;
    *) adco_dbms="${dbms}" ;;
esac

# Sandbox pre-population (see app_layer wrapper): upstream copy_to_sandbox
# may skip, so stage the codebase + managed marker beforehand.
if [ ! -f ${output_path}/.adco_sandbox ]; then
    ( cd ${codebase_path} && tar --exclude=.git --exclude=__pycache__ --exclude=.venv --exclude=venv -cf - . ) | ( cd ${output_path} && tar -xf - )
    printf '%s' "adco-managed-sandbox-v1" > ${output_path}/.adco_sandbox
fi

# Run from the sandbox root (upstream optimizer tools resolve
# sandbox-relative paths against CWD); venv python directly with PYTHONPATH.
adco_venv="${exp_path}/baselines/ADCo/.venv/bin/python"
[ -x "${adco_venv}" ] || adco_venv="${exp_path}/baselines/ADCo/venv/bin/python"
cd ${output_path}
PYTHONPATH="${exp_path}/baselines/ADCo" "${adco_venv}" -m src.adco ${codebase_path} \
    --model ${llm_model} \
    --db-type ${adco_dbms} \
    --db-name ${benchmark} \
    --db-config "${db_config_path}" \
    --cpu-cores "${CPU_CORES:-4}" \
    --memory "${MEMORY_GB:-8}" \
    --sandbox-dir ${output_path} \
    --log-file ${output_path}/knob_tuner.log \
    --output-path ${output_path}/result.json \
    --verbose
