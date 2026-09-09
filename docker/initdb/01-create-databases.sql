-- Creates the per-benchmark databases used by the db_layer experiments.
-- The official postgres image only creates the POSTGRES_DB database; any
-- additional databases must be created here (scripts in
-- /docker-entrypoint-initdb.d run once on first init of the data volume).
CREATE DATABASE agenttune;
CREATE DATABASE smallbank;
CREATE DATABASE tpcc;
CREATE DATABASE adcodb;
