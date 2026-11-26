FROM ghcr.io/astral-sh/uv:python3.10-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    JAVA_HOME=/opt/java8 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# System deps mirror run/setup/deps-local.sh (needed only on a
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

# Temurin 8 JRE for Py-DBridge's SCIRPy gateway (needs Java 8; bookworm apt has no openjdk-8).
# Java 17 (default-jre-headless above) is kept; JAVA_HOME redirect is enough for the bridge.
RUN ARCH="$(dpkg --print-architecture)" \
    && case "$ARCH" in amd64) ADOPT_ARCH=x64;; arm64) ADOPT_ARCH=aarch64;; *) echo "unsupported arch: $ARCH" >&2; exit 1;; esac \
    && curl -fsSL "https://api.adoptium.net/v3/binary/latest/8/ga/linux/${ADOPT_ARCH}/jre/hotspot/normal/eclipse" -o /tmp/jre8.tar.gz \
    && mkdir -p /opt/java8 \
    && tar -xzf /tmp/jre8.tar.gz -C /opt/java8 --strip-components=1 \
    && rm /tmp/jre8.tar.gz \
    && update-alternatives --install /usr/bin/java java /opt/java8/bin/java 1080 \
    && update-alternatives --set java /opt/java8/bin/java

COPY workload/src/requirements.txt /tmp/requirements.txt
RUN uv pip install --system -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
