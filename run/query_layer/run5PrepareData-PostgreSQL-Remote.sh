#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
data_path="${root_path}/data/stats"
workload_path="${root_path}/workload/databases/PostgreSQL/stats"

export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"

echo '-------------------<< Preparing STATS database >>-------------------'
dropdb --if-exists stats
createdb stats

cd "${data_path}"
psql -d stats -f "${workload_path}/schema.sql"
psql -d stats -f "${workload_path}/import_remote.sql"
psql -d stats -f "${workload_path}/index.sql"

echo '-------------------<< STATS database (Remote Compose PostgreSQL service) is ready >>-------------------'
