-- DISTRICT
ALTER TABLE district
  ADD CONSTRAINT fk_district_warehouse
  FOREIGN KEY (d_w_id) REFERENCES warehouse(w_id);

-- CUSTOMER
ALTER TABLE customer
  ADD CONSTRAINT fk_customer_district
  FOREIGN KEY (c_w_id, c_d_id) REFERENCES district(d_w_id, d_id);

-- HISTORY
ALTER TABLE history
  ADD CONSTRAINT fk_history_customer
  FOREIGN KEY (h_c_w_id, h_c_d_id, h_c_id) REFERENCES customer(c_w_id, c_d_id, c_id);

ALTER TABLE history
  ADD CONSTRAINT fk_history_warehouse
  FOREIGN KEY (h_w_id) REFERENCES warehouse(w_id);

ALTER TABLE history
  ADD CONSTRAINT fk_history_district
  FOREIGN KEY (h_w_id, h_d_id) REFERENCES district(d_w_id, d_id);

-- STOCK
ALTER TABLE stock
  ADD CONSTRAINT fk_stock_warehouse
  FOREIGN KEY (s_w_id) REFERENCES warehouse(w_id);

ALTER TABLE stock
  ADD CONSTRAINT fk_stock_item
  FOREIGN KEY (s_i_id) REFERENCES item(i_id);

-- ORDERS
ALTER TABLE orders
  ADD CONSTRAINT fk_orders_customer
  FOREIGN KEY (o_w_id, o_d_id, o_c_id) REFERENCES customer(c_w_id, c_d_id, c_id);

-- NEW_ORDER
ALTER TABLE new_order
  ADD CONSTRAINT fk_new_order_orders
  FOREIGN KEY (no_w_id, no_d_id, no_o_id) REFERENCES orders(o_w_id, o_d_id, o_id);

-- ORDER_LINE
ALTER TABLE order_line
  ADD CONSTRAINT fk_order_line_orders
  FOREIGN KEY (ol_w_id, ol_d_id, ol_o_id) REFERENCES orders(o_w_id, o_d_id, o_id);

ALTER TABLE order_line
  ADD CONSTRAINT fk_order_line_stock
  FOREIGN KEY (ol_supply_w_id, ol_i_id) REFERENCES stock(s_w_id, s_i_id);

ALTER TABLE order_line
  ADD CONSTRAINT fk_order_line_item
  FOREIGN KEY (ol_i_id) REFERENCES item(i_id);
