#!/bin/bash

rm -rf reports/db_layer
mkdir -p reports/db_layer

CMDRunReports=./scripts/db_layer/exp2_Reports/run_report.sh

$CMDRunReports "$@"
