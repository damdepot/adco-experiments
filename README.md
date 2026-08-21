# adco-experiments

Experiment harness for evaluating LLM-based SQL query rewriting approaches
([ReSequel](https://github.com/dannykhant/resequel), [R-Bot](https://github.com/dannykhant/r-bot))
against baseline execution on the STATS benchmark, using PostgreSQL or MySQL.

## Repository layout

| Path | Purpose |
|------|---------|
| `run1SetupDependencies.sh` | Install system build dependencies |
| `run2DownloadBaselines.sh` | Clone R-Bot and ReSequel into `baselines/` |
| `run3SetupBaselines.sh` | Create venvs and build artifacts for each baseline |
| `run4DownloadData.sh` | Download the STATS dataset CSVs into `data/stats/` |
| `run5PrepareData-*.sh` | Create and load the `stats` / `stats-lite` databases (local or remote PostgreSQL, MySQL) |
| `run6Experiments-*.sh` | Run the end-to-end experiments (catalog build, rewrite, verify, baseline runs) |
| `workload/` | Per-DBMS workload SQL: schemas, indexes, queries, import scripts |
| `workload_generator/` | Python harness that replays workloads and logs results (`DBConfig.yaml` holds its DB credentials) |
| `explocal/` | Individual experiment driver scripts called by the `run6*` entry points |
| `docker-compose.yml` | `db` (PostgreSQL 17) service plus the experiment container |

## Setup

```bash
./run1SetupDependencies.sh
./run2DownloadBaselines.sh
./run3SetupBaselines.sh
./run4DownloadData.sh
./run5PrepareData-PostgreSQL-Remote.sh   # or -Local.sh / MySQL variant
```

## Configuring ReSequel

ReSequel is cloned to `baselines/ReSequel`; its config lives in
`baselines/ReSequel/src/main/python/`.

### 1. API keys — `APIKeys.yaml`

Add your key under the LLM platform you use (OpenAI, Groq, Google):

```yaml
---

- llm_platform: OpenAI
  key_1: '<your-openai-api-key>'

- llm_platform: Groq
  key_1: '<your-groq-api-key>'

- llm_platform: Google
  key_1: '<your-google-api-key>'
```

### 2. Database — `DBConfig.yaml`

Point ReSequel at your database:

```yaml
---

- database: Postgres
  user: postgres
  password: postgres
  host: db        # 'db' for the docker-compose service, 127.0.0.1 for local
  port: 5432
```

## Running experiments

```bash
./run6Experiments-ReSequel.sh   # ReSequel pipeline + baselines
./run6Experiments-R-Bot.sh      # R-Bot pipeline + baselines
```

Results are written to `results/`.
