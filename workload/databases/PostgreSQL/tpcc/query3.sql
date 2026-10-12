select
        sum(OL_AMOUNT)
from
        ORDER_LINE
where
        OL_O_ID = 1000
        and OL_D_ID = 5
        and OL_W_ID = 1;
