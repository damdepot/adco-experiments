#!/bin/bash

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
output_path="${exp_path}/out/app_layer/ADCo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"
mkdir -p ${output_path}

# Upstream copy_to_sandbox may skip: pre-populate the sandbox so optimizer
# tools always find the files. Managed marker lets a later upstream copy
# still recognise (and refresh) the dir.
if [ ! -f ${output_path}/.adco_sandbox ]; then
    ( cd ${codebase_path} && tar --exclude=.git --exclude=__pycache__ --exclude=.venv --exclude=venv -cf - . ) | ( cd ${output_path} && tar -xf - )
    printf '%s' "adco-managed-sandbox-v1" > ${output_path}/.adco_sandbox
fi

# Upstream ADCo regression: optimizer tools resolve sandbox-relative paths
# against CWD (state["sandbox"] unset). Run from the sandbox root so
# relative paths resolve; invoke the project venv python directly with
# PYTHONPATH instead of `uv run` (which would mutate/recreate .venv).
adco_venv="${exp_path}/baselines/ADCo/.venv/bin/python"
[ -x "${adco_venv}" ] || adco_venv="${exp_path}/baselines/ADCo/venv/bin/python"
mkdir -p ${output_path}/out/adco

# Two processes, not one --mode=all: the rewriter's copy_to_sandbox
# deletes and recreates the sandbox dir, orphaning this process's CWD
# handle, so any later relative-path resolution (e.g. the tuner's
# results dir via os.path.abspath -> getcwd) fails with ENOENT. The
# second process re-anchors CWD after the wipe.
# shortcut: single --mode=all call once upstream re-anchors CWD after
# copy (or absolutizes results_dir), then drop phase 2.
cd ${output_path}
PYTHONPATH="${exp_path}/baselines/ADCo" "${adco_venv}" -m src.adco ${codebase_path} \
    --mode rewrite-only \
    --model ${llm_model} \
    --db-type ${dbms} \
    --db-name ${benchmark} \
    --sandbox-dir ${output_path} \
    --db-config ${output_path}/db.config \
    --intent-output ${output_path}/out/adco/intent_result.json \
    --rewriter-output ${output_path}/out/adco/rewriter_result.json \
    --log-file ${output_path}/knob_tuner.log \
    --output-path ${output_path}/result.json \
    --verbose
rc=$?
if [ $rc -ne 0 ]; then
    echo "--- ${output_path}/knob_tuner.log (tail) ---" >&2
    tail -n 50 ${output_path}/knob_tuner.log >&2 || true
    exit $rc
fi

# Tune-only never copies (rewriter skipped), so CWD stays valid; target
# the rewritten sandbox and reuse the phase-1 files for the combined
# output.
cd ${output_path}
PYTHONPATH="${exp_path}/baselines/ADCo" "${adco_venv}" -m src.adco ${output_path} \
    --mode tune-only \
    --model ${llm_model} \
    --db-type ${dbms} \
    --db-name ${benchmark} \
    --cpu-cores 2 \
    --memory 8 \
    --db-config ${output_path}/db.config \
    --intent-output ${output_path}/out/adco/intent_result.json \
    --rewriter-output ${output_path}/out/adco/rewriter_result.json \
    --log-file ${output_path}/knob_tuner.log \
    --output-path ${output_path}/result.json \
    --verbose
rc=$?
if [ $rc -ne 0 ]; then
    echo "--- ${output_path}/knob_tuner.log (tail) ---" >&2
    tail -n 50 ${output_path}/knob_tuner.log >&2 || true
    exit $rc
fi
