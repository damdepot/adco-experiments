#!/bin/bash

apt-get update
apt-get install libreadline-dev -y
apt-get install libicu-dev -y
apt-get -y install pkg-config
apt install python3.10-venv -y
apt-get install bison -y
apt-get install byacc -y
apt-get install bison flex -y
apt-get install git make gcc -y
apt install cmake -y
apt-get install ninja-build build-essential make ccache pip clang -y # DuckDB