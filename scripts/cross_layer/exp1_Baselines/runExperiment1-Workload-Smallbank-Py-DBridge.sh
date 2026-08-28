#!/bin/bash

dbms=$1
accounts=$2
transactions=$3
benchmark=$4

exp_path="$(pwd)"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

cd "${exp_path}/out/cross_layer/Py-DBridge-results/Rewrite/${dbms}/${benchmark}-Py-DBridge"

CMD="python main.py run \
                    --driver ${dbms} \
                    --accounts ${accounts} \
                    --transactions ${transactions}"
$CMD
