#!/bin/bash
# Build the ReSequel data catalog for a dataset (e.g. catalog/stats/
# including schema.json, which the LearnedRewrite baseline requires).
# Usage: stats-build-catalog.sh [dataset] [dbms] [scale]
# e.g.:  ./run/setup/stats-build-catalog.sh stats PostgreSQL 1
#
# Prerequisites: baseline venvs (./run/setup/stats-setup-baselines.sh) and
# a prepared database for the dataset (e.g. stats-prepare-postgres-remote.sh),
# since the catalog is read from the live schema.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

DATASET="${1:-stats}"
DBMS="${2:-PostgreSQL}"
SCALE="${3:-1}"

# ReSequel venv must exist; BuildCatalog runs inside it.
if [ ! -x "${ROOT}/baselines/ReSequel/src/main/python/venv/bin/python" ]; then
    echo "ERROR: ReSequel venv not found; run ./run/setup/stats-setup-baselines.sh first." >&2
    exit 1
fi

echo "-------------------<< Building catalog for ${DATASET} (${DBMS}) >>-------------------"
./scripts/common/query_layer/exp1_ReSequel/runExperiment1.sh BuildCatalog "${DATASET}" "${DBMS}" "${SCALE}"

# Fail loudly if nothing was produced (downstream baselines fail cryptically).
if [ ! -f "${ROOT}/catalog/${DATASET}/schema.json" ]; then
    echo "ERROR: catalog build produced no schema file: catalog/${DATASET}/schema.json." >&2
    exit 1
fi

echo "-------------------<< Catalog ready: catalog/${DATASET}/ >>-------------------"
