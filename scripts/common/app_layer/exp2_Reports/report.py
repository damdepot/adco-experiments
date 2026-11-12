#!/usr/bin/env python3
import argparse
import os
import glob
import csv
import re
import datetime
from collections import defaultdict
try:
    from tpcc_correctness import (correctness_cell, load_correctness_statuses,
                                  status_label, verify_warning_lines)
except ImportError:
    # Checker lives in scripts/tpcc/exp2_Correctness (sibling of the tpcc
    # workload drivers); fall back to loading it from there.
    try:
        import sys
        sys.path.insert(0, os.path.normpath(os.path.join(
            os.path.dirname(os.path.abspath(__file__)),
            '..', '..', '..', 'tpcc', 'exp2_Correctness')))
        from tpcc_correctness import (correctness_cell, load_correctness_statuses,
                                      status_label, verify_warning_lines)
    except ImportError:
        correctness_cell = None
        load_correctness_statuses = None
        status_label = None
        verify_warning_lines = None

def calculate_median(values):
    if not values:
        return None
    sorted_values = sorted(values)
    n = len(sorted_values)
    if n % 2 == 1:
        return sorted_values[n // 2]
    else:
        return (sorted_values[n // 2 - 1] + sorted_values[n // 2]) / 2.0

def calculate_mean(values):
    if not values:
        return None
    return sum(values) / len(values)

def geometric_mean(values):
    valid = [v for v in values if v is not None and v > 0]
    if not valid:
        return 0.0
    product = 1.0
    for v in valid:
        product *= v
    return product ** (1.0 / len(valid))

def format_mtime(ts):
    """Format an mtime epoch as 'YYYY-MM-DD HH:MM:SS (epoch)' in local time."""
    try:
        dt = datetime.datetime.fromtimestamp(ts)
        return f"{dt.strftime('%Y-%m-%d %H:%M:%S')} ({int(ts)})"
    except (OSError, OverflowError, ValueError):
        return f"epoch {ts}"


def describe_sources(sources, systems):
    """Build printable source/warning lines from the provenance dict.

    Returns (source_lines, warning_lines). Pure formatting, no I/O.
    """
    source_lines = []
    warning_lines = []
    all_mtimes = []
    for sys in systems:
        info = (sources or {}).get(sys, {})
        bench_dir = info.get('dir', '')
        exists = info.get('exists', False)
        files = info.get('files', [])
        if not exists:
            warning_lines.append(
                f"WARNING: results dir missing for arm '{sys}': {bench_dir} "
                f"-- column will show N/A (stale/other-run data is NOT substituted)."
            )
            source_lines.append(f"  - {sys}: MISSING ({bench_dir})")
        elif not files:
            warning_lines.append(
                f"WARNING: no result files found for arm '{sys}' in {bench_dir} "
                f"-- column will show N/A."
            )
            source_lines.append(f"  - {sys}: no matching files in {bench_dir}")
        else:
            for path, mtime in files:
                source_lines.append(f"  - {sys}: {path} (mtime: {format_mtime(mtime)})")
                all_mtimes.append(mtime)
    if len(set(int(m) for m in all_mtimes)) > 1:
        span = int(max(all_mtimes)) - int(min(all_mtimes))
        warning_lines.append(
            f"WARNING: arms' source files have differing mtimes (span {span}s) -- "
            f"they may come from different runs/scales. Compared as-is; "
            f"verify the source list above before trusting speedups."
        )
    return source_lines, warning_lines


def _arm_status(info):
    """Status of a correctness struct (or bare string), WARN shown as SUSPECT."""
    if status_label:
        return status_label(info)
    st = str((info.get('status') if isinstance(info, dict) else info) or 'UNVERIFIED').upper()
    return 'SUSPECT' if st == 'WARN' else st


def correctness_rows(systems, display_names, verify_statuses):
    """Markdown rows for the Correctness table (one per arm).

    Fallback arms report a single run; arms with no result at all stay
    UNVERIFIED rather than being silently dropped.
    """
    rows = []
    for sys in systems:
        info = (verify_statuses or {}).get(sys)
        name = display_names.get(sys, sys.capitalize())
        if not info:
            rows.append(f"| {name} | - | - | - | - | - | - | - | UNVERIFIED |")
            continue
        st = _arm_status(info)
        counts = (info.get('counts') or {}) if isinstance(info, dict) else {}
        if isinstance(info, dict) and info.get('fallback'):
            # Single-run fallback: one run, bucketed by its verdict. A missing
            # verify file is UNVERIFIED, i.e. no run at all.
            if st == 'UNVERIFIED':
                runs_str = '-'
                counts = {}
            else:
                runs_str = "1 (single run)"
                counts = {'pass': int(st == 'PASS'), 'fail': int(st == 'FAIL'),
                          'warn': int(st == 'SUSPECT'), 'unverified': 0}
        else:
            runs_str = str(info.get('runs') or '-')
            wh = info.get('verify_warehouses') if isinstance(info, dict) else None
            if runs_str != '-' and wh is not None:
                runs_str = f"{runs_str} ({wh}wh)"
        rows.append(
            f"| {name} | {runs_str} | {int(counts.get('pass') or 0)} | "
            f"{int(counts.get('fail') or 0)} | {int(counts.get('warn') or 0)} | "
            f"{int(counts.get('unverified') or 0)} | {st} |")
    return rows


def correctness_value(txn, info, has_data):
    """Correctness cell for a rate/time table row: verdict on TOTAL only,
    '-' on transaction rows, 'N/A' when the arm has no performance data."""
    if not has_data:
        return "N/A"
    if txn.upper() != 'TOTAL':
        return "-"
    if not correctness_cell:
        return _arm_status(info)
    return correctness_cell(info)


def discover_workloads(results_dir, dbms):
    """Discover available workloads in results_dir for the given dbms."""
    workloads = set()
    systems = ['baseline', 'adco', 'aco', 'py-dbridge', 'naive-llm', 'naive-llm-agenttune', 'agenttune-naive-llm']
    for workload in ['smallbank', 'tpcc']:
        for sys in systems:
            bench_dir = os.path.join(results_dir, workload, sys, 'benchmarks')
            if not os.path.exists(bench_dir):
                continue
            if glob.glob(os.path.join(bench_dir, f"{sys}.csv")) or glob.glob(os.path.join(bench_dir, f"{sys}_r*.csv")):
                workloads.add(workload)
                continue
            for fname in os.listdir(bench_dir):
                if fname.startswith('.'):
                    continue
                # Pattern: runExperiment1-{workload}-{dbms}*
                match = re.match(r'runExperiment\d+-([a-zA-Z0-9_]+)-' + re.escape(dbms), fname, re.IGNORECASE)
                if match:
                    workloads.add(match.group(1).lower())
                elif workload in fname.lower():
                    workloads.add(workload)
    if not workloads:
        for default_wl in ['smallbank', 'tpcc']:
            for sys in systems:
                pattern = os.path.join(results_dir, default_wl, sys, 'benchmarks', f"*{default_wl}*")
                if glob.glob(pattern):
                    workloads.add(default_wl)
                    break
    if not workloads:
        workloads = {'smallbank', 'tpcc'}
    return sorted(list(workloads))

def parse_workload_data(results_dir, workload, dbms, systems):
    """
    Parse benchmark files for a specific workload and dbms across all systems.
    Returns:
        data: dict[sys][transaction] -> { 'executed': list, 'execution_time': list, 'transaction_rate': list }
        raw_records: list of [sys, workload, dbms, file_name, transaction, executed, execution_time, transaction_rate]
        sources: dict[sys] -> { 'dir': bench_dir, 'exists': bool, 'files': [(filepath, mtime), ...] }
    """
    data = {sys: defaultdict(lambda: {'executed': [], 'execution_time': [], 'transaction_rate': []}) for sys in systems}
    raw_records = []
    sources = {}

    for sys in systems:
        bench_dir = os.path.join(results_dir, workload, sys, 'benchmarks')
        exists = os.path.exists(bench_dir)
        if not exists:
            sources[sys] = {'dir': bench_dir, 'exists': False, 'files': []}
            continue

        pattern1 = os.path.join(bench_dir, f"runExperiment*-{workload}-{dbms}*")
        pattern2 = os.path.join(bench_dir, f"*{workload}*{dbms}*")
        fixed = sorted(list(set(glob.glob(os.path.join(bench_dir, f"{sys}.csv")) + glob.glob(os.path.join(bench_dir, f"{sys}_r*.csv")))))
        if fixed:
            matched_files = fixed
        else:
            matched_files = sorted(list(set(glob.glob(pattern1) + glob.glob(pattern2))))

        file_entries = []
        for filepath in matched_files:
            try:
                file_entries.append((filepath, os.path.getmtime(filepath)))
            except OSError:
                continue
        sources[sys] = {'dir': bench_dir, 'exists': True, 'files': file_entries}
        
        for filepath in matched_files:
            fname = os.path.basename(filepath)
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    reader = csv.reader(f)
                    header_skipped = False
                    for row in reader:
                        if not row or len(row) < 4:
                            continue
                        if not header_skipped and row[0].strip().lower() == 'transaction':
                            header_skipped = True
                            continue
                        
                        txn_name = row[0].strip()
                        try:
                            executed = float(row[1].strip())
                            exec_time = float(row[2].strip())
                            txn_rate = float(row[3].strip())
                        except ValueError:
                            continue
                        
                        data[sys][txn_name]['executed'].append(executed)
                        data[sys][txn_name]['execution_time'].append(exec_time)
                        data[sys][txn_name]['transaction_rate'].append(txn_rate)
                        
                        raw_records.append([sys, workload, dbms, fname, txn_name, executed, exec_time, txn_rate])
            except Exception as e:
                print(f"Error reading {filepath}: {e}")

    return data, raw_records, sources

def generate_workload_report(data, raw_records, workload, dbms, systems, system_display_names, output_dir, sources=None, title_prefix="Application Layer Performance Comparison", quiet=False, verify_statuses=None):
    # Collect all transaction names preserving order if possible (placing TOTAL last)
    all_txns = []
    seen = set()
    for sys in systems:
        for txn in data[sys].keys():
            if txn not in seen and txn.upper() != 'TOTAL':
                seen.add(txn)
                all_txns.append(txn)
    all_txns.sort()
    if any('TOTAL' in [k.upper() for k in data[sys].keys()] for sys in systems):
        all_txns.append('TOTAL')
    
    # Calculate stats per transaction using median
    stats = {sys: {} for sys in systems}
    for sys in systems:
        for txn in all_txns:
            rate_vals = data[sys][txn]['transaction_rate']
            time_vals = data[sys][txn]['execution_time']
            exec_vals = data[sys][txn]['executed']
            stats[sys][txn] = {
                'rate': calculate_median(rate_vals),
                'time': calculate_median(time_vals),
                'executed': calculate_median(exec_vals)
            }
            
    base_sys = systems[0]
    other_systems = systems[1:]
    speedups = {sys: [] for sys in other_systems}
    # An arm with no parsed benchmark numbers gets N/A (not a verdict it never earned).
    has_data = {sys: any(stats[sys].get(t, {}).get('rate') is not None for t in all_txns)
                for sys in systems}
    
    # Format terminal output
    lines = []
    title = f"{title_prefix}: {workload.upper()} on {dbms}"
    lines.append(title)
    lines.append("=" * len(title))
    lines.append("")

    # Provenance: source file path (and mtime) per arm column.
    source_lines, warning_lines = describe_sources(sources, systems)
    if source_lines:
        lines.append("Data sources (one line per source file actually aggregated):")
        lines.extend(source_lines)
        lines.append("")
    for w in warning_lines:
        lines.append(w)
    if warning_lines:
        lines.append("")
    if verify_statuses and verify_warning_lines:
        for w in verify_warning_lines(verify_statuses, system_display_names):
            lines.append(w)
        if any(_arm_status(s) != "PASS" for s in verify_statuses.values()):
            lines.append("")
    
    base_display = system_display_names.get(base_sys, base_sys.capitalize())
    for sys in other_systems:
        for txn in all_txns:
            if txn.upper() == 'TOTAL':
                continue
            b = stats[base_sys].get(txn, {}).get('rate')
            r = stats[sys].get(txn, {}).get('rate')
            if b and r:
                speedups[sys].append(r / b)

    header = f"{'Arm':<20}"
    for txn in all_txns:
        header += f"| {txn[:14]:<16}"
    header += f"| {'Geo Mean':<12}"
    lines.append(header)
    lines.append("-" * len(header))

    for sys in [base_sys] + list(other_systems):
        name = system_display_names.get(sys, sys.capitalize())
        line = f"{name[:19]:<20}"
        for txn in all_txns:
            rate = stats[sys].get(txn, {}).get('rate')
            base_rate = stats[base_sys].get(txn, {}).get('rate')
            if rate is None:
                cell = "N/A"
            elif sys == base_sys or not base_rate or base_rate <= 0:
                cell = f"{rate:.2f}"
            else:
                cell = f"{rate:.2f} ({rate / base_rate:.2f}x)"
            line += f"| {cell:<16}"
        if sys == base_sys:
            g_str = "-"
        else:
            g_spd = geometric_mean(speedups[sys])
            g_str = f"{g_spd:.2f}x" if g_spd > 0 else "N/A"
        line += f"| {g_str:<12}"
        lines.append(line)
    lines.append("")
    
    report_text = "\n".join(lines)
    if quiet:
        for w in warning_lines:
            print(w)
    else:
        print(report_text)
    
    # Markdown Report Generation
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        md_path = os.path.join(output_dir, f"performance_comparison_{workload}_{dbms}.md")
        
        md_lines = []
        md_lines.append(f"# {title_prefix}: {workload.upper()} on {dbms}\n")

        # Provenance: source file path (and mtime) per arm column.
        md_lines.append("## Data sources\n")
        for sl in source_lines:
            md_lines.append(f"- {sl.strip().lstrip('- ')}")
        for w in warning_lines:
            md_lines.append(f"\n> {w}")
        md_lines.append("")
        if verify_statuses:
            md_lines.append("## Correctness\n")
            md_lines.append("| Arm | Runs | PASS | FAIL | SUSPECT | UNVERIFIED | Status |")
            md_lines.append("| :--- | :--- | :--- | :--- | :--- | :--- | :--- |")
            md_lines.extend(correctness_rows(systems, system_display_names, verify_statuses))
            md_lines.append("")
            if verify_warning_lines:
                warnings = verify_warning_lines(verify_statuses, system_display_names)
                if warnings:
                    for warning in warnings:
                        md_lines.append(f"> {warning}")
                    md_lines.append("")

        # Table 1: Throughput (Transaction Rate), arms as rows.
        md_lines.append("## Transaction Rate / Throughput (txn/s)\n")
        md_lines.append("| Arm | " + " | ".join(all_txns) + " | Geo Mean | Correctness |")
        md_lines.append("| :--- | " + " | ".join(":---" for _ in all_txns) + " | :--- | :--- |")
        for sys in [base_sys] + list(other_systems):
            name = system_display_names.get(sys, sys.capitalize())
            cells = []
            for txn in all_txns:
                rate = stats[sys].get(txn, {}).get('rate')
                base_rate = stats[base_sys].get(txn, {}).get('rate')
                if rate is None:
                    cell = "N/A"
                elif sys == base_sys or not base_rate or base_rate <= 0:
                    cell = f"{rate:.2f}"
                else:
                    cell = f"{rate:.2f} ({rate / base_rate:.2f}x)"
                if txn.upper() == 'TOTAL' and cell != "N/A":
                    cell = f"**{cell}**"
                cells.append(cell)
            if sys == base_sys:
                g_str = "-"
            else:
                g = geometric_mean(speedups[sys])
                g_str = f"{g:.2f}x" if g > 0 else "N/A"
            corr = correctness_value('TOTAL', (verify_statuses or {}).get(sys),
                                     has_data.get(sys, False))
            md_lines.append(f"| {name} | " + " | ".join(cells) + f" | {g_str} | {corr} |")
        md_lines.append("\n")

        # Table 2: Execution Time (ms), arms as rows.
        md_lines.append("## Execution Time (ms)\n")
        latencies = defaultdict(list)
        for sys in other_systems:
            for txn in all_txns:
                if txn.upper() == 'TOTAL':
                    continue
                b = stats[base_sys].get(txn, {}).get('time')
                v = stats[sys].get(txn, {}).get('time')
                if b and v and v > 0:
                    latencies[sys].append(b / v)
        md_lines.append("| Arm | " + " | ".join(all_txns) + " | Geo Mean | Correctness |")
        md_lines.append("| :--- | " + " | ".join(":---" for _ in all_txns) + " | :--- | :--- |")
        for sys in [base_sys] + list(other_systems):
            name = system_display_names.get(sys, sys.capitalize())
            cells = []
            for txn in all_txns:
                value = stats[sys].get(txn, {}).get('time')
                base_value = stats[base_sys].get(txn, {}).get('time')
                if value is None:
                    cell = "N/A"
                elif sys == base_sys or not base_value or value <= 0:
                    cell = f"{value:.2f}"
                else:
                    cell = f"{value:.2f} ({base_value / value:.2f}x)"
                if txn.upper() == 'TOTAL' and cell != "N/A":
                    cell = f"**{cell}**"
                cells.append(cell)
            if sys == base_sys:
                g_str = "-"
            else:
                g = geometric_mean(latencies[sys])
                g_str = f"{g:.2f}x" if g > 0 else "N/A"
            corr = correctness_value('TOTAL', (verify_statuses or {}).get(sys),
                                     has_data.get(sys, False))
            md_lines.append(f"| {name} | " + " | ".join(cells) + f" | {g_str} | {corr} |")
        md_lines.append("\n")

        # Detailed Raw Data Summary Table
        md_lines.append("## Transaction Breakdown Summary\n")
        md_lines.append("| System | Transaction | Executed | Execution Time (ms) | Transaction Rate (txn/s) |")
        md_lines.append("| :--- | :--- | :---: | :---: | :---: |")
        for sys in systems:
            sys_name = system_display_names.get(sys, sys.capitalize())
            for txn in all_txns:
                st = stats[sys].get(txn, {})
                exec_val = f"{st.get('executed'):.0f}" if st.get('executed') is not None else "N/A"
                time_val = f"{st.get('time'):.2f}" if st.get('time') is not None else "N/A"
                rate_val = f"{st.get('rate'):.2f}" if st.get('rate') is not None else "N/A"
                md_lines.append(f"| {sys_name} | {txn} | {exec_val} | {time_val} | {rate_val} |")
        md_lines.append("")
        
        with open(md_path, 'w', encoding='utf-8') as f:
            f.write("\n".join(md_lines))
        print(f"Report saved to: {md_path}")
        
        # Save Combined CSV
        csv_path = os.path.join(output_dir, f"raw_data_combined_{workload}_{dbms}.csv")
        with open(csv_path, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['system', 'workload', 'dbms', 'file_name', 'transaction', 'executed', 'execution_time', 'transaction_rate'])
            writer.writerows(raw_records)
        print(f"Raw data saved to: {csv_path}\n")

def main():
    parser = argparse.ArgumentParser(description='Parse application layer benchmark results and output performance comparisons.')
    parser.add_argument('--workload', default='all', help="Workload name ('smallbank', 'tpcc', or 'all')")
    parser.add_argument('--dbms', default='postgres', help='DBMS name (e.g. postgres, PostgreSQL)')
    parser.add_argument('--results-dir', default='results', help='Base results directory (benchmark-first layout: <dir>/<workload>/<system>/benchmarks)')
    parser.add_argument('--systems', default=None, help="Comma-separated systems to compare (default: baseline,adco,aco,py-dbridge)")
    parser.add_argument('--output-dir', default=None, help='Output directory for generated reports (default: reports/<workload>/app_layer)')
    parser.add_argument('--quiet', action='store_true', help='Suppress terminal table output; still print warnings and saved-file lines')
    args = parser.parse_args()

    default_systems = ['baseline', 'adco', 'aco', 'py-dbridge']
    if args.systems is None:
        systems = default_systems
        title_prefix = "Application Layer Performance Comparison"
    else:
        systems = [s.strip() for s in args.systems.split(',') if s.strip()]
        title_prefix = "Performance Comparison"
    system_display_names = {
        'baseline': 'Default',
        'adco': 'ADCo',
        'aco': 'ACo',
        'py-dbridge': 'Py-DBridge',
        'pydbridge': 'Py-DBridge',
        'naive-llm': 'Naive-LLM',
        'naive-llm-aggressive': 'Naive-LLM-Aggressive',
        'dco': 'DCo',
        'agenttune': 'AgentTune',
        'naive-llm-agenttune': 'Naive-LLM + AgentTune',
        'agenttune-naive-llm': 'AgentTune + Naive-LLM',
        'gptuner': 'GPTuner',
        'ottertune': 'OtterTune'
    }
    
    # Determine workloads to run
    if args.workload.lower() == 'all':
        workloads = discover_workloads(args.results_dir, args.dbms)
        if not workloads:
            workloads = ['smallbank', 'tpcc']
    else:
        workloads = [args.workload.lower()]
        
    for wl in workloads:
        data, raw_records, sources = parse_workload_data(args.results_dir, wl, args.dbms, systems)
        output_dir = args.output_dir or os.path.join('reports', wl, 'app_layer')
        verify_statuses = None
        if load_correctness_statuses:
            verify_statuses = load_correctness_statuses(args.results_dir, wl, systems)
        generate_workload_report(data, raw_records, wl, args.dbms, systems, system_display_names, output_dir, sources, title_prefix, quiet=args.quiet, verify_statuses=verify_statuses)

if __name__ == '__main__':
    main()
