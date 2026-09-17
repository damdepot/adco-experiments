#!/bin/bash

rm -rf reports/query_layer
mkdir -p reports/query_layer

CMDRunReports=./scripts/query_layer/exp3_Reports/run_report.sh

$CMDRunReports "$@"