#!/bin/bash

rm -rf reports/adco_only
mkdir -p reports/adco_only

CMDRunReports=./scripts/adco_only/run_report.sh

$CMDRunReports "$@"
