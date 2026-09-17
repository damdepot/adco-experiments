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
    systems = ['aco', 'dco', 'adco']
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

def parse_workload_data(results_dir, workload, dbms, systems):
    """
    Parse benchmark files for a specific workload and dbms across ACo, DCo, ADCo.
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

def generate_workload_report(data, raw_records, workload, dbms, output_dir):
    systems = ['aco', 'dco', 'adco']
    
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
    
    # Calculate stats per transaction using median rate
    stats = {sys: {} for sys in systems}
    for sys in systems:
        for txn in all_txns:
            rate_vals = data[sys][txn]['transaction_rate']
            stats[sys][txn] = {
                'rate': calculate_median(rate_vals)
            }
            
    adco_vs_aco_speedups = []
    adco_vs_dco_speedups = []
    
    # Terminal Output Header
    lines = []
    title = f"ADCo Performance Comparison: {workload.upper()} on {dbms}"
    lines.append(title)
    lines.append("=" * len(title))
    lines.append("")
    lines.append("--- Throughput / Transaction Rate (txn/s) ---")
    
    header = f"{'Transaction':<20} | {'ACo (Rewrite)':<15} | {'DCo (Tune)':<15} | {'ADCo (Unified)':<15} | {'ADCo vs ACo':<12} | {'ADCo vs DCo':<12}"
    lines.append(header)
    lines.append("-" * len(header))
    
    for txn in all_txns:
        aco_rate = stats['aco'].get(txn, {}).get('rate')
        dco_rate = stats['dco'].get(txn, {}).get('rate')
        adco_rate = stats['adco'].get(txn, {}).get('rate')
        
        aco_str = f"{aco_rate:.2f}" if aco_rate is not None else "N/A"
        dco_str = f"{dco_rate:.2f}" if dco_rate is not None else "N/A"
        adco_str = f"{adco_rate:.2f}" if adco_rate is not None else "N/A"
        
        # ADCo vs ACo
        if aco_rate is not None and adco_rate is not None and aco_rate > 0:
            spd_aco = adco_rate / aco_rate
            spd_aco_str = f"{spd_aco:.2f}x"
            if txn.upper() != 'TOTAL':
                adco_vs_aco_speedups.append(spd_aco)
        else:
            spd_aco_str = "N/A"
            
        # ADCo vs DCo
        if dco_rate is not None and adco_rate is not None and dco_rate > 0:
            spd_dco = adco_rate / dco_rate
            spd_dco_str = f"{spd_dco:.2f}x"
            if txn.upper() != 'TOTAL':
                adco_vs_dco_speedups.append(spd_dco)
        else:
            spd_dco_str = "N/A"
            
        lines.append(f"{txn:<20} | {aco_str:<15} | {dco_str:<15} | {adco_str:<15} | {spd_aco_str:<12} | {spd_dco_str:<12}")
        
    lines.append("-" * len(header))
    
    # Geo Mean row
    g_aco = geometric_mean(adco_vs_aco_speedups)
    g_dco = geometric_mean(adco_vs_dco_speedups)
    g_aco_str = f"{g_aco:.2f}x" if g_aco > 0 else "N/A"
    g_dco_str = f"{g_dco:.2f}x" if g_dco > 0 else "N/A"
    lines.append(f"{'Geo Mean (Txns)':<20} | {'-':<15} | {'-':<15} | {'-':<15} | {g_aco_str:<12} | {g_dco_str:<12}")
    lines.append("")
    
    print("\n".join(lines))
    
    # Markdown Report Generation (Throughput Table Only)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        md_path = os.path.join(output_dir, f"performance_comparison_{workload}_{dbms}.md")
        
        md_lines = []
        md_lines.append(f"# ADCo Performance Comparison: {workload.upper()} on {dbms}\n")
        md_lines.append("## Throughput / Transaction Rate (txn/s)\n")
        md_lines.append("| Transaction | ACo (Rewrite) | DCo (Tune) | ADCo (Unified) | ADCo vs ACo | ADCo vs DCo |")
        md_lines.append("| :--- | :---: | :---: | :---: | :---: | :---: |")
        
        for txn in all_txns:
            is_total = (txn.upper() == 'TOTAL')
            prefix = "**" if is_total else ""
            suffix = "**" if is_total else ""
            
            aco_rate = stats['aco'].get(txn, {}).get('rate')
            dco_rate = stats['dco'].get(txn, {}).get('rate')
            adco_rate = stats['adco'].get(txn, {}).get('rate')
            
            aco_str = f"{aco_rate:.2f}" if aco_rate is not None else "N/A"
            dco_str = f"{dco_rate:.2f}" if dco_rate is not None else "N/A"
            adco_str = f"{adco_rate:.2f}" if adco_rate is not None else "N/A"
            
            if aco_rate is not None and adco_rate is not None and aco_rate > 0:
                spd_aco_str = f"{(adco_rate / aco_rate):.2f}x"
            else:
                spd_aco_str = "N/A"
                
            if dco_rate is not None and adco_rate is not None and dco_rate > 0:
                spd_dco_str = f"{(adco_rate / dco_rate):.2f}x"
            else:
                spd_dco_str = "N/A"
                
            md_lines.append(f"| {prefix}{txn}{suffix} | {prefix}{aco_str}{suffix} | {prefix}{dco_str}{suffix} | {prefix}{adco_str}{suffix} | {prefix}{spd_aco_str}{suffix} | {prefix}{spd_dco_str}{suffix} |")
            
        md_lines.append(f"| **Geo Mean (Txns)** | **-** | **-** | **-** | **{g_aco_str}** | **{g_dco_str}** |")
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
    parser = argparse.ArgumentParser(description='Parse ADCo benchmark results (ACo vs DCo vs ADCo) and output throughput comparison reports.')
    parser.add_argument('--workload', default='all', help="Workload name ('smallbank', 'tpcc', or 'all')")
    parser.add_argument('--dbms', default='postgres', help='DBMS name (e.g. postgres, PostgreSQL)')
    parser.add_argument('--results-dir', default='results/adco_only', help='Base results directory for adco_only')
    parser.add_argument('--output-dir', default='reports/adco_only', help='Output directory for generated reports')
    args = parser.parse_args()
    
    systems = ['aco', 'dco', 'adco']
    
    # Determine workloads to run
    if args.workload.lower() == 'all':
        workloads = discover_workloads(args.results_dir, args.dbms)
        if not workloads:
            workloads = ['smallbank', 'tpcc']
    else:
        workloads = [args.workload.lower()]
        
    for wl in workloads:
        data, raw_records = parse_workload_data(args.results_dir, wl, args.dbms, systems)
        generate_workload_report(data, raw_records, wl, args.dbms, args.output_dir)

if __name__ == '__main__':
    main()
