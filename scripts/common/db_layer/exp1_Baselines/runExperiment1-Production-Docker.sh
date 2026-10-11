#!/usr/bin/env bash
# Backward-compat shim: delegates to the shared harness lib.
# Preserves the original CLI: <op> <container> <service> (pass-through "$@").
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/../../../_lib/docker.sh" "$@"
