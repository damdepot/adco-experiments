#!/bin/bash
set -e

dbms=$1
benchmark=$2

memory_gb="${3:-${TARGET_MEMORY_GB:-8.0}}"
cpu_cores="${4:-${TARGET_CPU_CORES:-2}}"

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
gptuner_path="${exp_path}/baselines/GPTuner"

cd "${gptuner_path}"
source venv/bin/activate

python run_gptuner_exp.py \
    --db "${dbms}" \
    --benchmark "${benchmark}" \
    --exp-path "${exp_path}" \
    --memory-gb "${memory_gb}" \
    --cpu-cores "${cpu_cores}" \
    --coarse-trials 30 \
    --fine-trials 110

