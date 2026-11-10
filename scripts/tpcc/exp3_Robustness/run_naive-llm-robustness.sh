#!/usr/bin/env bash
# Naive-LLM TPC-C rewrite robustness harness.
#
# Re-runs the rewrite N times from scratch (no reuse, no caching) and verifies
# every resulting tree with the generic verify arm. One extra run re-verifies
# the already-measured artifact so the reproducibility numbers sit next to the
# measurement that was actually reported.
#
# Usage: run_naive-llm-robustness.sh [runs=10] [dbms=postgres] [model]
#   model defaults to $MODEL, then gemini-3.5-flash-lite.
#
# Scratch (rewrites, smoke CSVs, per-run verify JSON) lives under
# out/app_layer/robustness/; the report dir only receives latest.json.
#
# Summary-only mode (no DB, used for tests and re-aggregation after an
# interrupted sweep): ROBUSTNESS_AGGREGATE_ONLY=<timestamp dir>.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

RUNS_ARG="${1:-10}"
DBMS_ARG="${2:-postgres}"
MODEL_ARG="${3:-${MODEL:-gemini-3.5-flash-lite}}"
REPORT_DIR="${ROBUSTNESS_REPORT_DIR:-results/tpcc/robustness/naive-llm}"

# The one place arm-specific paths live. Add py-dbridge/aco/adco here.
resolve_arm() {
    ARM="$1"
    case "${ARM}" in
        naive-llm)
            ARM_SOURCE="workload/apps/tpcc"
            ARM_PROMPT="baselines/NaiveLLM/prompts/selected-tpcc.txt"
            ARM_TREE="tpcc-NaiveLLM"
            ARM_DRIVER="drivers/postgresdriver.py"
            ARM_ENTRY="tpcc.py"
            ARM_REWRITE_CMD="scripts/common/app_layer/exp1_Baselines/runExperiment1-NaiveLLM.sh"
            ;;
        *)
            echo "ERROR: unknown robustness arm '${ARM}' (registry: naive-llm)." >&2
            exit 2
            ;;
    esac
}
resolve_arm "${ARM:-naive-llm}"

if ! [[ "${RUNS_ARG}" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: runs must be a positive integer (got '${RUNS_ARG}')." >&2
    exit 2
fi

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# sha256_tree <file>...: one hash over the concatenated contents, so a rewrite
# is identified by driver + workload entry together.
sha256_tree() {
    local f
    for f in "$@"; do
        [ -f "${f}" ] || return 1
    done
    if command -v sha256sum >/dev/null 2>&1; then
        cat "$@" | sha256sum | awk '{print $1}'
    else
        cat "$@" | shasum -a 256 | awk '{print $1}'
    fi
}

# Write summary.json + latest.json + summary.md from <ts-dir>/config.tsv and
# <ts-dir>/runs.tsv. Prints the markdown table (single implementation, shared
# by the live run and the aggregate-only mode).
write_summary() {
    python3 - "$1" "$2" <<'PY'
import json, math, os, shutil, sys

ts_dir, report_dir = sys.argv[1], sys.argv[2]
assert os.path.isdir(ts_dir), f"no such run dir: {ts_dir}"


def read_kv(path):
    d = {}
    with open(path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            k, _, v = line.partition("\t")
            d[k] = v
    return d


def as_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def check_failures(doc):
    out = []
    for key, val in (doc.get("checks") or {}).items():
        st = (val or {}).get("status")
        if st not in ("FAIL", "WARN"):
            continue
        issues = (val or {}).get("issues") or []
        reason = issues[0] if issues else ""
        if not isinstance(reason, str):
            reason = json.dumps(reason)
        out.append(f"{key}: {reason[:160]}" if reason else key)
    return out


def wilson(k, n, z=1.959963984540054):
    if n <= 0:
        return [0.0, 1.0]
    p = k / n
    denom = 1 + z * z / n
    centre = p + z * z / (2 * n)
    margin = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return [max(0.0, (centre - margin) / denom), min(1.0, (centre + margin) / denom)]


cfg = read_kv(os.path.join(ts_dir, "config.tsv"))
runs_requested = as_int(cfg.get("runs_requested")) or 0

runs = []
records = os.path.join(ts_dir, "runs.tsv")
if os.path.isfile(records):
    with open(records) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = (line.split("\t") + [""] * 10)[:10]
            run, kind, sha, rw, changed, restored, vstat, failed, vjson, _code = parts

            verify_status = vstat or "UNVERIFIED"
            failed_checks = [c for c in failed.split("; ") if c]
            # The verify JSON is the authority: a nonzero verify exit only means
            # "not PASS", the checks object says which invariant broke.
            if vjson:
                if os.path.isfile(vjson):
                    with open(vjson) as f:
                        doc = json.load(f)
                    verify_status = doc.get("status") or "UNVERIFIED"
                    failed_checks = check_failures(doc)
                else:
                    verify_status = "UNVERIFIED"
                    failed_checks = ["verify output missing"]

            runs.append({
                "run": as_int(run) or 0,
                "kind": kind or "fresh",
                "sha256": sha or None,
                "rewrite_status": rw or "missing",
                "changed": as_int(changed),
                "restored": as_int(restored),
                "verify_status": verify_status,
                "failed_checks": failed_checks,
                "verify_json": vjson or None,
            })

runs.sort(key=lambda r: r["run"])
fresh = [r for r in runs if r["kind"] == "fresh"]

counts = {
    "pass": sum(1 for r in fresh if r["verify_status"] == "PASS"),
    "fail": sum(1 for r in fresh if r["verify_status"] == "FAIL"),
    "warn": sum(1 for r in fresh if r["verify_status"] == "WARN"),
    "unverified": sum(1 for r in fresh if r["verify_status"] == "UNVERIFIED"),
}

# Overall verdict is over the fresh sweeps; the measured artifact is reported
# separately in measured_artifact so a stale measured tree cannot make a clean
# 10-run sweep read as "FAIL 0/10".
statuses = [r["verify_status"] for r in fresh]
if "FAIL" in statuses:
    status = "FAIL"
elif "WARN" in statuses:
    status = "WARN"
elif "PASS" in statuses:
    status = "PASS"
else:
    status = "UNVERIFIED"

# Headline rate is over the requested fresh runs (counts above), so a crashed
# or skipped run is never counted as correct.
n = runs_requested
incorrect_rate = round(counts["fail"] / n, 4) if n else 0.0
ci = [round(x, 4) for x in wilson(counts["fail"], n)]

hashes = [r["sha256"] for r in fresh if r["sha256"]]
distinct_outputs = len(set(hashes))

measured_row = next((r for r in runs if r["kind"] == "measured"), None)
measured_artifact = None
if measured_row is not None:
    measured_artifact = {
        "status": measured_row["verify_status"],
        "verify_json": measured_row["verify_json"],
    }

summary = {
    "arm": "naive-llm",
    "workload": "tpcc",
    "timestamp": cfg.get("timestamp", ""),
    "model": cfg.get("model", ""),
    "prompt_file": cfg.get("prompt_file", ""),
    "prompt_sha256": cfg.get("prompt_sha256", ""),
    "runs_requested": runs_requested,
    "runs_completed": len(fresh),
    "counts": counts,
    "status": status,
    "incorrect_rate": incorrect_rate,
    "wilson_ci95": ci,
    "distinct_outputs": distinct_outputs,
    "measured_artifact": measured_artifact,
    "runs": runs,
}

out_json = os.path.join(ts_dir, "summary.json")
with open(out_json, "w") as f:
    json.dump(summary, f, indent=2)
    f.write("\n")

os.makedirs(report_dir, exist_ok=True)
shutil.copyfile(out_json, os.path.join(report_dir, "latest.json"))


def cell(v):
    return "-" if v is None else str(v)


rows = [
    "| run | kind | verify | rewrite | changed | restored | sha256 | failed checks |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
]
for r in runs:
    sha = (r["sha256"] or "-")[:12]
    fails = "; ".join(r["failed_checks"]) or "-"
    rows.append(
        f"| {r['run']} | {r['kind']} | {r['verify_status']} | {r['rewrite_status']} | "
        f"{cell(r['changed'])} | {cell(r['restored'])} | {sha} | {fails} |"
    )

headline = (
    f"status **{status}**; fresh runs {counts['pass']} PASS / {counts['fail']} FAIL / "
    f"{counts['warn']} WARN / {counts['unverified']} UNVERIFIED of {runs_requested} "
    f"(incorrect rate {incorrect_rate:.2%}, Wilson 95% CI {ci[0]:.2%}-{ci[1]:.2%}); "
    f"distinct outputs {distinct_outputs}"
)

md = "\n".join([
    f"# Naive-LLM TPC-C robustness — {summary['timestamp']}",
    "",
    f"- model: `{summary['model']}`",
    f"- prompt: `{summary['prompt_file']}` (sha256 `{summary['prompt_sha256']}`)",
    f"- measured artifact: {measured_artifact if measured_artifact else 'none'}",
    "",
    *rows,
    "",
    headline,
    "",
])
with open(os.path.join(ts_dir, "summary.md"), "w") as f:
    f.write(md)

print("\n".join(rows))
print()
print(headline)
PY
}

if [ -n "${ROBUSTNESS_AGGREGATE_ONLY:-}" ]; then
    write_summary "${ROBUSTNESS_AGGREGATE_ONLY}" "${REPORT_DIR}"
    echo
    echo "summary: ${ROBUSTNESS_AGGREGATE_ONLY}/summary.json"
    echo "latest:  ${REPORT_DIR}/latest.json"
    exit 0
fi

# Single-writer: the rewrites' smoke runs and every verification write to the DB.
bench_lock "${ROOT}"

PROMPT_FILE_ABS="${ROOT}/${ARM_PROMPT}"
if [ ! -f "${PROMPT_FILE_ABS}" ]; then
    echo "ERROR: missing selected prompt ${ARM_PROMPT}" >&2
    echo "Run ./run/tpcc/run_prompt_search.sh first (an empty file is valid)." >&2
    exit 1
fi
PROMPT_SHA="$(sha256_of "${PROMPT_FILE_ABS}")"

if [ ! -f "${ROOT}/baselines/NaiveLLM/venv/bin/activate" ]; then
    echo "ERROR: NaiveLLM venv missing at baselines/NaiveLLM/venv." >&2
    echo "Setup: cd baselines/NaiveLLM && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt" >&2
    exit 1
fi
if [ ! -f "${ROOT}/workload/apps/tpcc/venv/bin/activate" ]; then
    echo "ERROR: TPC-C workload venv missing at workload/apps/tpcc/venv." >&2
    echo "Setup: cd workload/apps/tpcc && python3 -m venv venv && source venv/bin/activate && pip install -e ." >&2
    exit 1
fi

# bench_ensure_seed loads the seed via BENCH_CMDRUNTPCC (bench_lib default points
# at a nonexistent scripts/_lib/tpcc.sh); point it at the canonical DB runner.
export BENCH_CMDRUNTPCC="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"

echo "----------------->> Seed tpcc (reuse snapshot) <<-----------------"
bench_ensure_seed "tpcc" "tpcc_seed"
bench_assert_rows "tpcc" "warehouse" "${TPCC_WAREHOUSES}"

STAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
OUT_TS="out/app_layer/robustness/${ARM}/${STAMP}"
RECORDS="${OUT_TS}/runs.tsv"
mkdir -p "${OUT_TS}"
: >"${RECORDS}"
{
    printf 'arm\t%s\n' "${ARM}"
    printf 'workload\ttpcc\n'
    printf 'timestamp\t%s\n' "${STAMP}"
    printf 'model\t%s\n' "${MODEL_ARG}"
    printf 'prompt_file\t%s\n' "${ARM_PROMPT}"
    printf 'prompt_sha256\t%s\n' "${PROMPT_SHA}"
    printf 'runs_requested\t%s\n' "${RUNS_ARG}"
    printf 'dbms\t%s\n' "${DBMS_ARG}"
} >"${OUT_TS}/config.tsv"

# run | kind | sha256 | rewrite_status | changed | restored | verify_status |
# failed_checks | verify_json | driver_exit
record_row() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" >>"${RECORDS}"
}

# Verify one rewritten tree through the generic arm. A nonzero exit is not an
# error here: the verdict is the JSON's status/checks object.
verify_tree() {
    local arm="$1" rewrite_root="$2" out_rel="$3"
    mkdir -p "${ROOT}/${out_rel}/smoke/benchmarks"
    BENCH_LOCK_HELD=1 REVERIFY=1 \
        VERIFY_REWRITE_ROOT="${rewrite_root}" \
        VERIFY_CSV="${ROOT}/${out_rel}/smoke/${arm}.csv" \
        BENCH_RESULTS_DIR="${ROOT}/${out_rel}/smoke/benchmarks" \
        VERIFY_OUTPUT="${ROOT}/${out_rel}/verify.json" \
        bash "./scripts/tpcc/exp2_Correctness/run_verify.sh" "${DBMS_ARG}" "${arm}" \
        >"${ROOT}/${out_rel}/verify.log" 2>&1 || true
}

echo "=================>> Run 0: re-verify the measured artifact <<================="
MEASURED_ROOT="out/app_layer/NaiveLLM-results"
MEASURED_TREE="${MEASURED_ROOT}/Rewrite/${DBMS_ARG}/${ARM_TREE}"
if [ -d "${MEASURED_TREE}" ]; then
    verify_tree "naive-llm-measured" "${MEASURED_ROOT}" "${OUT_TS}/measured"
    sha="$(sha256_tree "${MEASURED_TREE}/${ARM_DRIVER}" "${MEASURED_TREE}/${ARM_ENTRY}")" || sha=""
    record_row 0 measured "${sha}" ok "" "" "" "" "${OUT_TS}/measured/verify.json" 0
    echo "measured artifact verified: ${MEASURED_TREE}"
else
    echo "measured artifact missing: ${MEASURED_TREE} (run/tpcc/run_naive-llm.sh first); recorded as null."
fi

for ((i = 1; i <= RUNS_ARG; i++)); do
    idx="$(printf '%02d' "${i}")"
    rel_run="${OUT_TS}/r${idx}"
    abs_run="${ROOT}/${rel_run}"
    tree_rel="${rel_run}/Rewrite/${DBMS_ARG}/${ARM_TREE}"
    driver_rel="${tree_rel}/${ARM_DRIVER}"
    mkdir -p "${abs_run}/smoke/benchmarks"

    echo "=================>> Run ${i}/${RUNS_ARG}: fresh rewrite <<================="
    rc=0
    NAIVE_REWRITE_ROOT="${rel_run}" PROMPT_FILE="${PROMPT_FILE_ABS}" \
        bash "./${ARM_REWRITE_CMD}" "${ARM_SOURCE}" "${DBMS_ARG}" tpcc "${MODEL_ARG}" \
        >"${abs_run}/rewrite.log" 2>&1 || rc=$?

    changed=""
    restored=""
    parsed="$(sed -nE 's/.*files changed: ([0-9]+), restored: ([0-9]+).*/\1 \2/p' "${abs_run}/rewrite.log" | tail -1 || true)"
    if [ -n "${parsed}" ]; then
        read -r changed restored <<<"${parsed}"
    fi

    if [ -f "${ROOT}/${driver_rel}" ]; then
        sha="$(sha256_tree "${ROOT}/${driver_rel}" "${ROOT}/${tree_rel}/${ARM_ENTRY}")" || sha=""
        rw_status="ok"
        [ "${rc}" -ne 0 ] && rw_status="failed"
        verify_tree "${ARM}-r${idx}" "${rel_run}" "${rel_run}"
        record_row "${i}" fresh "${sha}" "${rw_status}" "${changed}" "${restored}" "" "" "${rel_run}/verify.json" "${rc}"
        echo "run ${i}: rewrite=${rw_status} (exit ${rc}), verify JSON ${rel_run}/verify.json"
    else
        echo "WARNING: run ${i}: no rewrite tree at ${tree_rel} (driver exit ${rc}); UNVERIFIED." >&2
        record_row "${i}" fresh "" missing "${changed}" "${restored}" "UNVERIFIED" "no rewrite tree" "" "${rc}"
    fi
done

echo "=================>> Summary <<================="
write_summary "${OUT_TS}" "${REPORT_DIR}"
echo
echo "summary: ${OUT_TS}/summary.json"
echo "latest:  ${REPORT_DIR}/latest.json"
echo "report:  ${OUT_TS}/summary.md"
echo "logs:    ${OUT_TS}/r*/rewrite.log"
