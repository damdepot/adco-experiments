#!/bin/bash
# Build the ReSequel data catalog for a dataset (e.g. catalog/tpch-s1/
# including schema.json, which the LearnedRewrite baseline requires).
# Usage: tpch-build-catalog.sh [dataset] [dbms] [scale]
# e.g.:  ./run/setup/tpch-build-catalog.sh tpch PostgreSQL 1
#
# Prerequisites: baseline venvs (./run/setup/tpch-setup-baselines.sh) and
# a prepared database for the dataset (e.g. tpch-prepare-postgres-remote.sh),
# since the catalog is read from the live schema.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

DATASET="${1:-tpch}"
DBMS="${2:-PostgreSQL}"
SCALE="${3:-1}"

# ReSequel venv must exist; BuildCatalog runs inside it.
if [ ! -x "${ROOT}/baselines/ReSequel/src/main/python/venv/bin/python" ]; then
    echo "ERROR: ReSequel venv not found; run ./run/setup/tpch-setup-baselines.sh first." >&2
    exit 1
fi

echo "-------------------<< Building catalog for ${DATASET} (${DBMS}) >>-------------------"
./scripts/common/query_layer/exp1_ReSequel/runExperiment1.sh BuildCatalog "${DATASET}" "${DBMS}" "${SCALE}"

# runExperiment1.sh uses catalog/${dataset}-s${scale} for tpch/tpcds datasets,
# and catalog/${dataset} otherwise — mirror that logic here.
EXPECTED="catalog/${DATASET}"
if [ "${DATASET}" = "tpch" ] || [ "${DATASET}" = "tpcds" ]; then
    EXPECTED="catalog/${DATASET}-s${SCALE}"
fi

# Fail loudly if nothing was produced (downstream baselines fail cryptically).
if [ ! -f "${ROOT}/${EXPECTED}/schema.json" ]; then
    echo "ERROR: catalog build produced no schema file: ${EXPECTED}/schema.json." >&2
    exit 1
fi

echo "-------------------<< Catalog ready: ${EXPECTED}/ >>-------------------"
