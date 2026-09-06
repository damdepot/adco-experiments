#!/bin/bash

# Mirrors the apt packages in the Dockerfile (run1 only needed on a physical host).
# Host-only extras on top of the image: python3-dev, python3-pip, python3.10-venv.

sudo apt-get update
sudo apt-get install -y \
    bash \
    bison \
    build-essential \
    byacc \
    ca-certificates \
    ccache \
    clang \
    cmake \
    curl \
    default-jre-headless \
    default-libmysqlclient-dev \
    docker.io \
    flex \
    git \
    libicu-dev \
    libreadline-dev \
    ninja-build \
    pkg-config \
    postgresql-client \
    unzip \
    wget \
    python3-dev \
    python3-pip \
    python3.10-venv
