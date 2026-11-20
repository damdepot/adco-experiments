#!/usr/bin/env python3
"""Run deterministic read-only BALANCE probes and print JSON.

Run with cwd set to the app tree under test (baseline or a rewrite dir);
imports resolve from cwd so each tree's own driver code is exercised::

    cd <tree> && <venv-python> read_probe.py --dbms postgres --config <db.config>

Only BALANCE is probed: it is the one SmallBank transaction that mutates
nothing (the others write, and AMALGAMATE/SEND_PAYMENT/... are covered by the
invariant checks). Account names are the loader's zero-padded custids, so a
fixed id range gives the same reads on the same snapshot. Floats are rounded
so identical semantics compare equal despite driver float handling.
"""

import argparse
import importlib
import json
import os
import sys
from configparser import ConfigParser

sys.path.insert(0, os.getcwd())
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from smallbank_correctness import normalize_value  # noqa: E402

PROBE_IDS = range(1, 201)
CUST_NAME_FORMAT = "%064d"


def connect(dbms, config):
    if dbms == "postgres":
        import psycopg2

        return psycopg2.connect(
            host=config.get("host"),
            port=config.get("port"),
            user=config.get("user"),
            password=config.get("password"),
            dbname=config.get("database"),
        )
    import pymysql

    return pymysql.connect(
        host=config.get("host"),
        port=int(config.get("port", 3306)),
        user=config.get("user"),
        password=config.get("password"),
        database=config.get("database"),
        autocommit=False,
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dbms", default="postgres")
    ap.add_argument("--config", required=True)
    args = ap.parse_args()

    driver_mod = importlib.import_module("drivers.%sdriver" % args.dbms)

    cparser = ConfigParser()
    cparser.read(os.path.realpath(args.config))
    config = dict(cparser.items(args.dbms))

    conn = connect(args.dbms, config)
    out = []
    try:
        for acct_id in PROBE_IDS:
            name = CUST_NAME_FORMAT % acct_id
            try:
                result = normalize_value(driver_mod.balance(conn, name))
                out.append({"name": name, "result": result})
            except Exception as e:  # noqa: BLE001 — errors are data for the diff
                conn.rollback()
                out.append(
                    {
                        "name": name,
                        "error": "%s: %s" % (type(e).__name__, e),
                    }
                )
    finally:
        try:
            conn.close()
        except Exception:  # noqa: BLE001, S110 — best effort
            pass
    print(json.dumps({"probes": out}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
