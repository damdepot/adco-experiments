# NaiveLLM — single-shot LLM rewriter baseline

The deliberately simple baseline: copy an application, send its driver + entry
file to an LLM **once** at temperature 0, write back whatever comes back. No
profiling, no iteration, no feedback from the database.

Two layers use the same CLI: the **app layer** (TPC-C / Smallbank driver +
`tpcc.py`/`main.py`) and the **query layer** (`db_app.py` compiled from
`query*.sql`, used by Stats and TPC-H).

TPC-C runs with the prompt chosen by the offline search
(`prompts/selected-tpcc.txt`), not the unguided prompt. The file must exist
before the arm runs; an **empty** file is valid and means the search's
`control` (unguided) candidate won. Smallbank is deferred: it keeps the
unguided default and has no correctness gate on its search yet.

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
./run/tpcc/run_naive-llm.sh                  # searched prompt (selected-tpcc.txt)
./run/tpcc/run_naive-llm-robustness.sh 10    # 1 measured re-check + 10 fresh rewrites
./run/smallbank/run_naive-llm.sh             # unguided default (Smallbank search deferred)
```

Knobs (defaults are the reported TPC-C arm):

| Var | Default | Notes |
|-----|---------|-------|
| `ARM` | `naive-llm` | result dir `results/tpcc/<ARM>` |
| `NAIVE_REWRITE_ROOT` | `out/app_layer/NaiveLLM-results` | rewritten tree root |
| `PROMPT_FILE` | `baselines/NaiveLLM/prompts/selected-tpcc.txt` | hard-fails if missing; empty = unguided |
| `MODEL` | `gemini-3.5-flash-lite` | |

`run_naive-llm.sh` refuses to start until the selected prompt exists:

```
ERROR: missing selected prompt .../selected-tpcc.txt
Run ./run/tpcc/run_prompt_search.sh first (an empty file is valid).
```

The shell driver rewrites into `<root>/Rewrite/<dbms>/<bench>-NaiveLLM`, runs a
smoke pass (fails on `Traceback`, on TPC-C transaction errors other than
deadlocks, or on >5% Smallbank errors), then measures.

## Selected-prompt workflow

```bash
./run/tpcc/run_prompt_search.sh
./run/tpcc/run_naive-llm.sh
```

Optional args: `[dbms=postgres] [model] [reps=2]` (the benchmark is implicit).

| Step | Behavior |
|------|----------|
| Candidates | `control` (no prompt) + every non-empty `prompts/*.txt` whose name is not `selected-*` |
| Narrow the sweep | `CANDIDATES=control,aggressive-batch ./run/tpcc/run_prompt_search.sh` (tests/debug) |
| Score | median TOTAL txn/s across reps, on the real benchmark |
| Gate | after scoring, **only the winner** is verified with the TPC-C checker |
| PASS / WARN | auto-promotes `baselines/NaiveLLM/prompts/selected-tpcc.txt`; WARN is reported as SUSPECT |
| FAIL / UNVERIFIED | no promotion, previous selected prompt untouched, non-zero exit |
| `control` wins | selected file is written empty (unguided) |

Scratch (per-candidate rewrites/CSVs, `search-tpcc.json`, `winner-verify/`) goes
to `out/app_layer/NaiveLLM-search-results/` — never `results/`. The search JSON
records each candidate's status, score, CSV and rewrite `sha256`, plus the
winner, its verdict, and the promoted prompt's `sha256`.

Smallbank: the search still scores candidates and writes
`selected-smallbank.txt` into its scratch dir, but promotion stays manual and
there is no correctness oracle yet, so no gate and no auto-promote.

## Robustness (TPC-C)

```bash
./run/tpcc/run_naive-llm-robustness.sh [runs=10] [dbms=postgres] [model]
```

| Run | What it does |
|-----|--------------|
| `0` | re-verifies the actual measured tree in `out/app_layer/NaiveLLM-results/...` |
| `1..N` | fresh rewrite with the selected prompt, each verified with the generic TPC-C verify arm |

Reports:

| Path | Contents |
|------|----------|
| `results/tpcc/robustness/naive-llm/latest.json` | headline summary consumed by the report |
| `out/app_layer/robustness/naive-llm/<ts>/summary.json` | same, timestamped |
| `out/app_layer/robustness/naive-llm/<ts>/summary.md` | markdown table + headline |

`latest.json` holds `counts` (pass/fail/warn/unverified over fresh runs),
`incorrect_rate` with a Wilson 95% CI, `distinct_outputs` (distinct rewrite
hashes) and `measured_artifact` (run 0's verdict, kept separate so a stale
measured tree cannot make a clean sweep read as FAIL). Rewrites, smoke CSVs and
per-run verify JSON stay under `out/`; nothing is written under `results/`
except `latest.json`.

> Caveat: temperature 0. If `distinct_outputs` is 1, all N runs produced the
> same code and the sweep is one effective sample, not N independent ones.

## Correctness in reports

`./run/tpcc/run_reports.sh` adds a `## Correctness` table and a Correctness
column to both performance tables. Arms with a robustness summary use it
(`PASS 9/10`, run counts, distinct rewrites); arms without one fall back to the
single-run `results/tpcc/verify_<arm>.json` and show `1-run PASS`. The
`Measured` column is run 0's verdict on the tree that produced the reported
speedup, kept separate from the fresh sweep; a measured FAIL is warned even if
all fresh runs pass. WARN shows as SUSPECT; no check at all shows UNVERIFIED.

## Prompt bank

Hand-written guidance bank; the search sweeps whichever of these exist.
`selected-*.txt` are search outputs, not bank entries (and may be empty).

| File | Focus |
|------|-------|
| `aggressive-batch.txt` | replace N+1 / per-row lookups with set-based queries |
| `aggressive-bulkwrite.txt` | `executemany` / multi-row `INSERT` / `COPY`, same write set |
| `aggressive-sqlpushdown.txt` | push filter/aggregate/join into SQL, fewer columns |
| `aggressive-reuse.txt` | reuse connections, cursors, prepared statements; cache reads |
| `aggressive-criticalpath.txt` | optimize the hottest transaction first |
| `aggressive-plan-first.txt` | one-paragraph hot-path analysis, then all of the above |
| `aggressive-safe.txt` | all of the above plus the detailed equivalence rules (key mapping, type casts, write set) |
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
- `naive-llm-aggressive` is retired for TPC-C: there is one `naive-llm` arm, and
  the unguided prompt survives only as the search's `control` candidate. The
  Smallbank wrapper still exists (`run/smallbank/run_naive-llm-aggressive.sh`)
  and is deferred until Smallbank gets a correctness oracle.
- `results/tpcc/naive-llm` numbers recorded before the prompt switch are stale
  (unguided) and must be re-run with `./run/tpcc/run_naive-llm.sh`.
- The TPC-C prompt was tuned on TPC-C itself — label it that way, not as an
  out-of-the-box result.
