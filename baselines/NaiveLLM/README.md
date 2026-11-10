# NaiveLLM — single-shot LLM rewriter baseline

The deliberately unguided baseline: copy an application, send its driver + entry
file to an LLM **once** at temperature 0, write back whatever comes back. No
profiling, no iteration, no feedback from the database.

Two layers use the same CLI: the **app layer** (TPC-C / Smallbank driver +
`tpcc.py`/`main.py`) and the **query layer** (`db_app.py` compiled from
`query*.sql`, used by Stats and TPC-H).

An optional second arm, `naive-llm-aggressive`, uses a guidance prompt that was
chosen offline by evaluating a fixed bank of snippets (`run_prompt_search.sh`).

## Layout

| Path | Purpose |
|------|---------|
| `src/cli.py` | CLI: copy tree, select files, one LLM call, apply + syntax check |
| `src/rewrite.py` | file selection, prompt assembly (task + optional guidance + rules), `### FILE:` parsing |
| `src/query_codec.py` | `compile` `query*.sql` → `db_app.py`; `decompile` back to SQL |
| `prompts/` | guidance bank (`aggressive-*.txt`) and promoted `selected-*.txt` |
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
    [--prompt-file prompts/aggressive-batch.txt]
```

What it does:

1. Deletes and re-copies `--source-dir` (skips `.git`, `venv`, `__pycache__`).
2. Selects writable files: `drivers/postgresdriver.py` (or `mysqldriver.py`), plus
   `tpcc.py` / `main.py`; for query layer, `db_app.py`. Schema files are read-only
   context. Missing driver → exit 1.
3. Builds one prompt and calls the model once at `temperature=0.0`,
   `max_output_tokens=65536`.
4. Parses `### FILE: <relpath>` blocks, refuses paths outside the changed set
   (`safe_target`), writes them, then `py_compile`s each; any file that fails to
   compile is restored to its original bytes.
5. Prints `files changed: N, restored: M`; exits 1 if nothing usable was produced.

An empty `--prompt-file` (or one with only whitespace) is treated as no guidance,
so the prompt stays byte-identical to the unguided baseline.

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
./run/tpcc/run_naive-llm.sh          # original (unguided) arm
./run/smallbank/run_naive-llm.sh
```

Knobs (defaults keep the original arm):

| Var | Default |
|-----|---------|
| `ARM` | `naive-llm` |
| `NAIVE_REWRITE_ROOT` | `out/app_layer/NaiveLLM-results` |
| `PROMPT_FILE` | empty (control prompt) |
| `MODEL` | `gemini-3.5-flash-lite` |

The shell driver rewrites into `<root>/Rewrite/<dbms>/<bench>-NaiveLLM`, runs a
smoke pass (fails on `Traceback`, on TPC-C transaction errors other than
deadlocks, or on >5% Smallbank errors), then measures.

## Aggressive arm (offline prompt search)

```bash
./scripts/common/app_layer/exp3_PromptSearch/run_prompt_search.sh tpcc      # or smallbank
cp out/app_layer/NaiveLLM-search-results/selected-tpcc.txt baselines/NaiveLLM/prompts/selected-tpcc.txt
./run/tpcc/run_naive-llm-aggressive.sh
```

How the search works:

Candidates: `control` (no prompt) plus every non-empty `.txt` in `prompts/` whose
name is not `selected-*`. Each is rewritten on the real benchmark and measured
(default 2 reps); score is the **median TOTAL txn/s**. Smallbank uses the held-out
`SMALLBANK_SEED=1337` for search while the reported arm keeps the default seed 42;
TPC-C is unseeded. Results, per-candidate CSVs and driver/entry `sha256` hashes go
to `out/app_layer/NaiveLLM-search-results/search-<bench>.json` (scratch only —
never `results/`). The winner is copied to `selected-<bench>.txt` in the search
dir; if control wins that file is **empty**, which is valid and still promotes.
`run_naive-llm-aggressive.sh` hard-fails until `prompts/selected-<bench>.txt` exists.

## Prompt bank

| File | Focus |
|------|-------|
| `aggressive-batch.txt` | replace N+1 / per-row lookups with set-based queries |
| `aggressive-bulkwrite.txt` | `executemany` / multi-row `INSERT` / `COPY`, same write set |
| `aggressive-sqlpushdown.txt` | push filter/aggregate/join into SQL, fewer columns |
| `aggressive-reuse.txt` | reuse connections, cursors, prepared statements; cache reads |
| `aggressive-criticalpath.txt` | optimize the hottest transaction first |
| `aggressive-plan-first.txt` | one-paragraph hot-path analysis, then all of the above |
| `aggressive-all.txt` | all of the above combined |

## Tests

```bash
python3 baselines/NaiveLLM/tests/test_rewrite.py    # prints "ok"
```

Covers response parsing, path safety, file selection, that the default prompt is
unchanged, guidance placement, and that bank files are non-empty and contain no
markdown fences or `### FILE:` lines.

## Notes / limitations

- One shot, temperature 0; no retries, no profiling, no DB feedback.
- No schema changes, no new files, no new dependencies (enforced by prompt, not code).
- Validation is syntax-only (`py_compile`). Runtime failures are caught by the
  app-layer smoke run; TPC-C correctness by `run_verify.sh`.
- The default prompt is byte-for-byte the unguided baseline, so that arm stays a
  fair floor to beat.
- The aggressive arm's prompt was tuned on the benchmark it is reported on —
  label it that way, not as an out-of-the-box result.
