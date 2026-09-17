#!/bin/bash

set -e

op=$1
container=$2
service=$3

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
compose_file="${exp_path}/docker-compose.yml"


if [ "$op" == "Restart" ]; then  
    echo '-------------------<< Restarting docker production database >>-------------------'
    docker restart "${container}"

elif [ "$op" == "Down" ]; then  
    echo '-------------------<< Removing docker production database >>-------------------'
    docker stop "${container}"
    docker rm -v -f "${container}"

elif [ "$op" == "Up" ]; then  
    echo '-------------------<< Creating docker production database >>-------------------'
    docker-compose -p adco-experiments -f "${compose_file}" up -d "${service}"

else     
    echo "Invalid operation: $op. Supported operations are: Restart, Down, Up."
fi