#!/bin/bash

root_path="$(pwd)"
baseline_path="${root_path}/baselines"

mkdir -p ${baseline_path}
cd ${baseline_path}

echo '-------------------<< Downloading ReSequel >>-------------------'
rm -rf ReSequel
git clone --depth 1 https://github.com/dannykhant/resequel.git ReSequel

echo '-------------------<< Downloading R-Bot >>-------------------'
rm -rf R-Bot
git clone --depth 1 https://github.com/dannykhant/r-bot.git R-Bot

echo '-------------------<< Downloading LearnedRewrite >>-------------------'
rm -rf LearnedRewrite
git clone --depth 1 https://github.com/dannykhant/learnedrewrite.git LearnedRewrite