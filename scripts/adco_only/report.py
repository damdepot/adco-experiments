#!/usr/bin/env python3
import argparse
import os
import glob
import csv
import re
from collections import defaultdict

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

CANONICAL_LABELS = ('baseline', 'aco', 'dco', 'adco')
_CANONICAL_RE = re.compile(r'^(baseline|aco|dco|adco)_(\d{8}_\d{6})(?:_r\d+)?\.csv$')


def _newest_run_id(workload_dir):
    """Newest RUN_ID in a canonical workload dir.

    Prefers RUN_IDs that have baseline files (mirrors
    scripts/_lib/run_comparison.sh), falls back to any label.
    """
    baseline_ids = set()
    all_ids = set()
    try:
        names = os.listdir(workload_dir)
    except OSError:
        return None
    for fname in names:
        m = _CANONICAL_RE.match(fname)
        if not m:
            continue
        all_ids.add(m.group(2))
        if m.group(1) == 'baseline':
            baseline_ids.add(m.group(2))
    pool = sorted(baseline_ids) or sorted(all_ids)
    return pool[-1] if pool else None


def _rep_files(workload_dir, label, run_id):
    """Rep files for one label+RUN_ID: <label>_<RUN_ID>_rN.csv, else plain."""
    files = sorted(glob.glob(os.path.join(workload_dir, f"{label}_{run_id}_r*.csv")))
    files = [f for f in files if re.search(r"_r\d+\.csv$", f)]
    if not files:
        plain = os.path.join(workload_dir, f"{label}_{run_id}.csv")
        if os.path.isfile(plain):
            files = [plain]
    return files


def discover_workloads(results_dir, dbms):
    """Discover available workloads in results_dir for the given dbms."""
    # Canonical layout first: results/adco_only/<workload>/<label>_<RUN_ID>[_rN].csv
    if os.path.isdir(results_dir):
        workloads = []
        for entry in sorted(os.listdir(results_dir)):
            wdir = os.path.join(results_dir, entry)
            if not os.path.isdir(wdir):
                continue
            try:
                names = os.listdir(wdir)
            except OSError:
                continue
            if any(_CANONICAL_RE.match(n) for n in names if not n.startswith('.')):
                workloads.append(entry.lower())
        if workloads:
            return sorted(workloads)
    # Legacy layout fallback: results/adco_only/<sys>/benchmarks/runExperiment*-<workload>-<dbms>*
    workloads = set()
    systems = ['baseline', 'aco', 'dco', 'adco']
    for sys in systems:
        bench_dir = os.path.join(results_dir, sys, 'benchmarks')
        if not os.path.exists(bench_dir):
            continue
        for fname in os.listdir(bench_dir):
            if fname.startswith('.'):
                continue
            match = re.match(r'runExperiment\d+-([a-zA-Z0-9_]+)-' + re.escape(dbms), fname, re.IGNORECASE)
            if match:
                workloads.add(match.group(1).lower())
    if not workloads:
        for default_wl in ['smallbank', 'tpcc']:
            for sys in systems:
                pattern = os.path.join(results_dir, sys, 'benchmarks', f"*{default_wl}*")
                if glob.glob(pattern):
                    workloads.add(default_wl)
                    break
    if not workloads:
        workloads = {'smallbank', 'tpcc'}
    return sorted(list(workloads))

def parse_workload_data(results_dir, workload, dbms, systems, run_id=None):
    """
    Parse benchmark files for a specific workload and dbms across systems.
    Canonical layout: results/adco_only/<workload>/<label>_<RUN_ID>[_rN].csv
    with header transaction,executed,execution_time,transaction_rate. Reps for
    the selected RUN_ID (default: newest, preferring baseline) are averaged
    by the caller (mean over reps, per transaction).
    Returns:
        data: dict[sys][transaction] -> { 'executed': list, 'execution_time': list, 'transaction_rate': list }
        raw_records: list of [sys, workload, dbms, file_name, transaction, executed, execution_time, transaction_rate]
        selected_run_id: the RUN_ID used for the canonical layout, else None
    """
    data = {sys: defaultdict(lambda: {'executed': [], 'execution_time': [], 'transaction_rate': []}) for sys in systems}
    raw_records = []

    # Canonical layout branch.
    workload_dir = os.path.join(results_dir, workload)
    if os.path.isdir(workload_dir) and any(
        _CANONICAL_RE.match(n) for n in os.listdir(workload_dir) if not n.startswith('.')
    ):
        selected = run_id or _newest_run_id(workload_dir)
        if selected is None:
            return data, raw_records, None
        for sys in systems:
            for filepath in _rep_files(workload_dir, sys, selected):
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
        return data, raw_records, selected

    # Legacy layout fallback.
    for sys in systems:
        bench_dir = os.path.join(results_dir, sys, 'benchmarks')
        if not os.path.exists(bench_dir):
            continue
        
        pattern1 = os.path.join(bench_dir, f"runExperiment*-{workload}-{dbms}*")
        pattern2 = os.path.join(bench_dir, f"*{workload}*{dbms}*")
        matched_files = sorted(list(set(glob.glob(pattern1) + glob.glob(pattern2))))
        
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
                
    return data, raw_records, run_id

def generate_workload_report(data, raw_records, workload, dbms, systems, system_display_names, output_dir, run_id=None):
    
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
    
    # Calculate stats per transaction
    # Canonical parsing logic (mirrors scripts/_lib/run_comparison.sh):
    # average (mean) col-4 transaction_rate across reps, per transaction.
    stats = {sys: {} for sys in systems}
    for sys in systems:
        for txn in all_txns:
            rate_vals = data[sys][txn]['transaction_rate']
            time_vals = data[sys][txn]['execution_time']
            exec_vals = data[sys][txn]['executed']
            stats[sys][txn] = {
                'rate': calculate_mean(rate_vals),
                'time': calculate_mean(time_vals),
                'executed': calculate_mean(exec_vals)
            }
            
    # Calculate Speedups relative to baseline (Throughput speedup = sys_rate / baseline_rate)
    speedups = {sys: [] for sys in systems}
    adco_vs_aco_speedups = []
    adco_vs_dco_speedups = []
    adco_vs_aco_time_speedups = []
    adco_vs_dco_time_speedups = []
    
    # Format terminal output
    lines = []
    title = f"ADCo Performance Comparison: {workload.upper()} on {dbms}"
    lines.append(title)
    lines.append("=" * len(title))
    if run_id:
        lines.append(f"Source: results/adco_only/{workload} (RUN_ID {run_id})")
    lines.append("")
    
    header = f"{'Transaction':<20} | {'Baseline (txn/s)':<18}"
    for sys in systems[1:]:
        sys_name = system_display_names.get(sys, sys.capitalize())
        header += f" | {sys_name:<14} | Speedup (rate)"
    header += f" | {'ADCo vs ACo':<14} | {'ADCo vs DCo':<14}"
    lines.append(header)
    lines.append("-" * len(header))
    
    for txn in all_txns:
        line = f"{txn:<20} | "
        base_rate = stats['baseline'].get(txn, {}).get('rate')
        line += f"{f'{base_rate:.2f}':<18}" if base_rate is not None else f"{'N/A':<18}"
        
        for sys in systems[1:]:
            sys_rate = stats[sys].get(txn, {}).get('rate')
            if base_rate is not None and sys_rate is not None and base_rate > 0:
                spd = sys_rate / base_rate
                if txn.upper() != 'TOTAL':
                    speedups[sys].append(spd)
                spd_str = f"{spd:.2f}x"
            else:
                spd_str = "N/A"
            r_str = f"{sys_rate:.2f}" if sys_rate is not None else "N/A"
            line += f" | {r_str:<14} | {spd_str:<14}"
        # ADCo vs ACo / ADCo vs DCo
        aco_rate = stats['aco'].get(txn, {}).get('rate')
        dco_rate = stats['dco'].get(txn, {}).get('rate')
        adco_rate = stats['adco'].get(txn, {}).get('rate')
        if aco_rate is not None and adco_rate is not None and aco_rate > 0:
            spd = adco_rate / aco_rate
            if txn.upper() != 'TOTAL':
                adco_vs_aco_speedups.append(spd)
            spd_aco_str = f"{spd:.2f}x"
        else:
            spd_aco_str = "N/A"
        if dco_rate is not None and adco_rate is not None and dco_rate > 0:
            spd = adco_rate / dco_rate
            if txn.upper() != 'TOTAL':
                adco_vs_dco_speedups.append(spd)
            spd_dco_str = f"{spd:.2f}x"
        else:
            spd_dco_str = "N/A"
        # time-based for geo later (collect here as well)
        aco_time = stats['aco'].get(txn, {}).get('time')
        dco_time = stats['dco'].get(txn, {}).get('time')
        adco_time = stats['adco'].get(txn, {}).get('time')
        if aco_time is not None and adco_time is not None and adco_time > 0:
            spd_t = aco_time / adco_time
            if txn.upper() != 'TOTAL':
                adco_vs_aco_time_speedups.append(spd_t)
        if dco_time is not None and adco_time is not None and adco_time > 0:
            spd_t = dco_time / adco_time
            if txn.upper() != 'TOTAL':
                adco_vs_dco_time_speedups.append(spd_t)
        line += f" | {spd_aco_str:<14} | {spd_dco_str:<14}"
        lines.append(line)
        
    lines.append("-" * len(header))
    
    # Geo Mean of Speedup
    geo_line = f"{'Geo Mean (Txns)':<20} | {'-':<18}"
    for sys in systems[1:]:
        g_spd = geometric_mean(speedups[sys])
        g_str = f"{g_spd:.2f}x" if g_spd > 0 else "N/A"
        geo_line += f" | {'-':<14} | {g_str:<14}"
    g_aco = geometric_mean(adco_vs_aco_speedups)
    g_dco = geometric_mean(adco_vs_dco_speedups)
    geo_line += f" | {f'{g_aco:.2f}x' if g_aco>0 else 'N/A':<14} | {f'{g_dco:.2f}x' if g_dco>0 else 'N/A':<14}"
    lines.append(geo_line)
    lines.append("")
    
    report_text = "\n".join(lines)
    print(report_text)
    
    # Markdown Report Generation
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        md_path = os.path.join(output_dir, f"performance_comparison_{workload}_{dbms}.md")
        
        md_lines = []
        md_lines.append(f"# ADCo Performance Comparison: {workload.upper()} on {dbms}\n")
        if run_id:
            md_lines.append(f"Source: `results/adco_only/{workload}` (RUN_ID {run_id})\n")
        
        # Table 1: Throughput (Transaction Rate)
        md_lines.append("## Transaction Rate / Throughput (txn/s)\n")
        md_header = "| Transaction | Baseline (txn/s) |"
        md_sep = "| :--- | :---: |"
        for sys in systems[1:]:
            sys_name = system_display_names.get(sys, sys.capitalize())
            md_header += f" {sys_name} (txn/s) | {sys_name} Speedup |"
            md_sep += " :---: | :---: |"
        md_header += " ADCo vs ACo | ADCo vs DCo |"
        md_sep += " :---: | :---: |"
        md_lines.append(md_header)
        md_lines.append(md_sep)
        
        for txn in all_txns:
            is_total = (txn.upper() == 'TOTAL')
            prefix = "**" if is_total else ""
            suffix = "**" if is_total else ""
            
            base_rate = stats['baseline'].get(txn, {}).get('rate')
            base_rate_str = f"{base_rate:.2f}" if base_rate is not None else "N/A"
            row_str = f"| {prefix}{txn}{suffix} | {prefix}{base_rate_str}{suffix} |"
            
            for sys in systems[1:]:
                sys_rate = stats[sys].get(txn, {}).get('rate')
                if base_rate is not None and sys_rate is not None and base_rate > 0:
                    spd = sys_rate / base_rate
                    spd_str = f"{spd:.2f}x"
                else:
                    spd_str = "N/A"
                r_str = f"{sys_rate:.2f}" if sys_rate is not None else "N/A"
                row_str += f" {prefix}{r_str}{suffix} | {prefix}{spd_str}{suffix} |"
            # ADCo vs ACo / ADCo vs DCo
            aco_rate = stats['aco'].get(txn, {}).get('rate')
            dco_rate = stats['dco'].get(txn, {}).get('rate')
            adco_rate = stats['adco'].get(txn, {}).get('rate')
            if aco_rate is not None and adco_rate is not None and aco_rate > 0:
                spd_aco = adco_rate / aco_rate
                spd_aco_str = f"{spd_aco:.2f}x"
            else:
                spd_aco_str = "N/A"
            if dco_rate is not None and adco_rate is not None and dco_rate > 0:
                spd_dco = adco_rate / dco_rate
                spd_dco_str = f"{spd_dco:.2f}x"
            else:
                spd_dco_str = "N/A"
            row_str += f" {prefix}{spd_aco_str}{suffix} | {prefix}{spd_dco_str}{suffix} |"
            md_lines.append(row_str)
            
        # Geo Mean row
        geo_row = "| **Geo Mean (Txns)** | **-** |"
        for sys in systems[1:]:
            g_spd = geometric_mean(speedups[sys])
            g_str = f"{g_spd:.2f}x" if g_spd > 0 else "N/A"
            geo_row += f" **-** | **{g_str}** |"
        g_aco = geometric_mean(adco_vs_aco_speedups)
        g_dco = geometric_mean(adco_vs_dco_speedups)
        geo_row += f" **{f'{g_aco:.2f}x' if g_aco>0 else 'N/A'}** | **{f'{g_dco:.2f}x' if g_dco>0 else 'N/A'}** |"
        md_lines.append(geo_row)
        md_lines.append("\n")
        
        # Table 2: Execution Time (ms)
        md_lines.append("## Execution Time (ms)\n")
        md_header_time = "| Transaction | Baseline (ms) |"
        md_sep_time = "| :--- | :---: |"
        for sys in systems[1:]:
            sys_name = system_display_names.get(sys, sys.capitalize())
            md_header_time += f" {sys_name} (ms) | {sys_name} Latency Reduction |"
            md_sep_time += " :---: | :---: |"
        md_header_time += " ADCo vs ACo | ADCo vs DCo |"
        md_sep_time += " :---: | :---: |"
        md_lines.append(md_header_time)
        md_lines.append(md_sep_time)
        
        for txn in all_txns:
            is_total = (txn.upper() == 'TOTAL')
            prefix = "**" if is_total else ""
            suffix = "**" if is_total else ""
            
            base_time = stats['baseline'].get(txn, {}).get('time')
            base_time_str = f"{base_time:.2f}" if base_time is not None else "N/A"
            row_str = f"| {prefix}{txn}{suffix} | {prefix}{base_time_str}{suffix} |"
            
            for sys in systems[1:]:
                sys_time = stats[sys].get(txn, {}).get('time')
                if base_time is not None and sys_time is not None and sys_time > 0:
                    spd = base_time / sys_time
                    spd_str = f"{spd:.2f}x"
                else:
                    spd_str = "N/A"
                t_str = f"{sys_time:.2f}" if sys_time is not None else "N/A"
                row_str += f" {prefix}{t_str}{suffix} | {prefix}{spd_str}{suffix} |"
            # ADCo vs ACo / ADCo vs DCo latency reduction
            aco_time = stats['aco'].get(txn, {}).get('time')
            dco_time = stats['dco'].get(txn, {}).get('time')
            adco_time = stats['adco'].get(txn, {}).get('time')
            if aco_time is not None and adco_time is not None and adco_time > 0:
                spd_aco_t = aco_time / adco_time
                spd_aco_t_str = f"{spd_aco_t:.2f}x"
            else:
                spd_aco_t_str = "N/A"
            if dco_time is not None and adco_time is not None and adco_time > 0:
                spd_dco_t = dco_time / adco_time
                spd_dco_t_str = f"{spd_dco_t:.2f}x"
            else:
                spd_dco_t_str = "N/A"
            row_str += f" {prefix}{spd_aco_t_str}{suffix} | {prefix}{spd_dco_t_str}{suffix} |"
            md_lines.append(row_str)
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
    parser = argparse.ArgumentParser(description='Parse ADCo benchmark results (Baseline vs ACo vs DCo vs ADCo) and output throughput comparison reports.')
    parser.add_argument('--workload', default='all', help="Workload name ('smallbank', 'tpcc', or 'all')")
    parser.add_argument('--dbms', default='postgres', help='DBMS name (e.g. postgres, PostgreSQL)')
    parser.add_argument('--results-dir', default='results/adco_only', help='Base results directory for adco_only')
    parser.add_argument('--output-dir', default='reports/adco_only', help='Output directory for generated reports')
    parser.add_argument('--run-id', default=None, help='RUN_ID to report on (default: newest RUN_ID per workload, preferring baseline)')
    args = parser.parse_args()
    
    systems = ['baseline', 'aco', 'dco', 'adco']
    system_display_names = {
        'baseline': 'Baseline',
        'aco': 'ACo',
        'dco': 'DCo',
        'adco': 'ADCo'
    }
    
    # Determine workloads to run
    if args.workload.lower() == 'all':
        workloads = discover_workloads(args.results_dir, args.dbms)
        if not workloads:
            workloads = ['smallbank', 'tpcc']
    else:
        workloads = [args.workload.lower()]
        
    for wl in workloads:
        data, raw_records, selected = parse_workload_data(args.results_dir, wl, args.dbms, systems, run_id=args.run_id)
        generate_workload_report(data, raw_records, wl, args.dbms, systems, system_display_names, args.output_dir, run_id=selected)

if __name__ == '__main__':
    main()
