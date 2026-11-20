# App-Layer Rewrite Robustness (`exp3_Robustness`)

Asks whether a rewrite arm's correctness survives **repeated** generation:
each run makes a fresh rewrite, classifies it, then runs the workload's
verifier (`scripts/tpcc/exp2_Correctness/` or
`scripts/smallbank/exp2_Correctness/`). One harness serves both workloads.

## Files

| File | Purpose |
|------|---------|
| `run_arm_robustness.sh` | Generate -> classify -> verify -> record, N times. Writes `results/<workload>/<mode>/<arm>/latest.json` and `out/app_layer/<mode>/<arm>/<ts>/summary.{json,md}`. |
| `check_rewrite.py` | AST classifier: substantive / unchanged / cosmetic / no comparable file. Defaults to `drivers/postgresdriver.py tpcc.py`; SmallBank passes `drivers/postgresdriver.py main.py`. |
| `report_robustness.py` | `--workload tpcc\|smallbank` (default tpcc) writes `reports/<workload>/robustness.md`. |
| `log_robustness_runs.py` | `[arm] --workload tpcc\|smallbank [--full-scale]` lists recorded sweeps. |

## Usage

```bash
./run/tpcc/run_naive-llm-robustness.sh    [runs=10] [dbms=postgres] [model]
./run/tpcc/run_aco-robustness.sh          [runs=10]
./run/tpcc/run_adco-robustness.sh         [runs=10]
./run/tpcc/run_py-dbridge-robustness.sh   [runs=1]
./run/tpcc/run_naive-llm-agenttune-robustness.sh  [runs=10]
./run/tpcc/run_agenttune-naive-llm-robustness.sh  [runs=10]
./run/tpcc/run_report_robustness.sh
TEMP=0.7 ./run/tpcc/run_naive-llm-robustness.sh 10   # rewrite temperature

# same set under ./run/smallbank/
# generic form
./run/tpcc/run_all_robustness.sh <arm> [runs] [dbms=postgres] [model]
./run/smallbank/run_all_robustness.sh <arm> [runs] [dbms=postgres] [model]

# harness directly
./scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh <tpcc|smallbank> <arm> [runs] [dbms] [model]
```

Default runs: `naive-llm 10`, `naive-llm-agenttune 10`,
`agenttune-naive-llm 10`, `aco 10`, `adco 10`, `py-dbridge 1`. `FULL_SCALE=1`
forces 1 run.

Each iteration: generate a fresh tree with the arm's own pipeline, verify that
tree, record. A run whose rewrite failed, is missing, is unchanged, or is
cosmetic only (same AST, e.g. comments/formatting) is recorded as `FAIL` and is
not verified. `check_rewrite.py` does the comparison.

- `naive-llm`: one unguided rewrite.
- `aco` / `adco`: `runExperiment0.sh ACo|ADCo` (ADCo includes its tuner); the
  generated `<workload>-<model>` subtree is deleted first so repeated runs are
  independent.
- `py-dbridge`: one deterministic transpile.
- `naive-llm-agenttune` / `agenttune-naive-llm`: the rewrite phase of the
  stacked arm. AgentTune runs once per sweep (same order the arm uses) and the
  verifier keeps those knobs (`VERIFY_KEEP_KNOBS=1`) instead of resetting to
  defaults; the tuned config is snapshotted under `<ts>/tuned/`.

## Scale

Default verify scale: TPC-C `tpcc_verify_seed` at 1 warehouse, 10 s, 1 client;
SmallBank `smallbank_verify_seed` at 100000 accounts, 2000 transactions, 1
client. The seed is created once and reused; `RESEED=1` rebuilds it. The
performance seeds (`tpcc_seed`, `smallbank_seed`) are refused unless
`FULL_SCALE=1`.

Full scale passes the performance seed/load (`TPCC_WAREHOUSES`,
`TPCC_CLIENTS`, `TPCC_DURATION`, `TPCC_WARMUP`; `SMALLBANK_ACCOUNTS`,
`SMALLBANK_TRANSACTIONS`, `SMALLBANK_CLIENTS`) and records under
`results/<workload>/robustness-full-scale/<arm>/`. The SmallBank verifier gets
`VERIFY_ALLOW_PERF_SEED=1`; that is the only place it is set.

Overrides: `VERIFY_SEED_DB`, `VERIFY_WAREHOUSES`, `VERIFY_ACCOUNTS`,
`VERIFY_TRANSACTIONS`, `VERIFY_DURATION`, `VERIFY_CLIENTS`, `VERIFY_WARMUP`,
`VERIFY_TIMEOUT`, `ROBUSTNESS_REPORT_DIR`, `TEMP`/`TEMPERATURE`, `GEN_TIMEOUT`
(default 1800 s), `TUNE_TIMEOUT` (3600 s), `AGENTTUNE_ITERATIONS`, `RESEED`,
`VERBOSE`.

## Stacked tuning

`naive-llm-agenttune` / `agenttune-naive-llm` run AgentTune once per sweep:
`config.ini` is pinned to `DB_Name=<workload>` and `benchmark=SYSBENCH`, then
`runExperiment1-AgentTune.sh <dbms> <workload>` runs at the verify scale. The
resulting `postgresql.auto.conf` is snapshotted to `<ts>/tuned/`, every rewrite
is verified with `VERIFY_KEEP_KNOBS=1`, and default knobs are restored when the
sweep ends. Tuning output is `<ts>/tune.log`; the tuned-override count is in
`config.tsv`.

## FAIL semantics

A sweep is `FAIL` if any run failed; `WARN` only for warnings; `PASS` if at
least one run passed and none failed; otherwise `UNVERIFIED`. A run that fails
its rewrite gate skips verification. Py-DBridge's transform is a documented
no-op for SmallBank (no `**` unpacking), so its sweeps record
`FAIL: no substantive change` by design - that means "no optimization", not
"incorrect".

Sweeps write `results/<workload>/robustness/<arm>/latest.json`, which
`scripts/common/app_layer/exp2_Reports/report.py` prefers for the performance
report's `## Correctness` table. Full-scale sweeps use
`results/<workload>/robustness-full-scale/<arm>/` and are not read by the
default report.
