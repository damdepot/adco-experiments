import sys
import traceback
from argparse import ArgumentParser
from Config import load_config
from RunWorkload import WorkloadPG, WorkloadDuckDB, WorkloadMySQL

def parse_arguments():
    parser = ArgumentParser()
    parser.add_argument('--workload-path', type=str, default="/tmp/")
    parser.add_argument('--database-name', type=str, default="test")
    parser.add_argument('--database-path', type=str, default="test.duckdb")
    parser.add_argument('--dbms', type=str, default="postgresql")
    parser.add_argument('--iterations', type=int, default=5)
    parser.add_argument('--threads', type=int, default=None)
    parser.add_argument('--query-log-path', type=str, default="/tmp/")
    parser.add_argument('--output-path', type=str, default="/tmp/output.csv")

    args = parser.parse_args()
    return args


if __name__ == '__main__':
    try:
        args = parse_arguments()
        print(f"[main] args: workload_path={args.workload_path} database_name={args.database_name} "
              f"database_path={args.database_path} dbms={args.dbms} iterations={args.iterations} "
              f"threads={args.threads} query_log_path={args.query_log_path} output_path={args.output_path}")

        workload_dbms = None
        if args.dbms.lower() == "postgresql":
            workload_dbms = WorkloadPG

        elif args.dbms.lower() == "duckdb":
            workload_dbms = WorkloadDuckDB

        elif args.dbms.lower() == "mysql":
            workload_dbms = WorkloadMySQL
        else:
            raise ValueError(f"Unsupported dbms '{args.dbms}'")
        print(f"[main] dbms class: {workload_dbms.__name__}")

        print("[main] loading config...")
        load_config(dbms=args.dbms, dataset_name=args.database_name, workload_path=args.workload_path, database_path=args.database_path)
        from Config import _work_load
        print(f"[main] queued {_work_load.qsize()} queries")

        wl = workload_dbms(workload_path=args.workload_path, queries=_work_load, database_name=args.database_name,
                          dbms=args.dbms, query_log_path=args.query_log_path, output_path=args.output_path, threads=args.threads)
        print(f"[main] workload initialized with {wl.threads} threads; starting run...")
        wl.run(iteration=args.iterations)
        print(f"[main] run finished; results saved to {args.output_path}-{args.iterations}.dat")
    except Exception as e:
        print(f"[main] FAILED: {type(e).__name__}: {e}", file=sys.stderr)
        traceback.print_exc()
        sys.exit(1)
