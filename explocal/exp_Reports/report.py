import argparse
import os
import glob
import csv
import math
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

def calculate_stats(values):
    count = len(values)
    if count == 0:
        return {'count': 0, 'avg': None, 'median': None, 'min': None, 'max': None}
    
    avg = sum(values) / count
    median = calculate_median(values)
    min_val = min(values)
    max_val = max(values)
    
    return {'count': count, 'avg': avg, 'median': median, 'min': min_val, 'max': max_val}

def geometric_mean(values):
    if not values:
        return 0.0
    product = 1.0
    for v in values:
        if v <= 0:
            return 0.0
        product *= v
    return product ** (1.0 / len(values))

def main():
    parser = argparse.ArgumentParser(description='Parse benchmark results and output performance comparisons.')
    parser.add_argument('--dataset', default='stats-lite', help='Dataset name')
    parser.add_argument('--dbms', default='PostgreSQL', help='DBMS name')
    parser.add_argument('--results-dir', default='results', help='Base results directory')
    parser.add_argument('--output-dir', default='results/reports', help='Output directory for the report')
    args = parser.parse_args()

    systems = ['baseline', 'learnedrewrite', 'r-bot', 'resequel']
    system_display_names = {
        'baseline': 'Baseline',
        'learnedrewrite': 'LearnedRewrite',
        'r-bot': 'R-Bot',
        'resequel': 'ReSequel'
    }
    
    # data[system][query_id] = [execution_times...]
    data = {sys: defaultdict(list) for sys in systems}
    raw_records = []
    
    file_prefix = f"runExperiment2-{args.dataset}-{args.dbms}"
    
    for sys in systems:
        search_pattern = os.path.join(args.results_dir, sys, 'benchmarks', f"{file_prefix}*.dat")
        files = glob.glob(search_pattern)
        for filepath in files:
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    reader = csv.reader(f)
                    header_skipped = False
                    for row in reader:
                        if not row:
                            continue
                        if not header_skipped and row[0].strip().lower() == 'query_id':
                            header_skipped = True
                            continue
                        
                        if len(row) >= 6:
                            query_id = row[0].strip()
                            dbms_val = row[1].strip()
                            iteration = row[2].strip()
                            start_time = row[3].strip()
                            planning_time = row[4].strip()
                            exec_time_str = row[5].strip()
                            
                            raw_records.append([sys, query_id, dbms_val, iteration, start_time, planning_time, exec_time_str])
                            
                            try:
                                execution_time = float(exec_time_str)
                                data[sys][query_id].append(execution_time)
                            except ValueError:
                                pass
            except Exception as e:
                print(f"Error reading {filepath}: {e}")
                
    # Calculate medians for the main table
    medians = {sys: {} for sys in systems}
    all_queries = set()
    for sys in systems:
        for q_id, times in data[sys].items():
            m = calculate_median(times)
            medians[sys][q_id] = m if m is not None else 0.0
            all_queries.add(q_id)
            
    all_queries = sorted(list(all_queries))
    
    # Calculate performance comparisons relative to baseline
    baseline_medians = medians['baseline']
    results = []
    
    total_time = {sys: 0.0 for sys in systems}
    speedups = {sys: [] for sys in systems}
    
    for q_id in all_queries:
        row = {'query_id': q_id}
        base_time = baseline_medians.get(q_id, 0.0)
        row['baseline_time'] = base_time
        
        for sys in systems:
            sys_time = medians[sys].get(q_id, 0.0)
            if sys_time > 0:
                row[f'{sys}_time'] = sys_time
                total_time[sys] += sys_time
            else:
                row[f'{sys}_time'] = None
                
            if sys != 'baseline':
                if base_time > 0 and sys_time > 0:
                    speedup = base_time / sys_time
                    row[f'{sys}_speedup'] = speedup
                    speedups[sys].append(speedup)
                else:
                    row[f'{sys}_speedup'] = None
                    
        results.append(row)
        
    # Generate Output (Terminal)
    lines = []
    
    title = f"Performance Comparison: {args.dataset} on {args.dbms}"
    lines.append(title)
    lines.append("=" * len(title))
    lines.append("")
    
    header = f"{'Query ID':<15}"
    header += f"{'Baseline (ms)':<15}"
    for sys in systems[1:]:
        header += f"{sys.capitalize()[:10]} (ms) | Speedup"
        header += " " * 4
    lines.append(header)
    lines.append("-" * len(header))
    
    for row in results:
        q_id = row['query_id']
        line = f"{q_id:<15}"
        
        base_t = row.get('baseline_time')
        line += f"{base_t if base_t else 'N/A':<15.2f}" if base_t else f"{'N/A':<15}"
        
        for sys in systems[1:]:
            sys_t = row.get(f'{sys}_time')
            sys_s = row.get(f'{sys}_speedup')
            
            t_str = f"{sys_t:.2f}" if sys_t is not None else "N/A"
            s_str = f"{sys_s:.2f}x" if sys_s is not None else "N/A"
            
            cell = f"{t_str:<12} | {s_str:<8}"
            line += f"{cell:<24}"
            
        lines.append(line)
        
    lines.append("-" * len(header))
    
    line = f"{'Total':<15}"
    base_tot = total_time['baseline']
    line += f"{base_tot:<15.2f}"
    
    for sys in systems[1:]:
        sys_tot = total_time[sys]
        if sys_tot > 0 and base_tot > 0:
            tot_speedup = base_tot / sys_tot
        else:
            tot_speedup = None
            
        t_str = f"{sys_tot:.2f}"
        s_str = f"{tot_speedup:.2f}x" if tot_speedup is not None else "N/A"
        
        cell = f"{t_str:<12} | {s_str:<8}"
        line += f"{cell:<24}"
        
    lines.append(line)
    
    line = f"{'Geo Mean Spd':<15}"
    line += f"{'-':<15}"
    for sys in systems[1:]:
        geo_mean = geometric_mean(speedups[sys])
        s_str = f"{geo_mean:.2f}x" if geo_mean > 0 else "N/A"
        cell = f"{'-':<12} | {s_str:<8}"
        line += f"{cell:<24}"
        
    lines.append(line)
    
    report_content = "\n".join(lines)
    print(report_content)
    
    if args.output_dir:
        os.makedirs(args.output_dir, exist_ok=True)
        out_path = os.path.join(args.output_dir, f"performance_comparison_{args.dataset}_{args.dbms}.md")
        
        md_lines = []
        md_lines.append(f"# Performance Comparison: {args.dataset} on {args.dbms} (Median of Iterations)\n")
        
        md_header = "| Query ID | Baseline (ms) |"
        md_separator = "| :--- | :--- |"
        for sys in systems[1:]:
            sys_name = system_display_names.get(sys, sys.capitalize())
            md_header += f" {sys_name} (ms) | {sys_name} Speedup |"
            md_separator += " :---: | :---: |"
        
        md_lines.append(md_header)
        md_lines.append(md_separator)
        
        for row in results:
            q_id = row['query_id']
            base_t = row.get('baseline_time')
            base_t_str = f"{base_t:.2f}" if base_t else "N/A"
            md_row = f"| {q_id} | {base_t_str} |"
            
            for sys in systems[1:]:
                sys_t = row.get(f'{sys}_time')
                sys_s = row.get(f'{sys}_speedup')
                t_str = f"{sys_t:.2f}" if sys_t is not None else "N/A"
                s_str = f"{sys_s:.2f}x" if sys_s is not None else "N/A"
                md_row += f" {t_str} | {s_str} |"
            md_lines.append(md_row)
            
        base_tot = total_time['baseline']
        md_row_tot = f"| **Total** | **{base_tot:.2f}** |"
        for sys in systems[1:]:
            sys_tot = total_time[sys]
            if sys_tot > 0 and base_tot > 0:
                tot_speedup = base_tot / sys_tot
            else:
                tot_speedup = None
            t_str = f"{sys_tot:.2f}"
            s_str = f"{tot_speedup:.2f}x" if tot_speedup is not None else "N/A"
            md_row_tot += f" **{t_str}** | **{s_str}** |"
        md_lines.append(md_row_tot)
        
        md_row_geo = "| **Geo Mean Spd** | **-** |"
        for sys in systems[1:]:
            geo_mean = geometric_mean(speedups[sys])
            s_str = f"{geo_mean:.2f}x" if geo_mean > 0 else "N/A"
            md_row_geo += f" **-** | **{s_str}** |"
        md_lines.append(md_row_geo)
        
        # Append Query-Level Details
        md_lines.append("\n## Query-Level Execution Details\n")
        
        for sys in systems:
            sys_name = system_display_names.get(sys, sys.capitalize())
            md_lines.append(f"### {sys_name}\n")
            md_lines.append("| Query ID | Iterations | Avg (ms) | Median (ms) | Min (ms) | Max (ms) |")
            md_lines.append("| :--- | :---: | :---: | :---: | :---: | :---: |")
            
            for q_id in all_queries:
                times = data[sys].get(q_id, [])
                stats = calculate_stats(times)
                
                count = stats['count']
                avg = f"{stats['avg']:.2f}" if stats['avg'] is not None else "N/A"
                median = f"{stats['median']:.2f}" if stats['median'] is not None else "N/A"
                min_val = f"{stats['min']:.2f}" if stats['min'] is not None else "N/A"
                max_val = f"{stats['max']:.2f}" if stats['max'] is not None else "N/A"
                
                md_lines.append(f"| {q_id} | {count} | {avg} | {median} | {min_val} | {max_val} |")
            
            md_lines.append("")
        
        with open(out_path, 'w', encoding='utf-8') as f:
            f.write("\n".join(md_lines))
        print(f"\nReport saved to: {out_path}")
        
        csv_out_path = os.path.join(args.output_dir, f"raw_data_combined_{args.dataset}_{args.dbms}.csv")
        with open(csv_out_path, 'w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['system', 'query_id', 'dbms', 'iteration', 'start_time', 'planning_time', 'execution_time'])
            writer.writerows(raw_records)
        print(f"Raw data saved to: {csv_out_path}")

if __name__ == '__main__':
    main()
