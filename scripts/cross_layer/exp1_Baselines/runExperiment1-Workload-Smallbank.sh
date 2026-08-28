#!/bin/bash

dbms=$1
accounts=$2
transactions=$3

exp_path="$(pwd)"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

CMD="python main.py run \
                    --driver ${dbms} \
                    --accounts ${accounts} \
                    --transactions ${transactions}"
$CMD
