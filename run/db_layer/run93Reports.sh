#!/bin/bash

rm -rf reports
mkdir -p reports

CMDRunReports=./scripts/db_layer/exp3_Reports/run_report.sh

$CMDRunReports "$@"