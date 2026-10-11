#!/bin/bash
# Py-DBridge rewrite driver.
# Usage: runExperiment1-Py-DBridge.sh <source_path> <source_file> <dbms> <benchmark>
# e.g.:  runExperiment1-Py-DBridge.sh workload/apps/tpcc drivers/postgresdriver.py postgres tpcc
#
# Safest TPCC workaround for SCIRPy KeywordParser NPE on `**conn_params` in
# workload/apps/tpcc/drivers/postgresdriver.py loadConfig (~lines 149/173):
#   - stages a SANITIZED copy of the source where Call-site `**name` unpackings
#     are expanded to explicit kwargs derived from same-function assignments,
#   - runs baselines/Py-DBridge/src/cli.py transform on the staging copy,
#   - writes the transformed output to the usual out/ location.
# SmallBank has no `**` unpacking and passes through unchanged.
# Never aborts the run: ambiguous sanitization or transform failure falls back
# to the untransformed file with a clear WARNING and exit 0.

source_path=$1
source_file=$2
dbms=$3
benchmark=$4

if [ -z "${source_path:-}" ] || [ -z "${source_file:-}" ] || [ -z "${dbms:-}" ] || [ -z "${benchmark:-}" ]; then
    echo "Usage: $0 <source_path> <source_file> <dbms> <benchmark>" >&2
    exit 2
fi

exp_path="$(cd "$(dirname "$0")/../../../.." && pwd)"

# Resolve source dir robustly (caller passes a repo-relative path; accept absolute too).
case "${source_path}" in
    /*) src_dir="${source_path}" ;;
    *) src_dir="${exp_path}/${source_path}" ;;
esac
source="${src_dir}/${source_file}"

# Rewrite
output_path="${exp_path}/out/app_layer/Py-DBridge-results/Rewrite/${dbms}/${benchmark}-Py-DBridge"
mkdir -p "${output_path}"
# source_file contains a subdir (e.g. drivers/postgresdriver.py); ensure parent exists.
mkdir -p "${output_path}/$(dirname "${source_file}")"

# Stage full app tree so the workload can run from the rewrite dir (as before).
if [ -d "${src_dir}" ]; then
    # NB: `/*` (not `/.`) preserves the original semantics: dotfiles
    # (e.g. a nested .git checkout under workload/apps/tpcc) are NOT copied.
    cp -r "${src_dir}/"* "${output_path}/" || echo "WARNING: app-tree copy failed (${src_dir} -> ${output_path}); continuing." >&2
else
    echo "WARNING: source dir not found: ${src_dir}; continuing to transform single file." >&2
fi

if [ ! -f "${source}" ]; then
    echo "WARNING: source file not found: ${source}; nothing to transform." >&2
    exit 0
fi

# Sanitize staging copy: expand Call-site `**name` via same-function assignments.
staging_dir="$(mktemp -d 2>/dev/null || echo "${output_path}/.staging-$$")"
mkdir -p "${staging_dir}"
staged="${staging_dir}/$(basename "${source_file}")"

if ! python3 - "${source}" "${staged}" <<'PYEOF'
import ast, sys
from collections import OrderedDict

src_path, dst_path = sys.argv[1], sys.argv[2]
src = open(src_path, encoding="utf-8").read()
try:
    tree = ast.parse(src)
except SyntaxError as e:
    print(f"WARNING: sanitize: cannot parse {src_path}: {e}; passing through unchanged.", file=sys.stderr)
    open(dst_path, "w", encoding="utf-8").write(src)
    sys.exit(2)

parent = {}
for p in ast.walk(tree):
    for c in ast.iter_child_nodes(p):
        parent[id(c)] = p

def enclosing_func(node):
    cur = node
    while id(cur) in parent:
        cur = parent[id(cur)]
        if isinstance(cur, (ast.FunctionDef, ast.AsyncFunctionDef)):
            return cur
    return None

# Per-function map: dictvar -> OrderedDict(key -> value AST node), from
#   conn_params = {"host": self.host, ...}            (Dict literal)
#   conn_params["password"] = self.password           (Subscript store)
func_maps = {}
for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        m = {}
        for sub in ast.walk(node):
            if isinstance(sub, ast.Assign) and len(sub.targets) == 1:
                t = sub.targets[0]
                if isinstance(t, ast.Name) and isinstance(sub.value, ast.Dict):
                    d = m.setdefault(t.id, OrderedDict())
                    for k, v in zip(sub.value.keys, sub.value.values):
                        if isinstance(k, ast.Constant) and isinstance(k.value, str) and k.value not in d:
                            d[k.value] = v
                elif (isinstance(t, ast.Subscript) and isinstance(t.value, ast.Name)
                        and isinstance(t.slice, ast.Constant) and isinstance(t.slice.value, str)):
                    d = m.setdefault(t.value.id, OrderedDict())
                    if t.slice.value not in d:
                        d[t.slice.value] = sub.value
        func_maps[id(node)] = m

# Collect ONLY Call-node `**identifier` sites (never FunctionDef **kwargs, never regex).
targets = []
ambiguous = []
for node in ast.walk(tree):
    if isinstance(node, ast.Call):
        for kw in node.keywords:
            if kw.arg is None:
                if not isinstance(kw.value, ast.Name):
                    ambiguous.append(f"line {kw.lineno}: non-identifier **{ast.unparse(kw.value)[:40]}")
                    continue
                f = enclosing_func(node)
                m = func_maps.get(id(f), {}) if f is not None else {}
                if f is None or kw.value.id not in m or not m[kw.value.id]:
                    ambiguous.append(f"line {kw.lineno}: **{kw.value.id} has no same-function dict assignment")
                    continue
                repl = ", ".join(f"{k}={ast.unparse(v)}" for k, v in m[kw.value.id].items())
                targets.append((kw.lineno, kw.col_offset, kw.end_lineno, kw.end_col_offset, kw.value.id, repl))

if ambiguous:
    print(f"WARNING: sanitize: ambiguous ** expansion ({'; '.join(ambiguous)}); passing through unchanged.", file=sys.stderr)
    open(dst_path, "w", encoding="utf-8").write(src)
    sys.exit(2)

if not targets:
    open(dst_path, "w", encoding="utf-8").write(src)
    sys.exit(0)

lines = src.splitlines(keepends=True)
def off(l, c):
    return sum(len(x) for x in lines[:l - 1]) + c
for sl, sc, el, ec, name, repl in sorted(targets, key=lambda e: (e[0], e[1]), reverse=True):
    src = src[:off(sl, sc)] + repl + src[off(el, ec):]

# Safety: sanitized file must still parse and contain no Call-site `**`.
tree2 = ast.parse(src)
left = sum(1 for n in ast.walk(tree2) if isinstance(n, ast.Call) for k in n.keywords if k.arg is None)
if left:
    print(f"WARNING: sanitize: {left} Call-site ** remains after expansion; passing through unchanged.", file=sys.stderr)
    open(dst_path, "w", encoding="utf-8").write(open(src_path, encoding="utf-8").read())
    sys.exit(2)

open(dst_path, "w", encoding="utf-8").write(src)
names = sorted({t[4] for t in targets})
print(f"sanitize: expanded Call-site **{{{', '.join(names)}}} at {len(targets)} site(s) -> {dst_path}")
PYEOF
then
    # python exited nonzero (syntax/ambiguous case already wrote passthrough copy w/ WARNING).
    if [ ! -f "${staged}" ]; then
        cp "${source}" "${staged}" || true
    fi
    echo "WARNING: sanitization fell back to untransformed file (see above)." >&2
fi

cd "${exp_path}/baselines/Py-DBridge"
if [ -f venv/bin/activate ]; then
    # shellcheck disable=SC1091
    source venv/bin/activate || echo "WARNING: venv activation failed; continuing with system python." >&2
else
    echo "WARNING: venv not found at baselines/Py-DBridge/venv; using current python." >&2
fi

output_file="${output_path}/${source_file}"
SCRIPT="python -m src.cli ${staged} -o ${output_file} --db ${dbms}"

echo "${SCRIPT}"
if $SCRIPT; then
    :
else
    status=$?
    echo "WARNING: Py-DBridge transform failed (exit ${status}); falling back to untransformed file so measurements can still run." >&2
    cp "${staged}" "${output_file}" || cp "${source}" "${output_file}" || true
    rm -rf "${staging_dir}" || true
    exit 0
fi

rm -rf "${staging_dir}" || true
exit 0
