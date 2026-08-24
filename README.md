# adco-experiments

Experiment harness for evaluating LLM-based SQL query rewriting approaches
([ReSequel](https://github.com/dannykhant/resequel), [R-Bot](https://github.com/dannykhant/r-bot),
[LearnedRewrite](https://github.com/dannykhant/learnedrewrite))
against baseline execution on the STATS benchmark, using PostgreSQL or MySQL.

## Repository layout

| Path | Purpose |
|------|---------|
| `run1SetupDependencies.sh` | Install system build dependencies |
| `run2DownloadBaselines.sh` | Clone ReSequel, R-Bot, and LearnedRewrite into `baselines/` |
| `run3SetupBaselines.sh` | Create venvs and build artifacts for each baseline |
| `run4DownloadData.sh` | Download the STATS dataset CSVs into `data/stats/` |
| `run5PrepareData-*.sh` | Create and load the `stats` / `stats-lite` databases (local or remote PostgreSQL, MySQL) |
| `run6UpdateConfigs.sh` | Regenerate the baselines' `APIKeys.yaml` / `DBConfig.yaml` from `.env` |
| `run7Experiments-ReSequel.sh` | Run the ReSequel pipeline (catalog build, rewrite, verify) + baselines |
| `run8Experiments-R-Bot.sh` | Run the R-Bot pipeline (rewrite, verify) + workload |
| `run9Experiments-LearnedRewrite.sh` | Run the LearnedRewrite pipeline (rewrite, verify) + workload |
| `.env-example` | Template for API keys and Postgres credentials; copy to `.env` |
| `workload/databases/` | Per-DBMS workload SQL: schemas, indexes, queries, import scripts |
| `workload/src/` | Python harness that replays workloads and logs results (`DBConfig.yaml` holds its DB credentials) |
| `scripts/` | Individual experiment driver scripts called by the `run7*`–`run9*` entry points |
| `catalog/` | Generated ReSequel catalog files (per-dataset JSONs) |
| `results/` | Benchmark results per approach (`results/resequel`, `results/r-bot`, `results/learnedrewrite`) |
| `docker-compose.yml` | `db` (PostgreSQL 17) service plus the experiment container |

## Setup

```bash
./run1SetupDependencies.sh
./run2DownloadBaselines.sh
./run3SetupBaselines.sh
./run4DownloadData.sh
./run5PrepareData-PostgreSQL-Remote.sh   # or -Local.sh / MySQL variant
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

PGUSER=postgres
PGPASSWORD=postgres
PGHOST=127.0.0.1   # 'db' for the docker-compose service, 127.0.0.1 for local
PGPORT=5432
```

Then regenerate the `APIKeys.yaml` / `DBConfig.yaml` files for ReSequel and R-Bot:

```bash
./run6UpdateConfigs.sh
```

The workload harness's own credentials live separately in
`workload/src/DBConfig.yaml`.

## Running experiments

```bash
./run7Experiments-ReSequel.sh       # ReSequel pipeline + baselines
./run8Experiments-R-Bot.sh          # R-Bot pipeline + workload
./run9Experiments-LearnedRewrite.sh # LearnedRewrite pipeline + workload
```

Results are written to `results/`, with rewritten queries in
`ReSequel-results/`, `R-Bot-results/`, and `LearnedRewrite-results/`.
