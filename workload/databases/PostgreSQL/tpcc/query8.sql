select
        S_QUANTITY,
        S_DATA,
        S_YTD,
        S_ORDER_CNT,
        S_REMOTE_CNT,
        S_DIST_05
from
        STOCK
where
        S_I_ID = 5000
        and S_W_ID = 1;
