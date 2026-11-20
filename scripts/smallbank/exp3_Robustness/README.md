# SmallBank Rewrite Robustness (`exp3_Robustness`)

Asks whether a rewrite arm's correctness survives **repeated** generation:
each run makes a fresh rewrite, classifies it, then runs the SmallBank
verifier (`scripts/smallbank/exp2_Correctness/`). Mirrors the TPC-C harness in
`scripts/tpcc/exp3_Robustness/`; the checker and report/log tools are shared
from there.

## Files

| File | Purpose |
|------|---------|
| `run_arm_robustness.sh` | Generate -> classify -> verify -> record, N times. Writes `results/smallbank/<mode>/<arm>/latest.json` and `out/app_layer/<mode>/<arm>/<ts>/summary.{json,md}`. |
| `../../tpcc/exp3_Robustness/check_rewrite.py` | AST classifier: substantive / unchanged / cosmetic / no comparable file. Run with `drivers/postgresdriver.py main.py`. |
| `../../tpcc/exp3_Robustness/report_robustness.py` | `--workload smallbank` writes `reports/smallbank/robustness.md`. |
| `../../tpcc/exp3_Robustness/log_robustness_runs.py` | `--workload smallbank <arm>` lists recorded sweeps. |

## Usage

```bash
./run/smallbank/run_naive-llm-robustness.sh [runs=10] [dbms=postgres] [model]
./run/smallbank/run_aco-robustness.sh        [runs=10]
./run/smallbank/run_adco-robustness.sh       [runs=10]
./run/smallbank/run_py-dbridge-robustness.sh [runs=1]
./run/smallbank/run_report_robustness.sh
TEMP=0.7 ./run/smallbank/run_naive-llm-robustness.sh 10   # rewrite temperature

# generic form
./run/smallbank/run_all_robustness.sh <naive-llm|aco|adco|py-dbridge> [runs] [dbms=postgres] [model]
```

Default scale: `smallbank_verify_seed`, `SMALLBANK_VERIFY_ACCOUNTS` (100000),
`SMALLBANK_VERIFY_TRANSACTIONS` (2000), 1 client. The performance seed
`smallbank_seed` is refused unless `FULL_SCALE=1`, which switches to the
performance seed/load (`SMALLBANK_ACCOUNTS`, `SMALLBANK_TRANSACTIONS`,
`SMALLBANK_CLIENTS`) and defaults to 1 run via the `-full-scale` wrappers.

A run whose rewrite failed, was unchanged, or was cosmetic-only is recorded as
FAIL and skips verification, exactly like the TPC-C harness. Py-DBridge's
transform is a documented no-op for SmallBank (no `**` unpacking), so its
sweeps record `FAIL: no substantive change` by design - that means "no
optimization", not "incorrect". Verification is
the existing SmallBank verifier invoked in generic tree mode; the correctness
layer itself is untouched (the full-scale path sets
`VERIFY_ALLOW_PERF_SEED=1` so the verifier accepts `smallbank_seed`).

Sweeps write `results/smallbank/robustness/<arm>/latest.json`, which
`scripts/common/app_layer/exp2_Reports/report.py` prefers for the performance
report's `## Correctness` table. Full-scale sweeps use
`results/smallbank/robustness-full-scale/<arm>/` and are not read by the
default report.
