#!/bin/bash

dbms=$1
accounts=$2

exp_path="$(pwd)"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

CMD="python main.py load \
                    --driver ${dbms} \
                    --accounts ${accounts} \
                    --reset"
$CMD
