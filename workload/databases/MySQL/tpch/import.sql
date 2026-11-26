LOAD DATA LOCAL INFILE 'region.tbl' INTO TABLE region FIELDS TERMINATED BY '|'
(r_regionkey, r_name, r_comment);

LOAD DATA LOCAL INFILE 'nation.tbl' INTO TABLE nation FIELDS TERMINATED BY '|'
(n_nationkey, n_name, n_regionkey, n_comment);

LOAD DATA LOCAL INFILE 'customer.tbl' INTO TABLE customer FIELDS TERMINATED BY '|'
(c_custkey, c_name, c_address, c_nationkey, c_phone, c_acctbal, c_mktsegment, c_comment);

LOAD DATA LOCAL INFILE 'supplier.tbl' INTO TABLE supplier FIELDS TERMINATED BY '|'
(s_suppkey, s_name, s_address, s_nationkey, s_phone, s_acctbal, s_comment);

LOAD DATA LOCAL INFILE 'part.tbl' INTO TABLE part FIELDS TERMINATED BY '|'
(p_partkey, p_name, p_mfgr, p_brand, p_type, p_size, p_container, p_retailprice, p_comment);

LOAD DATA LOCAL INFILE 'partsupp.tbl' INTO TABLE partsupp FIELDS TERMINATED BY '|'
(ps_partkey, ps_suppkey, ps_availqty, ps_supplycost, ps_comment);

LOAD DATA LOCAL INFILE 'orders.tbl' INTO TABLE orders FIELDS TERMINATED BY '|'
(o_orderkey, o_custkey, o_orderstatus, o_totalprice, o_orderdate, o_orderpriority, o_clerk, o_shippriority, o_comment);

LOAD DATA LOCAL INFILE 'lineitem.tbl' INTO TABLE lineitem FIELDS TERMINATED BY '|'
(l_orderkey, l_partkey, l_suppkey, l_linenumber, l_quantity, l_extendedprice, l_discount, l_tax, l_returnflag, l_linestatus, l_shipdate, l_commitdate, l_receiptdate, l_shipinstruct, l_shipmode, l_comment);
