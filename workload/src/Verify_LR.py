from Database import PostgreDB, DuckDB, MySQLDB
from FileHandler import read_text_file_line_by_line, save_text_file
from LogResults import LogVerifyResults
import time
import os
import queue
import threading
import multiprocessing
import pandas as pd


class VerifyPG(object):
    def __init__(self, workload_path: str, rewrite_path: str, queries, database_name: str, dbms: str,
                 output_path_verify: str, verify_log_path: str, threads: int = None, verbose: bool = False):
        self.workload_path = workload_path
        self.rewrite_path = rewrite_path
        self.database_name = database_name
        self.dbms = dbms
        self.output_path_verify = output_path_verify
        self.queries = queries
        self.verify_log_path = verify_log_path
        self.number_threads = threads if (threads is not None and threads > 0) else min(multiprocessing.cpu_count(), 8)
        self.verbose = verbose

        self.impl_funcs = dict()
        self.connections = dict()
        self.results_lock = threading.Lock()
        self.log = LogVerifyResults()
        self.query_results = dict()
        self.query_verify_results = dict()
        self.timeout_queries = []

    def _debug(self, msg):
        if self.verbose:
            print(f"[DEBUG] {msg}")

    def _save_timeout_queries(self):
        if self.timeout_queries:
            with open(f"{self.verify_log_path}.timeouts", "a") as f:
                for q in sorted(self.timeout_queries):
                    f.write(f"{q}\n")
            print(f"[WARN] {len(self.timeout_queries)} main queries timed out: {sorted(self.timeout_queries)}")

    # Worker function for threads
    def _worker_main(self):
        while True:
            try:
                query = self.queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                query_fname = f"{self.workload_path}/{query}.sql"
                self._debug(f"Main {query} is running...")
                self._run_main_queries(query, query_fname, thread_name, True)
            except Exception as e:
                print(f"[ERROR] Main query {query} skipped: {e}")
                with self.results_lock:
                    self.timeout_queries.append(query)
                    self.query_verify_results[query] = {"verified_queries":[], "error_queries": [query],
                                                        "failed_queries": [], "query_elapsed_time": dict(),
                                                        "selected_query": None}
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
                self._debug(f"Rewrite {query} is verifying...")
                self._run_rewrite_queries(vi, query, thread_name)
            finally:
                queries.task_done()


    def _run_main_queries(self, query, query_fname, thread_name, add_result_or_return):
        query_str = read_text_file_line_by_line(query_fname)
        (pg, conn, cursor) = self.connections[thread_name]
        if add_result_or_return:
            res_an = pg.execute(cursor=cursor, query=query_str)
            with self.results_lock:
                self.query_results[query] = res_an
                self.query_verify_results[query] = {"verified_queries":[], "error_queries": [], "failed_queries": [], "query_elapsed_time": dict(), "selected_query": None}
        else:
            elapsed_time = -1
            res_an = None
            try:
                start = time.time()
                res_an = pg.execute(cursor=cursor, query=query_str)
                end = time.time()
                elapsed_time = end - start
            except:
                pass

            return elapsed_time, res_an

    def _run_rewrite_queries(self, query, main_query, thread_name):
        query_rewrite_fname = f"{self.rewrite_path}/{main_query}.sql"
        if os.path.exists(query_rewrite_fname):
            rewrite_elapsed_time, rewrite_result = self._run_main_queries(query=query, query_fname=query_rewrite_fname,
                                                        thread_name=thread_name, add_result_or_return=False)
            query_result = self.query_results[main_query]

            if rewrite_result == query_result:
                with self.results_lock:
                    self.query_verify_results[main_query]["verified_queries"].append(query)
                    self.query_verify_results[main_query]["query_elapsed_time"][query] = rewrite_elapsed_time

                    query_str =read_text_file_line_by_line(query_rewrite_fname)
                    query_rewrite_fname = f"{self.output_path_verify}/{main_query}.sql"
                    save_text_file(query_rewrite_fname, query_str)

            elif rewrite_result is None:
                self._debug(f"{main_query}: execution error (result is None)")
                with self.results_lock:
                    self.query_verify_results[main_query]["error_queries"].append(query)
            else:
                self._debug(f"{main_query}: result mismatch — expected {query_result[:2]}, got {rewrite_result[:2]}")
                with self.results_lock:
                    self.query_verify_results[main_query]["failed_queries"].append(query)
        else:
            self._debug(f"File not found: {query_rewrite_fname}")

    def run(self):
        number_threads = self.number_threads

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
                (pg, conn, cursor) = self.connections[thread_name]
                pg.close_connect(conn=conn, cursor=cursor)

        self._save_timeout_queries()

        version_queries = queue.Queue()
        for query in self.query_results.keys():
            version_queries.put((query, ""))

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
                (pg, conn, cursor) = self.connections[thread_name]
                pg.close_connect(conn=conn, cursor=cursor)
        self._debug("All rewrite threads joined.")
        for query_id, results in self.query_verify_results.items():
            self.log.add_results(query_id, results)
        self.log.save_results(self.verify_log_path)


class VerifyMySQL(object):
    def __init__(self, workload_path: str, rewrite_path: str, queries, database_name: str, dbms: str,
                 output_path_verify: str,  verify_log_path: str, threads: int = None, verbose: bool = False):
        self.workload_path = workload_path
        self.rewrite_path = rewrite_path
        self.database_name = database_name
        self.dbms = dbms
        self.output_path_verify = output_path_verify
        self.queries = queries
        self.verify_log_path = verify_log_path
        self.number_threads = threads if (threads is not None and threads > 0) else min(multiprocessing.cpu_count(), 8)
        self.verbose = verbose

        self.connections = dict()
        self.version_queries = queue.Queue()
        self.results_lock = threading.Lock()
        self.log = LogVerifyResults()
        self.query_results = dict()
        self.query_verify_results = dict()
        self.query_elapsed_time_results = dict()
        self.timeout_queries = []

    def _debug(self, msg):
        if self.verbose:
            print(f"[DEBUG] {msg}")

    def _save_timeout_queries(self):
        if self.timeout_queries:
            with open(f"{self.verify_log_path}.timeouts", "a") as f:
                for q in sorted(self.timeout_queries):
                    f.write(f"{q}\n")
            print(f"[WARN] {len(self.timeout_queries)} main queries timed out: {sorted(self.timeout_queries)}")

    def _worker_main(self):
        while True:
            try:
                query = self.queries.get(timeout=1)
            except queue.Empty:
                break

            try:
                thread_name = threading.current_thread().name
                query_fname = f"{self.workload_path}/{query}.sql"
                self._debug(f"{query} is verifying...")
                self._run_main_queries(query, query_fname, thread_name, True)
            except Exception as e:
                print(f"[ERROR] Main query {query} skipped: {e}")
                with self.results_lock:
                    self.timeout_queries.append(query)
                    self.query_verify_results[query] = {"verified_queries":[], "error_queries": [query],
                                                        "failed_queries": [], "query_elapsed_time": dict(),
                                                        "selected_query": None}
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
                self._debug(f"{query}-{vi} is verifying...")
                query_result = self.query_results[query]
                rewrite_elapsed_time, rewrite_result = self._run_rewrite_queries(f"{vi}",query, thread_name)
                if rewrite_result == query_result:
                    self.query_verify_results[query]["verified_queries"].append(f"{vi}")
                    self.query_verify_results[query]["query_elapsed_time"][f"{vi}"] = rewrite_elapsed_time

                    query_rewrite_fname = f"{self.rewrite_path}/{query}.sql"
                    query_str = read_text_file_line_by_line(query_rewrite_fname)

                    query_rewrite_fname = f"{self.output_path_verify}/{query}.sql"
                    save_text_file(query_rewrite_fname, query_str)


                elif rewrite_result is None:
                    self.query_verify_results[query]["error_queries"].append(f"{vi}")
                else:
                    self.query_verify_results[query]["failed_queries"].append(f"{vi}")
            except TimeoutError as e:
                print(f"Timeout {query}: {vi}")
            finally:
                self.version_queries.task_done()


    def _run_main_queries(self, query, query_fname, thread_name, add_result_or_return):
        query_str = read_text_file_line_by_line(query_fname)
        (mysql, conn, cursor) = self.connections[thread_name]
        if add_result_or_return:
            start = time.time()
            res_an = mysql.execute(cursor=cursor, query=query_str)
            end = time.time()
            elapsed_time = end - start
            self.query_elapsed_time_results[query] = elapsed_time
            self.query_results[query] = res_an
            self.query_verify_results[query] = {"verified_queries":[], "error_queries": [], "failed_queries": [], "query_elapsed_time": dict(), "selected_query": None}
        else:
            elapsed_time = -1
            res_an = None
            try:
                start = time.time()
                res_an = mysql.execute(cursor=cursor, query=query_str)
                end = time.time()
                elapsed_time = end - start
            except:
                pass
            return elapsed_time, res_an

    def _run_rewrite_queries(self, query, main_query, thread_name):
        query_rewrite_fname = f"{self.rewrite_path}/{main_query}.sql"
        if os.path.exists(query_rewrite_fname):
            rewrite_elapsed_time, rewrite_result = self._run_main_queries(query=query, query_fname=query_rewrite_fname,
                                                        add_result_or_return=False, thread_name=thread_name)
            return rewrite_elapsed_time, rewrite_result
        else:
            return None, None

    def run(self):
        number_threads = self.number_threads

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
                (mysql, conn, cursor) = self.connections[thread_name]
                mysql.close_connect(conn=conn, cursor=cursor)

        self._save_timeout_queries()

        for query in self.query_results.keys():
            self.version_queries.put((query, ""))

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
                (mysql, conn, cursor) = self.connections[thread_name]
                mysql.close_connect(conn=conn, cursor=cursor)
        self._debug("All rewrite threads joined.")
        for query_id, results in self.query_verify_results.items():
            self.log.add_results(query_id, results)
        self.log.save_results(self.verify_log_path)
