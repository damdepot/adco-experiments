select
        count(*) as low_stock_cnt
from
        (select
                OL_I_ID as item_id,
                sum(OL_QUANTITY) as tot_qty,
                count(*) as line_cnt
        from
                ORDER_LINE
        where
                OL_W_ID = 1
                and OL_D_ID = 5
                and OL_O_ID < 1000
                and OL_O_ID >= 1000 - 20
        group by
                OL_I_ID
        ) as recent
join
        STOCK
on
        S_W_ID = 1
        and S_I_ID = recent.item_id
join
        ITEM
on
        I_ID = recent.item_id
where
        S_W_ID = 1
        and S_QUANTITY < 10
        and recent.tot_qty > 0;
