# ADCo Experiments

Experiment harness for evaluating database optimization approaches against
baseline execution, across three groups:

| Group | What it changes | Workloads | Approaches |
|-------|-----------------|-----------|------------|
| **DB layer** | PostgreSQL / MySQL configuration knobs | TPC-C, SmallBank, TPCH | ADCo/DCo, AgentTune, GPTuner, OtterTune (TPCH runs DCo/AgentTune/GPTuner) |
| **App layer** | OLTP application code | TPC-C, SmallBank | ACo, ADCo, Py-DBridge, Naive-LLM, stacked arms |
| **Query layer** | SQL query rewrites | STATS, TPCH | ADCo, ReSequel, R-Bot, LearnedRewrite, Naive-LLM |

Project links: [ADCo](https://github.com/damdepot/ADCo), [AgentTune](https://github.com/dannykhant/AgentTune),
[GPTuner](https://github.com/dannykhant/gptuner), [OtterTune](https://github.com/dannykhant/ottertune),
[ReSequel](https://github.com/dannykhant/resequel), [R-Bot](https://github.com/dannykhant/r-bot),
[LearnedRewrite](https://github.com/dannykhant/learnedrewrite), [Py-DBridge](https://github.com/dannykhant/py-dbridge).

TPC-C/SmallBank arms run against PostgreSQL 17 (the `pgdb` Compose service) or
an external MySQL: pristine seed, one warmup, `REPS` measured reps, and
per-run metadata under `results/<workload>/`. STATS/TPCH arms replay their
query datasets instead (TPCH at `TPCH_SCALE`); TPCH additionally has
DB-tuning arms.

## Repository layout

`<wl>` is `tpcc` or `smallbank`; the same entry points exist under both.

| Path | Purpose |
|------|---------|
| `.env-example`, `docker-compose.yml` | Benchmark contract/keys/DB credentials; PostgreSQL 17 (`pgdb` + one-shot `db-init`), LiteLLM, `adcoexp` services |
| `docker/` | Experiment image entrypoint, Postgres init SQL, LiteLLM config |
| `run/setup/deps-local.sh` / `deps-google-adc.sh` | Host build deps / Google Cloud ADC from `.env` |
| `run/setup/db-*.sh` / `app-*.sh` | Download, build, and set up DB-layer and app-layer baselines and workloads |
| `run/setup/stats-*.sh`, `run/setup/tpch-*.sh` | Query-layer baselines, datasets, Postgres/MySQL prepare, ReSequel catalog |
| `run/setup/{db,app,stats,tpch}-update-configs.sh` | Regenerate baselines' configs and `.env`-derived values |
| `run/<wl>/run_baseline.sh` | Baseline workload |
| `run/<wl>/run_aco.sh`, `run_dco.sh`, `run_adco.sh` | ACo rewrite, DCo tuning, ADCo rewrite + tuning |
| `run/<wl>/run_py-dbridge.sh`, `run_naive-llm.sh` | App rewrites + workload |
| `run/<wl>/run_agenttune.sh`, `run_gptuner.sh`, `run_ottertune.sh` | Knob tuning + workload |
| `run/<wl>/run_naive-llm-agenttune.sh`, `run_agenttune-naive-llm.sh` | Stacked rewrite + tuning (rewrite-first / tune-first) |
| `run/<wl>/run_all.sh` / `run_all_only_benchmark.sh` | All arms, skipping completed ones / benchmark existing artifacts only |
| `run/<wl>/run_verify.sh` / `run_all_verify.sh` | Verify one arm / every rewrite tree already on disk |
| `run/<wl>/run_<arm>-robustness.sh`, `run_<arm>-robustness-full-scale.sh` | Repeated generate -> verify sweep; full-scale variant |
| `run/<wl>/run_all_robustness.sh`, `run_report_robustness.sh`, `run_log_naive-llm-robustness.sh` | Generic sweep wrapper, robustness report, sweep log |
| `run/<wl>/run_report_performance.sh`, `check_artifacts.sh`, `clear_benchmark_results.sh` | Report into `reports/<wl>/` / artifact check / clear CSVs |
| `run/data/` | Back up and inspect past results (`backup_results.sh`, `view_backup.sh`) |
| `run/stats/run_{baseline,aco,adco,resequel,r-bot,learnedrewrite,naive-llm,all,reports}.sh` | STATS query-layer arms and report |
| `run/tpch/run_{baseline,aco,dco,adco,resequel,r-bot,learnedrewrite,naive-llm,agenttune,gptuner,all,reports}.sh` | TPCH query-layer and tuning arms, report |
| `scripts/_lib/bench_lib.sh`, `docker.sh`, `run_comparison.sh` | Measurement protocol/env contract; container helpers; comparison runner |
| `baselines/` | Cloned/vendored baselines (`ADCo`, `AgentTune`, `GPTuner`, `OtterTune`, `NaiveLLM`, `Py-DBridge`, `ReSequel`, `R-Bot`, `LearnedRewrite`) |
| `workload/databases/`, `workload/src/`, `workload/apps/` | SQL workloads + replay harness (`DBConfig.yaml`); cloned OLTP apps and `db.config` |
| `data/`, `tools/` | Downloaded STATS/TPCH datasets; TPC-H kit and knob checker |
| `scripts/common/db_layer/{exp0_ADCo,exp1_Baselines,exp2_Reports}/` | Knob-tuning drivers and reports |
| `scripts/common/app_layer/{exp0_ADCo,exp1_Baselines,exp2_Reports}/`, `exp3_Robustness/` | App-layer drivers and rewrite robustness sweep |
| `scripts/common/query_layer/{exp0_ADCo,exp1_ReSequel,exp2_Baselines,exp3_Reports}/` | Query-layer drivers |
| `scripts/tpcc/`, `scripts/smallbank/` | Workload-specific drivers, incl. `exp2_Correctness/` verify helpers |
| `catalog/` | Generated ReSequel catalogs (`catalog/stats/`, `catalog/tpch-s1/`, ...) |
| `results/<wl>/<arm>/{benchmarks/,<arm>.json}`, `results/<wl>/*.json` | Per-arm CSVs + timer metadata; per-run status/timer JSON |
| `results/<wl>/verify_<arm>.json`, `robustness[-full-scale]/<arm>/latest.json` | Correctness verdicts; robustness summaries |
| `results/db_layer/`, `results/stats/`, `results/tpch/` | Tuner best configs; query-layer results per approach |
| `out/app_layer/`, `out/query_layer/`, `out/db_layer/`, `out/logs/` | Rewrite trees / query rewrites / knob-tuning artifacts; per-run logs |
| `out/app_layer/robustness[-full-scale]/<arm>/<timestamp>/` | Per-sweep trees: `summary.{json,md}`, run dirs, logs |
| `reports/`, `docs/ottertune.md` | Generated reports; OtterTune internals |
| `backups/` | Result snapshots written by `run/data/backup_results.sh` |

## Setup

Complete [Configuration](#configuration) below first: Compose interpolates `.env`
(`GOOGLE_CLOUD_PROJECT`, `LITELLM_MASTER_KEY`) and `deps-google-adc.sh` exits
without it.

```bash
./run/setup/deps-local.sh        # host: bare Ubuntu host only; the image ships these deps
./run/setup/deps-google-adc.sh   # host: ADC login from .env (before Compose mounts it)

docker compose up -d --build     # host: pgdb + db-init (databases) + litellm + adcoexp

# Everything below runs inside adcoexp: docker compose exec -it adcoexp bash
# DB layer: knob-tuning baselines (ADCo/DCo, AgentTune, GPTuner, OtterTune)
./run/setup/db-download-baselines.sh
./run/setup/db-setup-baselines.sh

# App layer: ADCo + Py-DBridge (downloaded), NaiveLLM (vendored), OLTP workloads
./run/setup/app-download-baselines.sh
./run/setup/app-setup-baselines.sh
./run/setup/app-setup-workloads.sh   # smallbank + tpcc (db-setup-workloads is the DB-layer equivalent)

# Query layer: STATS
./run/setup/stats-download-baselines.sh
./run/setup/stats-setup-baselines.sh
./run/setup/stats-download-data.sh
./run/setup/stats-prepare-postgres-remote.sh   # -local/-remote equivalent; -mysql for MySQL
./run/setup/stats-build-catalog.sh             # catalog/stats (ReSequel + LearnedRewrite)

# Query layer: TPCH (same pattern, TPCH_SCALE rows)
./run/setup/tpch-download-baselines.sh
./run/setup/tpch-setup-baselines.sh
./run/setup/tpch-download-data.sh
./run/setup/tpch-prepare-postgres-remote.sh
./run/setup/tpch-build-catalog.sh tpch PostgreSQL "${TPCH_SCALE:-1}"
```

The `*-prepare-postgres-remote.sh` / `-local.sh` variants are equivalent (both
use client-side `\copy`) and load into the Postgres named by `POSTGRES_HOST`
from `.env` (falling back to `pgdb`); `-mysql.sh` does the same for MySQL.
Catalog builds read the live schema, so run one after its prepare script.
`setup-recreate-production.sh` recreates the `pgdb` container and databases,
destroying data and seed snapshots. After editing `.env`, regenerate configs
with the matching `*-update-configs.sh` script (see Configuration).

## Configuration

Copy `.env-example` to `.env`. `scripts/_lib/bench_lib.sh` reads it at run time;
resource and pinning keys are also read by `docker-compose.yml`.

| Variable | Default | Meaning |
|----------|---------|---------|
| `CPU_CORES` / `MEMORY_GB` | `4` / `8` | DB container quota; tuners' resource contract |
| `DB_CPUSET` / `CLIENT_CPUSET` | unset | Optional core pinning for DB / client containers |
| `REPS` / `ROBUSTNESS_REPS` | `3` / `10` | Measured reps per arm / robustness sweep runs (Py-DBridge is always 1) |
| `TPCC_DURATION` / `TPCC_WARMUP` / `TPCC_WAREHOUSES` / `TPCC_CLIENTS` | `180` / `15` / `32` / `8` | TPC-C duration, warmup, scale, concurrency |
| `SMALLBANK_DURATION` / `SMALLBANK_WARMUP` / `SMALLBANK_CLIENTS` / `SMALLBANK_ACCOUNTS` | `180` / `15` / `8` / `5000000` | SmallBank duration, warmup, concurrency, seed scale |
| `SETTLE_SECS` | `5` | Quiet window after autovacuum quiesces |
| `DBMS` / `TPCH_SCALE` | `postgres` / `1` | Target DBMS (`postgres` or `mysql`) / TPCH data scale |

Precedence: shell environment > `.env` > defaults; set a one-off inline or
comment the line out to fall back.

```dotenv
# 127.0.0.1 when running from the host; 'pgdb' inside the Compose network
POSTGRES_HOST=127.0.0.1
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_PORT=5432
```

MySQL uses the same pattern (`MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_HOST`,
`MYSQL_PORT`). Fill in `OPENAI_API_KEY`, `GROQ_API_KEY`, the `GOOGLE_*` Vertex
AI values, and `LITELLM_*` as in `.env-example`; `LITELLM_MASTER_KEY` is the
internal proxy key (`openssl rand -hex 32`), not a Google credential. Compose
mounts `~/.config/gcloud/application_default_credentials.json` into the
LiteLLM and experiment containers. Regenerate configs after editing `.env`:

```bash
docker compose exec adcoexp ./run/setup/stats-update-configs.sh  # ReSequel/R-Bot YAML, ADCo .env, workload DBConfig
docker compose exec adcoexp ./run/setup/app-update-configs.sh    # smallbank / tpcc db.config
```

Use `tpch-update-configs.sh` or `db-update-configs.sh` for those groups; run
them inside `adcoexp` so endpoints resolve to the `litellm` service.

## Measurement protocol

Defined once in `scripts/_lib/bench_lib.sh`; the `run/` entry points and the
OLTP workload runners source it.

- **Seed / restore.** Load once, snapshot (`bench_ensure_seed` ->
  `bench_snapshot`), restore per arm (`bench_restore`); reps do not reload.
  `RESEED=1` rebuilds the seed and row-scale assertions catch a stale one.
- **Per-arm.** Restore -> (tool runs, e.g. a tuner) -> restore again so tool
  writes never reach the measurement -> restart -> settle -> measure.
- **Warmup + reps.** One warmup of `*_WARMUP` seconds, then `REPS` measured reps
  at `TPCC_DURATION` / `SMALLBANK_DURATION`; `bench_rep_prep` settles
  (autovacuum quiesce + `SETTLE_SECS`) between reps without reloading.
- **Settling, locking, metadata.** `bench_settle` waits for autovacuum to
  quiesce then holds `SETTLE_SECS`. `bench_lock` holds a non-blocking
  `.bench.lock` (`.bench.lock.dir` where `flock` is unavailable);
  `bench_timer` writes JSON (status, elapsed, resources, model, git commit)
  next to each arm's results.

## Running experiments

All commands below run inside `adcoexp` (`docker compose exec -it adcoexp bash`).

### TPC-C / SmallBank

```bash
./run/tpcc/run_all.sh                 # all arms in order, skips completed ones
./run/tpcc/run_all_only_benchmark.sh  # benchmark existing artifacts only
./run/tpcc/run_baseline.sh            # single arm (same scripts under run/smallbank/)
./run/tpcc/run_{aco,dco,adco}.sh      # ACo rewrite / DCo tuning / ADCo both
./run/tpcc/run_{py-dbridge,naive-llm}.sh    # app rewrites + workload
./run/tpcc/run_{agenttune,gptuner,ottertune}.sh  # knob tuning + workload
./run/tpcc/run_{naive-llm-agenttune,agenttune-naive-llm}.sh  # stacked arms
./run/tpcc/run_report_performance.sh  # reports into reports/tpcc/
```

A stacked arm caches only the AgentTune phase: a re-run skips completed tuning
but always regenerates the rewrite. Delete `results/<wl>/<arm>/state` to force
full re-tuning. `run_all.sh` skips arms that already have result CSVs and
records per-arm status in `results/<wl>/result.json`.

### Verification

```bash
./run/tpcc/run_verify.sh [dbms] [arm,...]        # one arm or subset
./run/tpcc/run_all_verify.sh [dbms]              # every rewrite tree on disk
```

Same commands under `run/smallbank/`.

Verification restores the verify seed per arm, resets knobs, runs a tiny
single-client smoke, and writes `results/<wl>/verify_<arm>.json`; benchmark
results are moved aside and restored afterwards. Fresh verdicts (<24h) are
reused unless `REVERIFY=1`. `VERIFY_DURATION` (default 20s), `VERIFY_WARMUP`
(default 0), and `VERIFY_OUTPUT` control the smoke and its JSON path.

TPC-C checks static diff, smoke completeness, and Clause 3.3 / 1.5 consistency
(W_YTD, D_NEXT_O_ID, NEW_ORDER gaps, O_OL_CNT vs ORDER_LINE, HISTORY sums,
balance reconciliation, PK uniqueness). SmallBank checks the six transactions,
commit/rollback ownership, write coverage, smoke health, table invariants, and
BALANCE read equivalence. Reports add a `## Correctness` section.

### Robustness

```bash
./run/tpcc/run_naive-llm-robustness.sh [runs] [dbms] [model]
./run/tpcc/run_aco-robustness.sh       # also adco, py-dbridge, stacked arms
./run/tpcc/run_all_robustness.sh <arm> [runs] [dbms] [model]
./run/tpcc/run_report_robustness.sh    # reports/tpcc/robustness.md
```

Each run generates and classifies a fresh rewrite (substantive / unchanged /
cosmetic), verifies it, and records the result. Defaults follow
`ROBUSTNESS_REPS`; Py-DBridge is fixed at 1 run, and `-full-scale` wrappers use
the performance seed/scale (default one run, but `ROBUSTNESS_REPS` overrides it;
pass a positional `[runs]` to force a count). Summaries land in
`results/<wl>/robustness[-full-scale]/<arm>/latest.json` and
`out/app_layer/robustness[-full-scale]/<arm>/<timestamp>/`; `TEMP=<float>` sets
Naive-LLM rewrite temperature.

### STATS / TPCH

```bash
./run/stats/run_all.sh                # all STATS arms
./run/stats/run_reports.sh            # reports/stats/
./run/tpch/run_all.sh                 # all TPCH arms (+ dco, agenttune, gptuner)
./run/tpch/run_reports.sh             # reports/tpch/
```

Query-layer arms write to `results/stats/` and `results/tpch/`; rewrites land
in `out/query_layer/`.

## Results

| Path | Contents |
|------|----------|
| `results/<wl>/<arm>/benchmarks/` | Per-rep and load CSVs, report-compatible aliases |
| `results/<wl>/<arm>/<arm>.json`; `results/<wl>/verify_<arm>.json` | Timer metadata; correctness verdict (+ `.smoke.csv` / `.smoke.log`) |
| `results/<wl>/robustness*/<arm>/latest.json`, `results/stats/`, `results/tpch/` | Robustness summaries; query-layer results |
| `out/app_layer/`, `out/query_layer/`, `out/logs/` | Rewrite trees by approach; per-run console logs |
| `reports/` | Performance, correctness, and robustness reports |
