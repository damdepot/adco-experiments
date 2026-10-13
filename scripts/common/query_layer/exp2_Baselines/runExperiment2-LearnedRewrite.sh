#!/bin/bash

dataset=$1
dbms=$2
baseline_name='LearnedRewrite'

exp_path="$(pwd)"

output_path="${exp_path}/out/query_layer/LearnedRewrite-results/Rewrite/${dbms}/${dataset}-${baseline_name}"
mkdir -p "${exp_path}/out/query_layer/LearnedRewrite-results/Rewrite/${dbms}"

rm -rf ${output_path}
mkdir -p ${output_path}

workload_path="${exp_path}/workload/databases/${dbms}/${dataset}"
schema_path="${exp_path}/catalog/${dataset}/schema.json"
log_file_name="${exp_path}/${RESULTS_DATASET_DIR:-results/${dataset}}/learnedrewrite/runExperiment2-${dataset}-${dbms}-${baseline_name}.dat"
mkdir -p "$(dirname "$log_file_name")"

if [ $dataset == "publicbibenchmark" ]; then
    mkdir -p "${output_path}/queries"
fi 

cd "${exp_path}/baselines/LearnedRewrite"
# LearnedRewrite's Calcite/JPype bridge requires Java 17 (JPype refuses
# Java ≤8). Pin JAVA_HOME so it never picks up a Java 8 default; an
# explicit LEARNEDREWRITE_JAVA_HOME wins.
if [ -n "${LEARNEDREWRITE_JAVA_HOME:-}" ]; then
    export JAVA_HOME="${LEARNEDREWRITE_JAVA_HOME}"
elif [ -x /usr/lib/jvm/default-java/bin/java ]; then
    export JAVA_HOME=/usr/lib/jvm/default-java
fi
_lr_java_bin="${JAVA_HOME:+$JAVA_HOME/bin/java}"
if [ -n "${_lr_java_bin:-}" ] && [ -x "${_lr_java_bin}" ]; then
    _lr_ver="$("${_lr_java_bin}" -version 2>&1 | head -1)"
else
    _lr_ver="$(java -version 2>&1 | head -1 || true)"
fi
case "${_lr_ver}" in
    *17.*) ;;
    *) echo "WARNING: LearnedRewrite Calcite/JPype bridge wants Java 17 (got: ${_lr_ver})." >&2 ;;
esac
unset _lr_java_bin _lr_ver
source venv/bin/activate

CMD="python my_rewriter/main.py --workload-path ${workload_path} \
                    --schema-path ${schema_path} \
                    --database-name ${dataset} \
                    --dbms ${dbms} \
                    --output-path ${output_path}"


start=$(date +%s%N)
$CMD
end=$(date +%s%N)

echo ${dataset}",${dbms},"$((($end - $start) / 1000000)) >>$log_file_name
