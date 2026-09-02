# ADCo Experiments

Experiment harness for evaluating LLM-based SQL query rewriting approaches
([ADCo](https://github.com/damdepot/ADCo), [ReSequel](https://github.com/dannykhant/resequel),
[R-Bot](https://github.com/dannykhant/r-bot), [LearnedRewrite](https://github.com/dannykhant/learnedrewrite),
[Py-DBridge](https://github.com/dannykhant/py-dbridge)) against baseline execution,
run on two layers:

- **DB layer** — batch SQL workloads (STATS, stats-lite, and other
  `workload/databases` datasets) on PostgreSQL or MySQL.
- **App layer** — OLTP application workloads (Smallbank, TPC-C) on PostgreSQL or MySQL.

## Repository layout

| Path | Purpose |
|------|---------|
| `run/query_layer/run1SetupDependencies.sh` | Install system build dependencies |
| `run/query_layer/run2DownloadBaselines.sh` | Clone ADCo, ReSequel, R-Bot, and LearnedRewrite into `baselines/` |
| `run/query_layer/run3SetupBaselines.sh` | Create venvs and build artifacts for each baseline |
| `run/query_layer/run4DownloadData.sh` | Download the STATS dataset CSVs into `data/stats/` |
| `run/query_layer/run5PrepareData-*.sh` | Create and load the `stats` / `stats-lite` databases (local or remote PostgreSQL, MySQL) |
| `run/query_layer/initpgSQL.sh` | Start the locally compiled PostgreSQL instance used by the workload runner |
| `run/query_layer/run6UpdateConfigs.sh` | Regenerate the baselines' `APIKeys.yaml` / `DBConfig.yaml` and ADCo's `.env` from `.env` |
| `run/query_layer/run7Experiments-ADCo.sh` | Run the ADCo pipeline (compile, rewrite, decompile, verify) + workload |
| `run/query_layer/run8Experiments-Baseline.sh` | Run the baseline (unrewritten) workload |
| `run/query_layer/run91Experiments-ReSequel.sh` | Run the ReSequel pipeline (catalog build, templatization, rewrite, verify) + workload |
| `run/query_layer/run92Experiments-R-Bot.sh` | Run the R-Bot pipeline (rewrite, verify) + workload |
| `run/query_layer/run9Experiments-LearnedRewrite.sh` | Run the LearnedRewrite pipeline (rewrite, verify) + workload |
| `run/query_layer/run93Reports.sh` | Generate comparison reports into `reports/` |
| `run/app_layer/run1DownloadBaselines.sh` | Clone ADCo and Py-DBridge into `baselines/` |
| `run/app_layer/run2SetupBaselines.sh` | Create venvs for the app-layer baselines |
| `run/app_layer/run3SetupWorkloads.sh` | Clone the Smallbank and TPC-C workload apps into `workload/apps/` |
| `run/app_layer/run4UpdateConfigs.sh` | Write `db.config` for each workload app from `.env` |
| `run/app_layer/run5Experiments-ADCo.sh` | Run ADCo rewrite + Smallbank/TPC-C workload |
| `run/app_layer/run6Experiments-Baselines.sh` | Run the baseline Smallbank/TPC-C workload |
| `run/app_layer/run7Experiments-Py-DBridge.sh` | Run the Py-DBridge rewrite + Smallbank/TPC-C workload |
| `.env-example` | Template for API keys, Postgres/MySQL credentials, and Vertex AI settings; copy to `.env` |
| `workload/databases/` | Per-DBMS SQL workloads: schemas, indexes, queries, import scripts |
| `workload/src/` | Python harness that replays DB-layer workloads and logs results (`DBConfig.yaml` holds its DB credentials) |
| `workload/apps/` | Cloned OLTP workload apps (Smallbank, TPC-C) with their own drivers and `db.config` |
| `scripts/query_layer/` | DB-layer experiment drivers called by `run/query_layer` entry points (`exp0_ADCo`, `exp1_ReSequel`, `exp2_Baselines`, `exp3_Reports`) |
| `scripts/app_layer/` | App-layer experiment drivers called by `run/app_layer` entry points (`exp0_ADCo`, `exp1_Baselines`) |
| `catalog/` | Generated ReSequel catalog files (per-dataset JSONs, e.g. `catalog/stats-lite/`) |
| `results/query_layer/` | DB-layer results per approach (`results/query_layer/adco`, `resequel`, `r-bot`, `learnedrewrite`, `baseline`) |
| `results/app_layer/` | App-layer results per approach (`results/app_layer/adco`, `py-dbridge`, `baseline`) |
| `out/query_layer/` | Rewritten queries for the DB layer (`ADCo-results/`, `ReSequel-results/`, `R-Bot-results/`, `LearnedRewrite-results/`) |
| `out/app_layer/` | Rewritten code for the app layer (`ADCo-results/`, `Py-DBridge-results/`) |
| `reports/` | Generated comparison reports (`run/query_layer/run93Reports.sh`) |
| `docker/` | Container entrypoint used by the experiment image |
| `docker-compose.yml` | `db` (PostgreSQL 17) service plus the experiment container |

## Setup (DB layer)

```bash
./run/query_layer/run1SetupDependencies.sh
./run/query_layer/run2DownloadBaselines.sh
./run/query_layer/run3SetupBaselines.sh
./run/query_layer/run4DownloadData.sh
./run/query_layer/run5PrepareData-PostgreSQL-Remote.sh   # or -Local.sh / MySQL variant
```

## Setup (App layer)

```bash
./run/app_layer/run1DownloadBaselines.sh
./run/app_layer/run2SetupBaselines.sh
./run/app_layer/run3SetupWorkloads.sh
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
./run/query_layer/run6UpdateConfigs.sh   # ReSequel/R-Bot YAML + ADCo .env
./run/app_layer/run4UpdateConfigs.sh  # smallbank / tpcc db.config
```

## Running experiments

DB layer:

```bash
./run/query_layer/run7Experiments-ADCo.sh           # ADCo pipeline + workload
./run/query_layer/run8Experiments-Baseline.sh       # baseline (unrewritten) workload
./run/query_layer/run91Experiments-ReSequel.sh      # ReSequel pipeline + workload
./run/query_layer/run92Experiments-R-Bot.sh         # R-Bot pipeline + workload
./run/query_layer/run9Experiments-LearnedRewrite.sh # LearnedRewrite pipeline + workload
./run/query_layer/run93Reports.sh                   # comparison reports into reports/
```

App layer:

```bash
./run/app_layer/run5Experiments-ADCo.sh          # ADCo rewrite + Smallbank/TPC-C workload
./run/app_layer/run6Experiments-Baselines.sh     # baseline Smallbank/TPC-C workload
./run/app_layer/run7Experiments-Py-DBridge.sh    # Py-DBridge rewrite + Smallbank/TPC-C workload
```

Results are written to `results/query_layer/` and `results/app_layer/`, with rewritten
queries in `out/query_layer/` and rewritten app code in `out/app_layer/`.