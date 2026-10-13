#!/usr/bin/env python3
"""Report knobs overridden in the production Postgres container.

A knob is "updated" when its value comes from postgresql.auto.conf (i.e. it was
set on top of the defaults), which is exactly the signal bench_lib's
bench_assert_fresh_knobs uses to detect tuned state.
"""

import os
import subprocess
import sys

CONTAINER = os.environ.get("BENCH_DB_CONTAINER", "adcoexp-db")
QUERY = "SELECT name FROM pg_settings WHERE sourcefile LIKE '%postgresql.auto.conf' ORDER BY name;"


def format_knobs(names):
    if not names:
        return "No updated knobs detected."
    return "{} updated knobs detected. They are - \n\n{}".format(len(names), "\n".join(names))


def fetch_knobs(container):
    out = subprocess.run(
        ["docker", "exec", "-u", "postgres", container, "psql", "-tA", "-c", QUERY],
        capture_output=True,
        text=True,
        check=True,
    )
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]


def _selftest():
    assert format_knobs([]) == "No updated knobs detected."
    assert format_knobs(["knob A", "knob B"]) == (
        "2 updated knobs detected. They are - \n\nknob A\nknob B"
    )
    print("selftest ok")


def main():
    try:
        names = fetch_knobs(CONTAINER)
    except subprocess.CalledProcessError as e:
        sys.stderr.write("ERROR: could not query '{}': {}\n".format(CONTAINER, e.stderr.strip()))
        return 1
    except FileNotFoundError:
        sys.stderr.write("ERROR: docker not found on PATH.\n")
        return 1
    print(format_knobs(names))
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
        sys.exit(0)
    sys.exit(main())
