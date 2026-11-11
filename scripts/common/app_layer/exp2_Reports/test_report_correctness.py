"""Correctness plumbing in the app-layer report.

Covers load_correctness_statuses (robustness summary preferred, single-run
verify_<sys>.json fallback, WARN -> SUSPECT), the table cell formatter, and
the rendered Markdown columns/table.
"""

import contextlib
import io
import json
import os
import sys
import tempfile

_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
_TPCC_DIR = os.path.normpath(os.path.join(_THIS_DIR, '..', '..', '..', 'tpcc', 'exp2_Correctness'))
for _p in (_THIS_DIR, _TPCC_DIR):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import report  # noqa: E402
from tpcc_correctness import (correctness_cell, load_correctness_statuses,  # noqa: E402
                              load_verify_statuses)

SYSTEMS = ['baseline', 'adco', 'aco', 'naive-llm']


def _write(path, doc):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(doc, f)


def _summary(**kw):
    doc = {
        "arm": "naive-llm", "workload": "tpcc", "timestamp": "2026-11-10T00:00:00",
        "model": "m", "prompt_file": "p.txt", "prompt_sha256": "abc",
        "runs_requested": 10, "runs_completed": 10,
        "counts": {"pass": 9, "fail": 1, "warn": 0, "unverified": 0},
        "status": "FAIL", "incorrect_rate": 0.1, "wilson_ci95": [0.02, 0.40],
        "distinct_outputs": 6, "measured_artifact": None,
        "verify_seed_db": "tpcc_verify_seed", "verify_warehouses": 10,
        "verify_duration": 10,
        "runs": [{"run": i, "kind": "fresh", "sha256": "s", "rewrite_status": "ok",
                  "changed": 1, "restored": 0,
                  "verify_status": "FAIL" if i == 4 else "PASS",
                  "failed_checks": [], "verify_json": "v.json"}
                 for i in range(1, 11)],
    }
    doc.update(kw)
    return doc


def _tree(tmp):
    """baseline: nothing; adco: WARN summary; aco: single-run PASS;
    naive-llm: 9 pass / 1 fail summary. (missing arm == adco absent case below)"""
    _write(os.path.join(tmp, 'tpcc', 'robustness', 'naive-llm', 'latest.json'), _summary())
    adco_runs = [{"run": i, "kind": "fresh", "sha256": "s", "rewrite_status": "ok",
                  "changed": 1, "restored": 0, "verify_status": "PASS",
                  "failed_checks": [], "verify_json": "v.json"} for i in range(1, 11)]
    _write(os.path.join(tmp, 'tpcc', 'robustness', 'adco', 'latest.json'),
           _summary(arm='adco', status='WARN',
                    counts={"pass": 9, "fail": 0, "warn": 1, "unverified": 0},
                    distinct_outputs=3, runs=adco_runs,
                    measured_artifact={"status": "FAIL", "verify_json": "v.json"}))
    _write(os.path.join(tmp, 'tpcc', 'verify_aco.json'), {"arm": "aco", "status": "PASS"})
    return tmp


def test_loader_prefers_robustness_summary():
    with tempfile.TemporaryDirectory() as tmp:
        info = load_correctness_statuses(_tree(tmp), 'tpcc', SYSTEMS)
    n = info['naive-llm']
    assert n['status'] == 'FAIL' and n['fallback'] is False
    assert n['runs'] == 10 and n['counts'] == {"pass": 9, "fail": 1, "warn": 0, "unverified": 0}
    assert n['distinct_outputs'] == 6
    assert n['wilson_ci95'] == [0.02, 0.40]
    assert n['incorrect_rate'] == 0.1
    assert len(n['run_details']) == 10
    assert n['measured_artifact'] is None
    assert n['verify_seed_db'] == "tpcc_verify_seed"
    assert n['verify_warehouses'] == 10
    assert n['verify_duration'] == 10


def test_loader_maps_warn_to_suspect():
    with tempfile.TemporaryDirectory() as tmp:
        info = load_correctness_statuses(_tree(tmp), 'tpcc', SYSTEMS)['adco']
    assert info['status'] == 'SUSPECT'
    assert info['counts']['warn'] == 1 and info['runs'] == 10


def test_loader_falls_back_to_single_run_verify():
    with tempfile.TemporaryDirectory() as tmp:
        info = load_correctness_statuses(_tree(tmp), 'tpcc', SYSTEMS)['aco']
    assert info['status'] == 'PASS' and info['fallback'] is True
    assert info['runs'] == 1
    assert info['verify_seed_db'] is None
    assert info['verify_warehouses'] is None
    assert info['verify_duration'] is None
    assert correctness_cell(info) == '1-run PASS'


def test_loader_missing_arm_is_unverified():
    with tempfile.TemporaryDirectory() as tmp:
        info = load_correctness_statuses(_tree(tmp), 'tpcc', SYSTEMS)['baseline']
    assert info['status'] == 'UNVERIFIED' and info['fallback'] is True
    assert correctness_cell(info) == 'UNVERIFIED'


def test_correctness_cell_formats():
    assert correctness_cell(None) == 'N/A'
    assert correctness_cell({"status": "PASS", "runs": 10, "counts": {"pass": 10},
                             "fallback": False}) == 'PASS 10/10'
    assert correctness_cell({"status": "FAIL", "runs": 10, "counts": {"fail": 1},
                             "fallback": False}) == 'FAIL 1/10'
    assert correctness_cell({"status": "SUSPECT", "runs": 10, "counts": {"warn": 1},
                             "fallback": False}) == 'SUSPECT 1/10'
    # WARN is normalized even if a caller passes the raw verdict.
    assert correctness_cell({"status": "WARN", "runs": 10, "counts": {"warn": 2},
                             "fallback": False}) == 'SUSPECT 2/10'
    assert correctness_cell({"status": "UNVERIFIED", "runs": 0, "fallback": True}) == 'UNVERIFIED'


def test_load_verify_statuses_still_returns_plain_strings():
    with tempfile.TemporaryDirectory() as tmp:
        statuses = load_verify_statuses(_tree(tmp), 'tpcc', SYSTEMS)
    assert statuses == {'baseline': 'UNVERIFIED', 'adco': 'SUSPECT',
                        'aco': 'PASS', 'naive-llm': 'FAIL'}


_CSV = """transaction,executed,execution_time,transaction_rate
NEW_ORDER,100,1000.0,100.0
TOTAL,100,1000.0,100.0
"""


def test_rendered_report_has_correctness_table_and_columns():
    with tempfile.TemporaryDirectory() as tmp:
        results = _tree(os.path.join(tmp, 'results'))
        for sys_name in ('baseline', 'naive-llm'):
            path = os.path.join(results, 'tpcc', sys_name, 'benchmarks', f'{sys_name}.csv')
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(_CSV)
        out = os.path.join(tmp, 'out')

        data, raw, sources = report.parse_workload_data(results, 'tpcc', 'postgres', SYSTEMS)
        statuses = load_correctness_statuses(results, 'tpcc', SYSTEMS)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            report.generate_workload_report(
                data, raw, 'tpcc', 'postgres', SYSTEMS, report_names(), out, sources,
                quiet=False, verify_statuses=statuses)
        terminal = buf.getvalue()

        with open(os.path.join(out, 'performance_comparison_tpcc_postgres.md'),
                  encoding='utf-8') as f:
            md = f.read()

    assert '## Correctness' in md
    assert '| Arm | Runs | PASS | FAIL | SUSPECT | UNVERIFIED | Status |' in md
    assert '| Naive-LLM | 10 (10wh) | 9 | 1 | 0 | 0 | FAIL |' in md
    assert '| ADCo | 10 (10wh) | 9 | 0 | 1 | 0 | SUSPECT |' in md
    assert '| ACo | 1 (single run) | 1 | 0 | 0 | 0 | PASS |' in md
    assert '| Default | - | 0 | 0 | 0 | 0 | UNVERIFIED |' in md
    # Both performance tables get a per-arm Correctness column after Speedup /
    # Latency Reduction, with 'N/A' where the arm has no benchmark data.
    for section in ('## Transaction Rate / Throughput (txn/s)', '## Execution Time (ms)'):
        chunk = md.split(section, 1)[1].split('\n## ', 1)[0]
        assert '| Naive-LLM Correctness |' in chunk
        assert '| ADCo Correctness |' in chunk
        total_rows = [ln for ln in chunk.splitlines() if ln.startswith('| **TOTAL**')]
        assert total_rows and '**FAIL 1/10**' in total_rows[0]
        # Non-TOTAL rows stay readable ('-' placeholder); arms with no
        # benchmark data show N/A instead of a verdict.
        txn_rows = [ln for ln in chunk.splitlines() if ln.startswith('| NEW_ORDER ')]
        assert txn_rows and txn_rows[0].endswith('| 1.00x | - |')
        assert txn_rows[0].count('N/A') == 6

    # Failures, warnings and missing results still surface as warning lines
    # (terminal output, as before) with the run detail from the summary.
    assert "SUSPECT: arm 'Naive-LLM' failed correctness verification" in terminal
    assert "1 of 10 runs failed: runs 4" in terminal
    assert "SUSPECT: arm 'ADCo' raised correctness warnings" in terminal
    assert "UNVERIFIED: no correctness result for arm 'Default'" in terminal


def report_names():
    return {'baseline': 'Default', 'adco': 'ADCo', 'aco': 'ACo',
            'naive-llm': 'Naive-LLM'}
