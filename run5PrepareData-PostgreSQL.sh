#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")" && pwd)"
data_path="${root_path}/Experiments/data/stats"
workload_path="${root_path}/Experiments/workload/PostgreSQL/stats"

export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

echo '-------------------<< Preparing STATS database >>-------------------'
dropdb --if-exists stats
createdb stats

cd "${data_path}"
psql -d stats -f "${workload_path}/schema.sql"
psql -d stats -f "${workload_path}/import.sql"
psql -d stats -f "${workload_path}/index.sql"

echo '-------------------<< STATS database (remote Compose PostgreSQL service) is ready >>-------------------'

echo '-------------------<< Preparing STATS-LITE database >>-------------------'
dropdb --if-exists stats-lite
createdb stats-lite

cd "${data_path}"
psql -d stats-lite -f "${workload_path}/schema.sql"
psql -d stats-lite -f "${workload_path}/import.sql"
psql -d stats-lite -f "${workload_path}/index.sql"

echo '-------------------<< STATS-LITE database (remote Compose PostgreSQL service) is ready >>-------------------'
