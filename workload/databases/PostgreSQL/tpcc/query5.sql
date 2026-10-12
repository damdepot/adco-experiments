select
        D_TAX,
        D_NEXT_O_ID
from
        DISTRICT
where
        D_ID = 5
        and D_W_ID = 1
for update;
