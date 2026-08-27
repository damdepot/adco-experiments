# ADCo Experiments

Experiment harness for evaluating LLM-based SQL query rewriting approaches
([ADCo](https://github.com/damdepot/ADCo), [ReSequel](https://github.com/dannykhant/resequel),
[R-Bot](https://github.com/dannykhant/r-bot), [LearnedRewrite](https://github.com/dannykhant/learnedrewrite))
against baseline execution on the STATS benchmark, using PostgreSQL or MySQL.

## Repository layout

| Path | Purpose |
|------|---------|
| `run_db_layer/run1SetupDependencies.sh` | Install system build dependencies |
| `run_db_layer/run2DownloadBaselines.sh` | Clone ReSequel, R-Bot, and LearnedRewrite into `baselines/` |
| `run_db_layer/run3SetupBaselines.sh` | Create venvs and build artifacts for each baseline |
| `run_db_layer/run4DownloadData.sh` | Download the STATS dataset CSVs into `data/stats/` |
| `run_db_layer/run5PrepareData-*.sh` | Create and load the `stats` / `stats-lite` databases (local or remote PostgreSQL, MySQL) |
| `run_db_layer/run6UpdateConfigs.sh` | Regenerate the baselines' `APIKeys.yaml` / `DBConfig.yaml` and ADCo's `.env` from `.env` |
| `run_db_layer/run7Experiments-ADCo.sh` | Run the ADCo pipeline (compile, rewrite, decompile, select, verify) + workload |
| `run_db_layer/run8Experiments-Baseline.sh` | Run the baseline (unrewritten) workload |
| `run_db_layer/run91Experiments-ReSequel.sh` | Run the ReSequel pipeline (catalog build, templatization, rewrite, verify) + workload |
| `run_db_layer/run92Experiments-R-Bot.sh` | Run the R-Bot pipeline (rewrite, verify) + workload |
| `run_db_layer/run9Experiments-LearnedRewrite.sh` | Run the LearnedRewrite pipeline (rewrite, verify) + workload |
| `run_db_layer/run93Reports.sh` | Generate comparison reports into `reports/` |
| `.env-example` | Template for API keys, Postgres credentials, and Vertex AI settings; copy to `.env` |
| `workload/databases/` | Per-DBMS workload SQL: schemas, indexes, queries, import scripts |
| `workload/src/` | Python harness that replays workloads and logs results (`DBConfig.yaml` holds its DB credentials) |
| `scripts/` | Experiment drivers called by the entry points (`exp0_ADCo`, `exp1_ReSequel`, `exp2_Baselines`, `exp3_Reports`) |
| `catalog/` | Generated ReSequel catalog files (per-dataset JSONs) |
| `results/` | Benchmark results per approach (`results/adco`, `results/resequel`, `results/r-bot`, `results/learnedrewrite`, `results/baseline`) |
| `*-results/` | Rewritten queries per approach (`ADCo-results/`, `ReSequel-results/`, `R-Bot-results/`, `LearnedRewrite-results/`) |
| `reports/` | Generated comparison reports (`run_db_layer/run93Reports.sh`) |
| `docker-compose.yml` | `db` (PostgreSQL 17) service plus the experiment container |

## Setup

```bash
./run_db_layer/run1SetupDependencies.sh
./run_db_layer/run2DownloadBaselines.sh
./run_db_layer/run3SetupBaselines.sh
./run_db_layer/run4DownloadData.sh
./run_db_layer/run5PrepareData-PostgreSQL-Remote.sh   # or -Local.sh / MySQL variant
```

## Configuring baselines

Copy `.env-example` to `.env` and fill in your API keys and Postgres credentials:

```bash
cp .env-example .env
```

```dotenv
OPENAI_API_KEY=sk-your-openai-key
GROQ_API_KEY=gsk_your-groq-key
GOOGLE_API_KEY=your-google-api-key

GOOGLE_GENAI_USE_VERTEXAI=1
GOOGLE_CLOUD_PROJECT=your-gcp-project
GOOGLE_CLOUD_LOCATION=global

PGUSER=postgres
PGPASSWORD=postgres
PGHOST=127.0.0.1   # 'db' for the docker-compose service, 127.0.0.1 for local
PGPORT=5432
```

Then regenerate the `APIKeys.yaml` / `DBConfig.yaml` files for ReSequel and
R-Bot, and the `.env` for ADCo:

```bash
./run_db_layer/run6UpdateConfigs.sh
```

## Running experiments

```bash
./run_db_layer/run7Experiments-ADCo.sh           # ADCo pipeline + workload
./run_db_layer/run8Experiments-Baseline.sh       # baseline (unrewritten) workload
./run_db_layer/run91Experiments-ReSequel.sh      # ReSequel pipeline + workload
./run_db_layer/run92Experiments-R-Bot.sh         # R-Bot pipeline + workload
./run_db_layer/run9Experiments-LearnedRewrite.sh # LearnedRewrite pipeline + workload
./run_db_layer/run93Reports.sh                   # comparison reports into reports/
```

Results are written to `results/`, with rewritten queries in `ADCo-results/`,
`ReSequel-results/`, `R-Bot-results/`, and `LearnedRewrite-results/`.
