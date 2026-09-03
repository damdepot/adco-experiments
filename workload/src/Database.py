import os
import psycopg2
import duckdb
import mysql.connector

class PostgreDB (object):
    def __init__(self, disable_parallel: bool = False):
        self.disable_parallel = disable_parallel or (os.environ.get("PG_DISABLE_PARALLEL", "0").lower() in ("1", "true", "yes"))

    def connect(self):
        from Config import _dataset_name, _pgsql_user, _pgsql_password, _pgsql_host, _pgsql_port
        kwargs = {
            "database": _dataset_name,
            "user": _pgsql_user,
            "password": _pgsql_password,
            "host": _pgsql_host,
            "port": _pgsql_port,
            "connect_timeout": 15,
        }
        
        options = []
        if self.disable_parallel:
            options.append("max_parallel_workers_per_gather=0")
            
        stmt_timeout = int(os.environ.get("PG_STATEMENT_TIMEOUT", "180000"))
        if stmt_timeout > 0:
            options.append(f"statement_timeout={stmt_timeout}")
            
        if options:
            kwargs["options"] = "-c " + " -c ".join(options)
            
        conn = psycopg2.connect(**kwargs)
        conn.autocommit = True
        return conn, conn.cursor()

    def close_connect(self, conn, cursor):
        try:
            if cursor is not None:
                cursor.close()
        finally:
            if conn is not None:
                conn.close()


    def execute(self, cursor, query):
        cursor.execute(query)
        if cursor.description is not None:
            return cursor.fetchall()
        return None


class MySQLDB (object):
    def __init__(self, *args, **kwargs):
        pass

    def connect(self):
        from Config import _dataset_name, _mysql_port, _mysql_user, _mysql_password, _mysql_host
        conn = mysql.connector.connect(
            host=_mysql_host,  # e.g., 'localhost' or IP address
            user=_mysql_user,  # your MySQL username
            password=_mysql_password,  # your MySQL password
            database=_dataset_name,  # the database you want to use
            connection_timeout=15
        )
        return conn, conn.cursor()

    def close_connect(self, conn, cursor):
        try:
            if cursor is not None:
                cursor.close()
        finally:
            if conn is not None:
                conn.close()


    def execute(self, cursor, query):
        cursor.execute(query)
        if cursor.description is not None:
            return cursor.fetchall()
        return None

class DuckDB:
    def __init__(self, *args, **kwargs):
        pass

    def connect(self, threads: int=-1):
        from Config import _dataset_name, _database_path
        if threads == -1:
            conn = duckdb.connect(f"{_database_path}/{_dataset_name}")  # ,config = {'threads': 1}
        else:
            conn = duckdb.connect(f"{_database_path}/{_dataset_name}", config = {'threads': threads})
        return conn

    def close_connect(self, conn):
        if conn is not None:
            conn.close()


    def execute(self, conn, query):
        result = conn.execute(query).fetchdf()
        return result