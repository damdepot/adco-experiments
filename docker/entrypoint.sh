#!/usr/bin/env bash
# ReSequel container entrypoint.
#
# PostgreSQL runs in the separate `db` service (see docker-compose.yml); this
# image ships no DBMS server. The app connects to `db` via the
# PGHOST/PGPORT/PGUSER/PGPASSWORD env vars, which src/main/python/util/Config.py
# honors at startup (overriding DBConfig.yaml).
#
# This script keeps the container alive so `docker exec -it <container> bash`
# works. A command passed at runtime (e.g. `docker compose run resequel bash`)
# is executed instead.
set -euo pipefail

echo "[ReSequel] ReSequel is deployed at /app (PYTHONPATH=/app/src/main/python)."
echo "[ReSequel] Example: python src/main/python/main.py --dataset-name <db> --catalog-path <path>"
echo "[ReSequel] Attach a shell with: docker compose exec resequel bash"

# If a command was passed (e.g. `docker run -it resequel bash`), run it.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# Keep the container alive so `docker exec` works.
exec tail -f /dev/null
