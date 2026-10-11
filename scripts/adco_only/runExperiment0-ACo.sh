#!/usr/bin/env bash
set -euo pipefail

codebase_path="${1:-}"
llm_model="${2:-gemini-3.5-flash-lite}"
dbms="${3:-postgres}"
benchmark="${4:-smallbank}"

if [ -z "${codebase_path}" ]; then
    echo "Usage: $(basename "$0") <codebase> <model> <dbms> <benchmark>" >&2
    exit 2
fi

exp_path="$(cd "$(dirname "$0")/../.." && pwd)"

output_path="${exp_path}/out/adco_only/ACo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"

# Start from a pristine sandbox. The rewriter refuses to overwrite a
# non-empty directory that lacks its .adco_sandbox marker, so stale output
# from an earlier run would abort the copy and every replace_function would
# fail with "not present in the sandbox filesystem".
rm -rf "${output_path}"
mkdir -p "${output_path}"

# Upstream copy_to_sandbox may skip: pre-populate the sandbox so optimizer
# tools always find the files. Managed marker lets a later upstream copy
# still recognise (and refresh) the dir.
if [ ! -f "${output_path}/.adco_sandbox" ]; then
    ( cd "${codebase_path}" && tar --exclude=.git --exclude=__pycache__ --exclude=.venv --exclude=venv -cf - . ) | ( cd "${output_path}" && tar -xf - )
    printf '%s' "adco-managed-sandbox-v1" > "${output_path}/.adco_sandbox"
fi

# Run from the ADCo checkout, NOT the sandbox: the pipeline writes its log
# and out/ relative to CWD before the rewriter copies the target, which would
# poison the sandbox and make the copy refuse. Target files resolve via
# state["sandbox"], so CWD does not matter. Invoke the project venv python
# directly with PYTHONPATH instead of `uv run` (which would mutate/recreate
# .venv).
adco_venv="${exp_path}/baselines/ADCo/.venv/bin/python"
[ -x "${adco_venv}" ] || adco_venv="${exp_path}/baselines/ADCo/venv/bin/python"
cd "${exp_path}/baselines/ADCo"
PYTHONPATH="${exp_path}/baselines/ADCo" "${adco_venv}" -m src.adco "${codebase_path}" \
    --model="${llm_model}" \
    --mode=rewrite-only \
    --db-type="${dbms}" \
    --db-name="${benchmark}" \
    --sandbox-dir="${output_path}" \
    --output-path="${output_path}/result.json" \
    --verbose
