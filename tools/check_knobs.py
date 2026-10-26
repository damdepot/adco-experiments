#!/usr/bin/env python3
"""Report knobs overridden in the production Postgres container.

A knob is "updated" when its value comes from postgresql.auto.conf (i.e. it was
set on top of the defaults). Step 1 finds names via pg_file_settings, not
pg_settings: the latter reports a pending restart-required knob (e.g.
shared_buffers) as coming from postgresql.conf until the server is restarted,
so it is invisible there. Step 2 checks those names against live pg_settings
to resolve values and units (bare file values like 16384 are ambiguous).
"""

import os
import subprocess
import sys

CONTAINER = os.environ.get("BENCH_DB_CONTAINER", "adcoexp-db")
QUERY_NAMES = "SELECT DISTINCT name FROM pg_file_settings WHERE sourcefile LIKE '%postgresql.auto.conf' ORDER BY name;"


def format_knobs(knobs):
    if not knobs:
        return "No updated knobs detected."
    return "{} updated knobs detected. They are - \n\n{}".format(len(knobs), "\n".join(knobs))


def fetch_names(container):
    out = subprocess.run(
        ["docker", "exec", "-u", "postgres", container, "psql", "-tA", "-c", QUERY_NAMES],
        capture_output=True,
        text=True,
        check=True,
    )
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]


def live_query(names):
    in_list = ", ".join("'{}'".format(n.replace("'", "''")) for n in names)
    return "SELECT name, setting, unit FROM pg_settings WHERE name IN ({}) ORDER BY name;".format(in_list)


def parse_live_line(line):
    parts = line.split("|")
    name = parts[0].strip() if len(parts) > 0 else ""
    setting = parts[1].strip() if len(parts) > 1 else ""
    unit = parts[2].strip() if len(parts) > 2 else ""
    if unit:
        return "{} = {} {}".format(name, setting, unit)
    return "{} = {}".format(name, setting)


def fetch_live(container, names):
    out = subprocess.run(
        ["docker", "exec", "-u", "postgres", container, "psql", "-tA", "-c", live_query(names)],
        capture_output=True,
        text=True,
        check=True,
    )
    return [parse_live_line(line) for line in out.stdout.splitlines() if line.strip()]


def _selftest():
    assert format_knobs([]) == "No updated knobs detected."
    assert format_knobs(["knob A = 1", "knob B = off"]) == (
        "2 updated knobs detected. They are - \n\nknob A = 1\nknob B = off"
    )
    assert live_query(["a", "b"]) == (
        "SELECT name, setting, unit FROM pg_settings WHERE name IN ('a', 'b') ORDER BY name;"
    )
    assert parse_live_line("work_mem|16384|kB") == "work_mem = 16384 kB"
    assert parse_live_line("max_wal_size|4096|MB") == "max_wal_size = 4096 MB"
    assert parse_live_line("autovacuum|on|") == "autovacuum = on"
    print("selftest ok")


def main():
    try:
        names = fetch_names(CONTAINER)
        if not names:
            print(format_knobs([]))
            return 0
        knobs = fetch_live(CONTAINER, names)
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
