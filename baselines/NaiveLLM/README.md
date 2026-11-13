# NaiveLLM — single-shot LLM rewriter baseline

The deliberately simple baseline: copy an application, send its driver + entry
file to an LLM **once** at temperature 0, write back whatever comes back. No
profiling, no iteration, no feedback from the database.

Two layers use the same CLI: the **app layer** (TPC-C / Smallbank driver +
`tpcc.py`/`main.py`) and the **query layer** (`db_app.py` compiled from
`query*.sql`, used by Stats and TPC-H).

## Layout

| Path | Purpose |
|------|---------|
| `src/cli.py` | CLI: copy tree, select files, one LLM call, apply + syntax check |
| `src/rewrite.py` | file selection, prompt assembly (task + rules), `### FILE:` parsing |
| `src/query_codec.py` | `compile` `query*.sql` → `db_app.py`; `decompile` back to SQL |
| `tests/test_rewrite.py` | prompt/parse/select-file unit tests |
| `venv/` | this baseline's venv (`uv`), hash-pinned by `.venv_hash` |

Deps are only `google-genai` and `python-dotenv`.

## Setup

```bash
./run/setup/app-setup-workloads.sh    # app workload venvs (tpcc/smallbank)
./run/setup/app-setup-baselines.sh    # creates baselines/NaiveLLM/venv
```

`.env` at the repo root needs Vertex AI credentials (see `.env-example`):

```bash
GOOGLE_CLOUD_PROJECT=your-gcp-project
GOOGLE_CLOUD_LOCATION=global
```

Default model is `gemini-3.5-flash-lite` (`MODEL` env, or the CLI `--model`).

## Direct CLI

```bash
cd baselines/NaiveLLM
venv/bin/python -m src.cli \
    --source-dir ../../workload/apps/tpcc --output-dir /tmp/rewrite-tpcc \
    --db postgres --model gemini-3.5-flash-lite \
```

What it does:

1. Deletes and re-copies `--source-dir` (skips `.git`, `venv`, `__pycache__`).
2. Selects writable files: `drivers/postgresdriver.py` (or `mysqldriver.py`), plus
   `tpcc.py` / `main.py`; for query layer, `db_app.py`. Schema files are read-only
   context. Missing driver → exit 1.
3. Builds one prompt and calls the model once at `temperature=0.0` (override with
   `--temperature`), `max_output_tokens=65536`.
4. Parses `### FILE: <relpath>` blocks, refuses paths outside the changed set
   (`safe_target`), writes them, then `py_compile`s each; any file that fails to
   compile is restored to its original bytes.
5. Prints `files changed: N, restored: M`; exits 1 if nothing usable was produced.

Artifacts land next to (not inside) the output dir: `llm_prompt.txt` (exact
prompt sent), `llm_response.txt` (raw model output), and `smoke.log` (rewrite
smoke run, written by the app-layer driver).

## Query layer (Stats, TPC-H)

```bash
cd baselines/NaiveLLM
venv/bin/python -m src.query_codec compile   --input-dir <query dir> --output-dir <dir>
venv/bin/python -m src.query_codec decompile --input-dir <dir>       --output-dir <query dir>
```

`compile` packs `query<N>.sql` in numeric order into one `db_app.py` (plus
`schema.sql` copied as context); `decompile` extracts `QUERY_<n>` constants back
to `query<N>.sql`. `run/stats/run_naive-llm.sh` and `run/tpch/run_naive-llm.sh`
drive the Compile → Rewrite → Decompile → Verify pipeline through
`scripts/common/query_layer/exp2_Baselines/runExperiment2-NaiveLLM.sh`, then run
the workload.

## App-layer runs

```bash
./run/tpcc/run_naive-llm.sh                  # unguided rewrite
./run/tpcc/run_naive-llm-robustness.sh 10    # 10 fresh rewrites, each verified
./run/smallbank/run_naive-llm.sh             # unguided rewrite
```

Knobs (defaults are the reported TPC-C arm):

| Var | Default | Notes |
|-----|---------|-------|
| `ARM` | `naive-llm` | result dir `results/tpcc/<ARM>` |
| `NAIVE_REWRITE_ROOT` | `out/app_layer/NaiveLLM-results` | rewritten tree root |
| `MODEL` | `gemini-3.5-flash-lite` | |

The shell driver rewrites into `<root>/Rewrite/<dbms>/<bench>-NaiveLLM`, runs a
smoke pass (fails on `Traceback`, on TPC-C transaction errors other than
deadlocks, or on >5% Smallbank errors), then measures.

## Robustness (TPC-C)

```bash
./run/tpcc/run_naive-llm-robustness.sh [runs=10] [dbms=postgres] [model]
# the other rewrite arms have their own wrappers (aco/adco 10 runs, py-dbridge 1):
./run/tpcc/run_aco-robustness.sh
./run/tpcc/run_adco-robustness.sh
./run/tpcc/run_py-dbridge-robustness.sh
```

Each run is: generate a fresh tree with the arm's pipeline → verify that tree →
record. No run 0, no measured-artifact check, no separate performance seed.
Default runs: naive-llm 10, aco 10, adco 10, py-dbridge 1.

| Path | Contents |
|------|----------|
| `results/tpcc/robustness/naive-llm/latest.json` | summary consumed by the report |
| `out/app_layer/robustness/naive-llm/<ts>/summary.json` | same, timestamped |
| `out/app_layer/robustness/naive-llm/<ts>/summary.md` | run table + headline |
| `out/app_layer/robustness/naive-llm/<ts>/rNN/` | rewrite, verify log/JSON |

`latest.json` holds `runs_completed`, `counts` (pass/fail/warn/unverified),
`status`, `failures`, and the per-run list. It verifies with a small
`tpcc_verify_seed` (default **1** warehouse), created once and reused; the
performance arm still measures on the full `tpcc_seed`. `RESEED=1` rebuilds the
verify seed.

Each iteration prints `run i/N: PASS|FAIL|UNVERIFIED`; the verify log under
`rNN/verify.log` has the four-gate detail. The whole verify child is capped at
`VERIFY_TIMEOUT` (default 300 s); a hung run becomes `UNVERIFIED` and the loop
continues. `VERBOSE=1` dumps the rewrite log.

## Correctness in reports

`./run/tpcc/run_report_performance.sh` adds a `## Correctness` table and a Correctness
column to both performance tables. Arms with a robustness summary use it
(`PASS 9/10`, run counts); arms without one fall back to the single-run
`results/tpcc/verify_<arm>.json` and show `1-run PASS`. WARN shows as SUSPECT;
no check shows UNVERIFIED.

## Tests

```bash
python3 baselines/NaiveLLM/tests/test_rewrite.py    # prints "ok"
```

Covers response parsing, path safety, file selection, and that the default
prompt is unchanged.

## Notes / limitations

- One shot, temperature 0; no retries, no profiling, no DB feedback.
- No schema changes, no new files, no new dependencies (enforced by prompt, not code).
- Validation is syntax-only (`py_compile`). Runtime failures are caught by the
  app-layer smoke run; TPC-C correctness by `run_verify.sh`.
- `results/tpcc/naive-llm` numbers recorded before the prompt switch are stale
  (guided) and must be re-run with `./run/tpcc/run_naive-llm.sh`.
