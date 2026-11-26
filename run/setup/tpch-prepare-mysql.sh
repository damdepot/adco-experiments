#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")/../.." && pwd)"
tpch_path="${root_path}/data/tpch"
workload_path="${root_path}/workload/databases/MySQL/tpch"

env_file="${root_path}/.env"
if [ ! -f "$env_file" ]; then
    echo "Error: .env not found in ${root_path}. See README.md." >&2
    exit 1
fi
while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="${line%%=*}"
    case "$key" in ''|*[!A-Za-z0-9_]* ) continue ;; esac
    value="${line#*=}"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf -v "$key" '%s' "$value"
    export "$key"
done < "$env_file"

TPCH_PATH="${tpch_path}" SCHEMA_PATH="${workload_path}/schema.sql" \
IMPORT_PATH="${workload_path}/import.sql" \
python3 - <<'PY'
import os
import mysql.connector

connection = mysql.connector.connect(
    host=os.getenv("MYSQL_HOST", "mysqldb"),
    port=int(os.getenv("MYSQL_PORT", "3306")),
    user=os.getenv("MYSQL_USER", "root"),
    password=os.getenv("MYSQL_PASSWORD", "root"),
    allow_local_infile=True,
)

try:
    cursor = connection.cursor()
    cursor.execute("DROP DATABASE IF EXISTS tpch")
    cursor.execute("CREATE DATABASE tpch")
    cursor.execute("USE tpch")
    os.chdir(os.environ["TPCH_PATH"])

    for path in (os.environ["SCHEMA_PATH"], os.environ["IMPORT_PATH"]):
        for statement in open(path).read().split(";"):
            if statement.strip():
                cursor.execute(statement)
    connection.commit()
finally:
    connection.close()
PY

echo '-------------------<< TPCH database (MySQL Compose db service) is ready >>-------------------'
