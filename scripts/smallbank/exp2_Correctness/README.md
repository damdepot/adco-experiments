# SmallBank Rewrite Correctness (`exp2_Correctness`)

Answers one question about each app-layer rewrite arm
(`baseline, naive-llm, aco, adco, py-dbridge`): **is the rewritten code
correct, or just fast?** A rewrite that drops a balance update, moves the
commit boundary, or returns the wrong balance looks faster while corrupting
data — these checks catch that.

SmallBank has no official consistency-condition suite like TPC-C, so the oracle
comes from SmallBank semantics alone: six transaction functions, client-owned
transaction boundaries, the ACCOUNTS/SAVINGS/CHECKING mapping, and BALANCE
results.

## Files

| File | Purpose |
|------|---------|
| `run_verify.sh` | Verify driver. Restores pristine `smallbank_verify_seed`, runs a tiny single-client smoke per arm (seed scale, 1 client, `SMALLBANK_VERIFY_TRANSACTIONS`, 1 rep, no warmup), runs every check below, writes `results/smallbank/verify_<arm>.json` (or `VERIFY_OUTPUT`). Called by thin entry point `run/smallbank/run_verify.sh`. Also supports generic tree mode for arbitrary rewrite trees. Never deletes real results (benchmark dirs are moved aside during smoke and restored after). |
| `smallbank_correctness.py` | Pure checker (no DB writes). Static guard, smoke CSV/log gate, invariant verdicts, read equivalence, verdict aggregation. Also usable standalone per arm (see CLI). |
| `read_probe.py` | Probe worker: runs deterministic read-only `BALANCE` calls (custids 1..200) through one tree's driver, prints normalized JSON. Run twice (baseline tree, rewrite tree) on the same snapshot; outputs diffed as the `reads` check. |
| `test_smallbank_correctness.py` | Spec-only unit tests: static pass/fail cases, smoke gate, invariant verdicts, read equivalence, report-loader contract. No DB, no arm dirs. |

## Check tiers

**T0 — static (no DB).** The rewritten driver must parse and must keep all six
transaction functions (`amalgamate`, `balance`, `deposit_checking`,
`send_payment`, `transact_savings`, `write_check`). The client owns
commit/rollback, so any `.commit()`/`.rollback()` that appears in the rewrite's
driver is a FAIL. Write coverage is compared per function: every baseline
`UPDATE`/`INSERT`/`DELETE` on ACCOUNTS/SAVINGS/CHECKING must still appear with
the same shape. SQL is read from string literals, f-strings, module/function
constants and simple concatenation; parameter placeholders and literal SET
values are normalized, so formatting and bound-value choices do not matter.
Catches broken edits before spending DB time.

**T1 — smoke (fixed-work run).** All six transaction types + TOTAL must execute
with `executed > 0`, no traceback, and failed attempts at/below 1% of executed.
SmallBank's runner prints failures as an `ERROR` row in the console table and
excludes them from the CSV; `ABORT` is a legitimate business abort
(`AMALGAMATE` zeroes a checking balance, later `SEND_PAYMENT`s can abort) and
is not counted as a failure. Catches crashes, dead paths and silent mass
aborts.

**INV — invariants (post-smoke SQL).** Any returned row is a violation:

| Key | Check |
|-----|-------|
| `accounts_count` | ACCOUNTS row count equals the verify seed scale |
| `savings_count` | SAVINGS row count equals ACCOUNTS count |
| `checking_count` | CHECKING row count equals ACCOUNTS count |
| `savings_mapping` | Every account has a savings row and vice versa (full join) |
| `checking_mapping` | Every account has a checking row and vice versa (full join) |
| `balance_sanity` | No NULL, NaN or infinite balances in either table |
| `dup_custid` | `custid` unique in all three tables (belt-and-braces; the schema has PKs) |

Count equality plus no orphans means a 1:1 mapping; the mapping checks also
catch rows pointing at accounts that no longer exist.

**RD — read equivalence (closes the read-blindness hole).** `BALANCE` mutates
nothing, so no post-hoc data check can see it lie. `read_probe.py` runs
identical `BALANCE` calls for zero-padded custids 1..200 through baseline and
rewrite code on the same restored snapshot (before the smoke run mutates it).
Any divergence, or a rewrite-only error, FAILs and names the account. Probes
the baseline itself cannot run (e.g. ids beyond a smaller seed) are skipped.
Floats are rounded to 4 decimals: driver float-repr noise is not divergence,
real money differences are.

**Policy:** missing results or a crashed check is a FAILURE, never a pass.
Overall FAIL if any check fails.

## Usage

```bash
./run/smallbank/run_verify.sh                     # all arms
./run/smallbank/run_verify.sh postgres aco,adco    # subset
./run/smallbank/run_verify.sh aco                 # lone arm name works too
REVERIFY=1 ./run/smallbank/run_verify.sh          # re-run even when verdicts are fresh (<24h)
./run/smallbank/run_all_verify.sh                 # verify every rewrite tree that exists (always re-runs)
RESEED=1 ./run/smallbank/run_verify.sh baseline   # rebuild the verify seed first
```

Statuses land in `results/smallbank/verify_<arm>.json` (plus
`verify_<arm>.smoke.log` and `verify_<arm>.smoke.csv`) and are consumed by
`scripts/common/app_layer/exp2_Reports/report.py` (same schema as TPC-C's
verdicts). Arms with no rewrite dir get `UNVERIFIED` and are skipped.

Defaults: `smallbank_verify_seed` at 100000 accounts, 2000 transactions, 1
client. The performance seed `smallbank_seed` is never used by verification;
`VERIFY_SEED_DB=smallbank_seed` is refused unless `VERIFY_ALLOW_PERF_SEED=1`
(set only by full-scale robustness). The verify seed is created once and
reused; `RESEED=1` rebuilds it at the current scale. A row-scale mismatch
aborts loudly (RESEED to fix).

## Robustness

Repeated rewrites of one arm, each checked and then verified, live in
`scripts/smallbank/exp3_Robustness/` (see its README). They reuse this verifier
through generic tree mode; this layer is unchanged by robustness runs.

```bash
./run/smallbank/run_naive-llm-robustness.sh 10   # 10 fresh rewrites, each verified
./run/smallbank/run_py-dbridge-robustness.sh 1
./run/smallbank/run_report_robustness.sh         # one table across arms
```

Per-run verdicts land under `out/app_layer/robustness/<arm>/<ts>/rNN/verify.json`;
the sweep summary is `results/smallbank/robustness/<arm>/latest.json`, which
the performance report prefers over `results/smallbank/verify_<arm>.json`.

## Generic tree mode

Verifies any Naive-LLM-style rewrite tree under an arbitrary arm name — used by
the robustness harness.

| Var | Required | Meaning |
|-----|----------|---------|
| `VERIFY_REWRITE_ROOT` | yes | repo-relative root holding `Rewrite/<dbms>/smallbank-NaiveLLM/` (`TREE_NAME` overrides the leaf name) |
| `VERIFY_CSV` | yes | **absolute** path for the smoke CSV |
| `BENCH_RESULTS_DIR` | yes | where the runner writes benchmarks; without it the runner falls back to `results/smallbank/<arm>/benchmarks` and the supplied CSV never appears |
| `VERIFY_OUTPUT` | no | verdict JSON path (default `results/smallbank/verify_<arm>.json`) |
| `BENCH_LOCK_HELD=1` | no | caller already holds `bench_lock` (robustness owns it) |
| `REVERIFY=1` | no | ignore a fresh verdict and re-run |
| `VERIFY_SKIP_SEED=1` | no | caller ensured the seed; skip the top-level ensure |
| `VERIFY_SKIP_SEED_ASSERT=1` | no | caller asserted the seed; skip the seed check |
| `VERIFY_SEED_DB` | no | seed to restore from (default `smallbank_verify_seed`; `smallbank_seed` is refused) |
| `VERIFY_ACCOUNTS` | no | account scale of the verify seed (default `SMALLBANK_VERIFY_ACCOUNTS`, 100000) |
| `VERIFY_TRANSACTIONS` | no | smoke transactions per arm (default `SMALLBANK_VERIFY_TRANSACTIONS`, 2000) |
| `VERIFY_CLIENTS` | no | verifier smoke clients (default 1) |
| `VERIFY_SMOKE_TIMEOUT` | no | smoke-run wall-clock cap in seconds (default 600) |
| `BENCH_SKIP_SETTLE=1` | no | skip settle/VACUUM in verification |
| `VERIFY_KEEP_KNOBS=1` | no | keep tuned knobs instead of resetting to defaults |
| `VERIFY_ALLOW_PERF_SEED=1` | no | allow `VERIFY_SEED_DB=smallbank_seed` (full-scale robustness only; default refusal) |

Any arm name maps to that tree, so the name is just the label on the verdict.

```bash
BENCH_LOCK_HELD=1 REVERIFY=1 \
  VERIFY_REWRITE_ROOT=out/app_layer/robustness/naive-llm/<ts>/r01 \
  VERIFY_CSV="$PWD/out/app_layer/robustness/naive-llm/<ts>/r01/smoke/naive-llm-r01.csv" \
  BENCH_RESULTS_DIR="$PWD/out/app_layer/robustness/naive-llm/<ts>/r01/smoke/benchmarks" \
  VERIFY_OUTPUT="$PWD/out/app_layer/robustness/naive-llm/<ts>/r01/verify.json" \
  ./scripts/smallbank/exp2_Correctness/run_verify.sh postgres naive-llm-r01
```

## False positives

A FAIL means *suspect*, not proven guilty; re-run before concluding an arm is
broken.

- **Static write coverage is per function.** A rewrite that extracts shared
  write helpers (e.g. `_add_balance(cursor, table, ...)`) can lose per-function
  SQL visibility and FAIL even when the work still happens. This is
  deliberately conservative: a silently dropped write is worse than a manual
  review.
- **BALANCE read equivalence only covers reads.** Writes are covered by static
  coverage and the mapping invariants; value-level write bugs that keep counts
  and mappings intact are not detected.
- **ABORTs are ignored.** Business aborts are legitimate SmallBank behaviour
  (insufficient funds), not failures; only `ERROR`/exception paths feed the
  failure-storm ratio.
