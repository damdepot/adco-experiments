#!/bin/bash
#
# Naive-LLM query-layer pipeline dispatcher.
# Mirrors exp0_ADCo/runExperiment0.sh, but the Rewrite step runs the
# single-shot NaiveLLM CLI on a driver file compiled from query*.sql.
#
# Usage: runExperiment2-NaiveLLM.sh <op> <dataset> <dbms> <scale> <llm_model>
# Ops: Compile, Rewrite, Decompile, Verify

op=$1
dataset=$2
dbms=$3
scale=$4
llm_model=$5

exp_path="$(pwd)"
workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"
res_dir="NaiveLLM-results"

compile_path="${exp_path}/out/query_layer/${res_dir}/Compile/${dbms}/${dataset}-${llm_model}"
rewrite_path="${exp_path}/out/query_layer/${res_dir}/Rewrite/${dbms}/${dataset}-${llm_model}"
decompile_path="${exp_path}/out/query_layer/${res_dir}/Decompile/${dbms}/${dataset}-${llm_model}"
select_path="${exp_path}/out/query_layer/${res_dir}/Select/${dbms}/${dataset}-${llm_model}-select"

naive_dir="${exp_path}/baselines/NaiveLLM"
naive_python="${naive_dir}/venv/bin/python"

if [ ! -x "${naive_python}" ]; then
    echo "ERROR: NaiveLLM venv not found at ${naive_python}; run run/setup/app-setup-baselines.sh." >&2
    exit 1
fi

if [ "$op" == "Compile" ]; then
    rm -rf "${compile_path}"
    mkdir -p "${compile_path}"
    cd "${naive_dir}"
    "${naive_python}" -m src.query_codec compile --input-dir "${workload_path}" --output-dir "${compile_path}"

elif [ "$op" == "Rewrite" ]; then
    rm -rf "${rewrite_path}"
    mkdir -p "${rewrite_path}"
    cd "${naive_dir}"
    "${naive_python}" -m src.cli --source-dir "${compile_path}" --output-dir "${rewrite_path}" --db "${dbms}" --model "${llm_model}"

elif [ "$op" == "Decompile" ]; then
    rm -rf "${decompile_path}"
    mkdir -p "${decompile_path}"
    cd "${naive_dir}"
    "${naive_python}" -m src.query_codec decompile --input-dir "${rewrite_path}" --output-dir "${decompile_path}"

    if [ -z "$(find "${decompile_path}" -maxdepth 2 -name '*.sql' -print -quit 2>/dev/null)" ]; then
        echo "ERROR: decompile produced no query files in ${decompile_path} (db_app.py missing or without QUERY_<n> constants)." >&2
        exit 1
    fi

elif [ "$op" == "Verify" ]; then
    if [ -z "$(find "${decompile_path}" -maxdepth 2 -name '*.sql' -print -quit 2>/dev/null)" ]; then
        echo "ERROR: no query files to verify in ${decompile_path}." >&2
        exit 1
    fi

    rm -rf "${select_path}"
    mkdir -p "${select_path}"

    cd "${exp_path}"
    if [ "$dbms" == "PostgreSQL" ]; then
        if [ -z "$PGHOST" ] || [[ "$PGHOST" == "localhost" || "$PGHOST" == "127.0.0.1" ]]; then
            ./run/setup/stats-init-pgsql.sh
            sleep 10
        fi
    elif [ "$dbms" == "MySQL" ]; then
        ./initMySQL.sh
        sleep 10
    fi

    verify_log_path="${exp_path}/${RESULTS_DATASET_DIR:-results/${dataset}}/naive-llm/Experiment0_Verify.dat"
    mkdir -p "$(dirname "${verify_log_path}")"

    cd "${exp_path}/workload/src"
    source venv/bin/activate

    CMD="python main_verify_LR.py --workload-path ${workload_path} \
                        --database-name ${dataset} \
                        --dbms ${dbms} \
                        --rewrite-path ${decompile_path} \
                        --verify-log-path ${verify_log_path} \
                        --output-path-verify ${select_path} \
                        --verbose"

    if [ -n "${THREADS:-}" ]; then
        CMD="${CMD} --threads ${THREADS}"
    fi

    $CMD

else
    echo "Invalid operation: $op. Supported operations are: Compile, Rewrite, Decompile, Verify."
    exit 1
fi
