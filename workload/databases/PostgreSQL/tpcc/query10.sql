select distinct
        C_ID,
        C_FIRST,
        C_MIDDLE,
        C_LAST,
        C_BALANCE,
        O_ID,
        O_CARRIER_ID,
        O_ENTRY_D,
        OL_NUMBER,
        OL_SUPPLY_W_ID,
        OL_I_ID,
        OL_QUANTITY,
        OL_AMOUNT,
        OL_DELIVERY_D
from
        CUSTOMER
join
        ORDERS
on
        O_W_ID = C_W_ID
        and O_D_ID = C_D_ID
        and O_C_ID = C_ID
left join
        ORDER_LINE
on
        OL_W_ID = O_W_ID
        and OL_D_ID = O_D_ID
        and OL_O_ID = O_ID
where
        C_W_ID = 1
        and C_D_ID = 5
        and C_ID = 100
        and O_ID = (select
                max(O2.O_ID)
        from
                ORDERS O2
        where
                O2.O_W_ID = C_W_ID
                and O2.O_D_ID = C_D_ID
                and O2.O_C_ID = C_ID);
