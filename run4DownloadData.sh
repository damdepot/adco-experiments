#!/bin/bash

root_path="$(pwd)"
data_path="${root_path}/data"
stats_path="${data_path}/stats"

mkdir -p "${data_path}"
rm -rf "${stats_path}"
mkdir "${stats_path}"

cd "${data_path}"
rm -rf part-1 part-2 part-1.zip part-2.zip

echo '-------------------<< Downloading STATS dataset >>-------------------'
wget -q https://raw.githubusercontent.com/dannykhant/benchmark-datasets/main/stats/part-1.zip
wget -q https://raw.githubusercontent.com/dannykhant/benchmark-datasets/main/stats/part-2.zip
unzip -q part-1.zip
unzip -q part-2.zip

mv part-1/* "${stats_path}/"
mv part-2/* "${stats_path}/"
rm -rf part-1 part-2 part-1.zip part-2.zip
