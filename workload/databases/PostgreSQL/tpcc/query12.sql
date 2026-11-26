select
        H_W_ID,
        H_D_ID,
        sum(H_AMOUNT) as sum_amount,
        count(*) as payment_count
from
        HISTORY
where
        H_W_ID = 1
        and H_DATE >= timestamp '2007-01-01 00:00:00'
        and H_DATE < timestamp '2007-01-01 00:00:00' + interval '1 year'
        and H_AMOUNT >= 1.0
        and H_AMOUNT <= 5000.0
        and exists (select
                1
        from
                CUSTOMER
        where
                C_W_ID = H_C_W_ID
                and C_D_ID = H_C_D_ID
                and C_ID = H_C_ID
                and C_D_ID = 5)
group by
        H_W_ID,
        H_D_ID
union
select
        H_W_ID,
        H_D_ID,
        sum(H_AMOUNT) as sum_amount,
        count(*) as payment_count
from
        HISTORY
where
        H_W_ID = 1
        and H_DATE >= timestamp '2007-01-01 00:00:00'
        and H_DATE < timestamp '2007-01-01 00:00:00' + interval '1 year'
        and H_AMOUNT > 5000.0
        and H_AMOUNT <= 10000.0
group by
        H_W_ID,
        H_D_ID
order by
        H_W_ID,
        H_D_ID;
