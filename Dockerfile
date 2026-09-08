FROM ghcr.io/astral-sh/uv:python3.10-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    JAVA_HOME=/usr/lib/jvm/default-java \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# System deps mirror run/query_layer/run1SetupDependencies.sh (needed only on a
# physical host, not when building this image). Excluded here because the uv base
# image already provides Python/venv/pip: python3.10-venv, python3-pip, python3-dev.
RUN apt-get update && apt-get install -y --no-install-recommends \
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
        docker-compose \
        flex \
        git \
        libicu-dev \
        libreadline-dev \
        ninja-build \
        pkg-config \
        postgresql-client \
        unzip \
        wget \
        sysbench \
    && rm -rf /var/lib/apt/lists/*

COPY workload/src/requirements.txt /tmp/requirements.txt
RUN uv pip install --system -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
