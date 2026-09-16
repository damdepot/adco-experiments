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

def discover_workloads(results_dir, dbms):
    """Discover available workloads in results_dir for the given dbms."""
    workloads = set()
    systems = ['baseline', 'adco', 'agenttune', 'gptuner', 'ottertune']
    for sys in systems:
        bench_dir = os.path.join(results_dir, sys, 'benchmarks')
        if not os.path.exists(bench_dir):
            continue
        for fname in os.listdir(bench_dir):
            if fname.startswith('.'):
                continue
            # Pattern: runExperiment1-{workload}-{dbms}*
            match = re.match(r'runExperiment\d+-([a-zA-Z0-9_]+)-' + re.escape(dbms), fname, re.IGNORECASE)
            if match:
                workloads.add(match.group(1).lower())
    if not workloads:
        # Fallback to checking default known workloads
        for default_wl in ['smallbank', 'tpcc']:
            for sys in systems:
                pattern = os.path.join(results_dir, sys, 'benchmarks', f"*{default_wl}*")
                if glob.glob(pattern):
                    workloads.add(default_wl)
                    break
    return sorted(list(workloads))

def parse_workload_data(results_dir, workload, dbms, systems):
    """
    Parse benchmark files for a specific workload and dbms across all systems.
    Returns:
        data: dict[sys][transaction] -> { 'executed': list, 'execution_time': list, 'transaction_rate': list }
        raw_records: list of [sys, workload, dbms, file_name, transaction, executed, execution_time, transaction_rate]
    """
    data = {sys: defaultdict(lambda: {'executed': [], 'execution_time': [], 'transaction_rate': []}) for sys in systems}
    raw_records = []
    
    for sys in systems:
        bench_dir = os.path.join(results_dir, sys, 'benchmarks')
        if not os.path.exists(bench_dir):
            continue
        
        # Search for files matching runExperiment*-{workload}-{dbms}*
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
                
    return data, raw_records

def generate_workload_report(data, raw_records, workload, dbms, systems, system_display_names, output_dir):
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
    # We will use median for aggregation
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
            
    # Calculate Speedups relative to baseline (Throughput speedup = sys_rate / baseline_rate)
    speedups = {sys: [] for sys in systems}
    
    # Format terminal output
    lines = []
    title = f"Database Layer Performance Comparison: {workload.upper()} on {dbms}"
    lines.append(title)
    lines.append("=" * len(title))
    lines.append("")
    
    header = f"{'Transaction':<20} | {'Baseline (txn/s)':<18}"
    for sys in systems[1:]:
        sys_name = system_display_names.get(sys, sys.capitalize())
        header += f" | {sys_name:<14} | Speedup (rate)"
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
        lines.append(line)
        
    lines.append("-" * len(header))
    
    # Geo Mean of Speedup
    geo_line = f"{'Geo Mean (Txns)':<20} | {'-':<18}"
    for sys in systems[1:]:
        g_spd = geometric_mean(speedups[sys])
        g_str = f"{g_spd:.2f}x" if g_spd > 0 else "N/A"
        geo_line += f" | {'-':<14} | {g_str:<14}"
    lines.append(geo_line)
    lines.append("")
    
    report_text = "\n".join(lines)
    print(report_text)
    
    # Markdown Report Generation
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        md_path = os.path.join(output_dir, f"performance_comparison_{workload}_{dbms}.md")
        
        md_lines = []
        md_lines.append(f"# Database Layer Performance Comparison: {workload.upper()} on {dbms}\n")
        
        # Table 1: Throughput (Transaction Rate)
        md_lines.append("## Transaction Rate / Throughput (txn/s)\n")
        md_header = "| Transaction | Baseline (txn/s) |"
        md_sep = "| :--- | :---: |"
        for sys in systems[1:]:
            sys_name = system_display_names.get(sys, sys.capitalize())
            md_header += f" {sys_name} (txn/s) | {sys_name} Speedup |"
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
            md_lines.append(row_str)
            
        # Geo Mean row
        geo_row = "| **Geo Mean (Txns)** | **-** |"
        for sys in systems[1:]:
            g_spd = geometric_mean(speedups[sys])
            g_str = f"{g_spd:.2f}x" if g_spd > 0 else "N/A"
            geo_row += f" **-** | **{g_str}** |"
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
    parser = argparse.ArgumentParser(description='Parse database layer benchmark results and output performance comparisons.')
    parser.add_argument('--workload', default='all', help="Workload name ('smallbank', 'tpcc', or 'all')")
    parser.add_argument('--dbms', default='postgres', help='DBMS name (e.g. postgres, PostgreSQL)')
    parser.add_argument('--results-dir', default='results/db_layer', help='Base results directory for db_layer')
    parser.add_argument('--output-dir', default='reports/db_layer', help='Output directory for generated reports')
    args = parser.parse_args()
    
    systems = ['baseline', 'adco', 'agenttune', 'gptuner', 'ottertune']
    system_display_names = {
        'baseline': 'Baseline',
        'adco': 'ADCo',
        'agenttune': 'AgentTune',
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
        data, raw_records = parse_workload_data(args.results_dir, wl, args.dbms, systems)
        generate_workload_report(data, raw_records, wl, args.dbms, systems, system_display_names, args.output_dir)

if __name__ == '__main__':
    main()
