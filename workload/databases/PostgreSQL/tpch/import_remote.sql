-- Run psql from the directory containing the .tbl files (paths are relative to it),
-- e.g.: cd data/tpch && psql -d tpch -f .../import_remote.sql
\copy "region" ("r_regionkey", "r_name", "r_comment") FROM 'region.tbl' WITH (FORMAT csv, DELIMITER '|');

\copy "nation" ("n_nationkey", "n_name", "n_regionkey", "n_comment") FROM 'nation.tbl' WITH (FORMAT csv, DELIMITER '|');

\copy "customer" ("c_custkey", "c_name", "c_address", "c_nationkey", "c_phone", "c_acctbal", "c_mktsegment", "c_comment") FROM 'customer.tbl' WITH (FORMAT csv, DELIMITER '|');

\copy "supplier" ("s_suppkey", "s_name", "s_address", "s_nationkey", "s_phone", "s_acctbal", "s_comment") FROM 'supplier.tbl' WITH (FORMAT csv, DELIMITER '|');

\copy "part" ("p_partkey", "p_name", "p_mfgr", "p_brand", "p_type", "p_size", "p_container", "p_retailprice", "p_comment") FROM 'part.tbl' WITH (FORMAT csv, DELIMITER '|');

\copy "partsupp" ("ps_partkey", "ps_suppkey", "ps_availqty", "ps_supplycost", "ps_comment") FROM 'partsupp.tbl' WITH (FORMAT csv, DELIMITER '|');

\copy "orders" ("o_orderkey", "o_custkey", "o_orderstatus", "o_totalprice", "o_orderdate", "o_orderpriority", "o_clerk", "o_shippriority", "o_comment") FROM 'orders.tbl' WITH (FORMAT csv, DELIMITER '|');

\copy "lineitem" ("l_orderkey", "l_partkey", "l_suppkey", "l_linenumber", "l_quantity", "l_extendedprice", "l_discount", "l_tax", "l_returnflag", "l_linestatus", "l_shipdate", "l_commitdate", "l_receiptdate", "l_shipinstruct", "l_shipmode", "l_comment") FROM 'lineitem.tbl' WITH (FORMAT csv, DELIMITER '|');
