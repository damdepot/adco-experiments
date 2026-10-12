-- SAVINGS
ALTER TABLE savings
  ADD CONSTRAINT fk_savings_accounts
  FOREIGN KEY (custid) REFERENCES accounts(custid);

-- CHECKING
ALTER TABLE checking
  ADD CONSTRAINT fk_checking_accounts
  FOREIGN KEY (custid) REFERENCES accounts(custid);
