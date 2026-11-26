-- index on accounts name

CREATE INDEX IF NOT EXISTS IDX_ACCOUNTS_NAME ON ACCOUNTS (name);

-- analyze tables

ANALYZE accounts;
ANALYZE savings;
ANALYZE checking;
