#!/bin/bash
set -e

dbms=$1
benchmark=$2

case "${dbms}" in
    postgres|postgresql) dbms_sec="postgres"; client="DB_client_pg.py" ;;
    mysql)                dbms_sec="mysql";   client="DB_client_mysql.py" ;;
    *) echo "Invalid dbms: ${dbms}. Supported: postgres, mysql." >&2; exit 1 ;;
esac

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"

workload_input="${exp_path}/baselines/AgentTune/workload analyzer/workloads/${benchmark}.wg"
workload_schema="${exp_path}/baselines/AgentTune/workload analyzer/workloads/${benchmark}.json"

cd "${exp_path}/baselines/AgentTune"
source venv/bin/activate

python "./workload analyzer/WorkloadParser.py" --workload_file "${workload_input}" --config_file "${workload_schema}"
python "./knob selector/anonymize.py" --dbms=${dbms_sec}
python "./knob selector/knob_select.py" --dbms=${dbms_sec}
python "./range pruner/anonymize.py" --dbms=${dbms_sec}
python "./range pruner/range_pruner.py" --dbms=${dbms_sec}

# Start the LLM server in the background so the tuning client can run after it.
python "./configuration recommender/LLM_server.py" --dbms=${dbms_sec} &
LLM_PID=$!
trap 'kill $LLM_PID 2>/dev/null || true; wait $LLM_PID 2>/dev/null || true' EXIT

# Wait until the LLM server accepts connections on the configured port.
LLM_PORT=$(python -c "import configparser; c = configparser.ConfigParser(); c.read('./config.ini'); print(c.get('configuration recommender', 'LLM_server_port'))")
LLM_HOST=$(python -c "import configparser; c = configparser.ConfigParser(); c.read('./config.ini'); print(c.get('configuration recommender', 'LLM_server_IP', fallback='localhost'))")
echo "Waiting for LLM server on ${LLM_HOST}:${LLM_PORT}..."
for _ in $(seq 1 60); do
    if (echo > "/dev/tcp/${LLM_HOST}/${LLM_PORT}") 2>/dev/null; then
        echo "LLM server is up."
        break
    fi
    sleep 1
done

python "./configuration recommender/${client}" --dbms=${dbms_sec}

echo '-------------------<< Shutting down LLM server >>-------------------'
kill $LLM_PID 2>/dev/null || true
wait $LLM_PID 2>/dev/null || true
trap - EXIT
