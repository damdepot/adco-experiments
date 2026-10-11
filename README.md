# ADCo Experiments

Experiment harness for evaluating LLM-based SQL query rewriting approaches
([ADCo](https://github.com/damdepot/ADCo), [ReSequel](https://github.com/dannykhant/resequel),
[R-Bot](https://github.com/dannykhant/r-bot), [LearnedRewrite](https://github.com/dannykhant/learnedrewrite),
[Py-DBridge](https://github.com/dannykhant/py-dbridge)) against baseline execution,
run on two layers:

- **DB layer** — batch and OLTP SQL workloads (Smallbank, TPC-C, STATS) tuning PostgreSQL / MySQL configuration knobs ([ADCo](https://github.com/damdepot/ADCo), [AgentTune](https://github.com/dannykhant/AgentTune), [GPTuner](https://github.com/dannykhant/gptuner), [OtterTune](https://github.com/dannykhant/ottertune)).
- **App layer** — OLTP application workloads (Smallbank, TPC-C) on PostgreSQL or MySQL.

## Repository layout

| Path | Purpose |
|------|---------|
| `run/setup/db-download-baselines.sh` | Clone ADCo, AgentTune, GPTuner, and OtterTune into `baselines/` |
| `run/setup/db-setup-baselines.sh` | Create venvs and build artifacts for each DB-layer baseline |
| `run/setup/db-setup-workloads.sh` | Clone Smallbank and TPC-C workload apps into `workload/apps/` |
| `run/setup/db-update-configs.sh` | Regenerate baselines' configs from `.env` |
| `run/tpcc/run_baseline.sh` / `run/smallbank/run_baseline.sh` | Run baseline workload (app + DB layer) |
| `run/tpcc/run_aco.sh` / `run/smallbank/run_aco.sh` | Run ACo rewrite + workload |
| `run/tpcc/run_dco.sh` / `run/smallbank/run_dco.sh` | Run DCo knob tuning + workload |
| `run/tpcc/run_adco.sh` / `run/smallbank/run_adco.sh` | Run ADCo rewrite + tuning + workload |
| `run/tpcc/run_py-dbridge.sh` / `run/smallbank/run_py-dbridge.sh` | Run Py-DBridge rewrite + workload |
| `run/tpcc/run_agenttune.sh` / `run/smallbank/run_agenttune.sh` | Run AgentTune knob tuning + workload |
| `run/tpcc/run_gptuner.sh` / `run/smallbank/run_gptuner.sh` | Run GPTuner knob tuning + workload |
| `run/tpcc/run_ottertune.sh` / `run/smallbank/run_ottertune.sh` | Run OtterTune knob tuning + workload |
| `run/tpcc/run_reports.sh` / `run/smallbank/run_reports.sh` | Generate comparison reports into `reports/` |
| `run/stats/run_baseline.sh` | Run stats baseline workload |
| `run/stats/run_aco.sh` | Run stats ACo rewrite + workload |
| `run/stats/run_adco.sh` | Run stats ADCo rewrite + tuning + workload |
| `run/stats/run_resequel.sh` | Run ReSequel rewrite + workload |
| `run/stats/run_r-bot.sh` | Run R-Bot rewrite + workload |
| `run/stats/run_learnedrewrite.sh` | Run LearnedRewrite + workload |
| `run/stats/run_reports.sh` | Generate stats comparison reports into `reports/` |
| `.env-example` | Template for API keys, Postgres/MySQL credentials, and Vertex AI settings; copy to `.env` |
| `workload/databases/` | Per-DBMS SQL workloads: schemas, indexes, queries, import scripts |
| `workload/src/` | Python harness that replays DB-layer workloads and logs results (`DBConfig.yaml` holds its DB credentials) |
| `workload/apps/` | Cloned OLTP workload apps (Smallbank, TPC-C) with their own drivers and `db.config` |
| `scripts/stats/` | DB-layer experiment drivers called by `run/stats` entry points (`exp0_ADCo`, `exp1_ReSequel`, `exp2_Baselines`, `exp3_Reports`) |
| `scripts/common/app_layer/` | Benchmark-neutral app-layer drivers (ADCo, Py-DBridge, reports) shared by `run/tpcc` and `run/smallbank` |
| `scripts/tpcc/` + `scripts/smallbank/` | Workload-specific app/DB-layer drivers called by `run/tpcc` and `run/smallbank` entry points |
| `scripts/common/db_layer/` | Benchmark-neutral DB-layer drivers (ADCo/DCo, AgentTune/GPTuner/OtterTune, reports) shared by `run/tpcc` and `run/smallbank` |
| `scripts/common/` | Benchmark-neutral drivers shared across workloads (`app_layer/`, `db_layer/`) |
| `scripts/_lib/` | Shared shell harness (`bench_lib.sh`, `docker.sh`, `run_comparison.sh`) |
| `catalog/` | Generated ReSequel catalog files (per-dataset JSONs, e.g. `catalog/stats/`) |
| `results/tpcc/` | TPC-C results per approach (`baseline`, `aco`, `dco`, `adco`, `py-dbridge`, `agenttune`, `ottertune`, `gptuner`) |
| `results/smallbank/` | Smallbank results per approach (same set as TPC-C) |
| `results/stats/` | Stats-dataset results per approach (`baseline`, `aco`, `adco`, `resequel`, `r-bot`, `learnedrewrite`) |
| `out/query_layer/` | Rewritten queries for the DB layer (`ADCo-results/`, `ReSequel-results/`, `R-Bot-results/`, `LearnedRewrite-results/`) |
| `out/app_layer/` | Rewritten code for the app layer (`ADCo-results/`, `Py-DBridge-results/`) |
| `reports/` | Generated comparison reports (`run/tpcc/run_reports.sh`, `run/smallbank/run_reports.sh`, `run/stats/run_reports.sh`) |
| `docker/` | Container entrypoint used by the experiment image |
| `docker-compose.yml` | `db` (PostgreSQL 17) service plus the experiment container |

## Setup (DB layer)

```bash
./run/setup/deps-local.sh
./run/setup/stats-download-baselines.sh
./run/setup/stats-setup-baselines.sh
./run/setup/stats-download-data.sh
./run/setup/stats-prepare-postgres-remote.sh   # or -local.sh / -mysql.sh variant
```

## Setup (App layer)

```bash
./run/setup/app-download-baselines.sh
./run/setup/app-setup-baselines.sh
./run/setup/app-setup-workloads.sh
```

## Configuring baselines

Copy `.env-example` to `.env` and fill in your API keys and database credentials:

```bash
cp .env-example .env
```

```dotenv
OPENAI_API_KEY=sk-your-openai-key
GROQ_API_KEY=gsk_your-groq-key
GOOGLE_API_KEY=your-google-api-key

POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_HOST=127.0.0.1   # 'db' for the docker-compose service, 127.0.0.1 for local
POSTGRES_PORT=5432

MYSQL_USER=root
MYSQL_PASSWORD=root
MYSQL_HOST=127.0.0.1
MYSQL_PORT=3306

GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project
GOOGLE_CLOUD_LOCATION=global
```

Then regenerate the baselines' config files:

```bash
./run/setup/stats-update-configs.sh   # ReSequel/R-Bot YAML + ADCo .env
./run/setup/app-update-configs.sh  # smallbank / tpcc db.config
```

## Running experiments

TPC-C / Smallbank (same scripts under `run/tpcc/` and `run/smallbank/`):

```bash
./run/tpcc/run_baseline.sh    # baseline workload (same under run/smallbank/)
./run/tpcc/run_aco.sh         # ACo rewrite + workload (same under run/smallbank/)
./run/tpcc/run_dco.sh         # DCo tuning + workload (same under run/smallbank/)
./run/tpcc/run_adco.sh        # ADCo rewrite + tuning + workload (same under run/smallbank/)
./run/tpcc/run_py-dbridge.sh  # Py-DBridge rewrite + workload (same under run/smallbank/)
./run/tpcc/run_agenttune.sh   # AgentTune tuning + workload (same under run/smallbank/)
./run/tpcc/run_gptuner.sh     # GPTuner tuning + workload (same under run/smallbank/)
./run/tpcc/run_ottertune.sh   # OtterTune tuning + workload (same under run/smallbank/)
./run/tpcc/run_reports.sh     # comparison reports into reports/ (same under run/smallbank/)
```

Stats:

```bash
./run/stats/run_baseline.sh       # baseline workload
./run/stats/run_aco.sh            # ACo rewrite + workload
./run/stats/run_adco.sh           # ADCo rewrite + tuning + workload
./run/stats/run_resequel.sh       # ReSequel rewrite + workload
./run/stats/run_r-bot.sh          # R-Bot rewrite + workload
./run/stats/run_learnedrewrite.sh # LearnedRewrite + workload
./run/stats/run_reports.sh        # comparison reports into reports/
```

Results are written to `results/tpcc/`, `results/smallbank/` and `results/stats/`, with rewritten
queries in `out/query_layer/` and rewritten app code in `out/app_layer/`.