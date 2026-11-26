#!/bin/bash

dataset=$1
dbms=$2
baseline_name='R-Bot'
llm_model=$4

exp_path="$(pwd)"


date=$(date '+%Y-%m-%d-%H-%M-%S')
system_log="${exp_path}/out/query_layer/R-Bot-results/system-log-${date}.dat"

output_path="${exp_path}/out/query_layer/R-Bot-results/Rewrite/${dbms}/${dataset}/${llm_model}"
log_dir="${exp_path}/out/query_layer/R-Bot-results/Rewrite/${dbms}/${dataset}/${llm_model}-LOG"

mkdir -p "${exp_path}/out/query_layer/R-Bot-results/Rewrite"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/Rewrite/${dbms}"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/Rewrite/${dbms}/${dataset}"
mkdir -p "${output_path}"
mkdir -p "${log_dir}"

workload_output="${exp_path}/out/query_layer/R-Bot-results/workload/${dbms}/${dataset}/${llm_model}"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/workload"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/workload/${dbms}"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/workload/${dbms}/${dataset}"
mkdir -p "${workload_output}"

cache_path="${exp_path}/out/query_layer/R-Bot-results/cache/${dbms}/${dataset}/${llm_model}"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/cache"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/cache/${dbms}"
mkdir -p "${exp_path}/out/query_layer/R-Bot-results/cache/${dbms}/${dataset}"
mkdir -p "${cache_path}"

result_log_path="${exp_path}/${RESULTS_DATASET_DIR:-results/${dataset}}/r-bot/Experiment2-R-Bot-Rewrite-${dataset}-${dbms}-${llm_model}.dat"
mkdir -p "$(dirname "$result_log_path")"

workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"
log_file_name="${exp_path}/${RESULTS_DATASET_DIR:-results/${dataset}}/r-bot/runExperiment2-${dataset}-${dbms}-${baseline_name}-${llm_model}.dat"
mkdir -p "$(dirname "$log_file_name")"

if [ $dataset == "publicbibenchmark" ]; then
    mkdir -p "${output_path}/queries"
fi 

cd "${exp_path}/baselines/R-Bot"
# R-Bot's Calcite/JPype bridge requires Java 17. Pin JAVA_HOME so JPype
# never picks up a Java 8 default; an explicit RBOT_JAVA_HOME wins.
if [ -n "${RBOT_JAVA_HOME:-}" ]; then
    export JAVA_HOME="${RBOT_JAVA_HOME}"
elif [ -x /usr/lib/jvm/default-java/bin/java ]; then
    export JAVA_HOME=/usr/lib/jvm/default-java
fi
_rbot_java_bin="${JAVA_HOME:+$JAVA_HOME/bin/java}"
if [ -n "${_rbot_java_bin:-}" ] && [ -x "${_rbot_java_bin}" ]; then
    _rbot_ver="$("${_rbot_java_bin}" -version 2>&1 | head -1)"
else
    _rbot_ver="$(java -version 2>&1 | head -1 || true)"
fi
case "${_rbot_ver}" in
    *17.*) ;;
    *) echo "WARNING: R-Bot Calcite/JPype bridge wants Java 17 (got: ${_rbot_ver})." >&2 ;;
esac
unset _rbot_java_bin _rbot_ver
source venv/bin/activate
cd my_rewriter

CMD="python main.py --database ${dataset} \
                    --llm-model ${llm_model} \
                    --workload-path ${workload_path} \
                    --output-path ${output_path} \
                    --workload-output ${workload_output} \
                    --cache-path ${cache_path} \
                    --dbms ${dbms} \
                    --log-dir ${log_dir} \
                    --result-log-path ${result_log_path} \
                    --system-log ${system_log}"


start=$(date +%s%N)
$CMD
end=$(date +%s%N)

echo ${dataset}",${dbms},"$((($end - $start) / 1000000)) >>$log_file_name

