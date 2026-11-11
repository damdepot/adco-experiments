# TPC-C Rewrite Correctness (`exp2_Correctness`)

Answers one question about each app-layer rewrite arm
(`baseline, aco, adco, py-dbridge, naive-llm`): **is the rewritten code
correct, or just fast?** A rewrite that drops writes, weakens isolation, or
skips work looks faster while corrupting data — these checks catch that.
`naive-llm` is a single arm that now rewrites with the prompt chosen by the
offline search (`baselines/NaiveLLM/prompts/selected-tpcc.txt`).

## Files

| File | Purpose |
|------|---------|
| `run_verify.sh` | Verify driver. Restores the pristine `tpcc_seed`, runs a tiny single-client smoke per arm (seed scale, 1 client, 20 s, no warmup), runs every check below, writes `results/tpcc/verify_<arm>.json` (or `VERIFY_OUTPUT`). Called by thin entry point `run/tpcc/run_verify.sh`. Also supports generic tree mode for arbitrary rewrite trees. Never deletes real results (benchmark dirs are moved aside during smoke and restored after). |
| `tpcc_correctness.py` | Pure checker (no DB writes). Static diff guard, smoke CSV/log gate, invariant verdicts, checksum drift, verify-status helpers consumed by `report.py`. Also usable standalone per arm (see CLI). |
| `read_probe.py` | Probe worker: runs deterministic read-only probes (ORDER_STATUS ×8, STOCK_LEVEL ×5) through one tree's driver code, prints normalized JSON. Run twice (baseline tree, rewrite tree) on the same snapshot; outputs diffed as the `reads` check. |
| `test_tpcc_correctness.py` | Spec-only unit tests: one per official condition below, plus fail-closed policy tests. No DB, no arm dirs. |

## Check tiers

**T0 — static (no DB).** Rewritten driver must parse; workload shape
(`loadConfig`, txn mix, client/scale handling) must not change; transaction
boundaries may only *gain* commits (WARN, needs human review) — losing one
FAILs. Catches broken edits before spending any DB time.

**T1 — smoke (tiny run).** All five txn types + TOTAL must execute with
`executed > 0`, no traceback, and failed-txn warnings at/below 1% of
executed (the legitimate 1% invalid-item rollback path never warns, so more
means a failure storm). Catches crashes, dead paths, and silent mass aborts.

**RP — read-probe equivalence (closes the read-blindness hole).**
ORDER_STATUS and STOCK_LEVEL mutate nothing, so no post-hoc check can see
them lie. `read_probe.py` runs identical deterministic reads through baseline
and rewrite code on the same snapshot; any divergence (or rewrite-only
error) FAILs, naming the probe. Comparison is spec-calibrated, not
byte-exact: datetimes canon to whole seconds (TPC-C resolution is 1 s, Spec
1.3.1 — sub-second digits and PG-JSON precisions are formatting noise),
floats rounded, and order-line row order ignored (display order is
insignificant, Spec 2.6.3.3 Comment 1).

**T2 — consistency conditions (Spec v5.11, Clause 3.3.2).** Post-smoke SQL;
any returned row is a violation:

| Key | Clause | Plain English | Catches |
|-----|--------|---------------|---------|
| CC1 | 3.3.2.1 | Warehouse totals = district totals | Updates applied to one table but not the other |
| CC2 | 3.3.2.2 | Next-order-ID − 1 = newest order = newest queued order | Skipped/repeated order numbers |
| CC3 | 3.3.2.3 | Queued orders form an unbroken sequence | Wrong-queue deletions |
| CC4 | 3.3.2.4 | District item totals = real order-line rows | Bulk inserts losing rows |
| CC5 | 3.3.2.5 | Undelivered flag matches queue entry | Delivered-but-queued (or reverse) states |
| CC6 | 3.3.2.6 (sampled) | Each recent order has all its lines | Silently dropped order lines |
| CC7 | 3.3.2.7 (sampled) | Delivery dates match delivery flags | Partial-delivery writes |
| CC8 | 3.3.2.8 | Warehouse takings = payment receipts | Payments skipping receipt rows |
| CC9 | 3.3.2.9 | Same, per district | Payments posted to the wrong district |
| CC10 | 3.3.2.10 | Balance = goods received − money paid | Wrong amounts (right rows, wrong values) |
| CC12 | 3.3.2.12 | Balance + payments = goods received | Value bugs, second angle |

CC10/CC12 are WARN-grade, never FAIL-grade: remote payments read one
customer's row (entry-district keys) but post to another's (home keys) — a
proven shared PyTPCC quirk (statement-log forensics: cross-copied `C_DATA`
audit strings), not rewrite logic. So per-customer value equations can break
on any arm. Genuine omissions always trip the global CC8/CC9 sums too, so
the rule is: CC10/CC12 alone → quirk-suspect WARN; CC10/CC12 plus CC8/CC9
failure → real defect FAIL.

CC6/CC7 run on a recent-orders window and CC10/CC12 on a deterministic
customer sample (~1/150); the rest are full checks. CC11
(`orders − new_orders = 2100`) is intentionally absent: every delivery
legitimately grows that gap, so it holds at load time only.

**Integrity rules (Clause 1.5):** `IR1` = primary-key uniqueness in all 8
keyed tables (HISTORY exempt — the spec gives it no key); `IR2` = no NULLs
in required business attributes. Belt-and-braces (the schema enforces both),
but a violation would mean silent corruption.

**T3 — checksum (informational).** Per-table counts/sums recorded for manual
inspection; drift never fails (concurrency makes exact cross-arm equality
impossible).

**Policy:** missing results or a crashed check is a FAILURE, never a pass.
Overall FAIL if any check fails; WARN/drift never fail.

## Official-spec adaptations (documented deviations)

- **Money epsilon 0.01.** PyTPCC passes Python floats for exact-numeric
  columns, leaving ~1e-9 noise; real bugs are dollars and up.
- **Carrier sentinel.** PyTPCC stores `0` (`NULL_CARRIER_ID`), not SQL NULL,
  for undelivered orders — CC5/CC7 match on `COALESCE(carrier,0)=0`, with
  NULL and 0 both meaning undelivered.
- **Sampling.** CC6/CC7 run on a per-district window of 500 recent orders
  (full scans scale with table size); CC12-style customer sampling where
  noted. Everything else is a full check.

## Usage

```bash
./run/tpcc/run_verify.sh                        # all arms (baseline,aco,adco,py-dbridge,naive-llm)
./run/tpcc/run_verify.sh postgres aco,adco      # subset (lone arm name as $1 also works)
REVERIFY=1 ./run/tpcc/run_verify.sh             # re-run even when verify_*.json is fresh (<24h)
VERIFY_DURATION=30 ./run/tpcc/run_verify.sh     # smoke seconds per arm (default 20)
```

Statuses land in `results/tpcc/verify_<arm>.json` (plus
`verify_<arm>.smoke.log`) and surface as a `## Correctness` section with
SUSPECT/UNVERIFIED warnings in the `run_reports.sh` output. Arms with no
rewrite dir get `UNVERIFIED` and are skipped. Requires the `tpcc_seed`
snapshot and a healthy `adcoexp-db` container.

> Rerun policy: CC10/CC12 value checks can false-alarm on rare shared-stack
> behavior (remote-lastname payments read one customer's row but post to
> another's — a pre-existing PyTPCC quirk, not rewrite logic). Every arm,
> including baseline, has failed these at least once across repeated runs
> while passing most runs. Treat a lone CC10/CC12 FAIL as suspect, not
> guilty: re-run before concluding an arm is broken; only a reproducibly
> failing arm is truly suspect.

## Generic tree mode

Verifies any Naive-LLM-style rewrite tree under an arbitrary arm name — used by
the robustness harness.
| Var | Required | Meaning |
|-----|----------|---------|
| `VERIFY_REWRITE_ROOT` | yes | repo-relative root holding `Rewrite/<dbms>/tpcc-NaiveLLM/` |
| `VERIFY_CSV` | yes | **absolute** path for the smoke CSV |
| `BENCH_RESULTS_DIR` | yes | where the runner writes benchmarks; without it the runner falls back to `results/tpcc/<arm>/benchmarks` and the supplied CSV never appears |
| `VERIFY_OUTPUT` | no | verdict JSON path (default `results/tpcc/verify_<arm>.json`) |
| `BENCH_LOCK_HELD=1` | no | caller already holds `bench_lock` (robustness owns it) |
| `REVERIFY=1` | no | ignore a fresh verdict and re-run |
| `VERIFY_SEED_DB` | no | seed to restore from (default `tpcc_seed`) |
| `VERIFY_WAREHOUSES` | no | warehouse scale of the verify seed (default `TPCC_WAREHOUSES`) |
| `VERIFY_DURATION` | no | verifier smoke seconds (default 20) |
| `BENCH_SKIP_SETTLE=1` | no | skip settle/autovacuum/VACUUM in verification |

Any arm name maps to that tree, so the name is just the label on the verdict.
The CSV must be supplied — there is no default path in tree mode.

```bash
BENCH_LOCK_HELD=1 REVERIFY=1 \
  VERIFY_REWRITE_ROOT=out/app_layer/robustness/naive-llm/<ts>/r01 \
  VERIFY_CSV="$PWD/out/app_layer/robustness/naive-llm/<ts>/r01/smoke/naive-llm-r01.csv" \
  BENCH_RESULTS_DIR="$PWD/out/app_layer/robustness/naive-llm/<ts>/r01/smoke/benchmarks" \
  VERIFY_OUTPUT="$PWD/out/app_layer/robustness/naive-llm/<ts>/r01/verify.json" \
  ./scripts/tpcc/exp2_Correctness/run_verify.sh postgres naive-llm-r01
```

## Robustness harness

```bash
./run/tpcc/run_naive-llm-robustness.sh [runs=10] [dbms=postgres] [model]
```

- Run `0` re-verifies the already-measured tree under
  `out/app_layer/NaiveLLM-results/` (recorded separately as
  `measured_artifact`).
- Runs `1..N` rewrite from scratch with the selected prompt, each verified via
  generic tree mode.
- Writes `results/tpcc/robustness/naive-llm/latest.json` plus timestamped
  `out/app_layer/robustness/naive-llm/<ts>/summary.{json,md}`. Rewrites, smoke
  CSVs and per-run verdicts stay under `out/`.
- Each child is bounded (`VERIFY_TIMEOUT`, default 600 s; `PROBE_TIMEOUT`,
  120 s; `PGCONNECT_TIMEOUT`, 10 s) and skips the per-run container restart
  unless `VERIFY_RESTART=1`. Robustness uses `BENCH_SKIP_SETTLE=1`,
  `VERIFY_DURATION=10`, and a `tpcc_verify_seed` (3 warehouses) so the
  per-run copy/VACUUM stays small; the performance arm still measures on the
  full `tpcc_seed`.

The reporter prefers `results/tpcc/robustness/<arm>/latest.json`; without it,
it falls back to this arm's single `verify_<arm>.json` and shows `1-run PASS`.
The summary's `Measured` column carries run 0's verdict on the tree that
produced the reported performance number; a measured FAIL is warned separately
from the fresh-run aggregate.
