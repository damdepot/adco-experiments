#!/bin/bash

root_path="$(pwd)"
baseline_path="${root_path}/baselines"

mkdir -p ${baseline_path}

cd ${baseline_path}
rm -rf R-Bot
git clone --depth 1 https://github.com/dannykhant/r-bot.git R-Bot

rm -rf ReSequel
git clone --depth 1 https://github.com/dannykhant/resequel.git ReSequel