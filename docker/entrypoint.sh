#!/usr/bin/env bash
# adcoexp app container entrypoint.
#
# PostgreSQL runs in the separate `pgdb` service (see docker-compose.yml); this
# image ships no DBMS server. The app connects to `pgdb` via its env vars /
# config files. The repo is bind-mounted into the container at /app.
#
# This script keeps the container alive so `docker exec -it <container> bash`
# works. A command passed at runtime (e.g. `docker compose run adcoexp bash`)
# is executed instead.
set -euo pipefail

echo "[adcoexp] Experiments are deployed at /app."
echo "[adcoexp] Attach a shell with: docker compose exec adcoexp bash"

# If a command was passed (e.g. `docker run -it adcoexp bash`), run it.
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# Keep the container alive so `docker exec` works.
exec tail -f /dev/null
