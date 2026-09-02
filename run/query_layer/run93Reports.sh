#!/bin/bash

rm -rf reports
mkdir -p reports

CMDRunReports=./scripts/query_layer/exp3_Reports/run_report.sh

$CMDRunReports "$@"