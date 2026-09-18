#!/bin/bash

rm -rf reports/app_layer
mkdir -p reports/app_layer

CMDRunReports=./scripts/app_layer/exp2_Reports/run_report.sh

$CMDRunReports "$@"
