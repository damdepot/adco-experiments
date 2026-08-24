-- Run psql from the directory containing the CSVs (paths are relative to it),
-- e.g.: cd data/stats && psql -d stats -f .../import_remote.sql
\copy users FROM 'users.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');

\copy badges FROM 'badges.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');

\copy posts FROM 'posts.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');

\copy tags FROM 'tags.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');

\copy postLinks FROM 'postLinks.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');

\copy postHistory FROM 'postHistory.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');

\copy comments FROM 'comments.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');

\copy votes FROM 'votes.csv' WITH (FORMAT csv, HEADER true, NULL 'NULL');