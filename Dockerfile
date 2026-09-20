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
        flex \
        git \
        libicu-dev \
        libreadline-dev \
        ninja-build \
        pkg-config \
        postgresql-client \
        swig \
        unzip \
        wget \
        sysbench \
    && rm -rf /var/lib/apt/lists/*

# Install docker compose V2 plugin (fixes compose V1 1.29.2 ContainerConfig / watch_events KeyError: 'id' bugs)
ARG COMPOSE_VERSION=v2.29.2
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in amd64) ARCH=x86_64;; arm64) ARCH=aarch64;; *) echo "unsupported arch: $ARCH" >&2; exit 1;; esac \
    && curl -fsSL "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${ARCH}" -o /usr/local/lib/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose \
    && ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose \
    && docker compose version

COPY workload/src/requirements.txt /tmp/requirements.txt
RUN uv pip install --system -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
