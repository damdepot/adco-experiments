select
        C.C_W_ID,
        C.C_D_ID,
        sum(C.C_BALANCE) as sum_balance,
        avg(C.C_BALANCE) as avg_balance,
        count(*) as customer_count
from
        CUSTOMER C
join
        CUSTOMER C2
on
        C2.C_W_ID = C.C_W_ID
        and C2.C_D_ID = C.C_D_ID
        and C2.C_ID = C.C_ID
join
        DISTRICT
on
        D_W_ID = C.C_W_ID
        and D_ID = C.C_D_ID
join
        WAREHOUSE
on
        W_ID = C.C_W_ID
where
        C.C_W_ID in (select
                O_W_ID
        from
                ORDERS
        where
                O_D_ID = 5
                and O_C_ID >= 100 - 50)
group by
        C.C_W_ID,
        C.C_D_ID
having
        sum(C.C_BALANCE) > 0
        and sum(C.C_BALANCE) > avg(C.C_BALANCE) * 10
order by
        C.C_W_ID,
        C.C_D_ID;
