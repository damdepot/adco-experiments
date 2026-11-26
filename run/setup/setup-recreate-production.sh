#!/bin/bash
# Recreate the production database from scratch (fresh container + all
# databases via the db-init service). Destroys all data including seed
# snapshots; runners will reseed on next run.
set -euo pipefail

root_path="$(cd "$(dirname "$0")/../.." && pwd)"

CMDDOCKER="${root_path}/scripts/_lib/docker.sh"
db_container="adcoexp-db"
db_service="pgdb"

echo '-------------------<< Recreating production database >>-------------------'
"${CMDDOCKER}" Down "${db_container}"
"${CMDDOCKER}" Up "${db_container}" "${db_service}"
"${CMDDOCKER}" WaitFor "${db_container}"

echo '-------------------<< Databases >>-------------------'
docker exec -u postgres "${db_container}" psql -tA -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY 1;"

echo '-------------------<< Production database recreated >>-------------------'
