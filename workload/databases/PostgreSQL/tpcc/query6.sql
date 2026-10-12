select
        C_DISCOUNT,
        C_LAST,
        C_CREDIT
from
        CUSTOMER
where
        C_W_ID = 1
        and C_D_ID = 5
        and C_ID = 100;
