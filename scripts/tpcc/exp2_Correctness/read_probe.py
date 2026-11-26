#!/usr/bin/env python3
"""Run deterministic read-only probes and print JSON.

Run with cwd set to the app tree under test (baseline or a rewrite dir);
imports resolve from cwd so each tree's own driver code is exercised::

    cd <tree> && <venv-python> read_probe.py --dbms postgres --config <db.config>

Only read-only transactions are probed (ORDER_STATUS, STOCK_LEVEL), so the
database state is unchanged. Floats are rounded and dates ISO-formatted so
identical semantics compare equal despite driver float handling.
"""

import argparse
import json
import os
import sys
from configparser import ConfigParser

sys.path.insert(0, os.getcwd())
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from tpcc_correctness import normalize_value  # noqa: E402
from tpcc_correctness import sort_probe_lines  # noqa: E402


def build_probes(cursor):
    probes = []
    for c_id in (1, 2, 3, 4, 5):
        probes.append(("order_status_id:1:1:%d" % c_id, "doOrderStatus",
                       {"w_id": 1, "d_id": 1, "c_id": c_id, "c_last": None}))
    cursor.execute("SELECT DISTINCT C_LAST FROM CUSTOMER "
                   "WHERE C_W_ID = 1 AND C_D_ID = 1 ORDER BY C_LAST LIMIT 3")
    for (last,) in cursor.fetchall():
        probes.append(("order_status_name:1:1:%s" % last, "doOrderStatus",
                       {"w_id": 1, "d_id": 1, "c_id": None, "c_last": last}))
    for (w, d, t) in ((1, 1, 10), (1, 1, 15), (1, 1, 20), (2, 3, 12), (1, 5, 18)):
        probes.append(("stock_level:%d:%d:%d" % (w, d, t), "doStockLevel",
                       {"w_id": w, "d_id": d, "threshold": t}))
    return probes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dbms", default="postgres")
    ap.add_argument("--config", required=True)
    args = ap.parse_args()

    from drivers.postgresdriver import PostgresDriver

    cparser = ConfigParser()
    cparser.read(os.path.realpath(args.config))
    config = dict(cparser.items(args.dbms))

    driver = PostgresDriver(os.path.join(os.getcwd(), "tpcc.sql"))
    driver.loadConfig(config)

    out = []
    for name, method, params in build_probes(driver.cursor):
        try:
            result = sort_probe_lines(
                method, normalize_value(getattr(driver, method)(dict(params))))
            out.append({"name": name, "params": params, "result": result})
        except Exception as e:  # noqa: BLE001 — errors are data for the diff
            out.append({"name": name, "params": params,
                        "error": "%s: %s" % (type(e).__name__, e)})
    try:
        driver.conn.close()
    except Exception:  # noqa: BLE001, S110 — best effort
        pass
    print(json.dumps({"probes": out}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
