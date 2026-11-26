#!/usr/bin/env bash
#
# Dispatcher for DCo / ADCo tuning (keeps <op> <model> <dbms> <benchmark> order).
# Callable standalone or as a bench_arm_from_seed tool fn (via the run6 tool
# wrappers, which export the canonical contract first).
#
set -euo pipefail

op="${1:-}"
llm_model="${2:-}"
dbms="${3:-}"
benchmark="${4:-}"
target_sys="${5:-}"

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
codebase_path="${exp_path}/workload/apps/${benchmark}"

CMDADCo=./scripts/common/db_layer/exp0_ADCo/runExperiment0-ADCo.sh
CMDDCo=./scripts/common/db_layer/exp0_ADCo/runExperiment0-DCo.sh

if [ "${op}" == "ADCo" ] || [ "${target_sys}" == "adco" ]; then
    $CMDADCo "${codebase_path}" "${llm_model}" "${dbms}" "${benchmark}"
elif [ "${op}" == "DCo" ] || [ "${target_sys}" == "dco" ]; then
    $CMDDCo "${codebase_path}" "${llm_model}" "${dbms}" "${benchmark}"
else
    echo "Invalid operation: $op. Supported operations are: ADCo, DCo, KnobTune."
    exit 2
fi
