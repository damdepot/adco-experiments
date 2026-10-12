select
        NO_O_ID
from
        NEW_ORDER
where
        NO_D_ID = 5
        and NO_W_ID = 1
        and NO_O_ID > -1
limit
        1;
