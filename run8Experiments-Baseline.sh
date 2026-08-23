#!/bin/bash

# clean baseline results
rm -rf results/baseline
mkdir -p results/baseline/benchmarks

## Run the baseline experiments
#***************
echo '-------------------<< Running the baseline experiments for Stats-Lite dataset >>-------------------'
$CMDBaseline stats-lite PostgreSQL 1