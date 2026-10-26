#!/usr/bin/env python3
"""Report knobs overridden in the production Postgres container.

A knob is "updated" when its value comes from postgresql.auto.conf (i.e. it was
set on top of the defaults). We read pg_file_settings, not pg_settings: the
latter reports a pending restart-required knob (e.g. shared_buffers) as coming
from postgresql.conf until the server is restarted, so it is invisible there.
"""

import os
import subprocess
import sys

CONTAINER = os.environ.get("BENCH_DB_CONTAINER", "adcoexp-db")
QUERY = "SELECT name, setting FROM pg_file_settings WHERE sourcefile LIKE '%postgresql.auto.conf' ORDER BY name;"


def format_knobs(knobs):
    if not knobs:
        return "No updated knobs detected."
    return "{} updated knobs detected. They are - \n\n{}".format(len(knobs), "\n".join(knobs))


def fetch_knobs(container):
    out = subprocess.run(
        ["docker", "exec", "-u", "postgres", container, "psql", "-tA", "-c", QUERY],
        capture_output=True,
        text=True,
        check=True,
    )
    knobs = []
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        name, _, value = line.partition("|")
        knobs.append("{} = {}".format(name.strip(), value.strip()))
    return knobs


def _selftest():
    assert format_knobs([]) == "No updated knobs detected."
    assert format_knobs(["knob A = 1", "knob B = off"]) == (
        "2 updated knobs detected. They are - \n\nknob A = 1\nknob B = off"
    )
    print("selftest ok")


def main():
    try:
        knobs = fetch_knobs(CONTAINER)
    except subprocess.CalledProcessError as e:
        sys.stderr.write("ERROR: could not query '{}': {}\n".format(CONTAINER, e.stderr.strip()))
        return 1
    except FileNotFoundError:
        sys.stderr.write("ERROR: docker not found on PATH.\n")
        return 1
    print(format_knobs(knobs))
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
        sys.exit(0)
    sys.exit(main())
