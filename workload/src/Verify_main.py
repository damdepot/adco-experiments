from Database import PostgreDB, DuckDB, MySQLDB
from FileHandler import read_text_file_line_by_line, save_text_file
from LogResults import LogVerifyResults
import time
import os
import queue
import threading
import multiprocessing
import pandas as pd
import sys

class ProgressTracker:
    def __init__(self, dbms, total_baseline, total_rewrite):
        self.lock = threading.Lock()
        self.dbms = dbms
        self.total_baseline = total_baseline
        self.total_rewrite = total_rewrite
        self.done_baseline = 0
        self.done_rewrite = 0
        self.start_time = time.time()
        self.baseline_success = 0
        self.rewrite_passed = 0
        self.rewrite_failed = 0
        self.rewrite_error = 0
        self.rewrite_timeout = 0
        self.accelerated_queries = 0
        self.unverified_queries = 0

    def print_msg(self, msg):
        with self.lock:
            sys.stdout.write(msg + "\n")
            sys.stdout.flush()

    def log_baseline(self, qid, thread_name, elapsed, error=None):
        with self.lock:
            self.done_baseline += 1
            pct = (self.done_baseline / self.total_baseline * 100) if self.total_baseline > 0 else 0
            if error:
                self.print_msg(f"[BASE] [{self.done_baseline}/{self.total_baseline}] ({pct:.1f}%) {thread_name} | Query '{qid}' error: {error}")
            else:
                self.baseline_success += 1
                self.print_msg(f"[BASE] [{self.done_baseline}/{self.total_baseline}] ({pct:.1f}%) {thread_name} | Query '{qid}' executed in {elapsed:.3f}s")

    def log_prep(self, msg):
        self.print_msg(f"[PREP] {msg}")

    def log_rewrite(self, status, qid, vi, elapsed=None, speedup=None, err_msg=None, timeout=None):
        with self.lock:
            self.done_rewrite += 1
            pct = (self.done_rewrite / self.total_rewrite * 100) if self.total_rewrite > 0 else 0
            q_name = f"{qid}-v{vi}"
            if status == "PASS":
                self.rewrite_passed += 1
                self.print_msg(f"[PASS] [{self.done_rewrite}/{self.total_rewrite}] ({pct:.1f}%) Query '{q_name}' VERIFIED in {elapsed:.3f}s (Speedup: {speedup:.2f}x)")
            elif status == "FAIL":
                self.rewrite_failed += 1
                self.print_msg(f"[FAIL] [{self.done_rewrite}/{self.total_rewrite}] ({pct:.1f}%) Query '{q_name}' MISMATCHED result (took {elapsed:.3f}s)")
            elif status == "ERR":
                self.rewrite_error += 1
                self.print_msg(f"[ERR]  [{self.done_rewrite}/{self.total_rewrite}] ({pct:.1f}%) Query '{q_name}' DB Error: {err_msg}")
            elif status == "TIMEOUT":
                self.rewrite_timeout += 1
                self.print_msg(f"[TIMEOUT] [{self.done_rewrite}/{self.total_rewrite}] ({pct:.1f}%) Query '{q_name}' timed out after {timeout}s")

    def summary(self, total_wall_time, num_threads, output_verify, output_select):
        self.print_msg("\n" + "="*60)
        self.print_msg(f" SUMMARY REPORT: {self.dbms}")
        self.print_msg("="*60)
        self.print_msg(f"Threads: {num_threads} | Total Wall Time: {total_wall_time:.3f}s")
        self.print_msg(f"Baseline Queries: {self.baseline_success} successful / {self.total_baseline} total")
        self.print_msg(f"Rewrite Candidates Evaluated: {self.total_rewrite}")
        if self.total_rewrite > 0:
            p_pass = self.rewrite_passed / self.total_rewrite * 100
            p_fail = self.rewrite_failed / self.total_rewrite * 100
            p_err = self.rewrite_error / self.total_rewrite * 100
            p_to = self.rewrite_timeout / self.total_rewrite * 100
        else:
            p_pass = p_fail = p_err = p_to = 0.0

        self.print_msg(f"  - Verified (PASS): {self.rewrite_passed} ({p_pass:.1f}%)")
        self.print_msg(f"  - Mismatch (FAIL): {self.rewrite_failed} ({p_fail:.1f}%)")
        self.print_msg(f"  - Errors (ERR):    {self.rewrite_error} ({p_err:.1f}%)")
        self.print_msg(f"  - Timeouts:        {self.rewrite_timeout} ({p_to:.1f}%)")
        self.print_msg(f"Queries Accelerated: {self.accelerated_queries}")
        self.print_msg(f"Queries Unverified:  {self.unverified_queries}")
        self.print_msg(f"Output Selected: {output_select}")
        self.print_msg(f"Output Verified: {output_verify}")
        self.print_msg("="*60 + "\n")


class VerifyPG(object):
    def __init__(self, workload_path: str, rewrite_path: str, queries, database_name: str, dbms: str,
                 output_path_verify: str, output_path_select: str, verify_log_path: str, threads: int = None):
        self.workload_path = workload_path
        self.rewrite_path = rewrite_path
        self.database_name = database_name
        self.dbms = dbms
        self.output_path_verify = output_path_verify
        self.output_path_select = output_path_select
        self.queries = queries
        self.verify_log_path = verify_log_path
        self.number_threads = threads if (threads is not None and threads > 0) else min(multiprocessing.cpu_count(), 8)

        self.impl_funcs = dict()
        self.connections = dict()
        self.results_lock = threading.Lock()
        self.log = LogVerifyResults()
        self.query_results = dict()
        self.query_verify_results = dict()
        self.query_elapsed_time_results = dict()

        self.tracker = None

    def _worker_main(self):
        while True:
            try:
                query = self.queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                query_fname = f"{self.workload_path}/{query}.sql"
                try:
                    self._run_main_queries(query, query_fname, thread_name, True)
                except Exception as e:
                    if self.tracker:
                        self.tracker.log_baseline(query, thread_name, 0, str(e))
            finally:
                self.queries.task_done()

    def _worker_rewrite(self, queries):
        while True:
            try:
                (query,vi) = queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                try:
                    self._run_rewrite_queries(vi, query, thread_name)
                except Exception as e:
                    if self.tracker:
                        self.tracker.log_rewrite("ERR", query, vi, err_msg=str(e))
            finally:
                queries.task_done()

    def _run_main_queries(self, query, query_fname, thread_name, add_result_or_return):
        query_str = read_text_file_line_by_line(query_fname)
        (pg, conn, cursor) = self.connections[thread_name]
        if add_result_or_return:
            start = time.time()
            res_an = None
            err = None
            try:
                res_an = pg.execute(cursor=cursor, query=query_str)
            except Exception as e:
                err = str(e)
            end = time.time()
            elapsed_time = end - start
            if err is None:
                with self.results_lock:
                    self.query_results[query] = res_an
                    self.query_verify_results[query] = {"verified_queries":[], "error_queries": [], "failed_queries": [], "query_elapsed_time": dict(), "selected_query": None}
                    self.query_elapsed_time_results[query] = elapsed_time
            if self.tracker:
                self.tracker.log_baseline(query, thread_name, elapsed_time, err)
        else:
            elapsed_time = -1
            res_an = None
            try:
                start = time.time()
                res_an = pg.execute(cursor=cursor, query=query_str)
                end = time.time()
                elapsed_time = end - start
            except Exception as e:
                pass

            return elapsed_time, res_an

    def _run_rewrite_queries(self, query, main_query, thread_name):
        query_rewrite_fname = f"{self.rewrite_path}/{main_query}-{query}.sql"
        if os.path.exists(query_rewrite_fname):
            rewrite_elapsed_time, rewrite_result = self._run_main_queries(query=query, query_fname=query_rewrite_fname,
                                                        thread_name=thread_name, add_result_or_return=False)
            
            baseline_elapsed = self.query_elapsed_time_results.get(main_query, 0.001)
            baseline_elapsed = baseline_elapsed if baseline_elapsed > 0 else 0.001
            speedup = baseline_elapsed / rewrite_elapsed_time if rewrite_elapsed_time > 0 else 0.0
            
            if main_query in self.query_results:
                query_result = self.query_results[main_query]
            else:
                query_result = None

            if rewrite_result is not None and rewrite_result == query_result:
                with self.results_lock:
                    self.query_verify_results[main_query]["verified_queries"].append(query)
                    self.query_verify_results[main_query]["query_elapsed_time"][query] = rewrite_elapsed_time

                    query_str = f"{self.impl_funcs.get(main_query, '')} \n {read_text_file_line_by_line(query_rewrite_fname)}"
                    query_rewrite_fname_out = f"{self.output_path_verify}/{main_query}-{query}.sql"
                    save_text_file(query_rewrite_fname_out, query_str)
                if self.tracker:
                    self.tracker.log_rewrite("PASS", main_query, query, elapsed=rewrite_elapsed_time, speedup=speedup)

            elif rewrite_result is None:
                with self.results_lock:
                    if main_query in self.query_verify_results:
                        self.query_verify_results[main_query]["error_queries"].append(query)
                if self.tracker:
                    self.tracker.log_rewrite("ERR", main_query, query, err_msg="Execution Failed")
            else:
                with self.results_lock:
                    if main_query in self.query_verify_results:
                        self.query_verify_results[main_query]["failed_queries"].append(query)
                if self.tracker:
                    self.tracker.log_rewrite("FAIL", main_query, query, elapsed=rewrite_elapsed_time)
        else:
            pass # rewrite file does not exist, do nothing

    def _run_implemented_functions(self, main_query):
        fun_fname = f"{self.rewrite_path}/{main_query}-0.sql"
        if os.path.exists(fun_fname):
            pg = PostgreDB(disable_parallel=True)
            conn, cursor = None, None
            try:
                conn, cursor = pg.connect()
                query_str = read_text_file_line_by_line(fun_fname)
                res_an = pg.execute(cursor=cursor, query=query_str)
                self.impl_funcs[main_query] = query_str + "\n"
                if self.tracker:
                    self.tracker.log_prep(f"Loaded UDF for '{main_query}'")
            except Exception as e:
                if self.tracker:
                    self.tracker.log_prep(f"Failed to load UDF for '{main_query}': {e}")
            finally:
                if conn is not None and cursor is not None:
                    pg.close_connect(conn=conn, cursor=cursor)

    def run(self):
        number_threads = self.number_threads
        total_baseline = self.queries.qsize()
        
        # We start PHASE 1
        print(f"\n--- Starting {self.dbms} Verification ---")
        print(f"Phase 1: Baseline Queries ({total_baseline} total, {number_threads} threads)")
        self.tracker = ProgressTracker(self.dbms, total_baseline, 0)
        start_time_wall = time.time()

        # Create and start threads
        threads = []
        for i in range(number_threads):
            pg = PostgreDB(disable_parallel=True)
            conn, cursor = pg.connect()
            thread_name = f"thread_{i}"
            self.connections[thread_name] = (pg, conn, cursor)
            t = threading.Thread(target=self._worker_main, args=(), name=thread_name)
            t.start()
            threads.append(t)

        # Wait for all tasks in the queue to be processed
        try:
            self.queries.join()
        finally:
            for i, t in enumerate(threads):
                t.join()
                thread_name = f"thread_{i}"
                if thread_name in self.connections:
                    (pg, conn, cursor) = self.connections[thread_name]
                    pg.close_connect(conn=conn, cursor=cursor)
                    
        self.tracker.print_msg(f"Phase 1 completed in {time.time() - start_time_wall:.3f}s. {self.tracker.baseline_success} succeeded.")

        # Phase 2
        self.tracker.print_msg("\nPhase 2: Preparation / Function Setup")
        version_queries = queue.Queue()
        for query in self.query_results.keys():
            self._run_implemented_functions(main_query=query)
            for vi in range(1, 32):
                version_queries.put((query, f"{vi}"))

        total_rewrites = version_queries.qsize()
        self.tracker.total_rewrite = total_rewrites
        self.tracker.print_msg(f"Total candidates queued for rewrite verification: {total_rewrites}")
        
        # Phase 3
        self.tracker.print_msg("\nPhase 3: Rewrite Verification")
        threads = []
        self.connections = dict()
        for i in range(number_threads):
            pg = PostgreDB(disable_parallel=True)
            conn, cursor = pg.connect()
            thread_name = f"thread_{i}"
            self.connections[thread_name] = (pg, conn, cursor)
            t = threading.Thread(target=self._worker_rewrite, args=(version_queries,), name=thread_name)
            t.start()
            threads.append(t)

        # Wait for all tasks in the queue to be processed
        try:
            version_queries.join()
        finally:
            for i, t in enumerate(threads):
                t.join()
                thread_name = f"thread_{i}"
                if thread_name in self.connections:
                    (pg, conn, cursor) = self.connections[thread_name]
                    pg.close_connect(conn=conn, cursor=cursor)

        # Phase 4
        self.tracker.print_msg("\nPhase 4: Selection & Summary Report")
        for query in self.query_results.keys():
                results = self.query_verify_results[query]
                min_time = -1
                selected_version = "-1"
                for qvi in results["query_elapsed_time"].keys():
                    query_time = results["query_elapsed_time"][qvi]
                    if query_time < min_time or min_time == -1:
                        min_time = query_time
                        results["selected_query"] = qvi
                        selected_version = qvi

                if selected_version != "-1" :
                    results["selected_query"] = selected_version
                    self.log.add_results(query_id=query, results=results)
                    query_selected_fname = f"{self.output_path_select}/{query}.sql"
                    query_rewrite_fname = f"{self.rewrite_path}/{query}-{selected_version}.sql"
                    query_str = read_text_file_line_by_line(query_rewrite_fname)
                    save_text_file(query_selected_fname, query_str)
                    
                    b_time = self.query_elapsed_time_results.get(query, 0.001)
                    speedup = b_time / min_time if min_time > 0 else 0.0
                    
                    verified_cnt = len(results.get("verified_queries", []))
                    failed_cnt = len(results.get("failed_queries", []))
                    error_cnt = len(results.get("error_queries", []))
                    
                    self.tracker.print_msg(f"Selected: Query '{query}' -> v{selected_version} | Base: {b_time:.3f}s | Best Rewrite: {min_time:.3f}s | Speedup: {speedup:.2f}x | (Verified: {verified_cnt}, Fail: {failed_cnt}, Err: {error_cnt})")
                    self.tracker.accelerated_queries += 1
                else:
                    self.tracker.print_msg(f"Unverified Status: Query '{query}' had no successful verified rewrites.")
                    self.tracker.unverified_queries += 1

        self.log.save_results(f"{self.verify_log_path}")
        
        total_wall = time.time() - start_time_wall
        self.tracker.summary(total_wall, number_threads, self.output_path_verify, self.output_path_select)


class VerifyDuckDB(object):
    def __init__(self, workload_path: str, rewrite_path: str, queries, database_name: str, dbms: str,
                 output_path_verify: str, output_path_select: str,  verify_log_path: str, threads: int = None):
        self.workload_path = workload_path
        self.rewrite_path = rewrite_path
        self.database_name = database_name
        self.dbms = dbms
        self.output_path_verify = output_path_verify
        self.output_path_select = output_path_select
        self.queries = queries
        self.verify_log_path = verify_log_path
        self.number_threads = threads if (threads is not None and threads > 0) else min(multiprocessing.cpu_count(), 8)

        self.version_queries = queue.Queue()
        self.connections = dict()
        self.results_lock = threading.Lock()
        self.log = LogVerifyResults()
        self.query_results = dict()
        self.query_verify_results = dict()
        self.query_elapsed_time_results = dict()
        self.tracker = None

    def are_dataframes_equal(self, df1: pd.DataFrame, df2: pd.DataFrame) -> bool:
        if df1 is None and df2 is None:
            return True
        if df1 is None or df2 is None:
            return False

        # Check if the shapes match first
        if df1.shape != df2.shape:
            return False

        # Compare the values directly, ignoring column names
        return (df1.values == df2.values).all()


    def _worker_main(self):
        while True:
            try:
                query = self.queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                query_fname = f"{self.workload_path}/{query}.sql"
                try:
                    self._run_main_queries(query, query_fname, thread_name, True)
                except Exception as e:
                    if self.tracker:
                        self.tracker.log_baseline(query, thread_name, 0, str(e))
            finally:
                self.queries.task_done()

    def _worker_rewrite(self):
        while True:
            try:
                (query,vi) = self.version_queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                if query not in self.query_results:
                    continue
                query_result = self.query_results[query]
                query_elapsed_time = self.query_elapsed_time_results.get(query, 0.0) * 3 + 20
                try:
                    rewrite_elapsed_time, rewrite_result = self.run_with_timeout(self._run_rewrite_queries, args=(f"{vi}", query, thread_name), timeout=query_elapsed_time)
                    
                    baseline_elapsed = self.query_elapsed_time_results.get(query, 0.001)
                    baseline_elapsed = baseline_elapsed if baseline_elapsed > 0 else 0.001
                    speedup = baseline_elapsed / rewrite_elapsed_time if (rewrite_elapsed_time is not None and rewrite_elapsed_time > 0) else 0.0
                    
                    if self.are_dataframes_equal(rewrite_result, query_result):
                        with self.results_lock:
                            self.query_verify_results[query]["verified_queries"].append(f"{vi}")
                            self.query_verify_results[query]["query_elapsed_time"][f"{vi}"] = rewrite_elapsed_time

                        query_rewrite_fname = f"{self.rewrite_path}/{query}-{vi}.sql"
                        query_str = read_text_file_line_by_line(query_rewrite_fname)

                        query_rewrite_fname_out = f"{self.output_path_verify}/{query}-{vi}.sql"
                        save_text_file(query_rewrite_fname_out, query_str)
                        if self.tracker:
                            self.tracker.log_rewrite("PASS", query, vi, elapsed=rewrite_elapsed_time, speedup=speedup)


                    elif rewrite_result is None:
                        with self.results_lock:
                            self.query_verify_results[query]["error_queries"].append(f"{vi}")
                        if self.tracker:
                            self.tracker.log_rewrite("ERR", query, vi, err_msg="Result is None")
                    else:
                        with self.results_lock:
                            self.query_verify_results[query]["failed_queries"].append(f"{vi}")
                        if self.tracker:
                            self.tracker.log_rewrite("FAIL", query, vi, elapsed=rewrite_elapsed_time)
                except TimeoutError as e:
                    if self.tracker:
                        self.tracker.log_rewrite("TIMEOUT", query, vi, timeout=query_elapsed_time)
                except Exception as e:
                    if self.tracker:
                        self.tracker.log_rewrite("ERR", query, vi, err_msg=str(e))
            finally:
                self.version_queries.task_done()

    def run_with_timeout(self, func, args=(), kwargs={}, timeout=5):
        def wrapper(queue, *args, **kwargs):
            try:
                result = func(*args, **kwargs)
                queue.put(('result', result))
            except Exception as e:
                queue.put(('error', e))

        q = multiprocessing.Queue()
        process = multiprocessing.Process(target=wrapper, args=(q, *args), kwargs=kwargs)
        process.start()
        process.join(timeout)

        if process.is_alive():
            process.terminate()
            process.join()
            raise TimeoutError(f"Function call exceeded time limit of {timeout} seconds")

        if not q.empty():
            status, value = q.get()
            if status == 'result':
                return value
            else:
                raise value
        else:
            raise RuntimeError("Function ended but did not return any result")

    def _run_main_queries(self, query, query_fname, thread_name, add_result_or_return):
        query_str = read_text_file_line_by_line(query_fname)
        (ddb, conn) = self.connections[thread_name]
        if add_result_or_return:
            start = time.time()
            err = None
            res_an = None
            try:
                res_an = ddb.execute(conn=conn, query=query_str)
            except Exception as e:
                err = str(e)
            end = time.time()
            elapsed_time = end - start
            if err is None:
                with self.results_lock:
                    self.query_elapsed_time_results[query] = elapsed_time
                    self.query_results[query] = res_an
                    self.query_verify_results[query] = {"verified_queries":[], "error_queries": [], "failed_queries": [], "query_elapsed_time": dict(), "selected_query": None}
            if self.tracker:
                self.tracker.log_baseline(query, thread_name, elapsed_time, err)
        else:
            elapsed_time = -1
            res_an = None
            try:
                start = time.time()
                res_an = ddb.execute(conn=conn, query=query_str)
                end = time.time()
                elapsed_time = end - start
            except Exception as e:
                pass
            return elapsed_time, res_an

    def _run_rewrite_queries(self, query, main_query, thread_name):
        query_rewrite_fname = f"{self.rewrite_path}/{main_query}-{query}.sql"
        if os.path.exists(query_rewrite_fname):
            rewrite_elapsed_time, rewrite_result = self._run_main_queries(query=query, query_fname=query_rewrite_fname,
                                                        add_result_or_return=False, thread_name=thread_name)
            return rewrite_elapsed_time, rewrite_result
        else:
            return None, None

    def run(self):
        number_threads = self.number_threads
        total_baseline = self.queries.qsize()

        # We start PHASE 1
        print(f"\n--- Starting {self.dbms} Verification ---")
        print(f"Phase 1: Baseline Queries ({total_baseline} total, {number_threads} threads)")
        self.tracker = ProgressTracker(self.dbms, total_baseline, 0)
        start_time_wall = time.time()

        # Create and start threads
        threads = []
        for i in range(number_threads):
            ddb = DuckDB()
            conn = ddb.connect()
            thread_name = f"thread_{i}"
            self.connections[thread_name] = (ddb, conn)
            t = threading.Thread(target=self._worker_main, args=(), name=thread_name)
            t.start()
            threads.append(t)

        # Wait for all tasks in the queue to be processed
        self.queries.join()
        for i, t in enumerate(threads):
            t.join()
            thread_name = f"thread_{i}"
            if thread_name in self.connections:
                (ddb, conn) = self.connections[thread_name]
                ddb.close_connect(conn=conn)
                
        self.tracker.print_msg(f"Phase 1 completed in {time.time() - start_time_wall:.3f}s. {self.tracker.baseline_success} succeeded.")

        # Phase 2
        self.tracker.print_msg("\nPhase 2: Preparation / Function Setup")
        for query in self.query_results.keys():
            for vi in range(1, 32):
                self.version_queries.put((query, f"{vi}"))
                
        total_rewrites = self.version_queries.qsize()
        self.tracker.total_rewrite = total_rewrites
        self.tracker.print_msg(f"Total candidates queued for rewrite verification: {total_rewrites}")

        # Phase 3
        self.tracker.print_msg("\nPhase 3: Rewrite Verification")
        threads = []
        self.connections = dict()
        for i in range(number_threads):
            ddb = DuckDB()
            conn = ddb.connect()
            thread_name = f"thread_{i}"
            self.connections[thread_name] = (ddb, conn)
            t = threading.Thread(target=self._worker_rewrite, args=(), name=thread_name)
            t.start()
            threads.append(t)

        # Wait for all tasks in the queue to be processed
        self.version_queries.join()

        for i, t in enumerate(threads):
            t.join()
            thread_name = f"thread_{i}"
            if thread_name in self.connections:
                (ddb, conn) = self.connections[thread_name]
                ddb.close_connect(conn=conn)

        # Phase 4
        self.tracker.print_msg("\nPhase 4: Selection & Summary Report")
        for query in self.query_results.keys():
            results = self.query_verify_results[query]
            min_time = -1
            selected_version = "-1"
            for qvi in results["query_elapsed_time"].keys():
                query_time = results["query_elapsed_time"][qvi]
                if query_time < min_time or min_time == -1:
                    min_time = query_time
                    results["selected_query"] = qvi
                    selected_version = qvi

            if selected_version != "-1" :
                results["selected_query"] = selected_version
                self.log.add_results(query_id=query, results=results)
                query_selected_fname = f"{self.output_path_select}/{query}.sql"
                query_rewrite_fname = f"{self.rewrite_path}/{query}-{selected_version}.sql"
                query_str = read_text_file_line_by_line(query_rewrite_fname)
                save_text_file(query_selected_fname, query_str)
                
                b_time = self.query_elapsed_time_results.get(query, 0.001)
                speedup = b_time / min_time if min_time > 0 else 0.0
                
                verified_cnt = len(results.get("verified_queries", []))
                failed_cnt = len(results.get("failed_queries", []))
                error_cnt = len(results.get("error_queries", []))
                
                self.tracker.print_msg(f"Selected: Query '{query}' -> v{selected_version} | Base: {b_time:.3f}s | Best Rewrite: {min_time:.3f}s | Speedup: {speedup:.2f}x | (Verified: {verified_cnt}, Fail: {failed_cnt}, Err: {error_cnt})")
                self.tracker.accelerated_queries += 1
            else:
                self.tracker.print_msg(f"Unverified Status: Query '{query}' had no successful verified rewrites.")
                self.tracker.unverified_queries += 1

        self.log.save_results(f"{self.verify_log_path}")
        
        total_wall = time.time() - start_time_wall
        self.tracker.summary(total_wall, number_threads, self.output_path_verify, self.output_path_select)


class VerifyMySQL(object):
    def __init__(self, workload_path: str, rewrite_path: str, queries, database_name: str, dbms: str,
                 output_path_verify: str, output_path_select: str,  verify_log_path: str, threads: int = None):
        self.workload_path = workload_path
        self.rewrite_path = rewrite_path
        self.database_name = database_name
        self.dbms = dbms
        self.output_path_verify = output_path_verify
        self.output_path_select = output_path_select
        self.queries = queries
        self.verify_log_path = verify_log_path
        self.number_threads = threads if (threads is not None and threads > 0) else min(multiprocessing.cpu_count(), 8)

        self.connections = dict()
        self.version_queries = queue.Queue()
        self.results_lock = threading.Lock()
        self.log = LogVerifyResults()
        self.query_results = dict()
        self.query_verify_results = dict()
        self.query_elapsed_time_results = dict()
        self.tracker = None


    def _worker_main(self):
        while True:
            try:
                query = self.queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                query_fname = f"{self.workload_path}/{query}.sql"
                try:
                    self._run_main_queries(query, query_fname, thread_name, True)
                except Exception as e:
                    if self.tracker:
                        self.tracker.log_baseline(query, thread_name, 0, str(e))
            finally:
                self.queries.task_done()

    def _worker_rewrite(self):
        while True:
            try:
                (query,vi) = self.version_queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                if query not in self.query_results:
                    continue
                query_result = self.query_results[query]

                try:
                    rewrite_elapsed_time, rewrite_result = self._run_rewrite_queries(f"{vi}",query, thread_name)
                    baseline_elapsed = self.query_elapsed_time_results.get(query, 0.001)
                    baseline_elapsed = baseline_elapsed if baseline_elapsed > 0 else 0.001
                    speedup = baseline_elapsed / rewrite_elapsed_time if (rewrite_elapsed_time is not None and rewrite_elapsed_time > 0) else 0.0
                    
                    if rewrite_result == query_result:
                        with self.results_lock:
                            self.query_verify_results[query]["verified_queries"].append(f"{vi}")
                            self.query_verify_results[query]["query_elapsed_time"][f"{vi}"] = rewrite_elapsed_time

                        query_rewrite_fname = f"{self.rewrite_path}/{query}-{vi}.sql"
                        query_str = read_text_file_line_by_line(query_rewrite_fname)

                        query_rewrite_fname_out = f"{self.output_path_verify}/{query}-{vi}.sql"
                        save_text_file(query_rewrite_fname_out, query_str)
                        if self.tracker:
                            self.tracker.log_rewrite("PASS", query, vi, elapsed=rewrite_elapsed_time, speedup=speedup)


                    elif rewrite_result is None:
                        with self.results_lock:
                            self.query_verify_results[query]["error_queries"].append(f"{vi}")
                        if self.tracker:
                            self.tracker.log_rewrite("ERR", query, vi, err_msg="Result is None")
                    else:
                        with self.results_lock:
                            self.query_verify_results[query]["failed_queries"].append(f"{vi}")
                        if self.tracker:
                            self.tracker.log_rewrite("FAIL", query, vi, elapsed=rewrite_elapsed_time)
                except Exception as e:
                    if self.tracker:
                        self.tracker.log_rewrite("ERR", query, vi, err_msg=str(e))
            finally:
                self.version_queries.task_done()

    def _run_main_queries(self, query, query_fname, thread_name, add_result_or_return):
        query_str = read_text_file_line_by_line(query_fname)
        (mysql, conn, cursor) = self.connections[thread_name]
        if add_result_or_return:
            start = time.time()
            err = None
            res_an = None
            try:
                res_an = mysql.execute(cursor=cursor, query=query_str)
            except Exception as e:
                err = str(e)
            end = time.time()
            elapsed_time = end - start
            if err is None:
                with self.results_lock:
                    self.query_elapsed_time_results[query] = elapsed_time
                    self.query_results[query] = res_an
                    self.query_verify_results[query] = {"verified_queries":[], "error_queries": [], "failed_queries": [], "query_elapsed_time": dict(), "selected_query": None}
            if self.tracker:
                self.tracker.log_baseline(query, thread_name, elapsed_time, err)
        else:
            elapsed_time = -1
            res_an = None
            try:
                start = time.time()
                res_an = mysql.execute(cursor=cursor, query=query_str)
                end = time.time()
                elapsed_time = end - start
            except Exception as e:
                pass
            return elapsed_time, res_an

    def _run_rewrite_queries(self, query, main_query, thread_name):
        query_rewrite_fname = f"{self.rewrite_path}/{main_query}-{query}.sql"
        if os.path.exists(query_rewrite_fname):
            rewrite_elapsed_time, rewrite_result = self._run_main_queries(query=query, query_fname=query_rewrite_fname,
                                                        add_result_or_return=False, thread_name=thread_name)
            return rewrite_elapsed_time, rewrite_result
        else:
            return None, None

    def run(self):
        number_threads = self.number_threads
        total_baseline = self.queries.qsize()

        # We start PHASE 1
        print(f"\n--- Starting {self.dbms} Verification ---")
        print(f"Phase 1: Baseline Queries ({total_baseline} total, {number_threads} threads)")
        self.tracker = ProgressTracker(self.dbms, total_baseline, 0)
        start_time_wall = time.time()

        # Create and start threads
        threads = []
        for i in range(number_threads):
            mysql = MySQLDB()
            conn, cursor = mysql.connect()
            thread_name = f"thread_{i}"
            self.connections[thread_name] = (mysql, conn, cursor)
            t = threading.Thread(target=self._worker_main, args=(), name=thread_name)
            t.start()
            threads.append(t)

        # Wait for all tasks in the queue to be processed
        try:
            self.queries.join()
        finally:
            for i, t in enumerate(threads):
                t.join()
                thread_name = f"thread_{i}"
                if thread_name in self.connections:
                    (mysql, conn, cursor) = self.connections[thread_name]
                    mysql.close_connect(conn=conn, cursor=cursor)

        self.tracker.print_msg(f"Phase 1 completed in {time.time() - start_time_wall:.3f}s. {self.tracker.baseline_success} succeeded.")
        
        # Phase 2
        self.tracker.print_msg("\nPhase 2: Preparation / Function Setup")
        for query in self.query_results.keys():
            for vi in range(1, 32):
                self.version_queries.put((query, f"{vi}"))
                
        total_rewrites = self.version_queries.qsize()
        self.tracker.total_rewrite = total_rewrites
        self.tracker.print_msg(f"Total candidates queued for rewrite verification: {total_rewrites}")

        # Phase 3
        self.tracker.print_msg("\nPhase 3: Rewrite Verification")
        threads = []
        self.connections = dict()
        for i in range(number_threads):
            mysql = MySQLDB()
            conn, cursor = mysql.connect()
            thread_name = f"thread_{i}"
            self.connections[thread_name] = (mysql, conn, cursor)
            t = threading.Thread(target=self._worker_rewrite,  name=thread_name)
            t.start()
            threads.append(t)

        # Wait for all tasks in the queue to be processed
        try:
            self.version_queries.join()
        finally:
            for i, t in enumerate(threads):
                t.join()
                thread_name = f"thread_{i}"
                if thread_name in self.connections:
                    (mysql, conn, cursor) = self.connections[thread_name]
                    mysql.close_connect(conn=conn, cursor=cursor)

        # Phase 4
        self.tracker.print_msg("\nPhase 4: Selection & Summary Report")
        for query in self.query_results.keys():
            results = self.query_verify_results[query]
            min_time = -1
            selected_version = "-1"
            for qvi in results["query_elapsed_time"].keys():
                query_time = results["query_elapsed_time"][qvi]
                if query_time < min_time or min_time == -1:
                    min_time = query_time
                    results["selected_query"] = qvi
                    selected_version = qvi

            if selected_version != "-1" :
                results["selected_query"] = selected_version
                self.log.add_results(query_id=query, results=results)
                query_selected_fname = f"{self.output_path_select}/{query}.sql"
                query_rewrite_fname = f"{self.rewrite_path}/{query}-{selected_version}.sql"
                query_str = read_text_file_line_by_line(query_rewrite_fname)
                save_text_file(query_selected_fname, query_str)
                
                b_time = self.query_elapsed_time_results.get(query, 0.001)
                speedup = b_time / min_time if min_time > 0 else 0.0
                
                verified_cnt = len(results.get("verified_queries", []))
                failed_cnt = len(results.get("failed_queries", []))
                error_cnt = len(results.get("error_queries", []))
                
                self.tracker.print_msg(f"Selected: Query '{query}' -> v{selected_version} | Base: {b_time:.3f}s | Best Rewrite: {min_time:.3f}s | Speedup: {speedup:.2f}x | (Verified: {verified_cnt}, Fail: {failed_cnt}, Err: {error_cnt})")
                self.tracker.accelerated_queries += 1
            else:
                self.tracker.print_msg(f"Unverified Status: Query '{query}' had no successful verified rewrites.")
                self.tracker.unverified_queries += 1

        self.log.save_results(f"{self.verify_log_path}")
        
        total_wall = time.time() - start_time_wall
        self.tracker.summary(total_wall, number_threads, self.output_path_verify, self.output_path_select)

