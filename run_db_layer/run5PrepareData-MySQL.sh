#!/bin/bash

set -e

root_path="$(cd "$(dirname "$0")" && pwd)"
stats_path="${root_path}/Experiments/data/stats"
workload_path="${root_path}/workload/databases/MySQL/stats"

STATS_PATH="${stats_path}" SCHEMA_PATH="${workload_path}/schema.sql" \
IMPORT_PATH="${workload_path}/import.sql" \
python3 - <<'PY'
import os
import mysql.connector

connection = mysql.connector.connect(
    host=os.getenv("MYSQL_HOST", "db"),
    port=int(os.getenv("MYSQL_PORT", "3306")),
    user=os.getenv("MYSQL_USER", "root"),
    password=os.getenv("MYSQL_PASSWORD", "root"),
    allow_local_infile=True,
)

try:
    cursor = connection.cursor()
    cursor.execute("DROP DATABASE IF EXISTS stats")
    cursor.execute("CREATE DATABASE stats")
    cursor.execute("USE stats")
    os.chdir(os.environ["STATS_PATH"])

    for path in (os.environ["SCHEMA_PATH"], os.environ["IMPORT_PATH"]):
        for statement in open(path).read().split(";"):
            if statement.strip():
                cursor.execute(statement)
    connection.commit()
finally:
    connection.close()
PY

echo '-------------------<< STATS database (MySQL Compose db service) is ready >>-------------------'
